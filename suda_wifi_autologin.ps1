<#
    Scheduled-task entry point for SUDA Wi-Fi.

    It first checks whether the Internet is reachable.  If it is not, the
    WLAN adapter is reconnected to SUDA_WIFI_5G before starting the existing
    headless portal-login script.
#>

[CmdletBinding()]
param([string]$ProxyUserSid)

$ErrorActionPreference = 'Stop'

$TargetSsid = 'SUDA_WIFI_5G'
$ScriptDirectory = Split-Path -Parent $PSCommandPath
$PythonPath = Join-Path $ScriptDirectory '.venv\Scripts\python.exe'
$LoginScriptPath = Join-Path $ScriptDirectory 'auto_login.pyw'
$LogPath = Join-Path $ScriptDirectory 'suda_wifi_autologin.log'
$WifiRecoveryTimeoutSeconds = 60
$ProxyShutdownSettleSeconds = 10
$WifiConnectRetryDelaySeconds = 5
$WifiAdapterName = 'WLAN'
$WifiAdapterResetDelaySeconds = 3
$InternetTestTimeoutMilliseconds = 8000
$MaxLoginAttempts = 10
$LoginRetryDelaySeconds = 10
$ProxyServiceNames = @('hongmoHelperService', 'clash_verge_service')
$ProxyProcessNames = @(
    'hongmo',
    'hongmoCore',
    'hongmoHelperService',
    'clash-verge',
    'clash-verge-service'
)

# Keep Chinese diagnostic output from the Python script readable when it is
# captured through the Windows PowerShell native-command pipeline.
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $Utf8NoBom
$OutputEncoding = $Utf8NoBom
$env:PYTHONIOENCODING = 'utf-8'

# The scheduled task runs as SYSTEM and already has these rights.  If the
# script is launched manually from a standard-user PowerShell, restart it
# elevated so that service and adapter recovery can also work in that case.
$currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$currentPrincipal = New-Object System.Security.Principal.WindowsPrincipal($currentIdentity)
$isElevated = $currentPrincipal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
if (!$isElevated) {
    $elevationLog = '{0:yyyy-MM-dd HH:mm:ss.fff} [WARN] Manual launch is not elevated; requesting UAC elevation for Wi-Fi recovery.' -f (Get-Date)
    Add-Content -LiteralPath $LogPath -Value $elevationLog -Encoding UTF8

    $powerShellPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $arguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}"' -f $PSCommandPath
    $elevatedProcess = Start-Process -FilePath $powerShellPath -Verb RunAs -ArgumentList $arguments -Wait -PassThru
    exit $elevatedProcess.ExitCode
}

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $line = '{0:yyyy-MM-dd HH:mm:ss.fff} [{1}] {2}' -f (Get-Date), $Level, $Message
    # Write-Host keeps diagnostic output out of function return values while
    # still displaying it during an interactive/manual run.
    Write-Host $line
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
}

function Test-InternetConnection {
    # HTTPS prevents a captive portal from being mistaken for a working
    # Internet connection.  Two independent public sites reduce false
    # negatives caused by a temporary outage at either one.
    $testUris = @(
        'https://www.baidu.com/',
        'https://www.qq.com/'
    )

    foreach ($uri in $testUris) {
        $response = $null
        try {
            Write-Log "Testing Internet access: $uri"
            $request = [System.Net.HttpWebRequest]::Create($uri)
            $request.Method = 'HEAD'
            $request.Timeout = $InternetTestTimeoutMilliseconds
            $request.ReadWriteTimeout = $InternetTestTimeoutMilliseconds
            $request.AllowAutoRedirect = $false
            $request.Proxy = $null
            $response = $request.GetResponse()
            $statusCode = [int]$response.StatusCode

            if ($statusCode -ge 200 -and $statusCode -lt 300) {
                Write-Log "Internet access succeeded: $uri returned HTTP $statusCode"
                return $true
            }

            Write-Log "Internet access did not pass: $uri returned HTTP $statusCode" 'WARN'
        }
        catch {
            Write-Log "Internet access failed: $uri; $($_.Exception.Message)" 'WARN'
        }
        finally {
            if ($response) {
                $response.Dispose()
            }
        }
    }

    Write-Log 'Internet access could not be confirmed from any test endpoint.' 'WARN'
    return $false
}

function Stop-ProxyClient {
    Write-Log 'Internet checks failed. Stopping Hongmoguan Network Accelerator and Clash Verge, then clearing proxy settings before Wi-Fi reconnect.' 'WARN'

    # Stop the client and its core first so they cannot restart the helper
    # service while the Wi-Fi recovery operation is in progress.
    foreach ($processName in $ProxyProcessNames) {
        try {
            $processes = @(Get-Process -Name $processName -ErrorAction SilentlyContinue)
            foreach ($process in $processes) {
                Write-Log "Stopping proxy process '$($process.ProcessName)' (PID $($process.Id))." 'WARN'
                Stop-Process -Id $process.Id -Force -ErrorAction Stop
            }
        }
        catch {
            Write-Log "Could not stop proxy process '$processName': $($_.Exception.Message)" 'ERROR'
        }
    }

    foreach ($serviceName in $ProxyServiceNames) {
        try {
            $service = Get-Service -Name $serviceName -ErrorAction Stop
            if ($service.Status -eq 'Running') {
                Write-Log "Stopping proxy service '$serviceName'." 'WARN'
                Stop-Service -Name $serviceName -Force -ErrorAction Stop
                $service.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Stopped, [TimeSpan]::FromSeconds(10))
                Write-Log "Proxy service '$serviceName' stopped."
            }
            else {
                Write-Log "Proxy service '$serviceName' is already $($service.Status)."
            }
        }
        catch {
            Write-Log "Could not stop proxy service '$serviceName': $($_.Exception.Message)" 'ERROR'
        }
    }

    Clear-SystemProxySettings
}

function Get-ProxyUserSids {
    # Internet Options / the Windows "system proxy" UI is per-user (WinINet),
    # while this recovery task runs as SYSTEM.  Locate the interactive user's
    # loaded hive explicitly instead of changing only HKCU for SYSTEM.
    $sids = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)

    try {
        $explorerProcesses = Get-CimInstance Win32_Process -Filter "Name = 'explorer.exe'" -ErrorAction Stop
        foreach ($process in $explorerProcesses) {
            $owner = Invoke-CimMethod -InputObject $process -MethodName GetOwner -ErrorAction Stop
            if ($owner.ReturnValue -eq 0 -and $owner.User) {
                $accountName = if ($owner.Domain) { "$($owner.Domain)\$($owner.User)" } else { $owner.User }
                $sid = ([System.Security.Principal.NTAccount]$accountName).Translate([System.Security.Principal.SecurityIdentifier]).Value
                [void]$sids.Add($sid)
            }
        }
    }
    catch {
        Write-Log "Could not obtain the interactive user's SID from explorer.exe: $($_.Exception.Message)" 'WARN'
    }

    # The installer passes the intended user's SID. It remains available even
    # when no interactive desktop (and therefore no explorer.exe) exists.
    if ($ProxyUserSid) {
        if ($ProxyUserSid -notmatch '^S-1-5-21-(?:\d+-){3}\d+$') {
            throw "Invalid ProxyUserSid: $ProxyUserSid"
        }
        [void]$sids.Add($ProxyUserSid)
    }

    # Also reset the scheduled task's own WinINet proxy hive.  This matters if
    # the headless browser is launched under SYSTEM.
    [void]$sids.Add('S-1-5-18')
    # Emit individual SID strings.  Do not return the HashSet as one object:
    # doing so would turn the registry path into its type name.
    return @($sids | ForEach-Object { $_ })
}

function Clear-SystemProxySettings {
    Write-Log 'Clearing Windows WinINet system-proxy settings.' 'WARN'
    $clearedAnyUserHive = $false

    foreach ($sid in Get-ProxyUserSids) {
        $settingsPath = "Registry::HKEY_USERS\$sid\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
        if (!(Test-Path -LiteralPath $settingsPath)) {
            Write-Log "Proxy settings hive is not loaded for SID '$sid'; it was skipped." 'WARN'
            continue
        }

        try {
            $old = Get-ItemProperty -LiteralPath $settingsPath -ErrorAction Stop
            $oldEnabled = if ($null -ne $old.ProxyEnable) { $old.ProxyEnable } else { '<unset>' }
            $oldServer = if ($old.ProxyServer) { $old.ProxyServer } else { '<empty>' }
            $oldPac = if ($old.AutoConfigURL) { $old.AutoConfigURL } else { '<empty>' }
            Write-Log "Clearing WinINet proxy for SID '$sid' (ProxyEnable=$oldEnabled, ProxyServer=$oldServer, AutoConfigURL=$oldPac)." 'WARN'

            Set-ItemProperty -LiteralPath $settingsPath -Name ProxyEnable -Type DWord -Value 0 -ErrorAction Stop
            Set-ItemProperty -LiteralPath $settingsPath -Name AutoDetect -Type DWord -Value 0 -ErrorAction Stop
            foreach ($propertyName in @('ProxyServer', 'ProxyOverride', 'AutoConfigURL')) {
                Remove-ItemProperty -LiteralPath $settingsPath -Name $propertyName -ErrorAction SilentlyContinue
            }
            $clearedAnyUserHive = $true
            Write-Log "WinINet proxy settings cleared for SID '$sid'."
        }
        catch {
            Write-Log "Could not clear WinINet proxy settings for SID '$sid': $($_.Exception.Message)" 'ERROR'
        }
    }

    if (!$clearedAnyUserHive) {
        Write-Log 'No loaded user WinINet proxy hive could be cleared.' 'ERROR'
    }

    try {
        $winHttpOutput = & netsh winhttp reset proxy 2>&1
        if ($LASTEXITCODE -eq 0) {
            foreach ($line in $winHttpOutput) { Write-Log "WinHTTP: $line" }
            Write-Log 'WinHTTP proxy reset to direct access.'
        }
        else {
            foreach ($line in $winHttpOutput) { Write-Log "WinHTTP: $line" 'WARN' }
            Write-Log "netsh winhttp reset proxy returned exit code $LASTEXITCODE." 'ERROR'
        }
    }
    catch {
        Write-Log "Could not reset the WinHTTP proxy: $($_.Exception.Message)" 'ERROR'
    }
}

function Get-WlanConnectionStatus {
    $output = & netsh wlan show interfaces 2>&1
    $interfaceName = $null
    $state = $null
    $ssid = $null

    foreach ($line in $output) {
        if ($line -match '^\s*Name\s*:\s*(.+?)\s*$') {
            $interfaceName = $Matches[1].Trim()
        }
        elseif ($line -match '^\s*State\s*:\s*(.+?)\s*$') {
            $state = $Matches[1].Trim()
        }
        # Match only the SSID field, not the AP BSSID field.
        elseif ($line -match '^\s*SSID\s*:\s*(.+?)\s*$') {
            $ssid = $Matches[1].Trim()
        }
    }

    [pscustomobject]@{
        InterfaceName = $interfaceName
        State = $state
        Ssid = $ssid
    }
}

function Test-TargetWifiConnection {
    param([pscustomobject]$Status)

    return $Status.State -eq 'connected' -and
        $Status.Ssid -eq $TargetSsid
}

function Enable-WifiAdapter {
    try {
        $adapter = Get-NetAdapter -Name $WifiAdapterName -IncludeHidden -ErrorAction Stop
        if ($adapter.AdminStatus -ne 'Up') {
            Write-Log "Enabling Wi-Fi adapter '$WifiAdapterName' (current admin status: $($adapter.AdminStatus))." 'WARN'
            Enable-NetAdapter -Name $WifiAdapterName -Confirm:$false -ErrorAction Stop
        }
        else {
            Write-Log "Wi-Fi adapter '$WifiAdapterName' is already administratively enabled."
        }
        return $true
    }
    catch {
        Write-Log "Could not enable Wi-Fi adapter '$WifiAdapterName': $($_.Exception.Message)" 'ERROR'
        return $false
    }
}

function Connect-TargetWifi {
    param([pscustomobject]$Status)

    Write-Log "Wi-Fi reconnect required. Current interface='$($Status.InterfaceName)', state='$($Status.State)', SSID='$($Status.Ssid)'."

    if ($Status.InterfaceName) {
        Write-Log "Disconnecting WLAN interface '$($Status.InterfaceName)'."
        $disconnectOutput = & netsh wlan disconnect "interface=$($Status.InterfaceName)" 2>&1
        $disconnectExitCode = $LASTEXITCODE
        foreach ($line in $disconnectOutput) { Write-Log "netsh disconnect: $line" }
        Write-Log "netsh disconnect exit code: $disconnectExitCode"
    }
    else {
        Write-Log 'No WLAN interface name was detected; using the default WLAN interface.' 'WARN'
        $disconnectOutput = & netsh wlan disconnect 2>&1
        $disconnectExitCode = $LASTEXITCODE
        foreach ($line in $disconnectOutput) { Write-Log "netsh disconnect: $line" }
        Write-Log "netsh disconnect exit code: $disconnectExitCode"
    }

    # TUN clients can temporarily power down the WLAN stack while their
    # virtual adapters and routes are being removed.  Reissue the connection
    # request instead of sending it only once during that transition.
    $deadline = (Get-Date).AddSeconds($WifiRecoveryTimeoutSeconds)
    $connectAttempt = 0
    do {
        $status = Get-WlanConnectionStatus
        if (Test-TargetWifiConnection -Status $status) {
            Write-Log "Wi-Fi connected to '$TargetSsid'."
            return $true
        }

        $connectAttempt++
        if ($status.InterfaceName) {
            Write-Log "Wi-Fi connect attempt ${connectAttempt}: interface='$($status.InterfaceName)', state='$($status.State)', SSID='$($status.Ssid)'."
            $connectOutput = & netsh wlan connect "name=$TargetSsid" "interface=$($status.InterfaceName)" 2>&1
        }
        else {
            Write-Log "Wi-Fi connect attempt ${connectAttempt}: no WLAN interface is currently available." 'WARN'
            $connectOutput = & netsh wlan connect "name=$TargetSsid" 2>&1
        }

        $connectExitCode = $LASTEXITCODE
        foreach ($line in $connectOutput) { Write-Log "netsh connect: $line" }
        Write-Log "netsh connect attempt $connectAttempt exit code: $connectExitCode"

        $connectText = $connectOutput -join "`n"
        # The dedicated every-minute WLAN recovery task owns software-radio
        # enablement. Do not disable the adapter here: that only resets the
        # device and does not reliably turn the Windows Wi-Fi switch back on.
        if ($connectText -match '0x80342002|2150899714|powered down') {
            Write-Log 'WLAN software radio is powered down; waiting for the dedicated WLAN recovery task.' 'WARN'
        }

        Start-Sleep -Seconds $WifiConnectRetryDelaySeconds
    } while ((Get-Date) -lt $deadline)

    Write-Log "Timed out reconnecting Wi-Fi SSID '$TargetSsid' after $connectAttempt attempts." 'ERROR'
    return $false
}

function Invoke-PortalAutoLoginWithRetry {
    for ($attempt = 1; $attempt -le $MaxLoginAttempts; $attempt++) {
        Write-Log "Starting portal auto-login attempt $attempt of ${MaxLoginAttempts}: $LoginScriptPath"

        & $PythonPath $LoginScriptPath 2>&1 | ForEach-Object {
            Write-Log "auto_login.pyw [attempt $attempt]: $_"
        }
        $pythonExitCode = $LASTEXITCODE
        Write-Log "Portal auto-login attempt $attempt exit code: $pythonExitCode"

        if ($pythonExitCode -eq 0) {
            Write-Log "Checking Internet access after portal auto-login attempt $attempt."
            if (Test-InternetConnection) {
                Write-Log "Portal auto-login succeeded and Internet access is restored on attempt $attempt."
                return $true
            }

            Write-Log "Portal auto-login attempt $attempt returned success, but Internet access is still unavailable." 'WARN'
        }
        else {
            Write-Log "Portal auto-login attempt $attempt failed." 'WARN'
        }

        if ($attempt -lt $MaxLoginAttempts) {
            Write-Log "Waiting $LoginRetryDelaySeconds seconds before the next portal auto-login attempt."
            Start-Sleep -Seconds $LoginRetryDelaySeconds
        }
    }

    Write-Log "Portal auto-login did not restore Internet access after $MaxLoginAttempts attempts." 'ERROR'
    return $false
}

try {
    Write-Log '===== SUDA Wi-Fi auto-login run started ====='
    Write-Log "Entry script: $PSCommandPath"
    Write-Log "Log file: $LogPath"

    if (!(Test-Path -LiteralPath $PythonPath)) {
        throw "Python interpreter not found: $PythonPath"
    }

    if (!(Test-Path -LiteralPath $LoginScriptPath)) {
        throw "Auto-login script not found: $LoginScriptPath"
    }

    $internetAvailable = Test-InternetConnection
    if (!$internetAvailable) {
        Stop-ProxyClient
        Enable-WifiAdapter | Out-Null
        Write-Log "Waiting $ProxyShutdownSettleSeconds seconds for proxy shutdown and WLAN recovery."
        Start-Sleep -Seconds $ProxyShutdownSettleSeconds
        $status = Get-WlanConnectionStatus
        $wifiConnected = Connect-TargetWifi -Status $status
        if (!$wifiConnected) {
            Write-Log "Wi-Fi reconnect was not confirmed within $WifiRecoveryTimeoutSeconds seconds; continuing with portal auto-login anyway." 'WARN'
        }
    }
    else {
        Write-Log 'Internet is reachable; Wi-Fi reconnect is not needed.'
    }

    if (Invoke-PortalAutoLoginWithRetry) {
        Write-Log '===== SUDA Wi-Fi auto-login run finished successfully ====='
        exit 0
    }

    Write-Log '===== SUDA Wi-Fi auto-login run finished with errors =====' 'ERROR'
    exit 1
}
catch {
    Write-Log "Run failed: $($_.Exception.Message)" 'ERROR'
    Write-Log '===== SUDA Wi-Fi auto-login run finished with errors =====' 'ERROR'
    exit 1
}

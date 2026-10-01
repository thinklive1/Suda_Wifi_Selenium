[CmdletBinding()]
param([switch]$IncludeUuRemote)

$ErrorActionPreference = 'Stop'
$scriptDirectory = Split-Path -Parent $PSCommandPath
$powershellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$currentPrincipal = [System.Security.Principal.WindowsPrincipal]::new($currentIdentity)
if (!$currentPrincipal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this registration script from an elevated PowerShell window.'
}

function New-ScriptAction {
    param([string]$FilePath, [string]$ExtraArguments = '')
    if (!(Test-Path -LiteralPath $FilePath -PathType Leaf)) { throw "Missing script: $FilePath" }
    $arguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" {1}' -f $FilePath, $ExtraArguments
    New-ScheduledTaskAction -Execute $powershellPath -Argument $arguments.Trim()
}

function New-RepeatingTrigger {
    param([int]$Minutes)
    New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes $Minutes) -RepetitionDuration (New-TimeSpan -Days 3650)
}

$systemPrincipal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$wifiBootTrigger = New-ScheduledTaskTrigger -AtStartup
$wifiBootTrigger.Delay = 'PT30S'
$wifiAction = New-ScriptAction -FilePath (Join-Path $scriptDirectory 'suda_wifi_autologin.ps1') -ExtraArguments ('-ProxyUserSid "{0}"' -f $currentIdentity.User.Value)
$wifiSettings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 30) -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -Hidden
Register-ScheduledTask -TaskName 'SUDA-WiFi-AutoLogin' -Action $wifiAction -Trigger @($wifiBootTrigger, (New-RepeatingTrigger -Minutes 5)) -Principal $systemPrincipal -Settings $wifiSettings -Force | Out-Null
Write-Output 'Registered SUDA-WiFi-AutoLogin: boot + 30 seconds, then every 5 minutes.'

$radioBootTrigger = New-ScheduledTaskTrigger -AtStartup
$radioBootTrigger.Delay = 'PT15S'
$radioAction = New-ScriptAction -FilePath (Join-Path $scriptDirectory 'wlan_radio_recovery.ps1')
$radioSettings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 2) -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -Hidden
Register-ScheduledTask -TaskName 'SUDA-WLAN-RadioRecovery' -Action $radioAction -Trigger @($radioBootTrigger, (New-RepeatingTrigger -Minutes 1)) -Principal $systemPrincipal -Settings $radioSettings -Force | Out-Null
Write-Output 'Registered SUDA-WLAN-RadioRecovery: boot + 15 seconds, then every minute.'

if ($IncludeUuRemote) {
    $launcherPath = Join-Path $scriptDirectory 'uu_remote_watchdog.vbs'
    if (!(Test-Path -LiteralPath $launcherPath -PathType Leaf)) { throw "Missing launcher: $launcherPath" }
    $uuAction = New-ScheduledTaskAction -Execute (Join-Path $env:SystemRoot 'System32\wscript.exe') -Argument ('//B //NoLogo "{0}"' -f $launcherPath)
    $uuPrincipal = New-ScheduledTaskPrincipal -UserId $currentIdentity.Name -LogonType Interactive -RunLevel Limited
    $uuSettings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 2) -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -Hidden
    Register-ScheduledTask -TaskName 'UU-Remote-Watchdog' -Action $uuAction -Trigger (New-RepeatingTrigger -Minutes 1) -Principal $uuPrincipal -Settings $uuSettings -Force | Out-Null
    Write-Output 'Registered UU-Remote-Watchdog for the current interactive user: every minute.'
}

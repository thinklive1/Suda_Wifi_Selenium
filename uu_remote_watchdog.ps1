<#
    Keep UU Remote (GameViewer) available in the current user's desktop
    session. This script is intended to be launched by the
    UU-Remote-Watchdog scheduled task once per minute.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ProcessName = 'GameViewer'
$LogPath = Join-Path (Split-Path -Parent $PSCommandPath) 'uu_remote_watchdog.log'

function Get-UuRemotePath {
    $uninstallKeys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($entry in @(Get-ItemProperty $uninstallKeys -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayIcon -match 'GameViewer\.exe' })) {
        $iconPath = [string]$entry.DisplayIcon
        if ($iconPath -match '^"([^"]+\.exe)"') { $iconPath = $Matches[1] }
        $iconPath = $iconPath -replace ',\d+$', ''
        if ($iconPath) {
            $candidate = Join-Path (Split-Path -Parent $iconPath) 'bin\GameViewer.exe'
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
        }
    }
    throw 'UU Remote was not found in Windows installed applications.'
}

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO'
    )

    $line = '{0:yyyy-MM-dd HH:mm:ss.fff} [{1}] {2}' -f (Get-Date), $Level, $Message
    Write-Host $line
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
}

try {
    $UuRemotePath = Get-UuRemotePath
    $running = @(Get-Process -Name $ProcessName -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -eq $UuRemotePath })

    if ($running.Count -gt 0) {
        Write-Log "UU Remote is already running (PID: $($running.Id -join ', '))."
        exit 0
    }

    if (!(Test-Path -LiteralPath $UuRemotePath -PathType Leaf)) {
        throw "UU Remote executable was not found: $UuRemotePath"
    }

    Write-Log "UU Remote is not running; starting: $UuRemotePath" 'WARN'
    $process = Start-Process -FilePath $UuRemotePath -WorkingDirectory (Split-Path -Parent $UuRemotePath) -PassThru -ErrorAction Stop
    Start-Sleep -Seconds 3

    if (!(Get-Process -Id $process.Id -ErrorAction SilentlyContinue)) {
        throw "UU Remote exited immediately after launch (PID $($process.Id))."
    }

    Write-Log "UU Remote started successfully (PID: $($process.Id))."
    exit 0
}
catch {
    Write-Log "UU Remote watchdog failed: $($_.Exception.Message)" 'ERROR'
    exit 1
}

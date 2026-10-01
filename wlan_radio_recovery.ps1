<#
    SYSTEM-task helper which restores the actual Wi-Fi *software radio*.
    It deliberately has no SSID, proxy, or portal-login logic: that belongs
    to suda_wifi_autologin.ps1.  The two concerns must remain independent.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$WifiAdapterName = 'WLAN'
$LogPath = Join-Path (Split-Path -Parent $PSCommandPath) 'wlan_radio_recovery.log'
$RadioEnableSettleSeconds = 3
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $Utf8NoBom
$OutputEncoding = $Utf8NoBom

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO'
    )
    $line = '{0:yyyy-MM-dd HH:mm:ss.fff} [{1}] {2}' -f (Get-Date), $Level, $Message
    Write-Host $line
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
}

function Initialize-WlanNativeApi {
    if ('SudaWlanNative' -as [type]) { return }

    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public sealed class SudaWlanRadioState
{
    public uint PhyIndex { get; set; }
    public uint SoftwareState { get; set; }
    public uint HardwareState { get; set; }
}

public static class SudaWlanNative
{
    private const uint WLAN_CLIENT_VERSION_LONGHORN = 2;
    private const uint WLAN_INTF_OPCODE_RADIO_STATE = 4;
    private const uint DOT11_RADIO_STATE_ON = 1;

    [StructLayout(LayoutKind.Sequential)]
    private struct WLAN_PHY_RADIO_STATE
    {
        public UInt32 PhyIndex;
        public UInt32 SoftwareRadioState;
        public UInt32 HardwareRadioState;
    }

    [DllImport("wlanapi.dll", SetLastError = false)]
    private static extern UInt32 WlanOpenHandle(UInt32 clientVersion, IntPtr reserved,
        out UInt32 negotiatedVersion, out IntPtr clientHandle);

    [DllImport("wlanapi.dll", SetLastError = false)]
    private static extern UInt32 WlanSetInterface(IntPtr clientHandle, ref Guid interfaceGuid,
        UInt32 opcode, UInt32 dataSize, IntPtr data, IntPtr reserved);

    [DllImport("wlanapi.dll", SetLastError = false)]
    private static extern UInt32 WlanQueryInterface(IntPtr clientHandle, ref Guid interfaceGuid,
        UInt32 opcode, IntPtr reserved, out UInt32 dataSize, out IntPtr data,
        out UInt32 opcodeValueType);

    [DllImport("wlanapi.dll", SetLastError = false)]
    private static extern void WlanFreeMemory(IntPtr memory);

    [DllImport("wlanapi.dll", SetLastError = false)]
    private static extern UInt32 WlanCloseHandle(IntPtr clientHandle, IntPtr reserved);

    private static UInt32 Open(out IntPtr clientHandle)
    {
        UInt32 version;
        return WlanOpenHandle(WLAN_CLIENT_VERSION_LONGHORN, IntPtr.Zero, out version, out clientHandle);
    }

    public static SudaWlanRadioState[] GetRadioStates(Guid interfaceGuid, out UInt32 errorCode)
    {
        IntPtr clientHandle = IntPtr.Zero;
        IntPtr data = IntPtr.Zero;
        errorCode = Open(out clientHandle);
        if (errorCode != 0) return new SudaWlanRadioState[0];
        try
        {
            UInt32 dataSize, valueType;
            errorCode = WlanQueryInterface(clientHandle, ref interfaceGuid,
                WLAN_INTF_OPCODE_RADIO_STATE, IntPtr.Zero, out dataSize, out data, out valueType);
            if (errorCode != 0) return new SudaWlanRadioState[0];

            const int headerSize = 4;
            int stateSize = Marshal.SizeOf(typeof(WLAN_PHY_RADIO_STATE));
            int count = Marshal.ReadInt32(data, 0);
            if (count < 1 || count > 64 || dataSize < headerSize + (uint)(count * stateSize))
            {
                errorCode = 87;
                return new SudaWlanRadioState[0];
            }
            List<SudaWlanRadioState> states = new List<SudaWlanRadioState>();
            for (int i = 0; i < count; i++)
            {
                IntPtr statePtr = IntPtr.Add(data, headerSize + i * stateSize);
                WLAN_PHY_RADIO_STATE state = (WLAN_PHY_RADIO_STATE)Marshal.PtrToStructure(
                    statePtr, typeof(WLAN_PHY_RADIO_STATE));
                states.Add(new SudaWlanRadioState {
                    PhyIndex = state.PhyIndex,
                    SoftwareState = state.SoftwareRadioState,
                    HardwareState = state.HardwareRadioState
                });
            }
            return states.ToArray();
        }
        finally
        {
            if (data != IntPtr.Zero) WlanFreeMemory(data);
            if (clientHandle != IntPtr.Zero) WlanCloseHandle(clientHandle, IntPtr.Zero);
        }
    }

    public static UInt32 EnableSoftwareRadio(Guid interfaceGuid)
    {
        IntPtr clientHandle = IntPtr.Zero;
        IntPtr data = IntPtr.Zero;
        UInt32 result = Open(out clientHandle);
        if (result != 0) return result;
        try
        {
            UInt32 stateError;
            SudaWlanRadioState[] states = GetRadioStates(interfaceGuid, out stateError);
            if (stateError != 0) return stateError;
            int stateSize = Marshal.SizeOf(typeof(WLAN_PHY_RADIO_STATE));
            foreach (SudaWlanRadioState current in states)
            {
                WLAN_PHY_RADIO_STATE desired = new WLAN_PHY_RADIO_STATE {
                    PhyIndex = current.PhyIndex,
                    SoftwareRadioState = DOT11_RADIO_STATE_ON,
                    HardwareRadioState = DOT11_RADIO_STATE_ON
                };
                data = Marshal.AllocHGlobal(stateSize);
                Marshal.StructureToPtr(desired, data, false);
                result = WlanSetInterface(clientHandle, ref interfaceGuid,
                    WLAN_INTF_OPCODE_RADIO_STATE, (UInt32)stateSize, data, IntPtr.Zero);
                Marshal.FreeHGlobal(data);
                data = IntPtr.Zero;
                if (result != 0) return result;
            }
            return 0;
        }
        finally
        {
            if (data != IntPtr.Zero) Marshal.FreeHGlobal(data);
            if (clientHandle != IntPtr.Zero) WlanCloseHandle(clientHandle, IntPtr.Zero);
        }
    }
}
'@
}

function Get-RadioStateText {
    param([guid]$InterfaceGuid)
    [uint32]$errorCode = 0
    $states = [SudaWlanNative]::GetRadioStates($InterfaceGuid, [ref]$errorCode)
    if ($errorCode -ne 0) { throw "WlanQueryInterface(radio_state) failed with error $errorCode." }
    if ($states.Count -lt 1) { throw 'WlanQueryInterface(radio_state) returned no PHY state.' }
    return (($states | ForEach-Object {
        "PHY $($_.PhyIndex): software=$($_.SoftwareState), hardware=$($_.HardwareState)"
    }) -join '; ')
}

try {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    Write-Log "===== WLAN radio recovery started (identity: $identity) ====="
    $adapter = Get-NetAdapter -Name $WifiAdapterName -IncludeHidden -ErrorAction Stop
    Write-Log "Adapter: status=$($adapter.Status), admin=$($adapter.AdminStatus), interfaceGuid=$($adapter.InterfaceGuid)"

    if ($adapter.AdminStatus -ne 'Up') {
        Write-Log "WLAN adapter admin state is '$($adapter.AdminStatus)'; enabling it." 'WARN'
        Enable-NetAdapter -Name $WifiAdapterName -Confirm:$false -ErrorAction Stop
        Start-Sleep -Seconds $RadioEnableSettleSeconds
        $adapter = Get-NetAdapter -Name $WifiAdapterName -IncludeHidden -ErrorAction Stop
    }

    Initialize-WlanNativeApi
    $before = Get-RadioStateText -InterfaceGuid ([guid]$adapter.InterfaceGuid)
    Write-Log "WLAN radio state before enable request: $before"

    # Always issue this idempotent request.  Some Wi-Fi drivers report an
    # already-on state from a SYSTEM session while the interactive-session
    # quick-setting has disabled the usable radio.  Calling WlanSetInterface
    # regardless avoids relying on that inconsistent status report.
    Write-Log 'Issuing the idempotent WLAN software-radio ON request.'
    $result = [SudaWlanNative]::EnableSoftwareRadio([guid]$adapter.InterfaceGuid)
    if ($result -ne 0) { throw "WlanSetInterface(radio_state) failed with error $result." }
    Start-Sleep -Seconds $RadioEnableSettleSeconds
    $after = Get-RadioStateText -InterfaceGuid ([guid]$adapter.InterfaceGuid)
    Write-Log "WLAN radio state after enable request: $after"
    if ($after -match 'software=0') { throw 'WLAN software radio remains off after the enable request.' }
    if ($after -match 'hardware=0') {
        Write-Log 'WLAN hardware radio is off (for example airplane mode or a physical radio switch); software cannot override that state.' 'WARN'
    }
    elseif ($before -match 'software=0') {
        Write-Log 'WLAN software radio has been restored.'
    }
    else {
        Write-Log 'WLAN software radio is on after the verification.'
    }
    Write-Log '===== WLAN radio recovery finished ====='
    exit 0
}
catch {
    Write-Log "WLAN radio recovery failed: $($_.Exception.Message)" 'ERROR'
    exit 1
}

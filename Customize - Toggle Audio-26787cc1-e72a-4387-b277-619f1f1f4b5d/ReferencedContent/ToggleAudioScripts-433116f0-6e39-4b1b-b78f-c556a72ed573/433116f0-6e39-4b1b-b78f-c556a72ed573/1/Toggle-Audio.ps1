<#
.SYNOPSIS
    Mutes, unmutes, or toggles the mute state of the default audio playback device.

.DESCRIPTION
    Controls the master mute state of the default render (playback) audio endpoint
    using the Windows Core Audio IAudioEndpointVolume COM interface.

    No external dependencies - the required COM interop is compiled inline.

.EXAMPLE
    .\Toggle-Audio.ps1
    Toggles the mute state of the default playback device.

.EXAMPLE
    .\Toggle-Audio.ps1 -Mute
    Mutes the default playback device.

.EXAMPLE
    .\Toggle-Audio.ps1 -Unmute
    Unmutes the default playback device.

.NOTES
    Affects the default render endpoint of the calling session. Must run in an
    interactive session; there is no audio endpoint in Session 0.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$Mute,

    [Parameter(Mandatory = $false)]
    [switch]$Unmute,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Toggle', 'Mute', 'Unmute')]
    [string]$Behaviour = 'Toggle'
)

if ($Mute -and $Unmute) {
    Write-Error "Specify either -Mute or -Unmute, not both."
    exit 1
}

try {
    Import-Module DeployR.Utility -ErrorAction SilentlyContinue
}
catch {
    Write-Verbose "DeployR.Utility could not be imported: $($_.Exception.Message)"
}

if (Get-Module -Name 'DeployR.Utility') {
    $tsBehaviour = try { ${TSEnv:Behaviour} } catch { $null }
    if (-not [string]::IsNullOrWhiteSpace($tsBehaviour)) {
        if ($tsBehaviour -notin @('Toggle', 'Mute', 'Unmute')) {
            Write-Error "Behaviour has an unsupported value '$tsBehaviour'. Expected Toggle, Mute, or Unmute."
            exit 1
        }
        $Behaviour = $tsBehaviour
    }
}

$source = @'
using System;
using System.Runtime.InteropServices;

namespace CoreAudio {
    public enum EDataFlow { eRender = 0, eCapture = 1, eAll = 2 }
    public enum ERole { eConsole = 0, eMultimedia = 1, eCommunications = 2 }

    [Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IMMDeviceEnumerator {
        [PreserveSig]
        int EnumAudioEndpoints(EDataFlow dataFlow, uint stateMask, out IntPtr devices);
        [PreserveSig]
        int GetDefaultAudioEndpoint(EDataFlow dataFlow, ERole role, out IntPtr device);
    }

    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IMMDevice {
        [PreserveSig]
        int Activate([MarshalAs(UnmanagedType.LPStruct)] Guid iid, int clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object activated);
    }

    [Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IAudioEndpointVolume {
        int RegisterControlChangeNotify(IntPtr notify);
        int UnregisterControlChangeNotify(IntPtr notify);
        int GetChannelCount(out uint channelCount);
        int SetMasterVolumeLevel(float levelDb, ref Guid eventContext);
        int SetMasterVolumeLevelScalar(float level, ref Guid eventContext);
        int GetMasterVolumeLevel(out float levelDb);
        int GetMasterVolumeLevelScalar(out float level);
        int SetChannelVolumeLevel(uint channelNumber, float levelDb, ref Guid eventContext);
        int SetChannelVolumeLevelScalar(uint channelNumber, float level, ref Guid eventContext);
        int GetChannelVolumeLevel(uint channelNumber, out float levelDb);
        int GetChannelVolumeLevelScalar(uint channelNumber, out float level);
        int SetMute([MarshalAs(UnmanagedType.Bool)] bool mute, ref Guid eventContext);
        int GetMute([MarshalAs(UnmanagedType.Bool)] out bool mute);
        int GetVolumeStepInfo(out uint step, out uint stepCount);
        int VolumeStepUp(ref Guid eventContext);
        int VolumeStepDown(ref Guid eventContext);
        int QueryHardwareSupport(out uint hardwareSupportMask);
        int GetVolumeRange(out float volumeMindB, out float volumeMaxdB, out float volumeIncrementdB);
    }

    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    public class MMDeviceEnumerator { }

    public static class AudioEndpoint {
        private static readonly Guid IidIAudioEndpointVolume = new Guid("5CDF2C82-841E-4546-9722-0CF74078229A");

        public static bool GetMute() {
            bool muted;
            Marshal.ThrowExceptionForHR(GetDefault().GetMute(out muted));
            return muted;
        }

        public static void SetMute(bool muted) {
            var empty = Guid.Empty;
            Marshal.ThrowExceptionForHR(GetDefault().SetMute(muted, ref empty));
        }

        private static IAudioEndpointVolume GetDefault() {
            var enumerator = (IMMDeviceEnumerator)new MMDeviceEnumerator();
            IntPtr devicePtr;
            Marshal.ThrowExceptionForHR(enumerator.GetDefaultAudioEndpoint(EDataFlow.eRender, ERole.eMultimedia, out devicePtr));
            var device = (IMMDevice)Marshal.GetObjectForIUnknown(devicePtr);
            Marshal.Release(devicePtr);
            object activated;
            Marshal.ThrowExceptionForHR(device.Activate(IidIAudioEndpointVolume, 1 /* CLSCTX_INPROC_SERVER */, IntPtr.Zero, out activated));
            return (IAudioEndpointVolume)activated;
        }
    }
}
'@

try {
    if (-not ('CoreAudio.AudioEndpoint' -as [type])) {
        Add-Type -TypeDefinition $source -ErrorAction Stop
    }

    try {
        $isMuted = [CoreAudio.AudioEndpoint]::GetMute()
    }
    catch [System.Runtime.InteropServices.COMException] {
        # 0x80070490 = ERROR_NOT_FOUND: no default audio render endpoint exists
        if ($_.Exception.HResult -eq [int]0x80070490 -or $_.Exception.ErrorCode -eq [int]0x80070490) {
            Write-Output "No audio playback device present. Skipping."
            exit 0
        }
        throw
    }

    $effectiveBehaviour = if ($Mute) { 'Mute' } elseif ($Unmute) { 'Unmute' } else { $Behaviour }

    switch ($effectiveBehaviour) {
        'Mute'   { $target = $true }
        'Unmute' { $target = $false }
        default  { $target = -not $isMuted }
    }

    [CoreAudio.AudioEndpoint]::SetMute($target)
    Write-Output $(if ($target) { "Muted" } else { "Unmuted" })
    exit 0
}
catch {
    Write-Error "Failed to control audio endpoint: $($_.Exception.Message)"
    exit 1
}

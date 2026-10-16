param(
    [string]$GameId,
    [switch]$Browse,
    [string]$MarkerPath,
    [string]$SettingsPath = (Join-Path $PSScriptRoot 'settings.json'),
    [switch]$TvOnly,
    [switch]$TestLayout,
    [string]$RecoverPath,
    [switch]$SelfTest,
    [switch]$LibraryOnly
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Settings.ps1')

# Win32 references: EnumDisplaySettingsExW, ChangeDisplaySettingsExW, DEVMODEW.
if (!('PlayniteBridgeDisplay.Native' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
namespace PlayniteBridgeDisplay {
 [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
 public struct Device {
  public int cb;
  [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string Name;
  [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string Description;
  public uint Flags;
  [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string Id;
  [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string Key;
 }
 [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
 public struct Mode {
  [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string DeviceName;
  public ushort SpecVersion, DriverVersion, Size, DriverExtra;
  public uint Fields;
  public int X, Y;
  public uint Orientation, FixedOutput;
  public short Color, Duplex, YResolution, TTOption, Collate;
  [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string FormName;
  public ushort LogPixels;
  public uint BitsPerPel, Width, Height, DisplayFlags, Frequency;
  public uint ICMMethod, ICMIntent, MediaType, DitherType, Reserved1, Reserved2, PanningWidth, PanningHeight;
 }
 public class State {
  public string Name, MonitorId, ModeData;
  public bool Primary, Enabled;
  public int X, Y;
  public uint Width, Height;
 }
 [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
 struct Startup {
  public int cb; public string reserved, desktop, title;
  public int x,y,xSize,ySize,xCount,yCount,fill,flags;
  public short show,reserved2; public IntPtr reservedPtr,input,output,error;
 }
 [StructLayout(LayoutKind.Sequential)]
 struct ProcessInfo { public IntPtr process,thread; public uint processId,threadId; }
 public static class Native {
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern bool EnumDisplayDevices(string name,uint index,ref Device device,uint flags);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern bool EnumDisplaySettingsEx(string name,int index,ref Mode mode,uint flags);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int ChangeDisplaySettingsEx(string name,ref Mode mode,IntPtr hwnd,uint flags,IntPtr param);
  [DllImport("user32.dll", CharSet=CharSet.Unicode, EntryPoint="ChangeDisplaySettingsExW")] static extern int ApplyAll(IntPtr name,IntPtr mode,IntPtr hwnd,uint flags,IntPtr param);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool CreateProcess(string app,StringBuilder command,IntPtr processAttributes,IntPtr threadAttributes,bool inherit,uint flags,IntPtr environment,string directory,ref Startup startup,out ProcessInfo info);
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool IsProcessInJob(IntPtr process,IntPtr job,out bool inJob);
  [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr OpenProcess(uint access,bool inherit,uint processId);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
  [DllImport("kernel32.dll")] static extern bool TerminateProcess(IntPtr process,uint code);
  static Device NewDevice() { Device d=new Device(); d.cb=Marshal.SizeOf(typeof(Device)); return d; }
  static string Pack(Mode mode) {
   IntPtr p=Marshal.AllocHGlobal(Marshal.SizeOf(typeof(Mode)));
   try { Marshal.StructureToPtr(mode,p,false); byte[] b=new byte[Marshal.SizeOf(typeof(Mode))]; Marshal.Copy(p,b,0,b.Length); return Convert.ToBase64String(b); }
   finally { Marshal.FreeHGlobal(p); }
  }
  static Mode Unpack(string data) {
   byte[] b=Convert.FromBase64String(data);
   if(b.Length!=Marshal.SizeOf(typeof(Mode))) throw new Exception("Invalid saved display mode");
   IntPtr p=Marshal.AllocHGlobal(b.Length);
   try { Marshal.Copy(b,0,p,b.Length); return (Mode)Marshal.PtrToStructure(p,typeof(Mode)); }
   finally { Marshal.FreeHGlobal(p); }
  }
  public static State[] Capture() {
   List<State> states=new List<State>();
   for(uint i=0;;i++) {
    Device d=NewDevice(); if(!EnumDisplayDevices(null,i,ref d,0)) break;
    if((d.Flags&1)==0 || (d.Flags&8)!=0) continue;
    Device monitor=NewDevice();
    if(!EnumDisplayDevices(d.Name,0,ref monitor,0)) throw new Exception("Cannot identify monitor "+d.Name);
    Mode mode=new Mode(); mode.Size=(ushort)Marshal.SizeOf(typeof(Mode));
    if(!EnumDisplaySettingsEx(d.Name,-1,ref mode,0)) throw new Exception("Cannot read mode "+d.Name);
    if(mode.DriverExtra!=0) throw new Exception("Unexpected private display mode data");
    states.Add(new State {Name=d.Name,MonitorId=monitor.Id,ModeData=Pack(mode),Primary=(d.Flags&4)!=0,Enabled=true,X=mode.X,Y=mode.Y,Width=mode.Width,Height=mode.Height});
   }
   return states.ToArray();
  }
  public static void Apply(State[] states) {
   int primary=0; foreach(State s in states) if(s.Enabled && s.Primary) primary++;
   if(primary!=1) throw new Exception("Exactly one enabled primary display is required");
   // Validate identities before staging any registry changes, including detached monitors.
   foreach(State s in states) {
    Device monitor=NewDevice();
    if(!EnumDisplayDevices(s.Name,0,ref monitor,0) || monitor.Id!=s.MonitorId) throw new Exception("Display identity changed: "+s.Name);
   }
   foreach(State s in states) {
    Mode mode=Unpack(s.ModeData); mode.X=s.X; mode.Y=s.Y; mode.Fields|=0x20;
    if(!s.Enabled) { mode.Width=0; mode.Height=0; mode.Fields=0x20|0x80000|0x100000; }
    uint flags=1|0x10000000; if(s.Primary && s.Enabled) flags|=0x10;
    int rc=ChangeDisplaySettingsEx(s.Name,ref mode,IntPtr.Zero,flags,IntPtr.Zero);
    if(rc!=0) throw new Exception("Staging display "+s.Name+" failed: "+rc);
   }
   int applied=ApplyAll(IntPtr.Zero,IntPtr.Zero,IntPtr.Zero,0,IntPtr.Zero);
   if(applied!=0) throw new Exception("Applying display layout failed: "+applied);
   State[] actual=Capture(); int enabled=0;
   foreach(State s in states) {
    if(!s.Enabled) continue; enabled++;
    State match=Array.Find(actual,a=>a.Name==s.Name);
    if(match==null || match.Primary!=s.Primary || match.X!=s.X || match.Y!=s.Y || match.Width!=s.Width || match.Height!=s.Height)
     throw new Exception("Display layout readback mismatch: "+s.Name);
   }
   if(actual.Length!=enabled) throw new Exception("Unexpected active display count");
  }
  public static uint StartIndependent(string exe,string command) {
   Startup startup=new Startup(); startup.cb=Marshal.SizeOf(typeof(Startup)); ProcessInfo info;
   // Refuse launch if Sunshine's job disallows an independently surviving recovery helper.
   if(!CreateProcess(exe,new StringBuilder(command),IntPtr.Zero,IntPtr.Zero,false,0x01000000|0x08000000,IntPtr.Zero,null,ref startup,out info)) throw new Win32Exception(Marshal.GetLastWin32Error());
   try {
    bool inJob;
    if(!IsProcessInJob(info.process,IntPtr.Zero,out inJob) || inJob) { TerminateProcess(info.process,1); throw new Exception("Recovery helper remained in a process job"); }
    return info.processId;
   } finally { CloseHandle(info.thread); CloseHandle(info.process); }
  }
  public static bool IsIndependent(uint processId) {
   IntPtr process=OpenProcess(0x400,false,processId);
   if(process==IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
   try {
    bool inJob;
    if(!IsProcessInJob(process,IntPtr.Zero,out inJob)) throw new Win32Exception(Marshal.GetLastWin32Error());
    return !inJob;
   } finally { CloseHandle(process); }
  }
 }
}
'@
}

function Write-SessionJson($Path, $Value) {
    $temporary = $Path + '.tmp'
    [IO.File]::WriteAllText($temporary, (ConvertTo-Json -InputObject $Value -Depth 8), (New-Object Text.UTF8Encoding($false)))
    if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temporary, $Path, [NullString]::Value) }
    else { [IO.File]::Move($temporary, $Path) }
}

function Convert-Layout($Layout) {
    return [PlayniteBridgeDisplay.State[]]@($Layout | ForEach-Object {
        $state = New-Object PlayniteBridgeDisplay.State
        foreach ($name in @('Name','MonitorId','ModeData','Primary','Enabled','X','Y','Width','Height')) { $state.$name = $_.$name }
        $state
    })
}

function Get-TVLayout($Layout, [string]$Target, [bool]$OnlyTV) {
    $selected = @($Layout | Where-Object Name -eq $Target)
    if ($selected.Count -ne 1) { throw 'Target monitor is not uniquely active' }
    $offsetX = $selected[0].X; $offsetY = $selected[0].Y
    $result = Convert-Layout $Layout
    foreach ($state in $result) {
        $state.X -= $offsetX; $state.Y -= $offsetY
        $state.Primary = $state.Name -eq $Target
        $state.Enabled = !$OnlyTV -or $state.Primary
    }
    return $result
}

function Remove-OwnedMarker([string]$Path, $Expected) {
    if (!$Expected -or ![IO.File]::Exists($Path)) { return }
    $current = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if ($current.game_id -eq $Expected.game_id -and $current.playnite_pid -eq $Expected.playnite_pid -and
        $current.playnite_start_ticks -eq $Expected.playnite_start_ticks) { Remove-Item -LiteralPath $Path }
}

function Test-OwnerAlive($State) {
    try {
        $owner = Get-Process -Id $State.owner_pid -ErrorAction SilentlyContinue
        return $owner -and $owner.StartTime.ToUniversalTime().Ticks.ToString() -eq $State.owner_start_ticks
    } catch { return $false } # The owner can exit between lookup and StartTime.
}

function Invoke-Recovery([string]$Path) {
    if (![IO.File]::Exists($Path)) { return }
    $initial = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if ((Get-Process -Id $PID).SessionId -ne $initial.owner_session -or
        [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne $initial.owner_user_sid -or
        ![PlayniteBridgeDisplay.Native]::IsIndependent($PID)) { throw 'Recovery helper must run independently in the same user session' }
    $expectedSession = $initial.session_id
    [IO.File]::WriteAllText($Path + '.ready', $expectedSession)
    while ([IO.File]::Exists($Path)) {
        $state = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
        if ($state.session_id -ne $expectedSession) { break }
        if (!(Test-OwnerAlive $state)) {
            [PlayniteBridgeDisplay.Native]::Apply((Convert-Layout $state.layout))
            Remove-OwnedMarker $state.marker_path $state.marker
            Remove-Item -LiteralPath $Path
            break
        }
        Start-Sleep -Milliseconds 500
    }
    if ([IO.File]::Exists($Path + '.ready') -and [IO.File]::ReadAllText($Path + '.ready') -eq $expectedSession) {
        Remove-Item -LiteralPath ($Path + '.ready')
    }
}

function Resolve-TVDisplay($Layout, [string]$MonitorId) {
    $matches = @($Layout | Where-Object { $_.MonitorId -ceq $MonitorId })
    if ($matches.Count -ne 1) { throw 'Configured monitor is not uniquely active' }
    return $matches[0].Name
}

function Start-RecoveryHelper([string]$Exe, [string]$Command) {
    try { return [PlayniteBridgeDisplay.Native]::StartIndependent($Exe, $Command) }
    catch {
        # Local WMI creates only this recovery helper outside the application's job.
        $startup = New-CimInstance -Namespace root/cimv2 -ClassName Win32_ProcessStartup -ClientOnly -Property @{ShowWindow=[uint16]0}
        $created = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine=$Command; ProcessStartupInformation=$startup}
        if ($created.ReturnValue -ne 0 -or !$created.ProcessId) { throw "Independent recovery helper creation failed: $($created.ReturnValue)" }
        $helper = Get-Process -Id $created.ProcessId -ErrorAction Stop
        if (![PlayniteBridgeDisplay.Native]::IsIndependent($created.ProcessId) -or $helper.SessionId -ne (Get-Process -Id $PID).SessionId) {
            $helper.Kill()
            throw 'WMI recovery helper did not escape the job in the same desktop session'
        }
        return [uint32]$created.ProcessId
    }
}

function Get-PlayniteLaunch([string]$Id, [bool]$BrowseMode) {
    if ($BrowseMode) {
        if ($Id) { throw 'Browse and GameId are mutually exclusive' }
        return @{game_id=$null; close_on_game_stop=$false; arguments=@('--startfullscreen','--nolibupdate')}
    }
    if ($Id -notmatch '^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$') { throw 'A canonical game GUID or explicit Browse mode is required' }
    $idValue = ([guid]$Id).ToString()
    return @{game_id=$idValue; close_on_game_stop=$true; arguments=@('--startfullscreen','--nolibupdate','--start',$idValue)}
}

function Start-PlayniteBridgeGame {
    $settings = Read-PlayniteBridgeSettings $SettingsPath
    $PlaynitePath = $settings.playnite_path
    if (!$MarkerPath) { $MarkerPath = Join-Path $settings.extension_directory 'session-marker.json' }
    $launch = Get-PlayniteLaunch $GameId ([bool]$Browse)
    if (!$MarkerPath -or ![IO.Path]::IsPathRooted($MarkerPath)) { throw 'An absolute extension session-marker.json path is required' }
    if (![IO.File]::Exists($PlaynitePath) -or [IO.Path]::GetFileName($PlaynitePath) -ne 'Playnite.FullscreenApp.exe') { throw 'Expected Playnite.FullscreenApp.exe' }
    if (@(Get-Process -Name 'Playnite.DesktopApp','Playnite.FullscreenApp' -ErrorAction SilentlyContinue).Count) { throw 'Playnite is already running; launch cancelled' }
    $directory = Split-Path -Parent $MarkerPath
    if (![IO.Directory]::Exists($directory)) { throw 'Marker directory must already exist' }
    $statePath = Join-Path $directory 'playnitebridge-display-recovery.json'
    $lock = [IO.File]::Open((Join-Path $directory 'playnitebridge-display.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    $changed = $false; $state = $null; $playnite = $null
    try {
        if ([IO.File]::Exists($statePath) -or [IO.File]::Exists($MarkerPath)) { throw 'Previous session state exists; recover/inspect it before launching' }
        $layout = [PlayniteBridgeDisplay.Native]::Capture()
        $target = Resolve-TVDisplay $layout $settings.monitor_id
        $next = Get-TVLayout $layout $target ([bool]$TvOnly)
        $owner = Get-Process -Id $PID
        $state = @{session_id=[guid]::NewGuid().ToString(); owner_pid=$PID; owner_start_ticks=$owner.StartTime.ToUniversalTime().Ticks.ToString();
                   owner_session=$owner.SessionId; owner_user_sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;
                   layout=@($layout); marker_path=$MarkerPath; marker=$null}
        Write-SessionJson $statePath $state
        $exe = Join-Path $PSHOME 'powershell.exe'
        foreach ($path in @($exe,$PSCommandPath,$statePath)) { if ($path.Contains('"') -or $path.Contains("`n") -or $path.Contains("`r")) { throw 'Unsupported quote/newline in helper path' } }
        $command = '"' + $exe + '" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $PSCommandPath + '" -RecoverPath "' + $statePath + '"'
        $watcherId = Start-RecoveryHelper $exe $command
        $deadline = [datetime]::UtcNow.AddSeconds(15)
        while (![IO.File]::Exists($statePath + '.ready') -or [IO.File]::ReadAllText($statePath + '.ready') -ne $state.session_id) {
            if ([datetime]::UtcNow -gt $deadline -or !(Get-Process -Id $watcherId -ErrorAction SilentlyContinue)) { throw 'Independent recovery helper did not become ready' }
            Start-Sleep -Milliseconds 100
        }
        $changed = $true
        [PlayniteBridgeDisplay.Native]::Apply($next)
        if ($TestLayout) { Start-Sleep -Seconds 5; return }
        if (@(Get-Process -Name 'Playnite.DesktopApp','Playnite.FullscreenApp' -ErrorAction SilentlyContinue).Count) { throw 'Playnite started concurrently; launch cancelled' }
        # Playnite's documented --start accepts the library GUID, not a command string.
        $playnite = Start-Process -FilePath $PlaynitePath -WorkingDirectory (Split-Path -Parent $PlaynitePath) -ArgumentList $launch.arguments -PassThru
        $marker = @{game_id=$launch.game_id; playnite_pid=$playnite.Id;
                    playnite_start_ticks=$playnite.StartTime.ToUniversalTime().Ticks.ToString(); close_on_game_stop=$launch.close_on_game_stop}
        $state.marker = $marker
        Write-SessionJson $statePath $state
        Write-SessionJson $MarkerPath $marker
        $playnite.WaitForExit()
    } finally {
        try {
            if ($changed) { [PlayniteBridgeDisplay.Native]::Apply((Convert-Layout $state.layout)) }
            if ($state) {
                Remove-OwnedMarker $MarkerPath $state.marker
                if ([IO.File]::Exists($statePath)) { Remove-Item -LiteralPath $statePath }
            }
        } finally { $lock.Dispose() }
    }
}

function Test-PlayniteBridgeHost {
    if ([Runtime.InteropServices.Marshal]::SizeOf([type][PlayniteBridgeDisplay.Mode]) -ne 220) { throw 'DEVMODEW layout mismatch' }
    if ([Runtime.InteropServices.Marshal]::SizeOf([type][PlayniteBridgeDisplay.Device]) -ne 840) { throw 'DISPLAY_DEVICEW layout mismatch' }
    $layout = Convert-Layout @(
        @{Name='PC';MonitorId='PC';ModeData='';Primary=$true;Enabled=$true;X=0;Y=0;Width=3440;Height=1440},
        @{Name='TV';MonitorId='TV';ModeData='';Primary=$false;Enabled=$true;X=-3840;Y=100;Width=3840;Height=2160})
    $next = Get-TVLayout $layout 'TV' $false
    if ($next[0].X -ne 3840 -or $next[0].Y -ne -100 -or $next[0].Primary -or !$next[0].Enabled -or
        $next[1].X -ne 0 -or $next[1].Y -ne 0 -or !$next[1].Primary -or $layout[0].X -ne 0) { throw 'Primary translation or source preservation failed' }
    $only = Get-TVLayout $layout 'TV' $true
    if ($only[0].Enabled -or !$only[1].Enabled -or $only[1].Width -ne 3840 -or $only[1].Height -ne 2160) { throw 'TV-only layout failed' }
    $temporary = Join-Path ([IO.Path]::GetTempPath()) ('playnitebridge-marker-' + [guid]::NewGuid() + '.json')
    try {
        $owner = @{game_id='test';playnite_pid=10;playnite_start_ticks='123'}
        Write-SessionJson $temporary $owner
        Remove-OwnedMarker $temporary @{game_id='other';playnite_pid=10;playnite_start_ticks='123'}
        if (![IO.File]::Exists($temporary)) { throw 'Removed foreign marker' }
        Remove-OwnedMarker $temporary $owner
        if ([IO.File]::Exists($temporary)) { throw 'Owned marker not removed' }
    } finally { if ([IO.File]::Exists($temporary)) { Remove-Item -LiteralPath $temporary } }
    Write-Output 'PASS: native struct sizes, primary translation, TV-only selection, preserved original layout, marker ownership. No display APIs invoked.'
}

if ($LibraryOnly) { return }
if ($SelfTest) { Test-PlayniteBridgeHost }
elseif ($RecoverPath) { Invoke-Recovery $RecoverPath }
else { Start-PlayniteBridgeGame }

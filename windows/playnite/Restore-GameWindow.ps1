param([Parameter(Mandatory=$true)][int]$GameProcessId)
$ErrorActionPreference = 'Stop'
if ($GameProcessId -le 0) { return }
$origin = Get-Process -Id $GameProcessId -ErrorAction SilentlyContinue
if (!$origin) { return }
$session = $origin.SessionId
$known = @{$GameProcessId = $origin.StartTime.ToUniversalTime().Ticks}
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class SpaceTVGameWindow {
 [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr window, int command);
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
}
'@
# Allow Playnite's minimise-after-launch action to finish before restoring the game.
Start-Sleep -Seconds 3
$deadline = [datetime]::UtcNow.AddSeconds(45)
while ([datetime]::UtcNow -lt $deadline) {
    $processes = @(Get-CimInstance Win32_Process -Filter "SessionId=$session")
    foreach ($child in $processes) {
        if ($known.ContainsKey([int]$child.ParentProcessId) -and !$known.ContainsKey([int]$child.ProcessId)) {
            $parent = Get-Process -Id $child.ParentProcessId -ErrorAction SilentlyContinue
            if ($parent -and $parent.StartTime.ToUniversalTime().Ticks -eq $known[[int]$child.ParentProcessId]) {
                $childProcess = Get-Process -Id $child.ProcessId -ErrorAction SilentlyContinue
                if ($childProcess) { $known[[int]$child.ProcessId] = $childProcess.StartTime.ToUniversalTime().Ticks }
            }
        }
    }
    foreach ($ident in @($known.Keys)) {
        $game = Get-Process -Id $ident -ErrorAction SilentlyContinue
        if (!$game -or $game.StartTime.ToUniversalTime().Ticks -ne $known[$ident]) { continue }
        if ($game.MainWindowHandle -ne 0) {
            $null = [SpaceTVGameWindow]::ShowWindowAsync($game.MainWindowHandle, 9)
            $null = [SpaceTVGameWindow]::SetForegroundWindow($game.MainWindowHandle)
            return
        }
    }
    Start-Sleep -Milliseconds 500
}

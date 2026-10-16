$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Start-PlayniteBridgeGame.ps1') -LibraryOnly
function Assert($value, $message) { if (!$value) { throw $message } }
$browseLaunch = Get-PlayniteLaunch '' $true
Assert (($browseLaunch.arguments -join ' ') -eq '--startfullscreen --nolibupdate') 'Browse must not start a specific game'
Assert (!$browseLaunch.close_on_game_stop -and $null -eq $browseLaunch.game_id) 'Browse marker must keep library open after game exit'
$gameIdValue = '00000000-0000-0000-0000-000000000001'
$gameLaunch = Get-PlayniteLaunch $gameIdValue $false
Assert (($gameLaunch.arguments -join ' ') -eq ('--startfullscreen --nolibupdate --start ' + $gameIdValue)) 'Direct launch arguments changed'
Assert $gameLaunch.close_on_game_stop 'Direct launch must still close after its game'
foreach ($case in @(@($gameIdValue,$true), @('',$false), @('bad',$false))) {
    $failed = $false
    try { Get-PlayniteLaunch $case[0] $case[1] | Out-Null } catch { $failed = $true }
    Assert $failed 'Invalid or ambiguous mode was accepted'
}
$markerFile = Join-Path ([IO.Path]::GetTempPath()) ('playnitebridge-browse-test-' + [guid]::NewGuid() + '.json')
try {
    $owner = @{game_id=$null;playnite_pid=42;playnite_start_ticks='123';close_on_game_stop=$false}
    Write-SessionJson $markerFile $owner
    Remove-OwnedMarker $markerFile @{game_id=$null;playnite_pid=43;playnite_start_ticks='123'}
    Assert ([IO.File]::Exists($markerFile)) 'Browse must preserve a different process marker'
    Remove-OwnedMarker $markerFile $owner
    Assert (![IO.File]::Exists($markerFile)) 'Owned browse marker must be cleaned up'
} finally { if ([IO.File]::Exists($markerFile)) { Remove-Item -LiteralPath $markerFile } }
Write-Output 'PASS: browse/direct arguments, mode validation, browse marker lifetime and cleanup. No display or process launch.'

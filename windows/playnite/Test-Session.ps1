$ErrorActionPreference = 'Stop'
$module = Import-Module (Join-Path $PSScriptRoot 'PlayniteBridgeCatalogue.psm1') -Force -PassThru
& $module {
    function Assert($value, $message) { if (!$value) { throw $message } }
    $directory = Join-Path $PSScriptRoot ('test-output-' + [guid]::NewGuid())
    $null = [IO.Directory]::CreateDirectory($directory)
    $path = Join-Path $directory 'session-marker.json'
    $id = [guid]::NewGuid()
    $event = [pscustomobject]@{Game=[pscustomobject]@{Id=$id}}
    $api = [pscustomobject]@{Database=[pscustomobject]@{Games=@()}}
    $script:closes = 0
    function Request-PlayniteBridgeShutdown($Api) { $script:closes++ }
    function Check { Complete-PlayniteBridgeSession $event $api $path 42 '12345' }
    Check
    Assert ($script:closes -eq 0) 'No marker must not close ordinary Playnite'
    $marker = @{game_id=$id.ToString();playnite_pid=42;playnite_start_ticks='12345';close_on_game_stop=$true}
    foreach ($field in @('game_id','playnite_pid','playnite_start_ticks','close_on_game_stop')) {
        $bad = $marker.Clone()
        switch ($field) {
            game_id { $bad[$field] = [guid]::NewGuid().ToString() }
            playnite_pid { $bad[$field] = 43 }
            playnite_start_ticks { $bad[$field] = '12346' }
            close_on_game_stop { $bad[$field] = 'true' }
        }
        $bad | ConvertTo-Json | Set-Content -LiteralPath $path
        Check
    }
    Assert ($script:closes -eq 0) 'Mismatched session identity must not close'
    $marker | ConvertTo-Json | Set-Content -LiteralPath $path
    $event | Add-Member NoteProperty ManuallyStopped $true
    Check
    Assert ($script:closes -eq 0) 'Manual tracking stop must not close a possibly running game'
    $event.ManuallyStopped = $false
    $api.Database.Games = @([pscustomobject]@{Id=[guid]::NewGuid();IsRunning=$true})
    Check
    Assert ($script:closes -eq 0) 'Another running game must prevent shutdown'
    $api.Database.Games = @()
    Check
    Assert ($script:closes -eq 1) 'Matching owned session must request shutdown'
    $script:order = @()
    function Update-PlayniteBridgeCatalogue { $script:order += 'export-sync' }
    function Complete-PlayniteBridgeSession($EventArgs) { $script:order += 'shutdown' }
    OnGameStopped $event
    Assert (($script:order -join ',') -eq 'export-sync,shutdown') 'Export/sync must precede shutdown'
    $script:owned = $false
    $script:focusLaunches = @()
    function Test-PlayniteBridgeProcessMarker { return $script:owned }
    function Start-Process($FilePath, $WindowStyle, $ArgumentList) {
        Assert ($WindowStyle -eq 'Hidden') 'Focus helper must not show a console'
        $script:focusLaunches += ,$ArgumentList
    }
    $started = [pscustomobject]@{StartedProcessId=123}
    OnGameStarted $started
    Assert ($script:focusLaunches.Count -eq 0) 'Normal desktop Playnite must not steal focus'
    $script:owned = $true
    OnGameStarted ([pscustomobject]@{StartedProcessId=0})
    Assert ($script:focusLaunches.Count -eq 0) 'Invalid process must not start focus helper'
    OnGameStarted $started
    Assert ($script:focusLaunches.Count -eq 1 -and $script:focusLaunches[0][-1] -eq '123') 'Owned game launch must restore its exact process'
}
Write-Output 'PASS: session identity guards, other-game protection, export-before-exit ordering'

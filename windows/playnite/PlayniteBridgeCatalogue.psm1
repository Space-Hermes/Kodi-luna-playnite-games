function Export-PlayniteBridgeCatalogue {
    param($Api = $PlayniteApi, [string]$OutputDirectory = (Join-Path $PSScriptRoot 'catalogue'))
    $ErrorActionPreference = 'Stop'
    [System.IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null
    $artworkDirectory = Join-Path $OutputDirectory 'artwork'
    [System.IO.Directory]::CreateDirectory($artworkDirectory) | Out-Null
    $games = @(foreach ($game in $Api.Database.Games) {
        $id = ([guid]$game.Id).ToString()
        $cover = $null
        if ($game.CoverImage -and $game.CoverImage -notmatch '^https?://') {
            $source = $Api.Database.GetFullFilePath($game.CoverImage)
            if ($source -and [System.IO.File]::Exists($source)) {
                $extension = [System.IO.Path]::GetExtension($source).ToLowerInvariant()
                if ($extension -in @('.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp')) {
                    $cover = 'artwork/' + $id + $extension
                    $destination = Join-Path $OutputDirectory $cover
                    $temporaryCover = $destination + '.tmp'
                    try {
                        [System.IO.File]::Copy($source, $temporaryCover, $true)
                        if ([System.IO.File]::Exists($destination)) {
                            [System.IO.File]::Replace($temporaryCover, $destination, [NullString]::Value)
                        } else {
                            [System.IO.File]::Move($temporaryCover, $destination)
                        }
                    } finally {
                        if ([System.IO.File]::Exists($temporaryCover)) { [System.IO.File]::Delete($temporaryCover) }
                    }
                }
            }
        }
        $lastActivity = $null
        if ($game.LastActivity) { $lastActivity = ([datetime]$game.LastActivity).ToString('o') }
        [ordered]@{
            id = $id; name = $game.Name; installed = [bool]$game.IsInstalled
            favourite = [bool]$game.Favorite; hidden = [bool]$game.Hidden
            last_activity = $lastActivity; playtime_seconds = [uint64]$game.Playtime
            play_count = [uint64]$game.PlayCount; cover = $cover
        }
    })
    $document = [ordered]@{
        schema_version = 1
        generated_at = [datetime]::UtcNow.ToString('o')
        games = $games
    }
    $json = ConvertTo-Json -InputObject $document -Depth 5
    $null = ConvertFrom-Json -InputObject $json
    $destination = Join-Path $OutputDirectory 'catalogue.json'
    $temporary = $destination + '.tmp'
    try {
        [System.IO.File]::WriteAllText($temporary, $json, (New-Object System.Text.UTF8Encoding($false)))
        if ([System.IO.File]::Exists($destination)) {
            [System.IO.File]::Replace($temporary, $destination, [NullString]::Value)
        } else {
            [System.IO.File]::Move($temporary, $destination)
        }
    } finally {
        if ([System.IO.File]::Exists($temporary)) { [System.IO.File]::Delete($temporary) }
    }
}

function Test-PlayniteBridgeProcessMarker([string]$Path = (Join-Path $PSScriptRoot 'session-marker.json')) {
    if (!(Test-Path -LiteralPath $Path)) { return $false }
    $marker = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    return ($marker.close_on_game_stop -is [bool] -and
        $marker.playnite_pid -eq $PID -and
        $marker.playnite_start_ticks -ceq ([Diagnostics.Process]::GetCurrentProcess().StartTime.ToUniversalTime().Ticks.ToString()))
}

function Start-IndependentPlayniteBridgeSync([string]$Worker) {
    $exe = Join-Path $PSHOME 'powershell.exe'
    foreach ($path in @($exe, $Worker)) {
        if ($path.Contains('"') -or $path.Contains("`n") -or $path.Contains("`r")) { throw 'Unsupported sync worker path' }
    }
    $command = '"' + $exe + '" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $Worker + '"'
    # Local WMI owns this worker, so Sunshine's application job cannot terminate it.
    $startup = New-CimInstance -Namespace root/cimv2 -ClassName Win32_ProcessStartup -ClientOnly -Property @{ShowWindow=[uint16]0}
    $created = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine=$command; ProcessStartupInformation=$startup}
    if ($created.ReturnValue -ne 0 -or !$created.ProcessId) { throw "Independent sync creation failed: $($created.ReturnValue)" }
    $helper = Get-CimInstance -ClassName Win32_Process -Filter ('ProcessId=' + [uint32]$created.ProcessId)
    if (!$helper) { throw 'Independent sync worker exited before identity verification' }
    $owner = Invoke-CimMethod -InputObject $helper -MethodName GetOwnerSid
    if ($owner.ReturnValue -ne 0 -or $owner.Sid -ne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -or
        $helper.SessionId -ne ([Diagnostics.Process]::GetCurrentProcess().SessionId)) {
        $null = Invoke-CimMethod -InputObject $helper -MethodName Terminate
        throw 'Independent sync worker user/session mismatch'
    }
}

function Update-PlayniteBridgeCatalogue {
    try {
        Export-PlayniteBridgeCatalogue
        Request-PlayniteBridgeRegistration
        if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'sync-config.json')) {
            $worker = Join-Path $PSScriptRoot 'Sync-Catalogue.ps1'
            if (Test-PlayniteBridgeProcessMarker) { Start-IndependentPlayniteBridgeSync $worker }
            else {
                Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -WindowStyle Hidden -ArgumentList @(
                    '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $worker + '"')) | Out-Null
            }
        }
    } catch { Write-Warning ('PlayniteBridge catalogue export/sync start failed: ' + $_.Exception.Message) }
}

function Request-PlayniteBridgeRegistration {
    if (!(Test-Path -LiteralPath (Join-Path $PSScriptRoot 'registration-enabled'))) { return }
    try {
        $null = & "$env:WINDIR\System32\schtasks.exe" /Run /TN 'PlayniteBridge Update Games' 2>&1
        if ($LASTEXITCODE -ne 0) { throw 'Windows registration task did not start' }
    } catch { Write-Warning ('PlayniteBridge game registration pending: ' + $_.Exception.Message) }
}

function OnApplicationStarted { param($eventArgs) Update-PlayniteBridgeCatalogue }
function OnLibraryUpdated { param($eventArgs) Update-PlayniteBridgeCatalogue }
function OnGameInstalled { param($eventArgs) Update-PlayniteBridgeCatalogue }
function OnGameUninstalled { param($eventArgs) Update-PlayniteBridgeCatalogue }
function Complete-PlayniteBridgeSession {
    param($EventArgs, $Api = $PlayniteApi,
        [string]$MarkerPath = (Join-Path $PSScriptRoot 'session-marker.json'),
        [int]$ProcessId = $PID,
        [string]$ProcessStartTicks = ([Diagnostics.Process]::GetCurrentProcess().StartTime.ToUniversalTime().Ticks.ToString()))
    if (!(Test-Path -LiteralPath $MarkerPath)) { return }
    if ($EventArgs.ManuallyStopped) { return }
    try {
        $marker = Get-Content -LiteralPath $MarkerPath -Raw | ConvertFrom-Json
        if ($marker.close_on_game_stop -isnot [bool] -or !$marker.close_on_game_stop) { return }
        if ($marker.playnite_pid -ne $ProcessId -or $marker.playnite_start_ticks -cne $ProcessStartTicks) { return }
        if ([guid]$marker.game_id -ne [guid]$EventArgs.Game.Id) { return }
        if (@($Api.Database.Games | Where-Object { $_.IsRunning -and $_.Id -ne $EventArgs.Game.Id }).Count) { return }
        Request-PlayniteBridgeShutdown $Api
    } catch { Write-Warning ('PlayniteBridge session completion failed: ' + $_.Exception.Message) }
}

function Request-PlayniteBridgeShutdown($Api) {
    # A CLR delegate avoids running a PowerShell scriptblock on a foreign UI thread.
    $application = [System.Windows.Application]::Current
    if (!$application) { throw 'Playnite WPF application is unavailable' }
    $method = $application.GetType().GetMethod('Shutdown', [type[]]@())
    $action = [Delegate]::CreateDelegate([Action], $application, $method)
    $null = $Api.MainView.UIDispatcher.BeginInvoke($action)
}

function OnGameStopped {
    param($eventArgs)
    Update-PlayniteBridgeCatalogue
    Complete-PlayniteBridgeSession $eventArgs
}

function GetMainMenuItems {
    param($eventArgs)
    $item = New-Object Playnite.SDK.Plugins.ScriptMainMenuItem
    $item.Description = 'Export PlayniteBridge catalogue'
    $item.FunctionName = 'Update-PlayniteBridgeCatalogue'
    $item.MenuSection = '@PlayniteBridge'
    return $item
}

# Playnite invokes exported CommandInfo objects; their helper calls must also resolve in its runspace.
Export-ModuleMember -Function Export-PlayniteBridgeCatalogue, Update-PlayniteBridgeCatalogue, OnApplicationStarted, OnLibraryUpdated, OnGameInstalled, OnGameUninstalled, OnGameStopped, GetMainMenuItems, Test-PlayniteBridgeProcessMarker, Start-IndependentPlayniteBridgeSync, Complete-PlayniteBridgeSession, Request-PlayniteBridgeShutdown, Request-PlayniteBridgeRegistration


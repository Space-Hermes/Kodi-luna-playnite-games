$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Build-Apps.ps1') -LibraryOnly
function Assert($value,$message) { if (!$value) { throw $message } }
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('playnitebridge-settings-' + [guid]::NewGuid())
$null = [IO.Directory]::CreateDirectory($fixture)
try {
    $exe = Join-Path $fixture 'Playnite.FullscreenApp.exe'
    [IO.File]::WriteAllText($exe,'test fixture, never execute')
    $configPath = Join-Path $fixture 'settings.json'
    $config = @{playnite_path=$exe;extension_directory=$fixture;monitor_id='MONITOR\TEST\IDENTITY'}
    $config | ConvertTo-Json | Set-Content -LiteralPath $configPath
    $read = Read-PlayniteBridgeSettings $configPath
    Assert ($read.monitor_id -eq $config.monitor_id) 'Monitor identity changed'
    $config.playnite_path = 'relative.exe'
    $config | ConvertTo-Json | Set-Content -LiteralPath $configPath
    $failed=$false; try { Read-PlayniteBridgeSettings $configPath } catch { $failed=$true }
    Assert $failed 'Relative executable accepted'
    $original = @{env=@{keep='yes'};apps=@(@{name='Desktop';cmd='original'})}
    $catalogue = @{schema_version=1;games=@(@{id='11111111-2222-3333-4444-555555555555';installed=$true;hidden=$false})}
    $built = New-PlayniteBridgeApps $original $catalogue (Join-Path $fixture 'wrapper.ps1') $configPath
    Assert ($built.apps.Count -eq 3 -and $built.apps[0].cmd -eq 'original') 'Builder lost original apps'
    Assert ($built.apps[1].cmd -like '*-Browse -TvOnly' -and $built.apps[2].cmd -like '*-GameId 11111111-2222-3333-4444-555555555555 -TvOnly') 'Generated selectors incorrect'
    Assert (!$built.apps[1].elevated -and !$built.apps[2].elevated) 'Generated apps must be unelevated'
} finally { [IO.Directory]::Delete($fixture,$true) }
Write-Output 'PASS: portable settings validation and manual app generation; no processes launched'

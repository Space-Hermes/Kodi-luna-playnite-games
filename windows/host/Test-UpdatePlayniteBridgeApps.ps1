$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Update-PlayniteBridgeApps.ps1') -LibraryOnly
$script:Registration = @{wrapper_path='C:\test\Start-PlayniteBridgeGame.ps1';settings_path='C:\test\settings.json'}
function Assert($Condition, $Message) { if (!$Condition) { throw $Message } }
$id = '11111111-2222-3333-4444-555555555555'
$original = '{"env":{"keep":"yes"},"apps":[{"name":"Desktop","cmd":""},{"name":"PlayniteBridge-old","cmd":"old"}]}' | ConvertFrom-Json
$catalogue = @{schema_version=1; games=@(@{id=$id; hidden=$false; installed=$true}, @{id=$id; hidden=$false; installed=$true})}
$new = New-PlayniteBridgeApps $original $catalogue
Assert ($new.apps.Count -eq 3) 'Build/deduplication failed'
Assert ($new.env.keep -eq 'yes' -and $new.apps[0].name -eq 'Desktop') 'Preservation failed'
Assert ($new.apps[2].cmd.Contains('-GameId ' + $id) -and !$new.apps[2].elevated) 'Command incorrect'
foreach ($bad in @(@{schema_version=2; games=@()}, @{schema_version=1; games=@(@{id='x; bad';hidden=$false;installed=$true})}, @{schema_version=1; games=@(@{id=$id;hidden='false';installed=$true})})) {
    $rejected = $false; try { New-PlayniteBridgeApps $original $bad | Out-Null } catch { $rejected = $true }; Assert $rejected 'Invalid catalogue accepted'
}
$folder = Join-Path ([IO.Path]::GetTempPath()) ('playnitebridge-updater-test-' + [guid]::NewGuid())
$null = [IO.Directory]::CreateDirectory($folder)
$path = Join-Path $folder 'apps.json'
$script:idle = $false; $script:restarts = 0; $script:failFirst = $false
function Test-SunshineIdle { return $script:idle }
function Restart-PlayniteBridgeSunshine { $script:restarts++; if ($script:failFirst -and $script:restarts -eq 1) { throw 'Mock restart failure' } }
try {
    $original | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $path
    $before = [IO.File]::ReadAllText($path)
    Assert ((Invoke-PlayniteBridgeAppUpdate $path $catalogue) -eq 'deferred-active') 'Active not deferred'
    Assert ([IO.File]::ReadAllText($path) -ceq $before) 'Active state mutated'
    $script:idle = $true
    Assert ((Invoke-PlayniteBridgeAppUpdate $path $catalogue) -eq 'updated') 'Update failed'
    Assert ($script:restarts -eq 1) 'Restart missing'
    Assert ((Invoke-PlayniteBridgeAppUpdate $path $catalogue) -eq 'unchanged') 'Unchanged not detected'
    Assert ($script:restarts -eq 1) 'Unchanged restarted'
    [IO.File]::WriteAllText($path, $before)
    $script:restarts = 0; $script:failFirst = $true
    $rejected = $false; try { Invoke-PlayniteBridgeAppUpdate $path $catalogue | Out-Null } catch { $rejected = $true }
    Assert ($rejected -and $script:restarts -eq 2) 'Failed restart did not recover'
    Assert ([IO.File]::ReadAllText($path) -ceq $before) 'Rollback failed'
    Write-Output 'PASS: build/dedupe, validation, preservation, active deferral, update, unchanged, rollback'
} finally { [IO.Directory]::Delete($folder, $true) }

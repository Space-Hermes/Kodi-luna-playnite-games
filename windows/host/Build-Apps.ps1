param([string]$SettingsPath = (Join-Path $PSScriptRoot 'settings.json'),
      [string]$ExistingApps, [string]$OutputPath, [switch]$LibraryOnly)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Settings.ps1')

function New-PlayniteBridgeApps($Original, $Catalogue, [string]$Wrapper, [string]$SettingsFile) {
    if ($Catalogue.schema_version -ne 1 -or $Catalogue.games -isnot [array] -or $Original.apps -isnot [array]) { throw 'Invalid input schema' }
    foreach ($path in @($Wrapper,$SettingsFile)) {
        if (![IO.Path]::IsPathRooted($path) -or $path -match '["\r\n]') { throw 'Invalid command path' }
    }
    $ids = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($game in $Catalogue.games) {
        if ($game.id -isnot [string] -or $game.id -cnotmatch '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' -or
            $game.hidden -isnot [bool] -or $game.installed -isnot [bool]) { throw 'Invalid catalogue game' }
        if (!$game.hidden -and $game.installed) { $null = $ids.Add($game.id) }
    }
    $copy = $Original | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $apps = @($Original.apps | Where-Object { $_.name -notlike 'PlayniteBridge-*' })
    foreach ($id in @('Playnite') + @($ids | Sort-Object)) {
        $selector = if ($id -eq 'Playnite') { '-Browse' } else { '-GameId ' + $id }
        $apps += [pscustomobject]@{name=('PlayniteBridge-' + $id); cmd=('"' + $env:WINDIR + '\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $Wrapper + '" -SettingsPath "' + $SettingsFile + '" ' + $selector + ' -TvOnly');
            'auto-detach'=$false; 'wait-all'=$false; 'exit-timeout'=10; elevated=$false; 'image-path'=''}
    }
    $copy.apps = $apps
    return $copy
}

if ($LibraryOnly) { return }
$settings = Read-PlayniteBridgeSettings $SettingsPath
if (!$ExistingApps -or !$OutputPath -or [IO.Path]::GetFullPath($ExistingApps) -eq [IO.Path]::GetFullPath($OutputPath)) { throw 'Provide different input and output files; live replacement is not supported' }
if (Test-Path -LiteralPath $OutputPath) { throw 'Output already exists; use a new output filename' }
$original = Get-Content -LiteralPath $ExistingApps -Raw | ConvertFrom-Json
$catalogue = Get-Content -LiteralPath (Join-Path $settings.extension_directory 'catalogue/catalogue.json') -Raw | ConvertFrom-Json
$updated = New-PlayniteBridgeApps $original $catalogue (Join-Path $PSScriptRoot 'Start-PlayniteBridgeGame.ps1') ([IO.Path]::GetFullPath($SettingsPath))
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath), ($updated | ConvertTo-Json -Depth 30), (New-Object Text.UTF8Encoding($false)))

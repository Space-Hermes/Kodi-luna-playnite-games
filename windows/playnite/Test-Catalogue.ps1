$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'PlayniteBridgeCatalogue.psm1') -Force
function Assert($condition, $message) { if (!$condition) { throw $message } }
$testRoot = Join-Path $PSScriptRoot ('test-output-' + [guid]::NewGuid())
[System.IO.Directory]::CreateDirectory($testRoot) | Out-Null
$coverFile = Join-Path $testRoot 'source.png'
[System.IO.File]::WriteAllBytes($coverFile, [byte[]]@(1, 2, 3))
$database = [pscustomobject]@{ Games = @(); CoverPath = $coverFile }
$database | Add-Member ScriptMethod GetFullFilePath { param($reference) if ($reference -eq 'cover') { return $this.CoverPath }; return $null }
$api = [pscustomobject]@{ Database = $database }
$outputDirectory = Join-Path $testRoot 'export'
$catalogue = Join-Path $outputDirectory 'catalogue.json'
function Read-Catalogue { ConvertFrom-Json ([System.IO.File]::ReadAllText($catalogue)) }
Export-PlayniteBridgeCatalogue -Api $api -OutputDirectory $outputDirectory
$result = Read-Catalogue
Assert ($result.games -is [array] -and $result.games.Count -eq 0) 'Empty games must be an array'
$game = [pscustomobject]@{
    Id = [guid]::NewGuid(); Name = ('Pok' + [char]0x00e9 + 'mon ' + [char]0x65e5)
    IsInstalled = $true; Favorite = $true; Hidden = $false; LastActivity = $null
    Playtime = 60; PlayCount = 1; CoverImage = 'cover'
}
$database.Games = @($game)
Export-PlayniteBridgeCatalogue -Api $api -OutputDirectory $outputDirectory
$result = Read-Catalogue
Assert ($result.games -is [array] -and $result.games.Count -eq 1) 'Single game must be an array'
Assert ($result.games[0].name -eq $game.Name) 'Unicode roundtrip'
Assert ($result.games[0].last_activity -eq $null) 'Missing date must be null'
Assert ($result.games[0].playtime_seconds -eq 60) 'Playtime stays in seconds'
Assert ([System.IO.File]::Exists((Join-Path $outputDirectory $result.games[0].cover))) 'Cover copied'
$firstCover = $result.games[0].cover
$missing = $game.PSObject.Copy(); $missing.Id = [guid]::NewGuid(); $missing.CoverImage = 'missing'
$remote = $game.PSObject.Copy(); $remote.Id = [guid]::NewGuid(); $remote.CoverImage = 'https://example.invalid/art.jpg'
$remote.IsInstalled = $false; $remote.Hidden = $true; $remote.LastActivity = [datetime]'2026-10-16T12:00:00Z'
$database.Games = @($game, $missing, $remote)
Export-PlayniteBridgeCatalogue -Api $api -OutputDirectory $outputDirectory
$result = Read-Catalogue
Assert ($result.games.Count -eq 3) 'All games included'
Assert ($result.games[0].cover -eq $firstCover) 'Stable cover name'
Assert ($null -eq $result.games[1].cover -and $null -eq $result.games[2].cover) 'Missing/remote artwork skipped'
Assert ($result.games[2].hidden -and !$result.games[2].installed) 'Flags retained'
$lastGood = [System.IO.File]::ReadAllText($catalogue)
$missing.Id = 'not-a-guid'
$failed = $false
try { Export-PlayniteBridgeCatalogue -Api $api -OutputDirectory $outputDirectory } catch { $failed = $true }
Assert $failed 'Invalid data fails export'
Assert ([System.IO.File]::ReadAllText($catalogue) -ceq $lastGood) 'Last good catalogue retained'
Write-Output ('PASS: zero/one/many games, Unicode, artwork, flags, stable names, failure preservation. Fixtures: ' + $testRoot)

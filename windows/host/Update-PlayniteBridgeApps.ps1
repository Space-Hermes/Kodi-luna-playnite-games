param([switch]$LibraryOnly)
$ErrorActionPreference = 'Stop'

function Read-RegistrationConfig([string]$Path) {
    Assert-NoReparse $Path
    $config = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    foreach ($field in @('apps_path','catalogue_path','wrapper_path','settings_path')) {
        $value = $config.$field
        if ($value -isnot [string] -or $value -notmatch '^[A-Za-z]:\\' -or $value -match '["\r\n]') { throw "Invalid registration path: $field" }
        Assert-NoReparse $value
        if (![IO.File]::Exists($value)) { throw "Missing registration file: $field" }
    }
    $fixedApps = Join-Path $env:ProgramFiles 'Sunshine\config\apps.json'
    if ([IO.Path]::GetFullPath($config.apps_path) -ine [IO.Path]::GetFullPath($fixedApps)) { throw 'Automatic registration supports only the default Program Files Sunshine installation' }
    Assert-ProtectedSunshine $fixedApps
    return $config
}

function Assert-AdministratorOwned([string]$Path) {
    Assert-NoReparse $Path
    $acl = Get-Acl -LiteralPath $Path
    $trusted = @('S-1-5-18','S-1-5-32-544','S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')
    if ($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -notin $trusted) { throw "Untrusted owner: $Path" }
    $writeMask = [Security.AccessControl.FileSystemRights]'Write,Delete,DeleteSubdirectoriesAndFiles,ChangePermissions,TakeOwnership'
    foreach ($rule in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])) {
        if ($rule.AccessControlType -eq 'Allow' -and $rule.IdentityReference.Value -notin $trusted -and
            ($rule.FileSystemRights -band $writeMask)) { throw "Non-administrator write access: $Path" }
    }
}

function Assert-ProtectedSunshine([string]$AppsPath) {
    Assert-AdministratorOwned (Join-Path $env:ProgramFiles 'Sunshine')
    Assert-AdministratorOwned (Split-Path -Parent $AppsPath)
    Assert-AdministratorOwned $AppsPath
    foreach ($sidecar in @($AppsPath + '.playnitebridge-new', $AppsPath + '.playnitebridge-backup')) {
        if (Test-Path -LiteralPath $sidecar) { Assert-AdministratorOwned $sidecar }
    }
}

function ConvertTo-StableJson($Value) {
    function Order-Value($v) {
        if ($null -eq $v) { return $null }
        if ($v -is [System.Collections.IDictionary]) {
            $o = [ordered]@{}; foreach ($k in @($v.Keys | Sort-Object)) { $o[$k] = Order-Value $v[$k] }; return $o
        }
        if ($v -is [pscustomobject]) {
            $o = [ordered]@{}; foreach ($p in @($v.PSObject.Properties | Sort-Object Name)) { $o[$p.Name] = Order-Value $p.Value }; return $o
        }
        if ($v -is [array]) { return ,@(foreach ($item in $v) { Order-Value $item }) }
        return $v
    }
    ConvertTo-Json -InputObject (Order-Value $Value) -Depth 30 -Compress
}

function New-PlayniteBridgeApps($Original, $Catalogue) {
    if ($Catalogue.schema_version -isnot [int] -or $Catalogue.schema_version -ne 1 -or $Catalogue.games -isnot [array]) { throw 'Invalid catalogue schema' }
    if ($Original.apps -isnot [array] -or $null -eq $Original.env) { throw 'Invalid Sunshine applications document' }
    $ids = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($game in $Catalogue.games) {
        if ($game.id -isnot [string] -or $game.id -cnotmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' -or
            $game.hidden -isnot [bool] -or $game.installed -isnot [bool]) { throw 'Invalid catalogue game' }
        if (!$game.hidden -and $game.installed) { $null = $ids.Add($game.id) }
    }
    $wrapper = $script:Registration.wrapper_path
    $settingsFile = $script:Registration.settings_path
    $apps = @(foreach ($app in $Original.apps) {
        if ($app.name -isnot [string]) { throw 'Invalid existing app name' }
        if (!$app.name.StartsWith('PlayniteBridge-', [StringComparison]::Ordinal)) { $app }
    })
    foreach ($id in @('Playnite') + @($ids | Sort-Object)) {
        $selector = if ($id -eq 'Playnite') { '-Browse' } else { '-GameId ' + $id }
        $apps += [pscustomobject][ordered]@{
            name = 'PlayniteBridge-' + $id
            cmd = '"' + $env:WINDIR + '\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $wrapper + '" ' + $selector + ' -SettingsPath "' + $settingsFile + '" -TvOnly'
            'auto-detach' = $false; 'wait-all' = $false; 'exit-timeout' = 10; elevated = $false; 'image-path' = ''
        }
    }
    $copy = $Original | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $copy.apps = $apps
    return $copy
}

function Assert-NoReparse([string]$Path) {
    $current = [IO.Path]::GetFullPath($Path)
    while ($current) {
        if (Test-Path -LiteralPath $current) {
            if ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Reparse point rejected: $current" }
        }
        $parent = [IO.Path]::GetDirectoryName($current)
        if ($parent -eq $current) { break }; $current = $parent
    }
}

function Test-SunshineIdle {
    $state = Invoke-RestMethod 'http://127.0.0.1:47989/serverinfo' -TimeoutSec 5
    if ($null -eq $state.root.currentgame -or [string]$state.root.currentgame -notmatch '^\d+$') { throw 'Invalid Sunshine state' }
    return ([string]$state.root.currentgame -eq '0')
}

function Restart-PlayniteBridgeSunshine {
    Restart-Service -Name SunshineService -ErrorAction Stop
    $timer = [Diagnostics.Stopwatch]::StartNew()
    do {
        try { $null = Test-SunshineIdle; return } catch { Start-Sleep -Milliseconds 500 }
    } while ($timer.Elapsed.TotalSeconds -lt 20)
    throw 'Sunshine failed to become reachable after restart'
}

function Invoke-PlayniteBridgeAppUpdate([string]$AppsPath, $Catalogue) {
    Assert-NoReparse $AppsPath
    $original = [IO.File]::ReadAllText($AppsPath) | ConvertFrom-Json
    $updated = New-PlayniteBridgeApps $original $Catalogue
    if ((ConvertTo-StableJson $original) -ceq (ConvertTo-StableJson $updated)) { return 'unchanged' }
    if (!(Test-SunshineIdle)) { return 'deferred-active' }
    $temporary = $AppsPath + '.playnitebridge-new'
    $backup = $AppsPath + '.playnitebridge-backup'
    foreach ($path in @($temporary, $backup)) { Assert-NoReparse $path }
    $changed = $false
    try {
        [IO.File]::WriteAllText($temporary, ($updated | ConvertTo-Json -Depth 30), (New-Object Text.UTF8Encoding($false)))
        # Recheck immediately before mutation; no atomic server-side idle/reload API exists.
        if (!(Test-SunshineIdle)) { return 'deferred-active' }
        [IO.File]::Replace($temporary, $AppsPath, $backup)
        $changed = $true
        Restart-PlayniteBridgeSunshine
        return 'updated'
    } catch {
        if ($changed) {
            [IO.File]::Copy($backup, $AppsPath, $true)
            try { Restart-PlayniteBridgeSunshine } catch { throw 'Update failed and Sunshine recovery restart also failed; original apps restored' }
        }
        throw
    } finally { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
}

if ($LibraryOnly) { return }
# Only this fixed entry point is scheduled elevated; the catalogue contributes GUIDs and booleans, never commands.
$protected = Join-Path $env:ProgramFiles 'PlayniteBridge'
$status = Join-Path $protected 'apps-update-status.json'
$lock = $null
try {
    Assert-NoReparse $protected
    Assert-NoReparse $status
    Assert-NoReparse (Join-Path $protected 'apps-update.lock')
    $lock = [IO.File]::Open((Join-Path $protected 'apps-update.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    $script:Registration = Read-RegistrationConfig (Join-Path $protected 'registration.json')
    Assert-AdministratorOwned $protected
    Assert-AdministratorOwned (Join-Path $protected 'registration.json')
    Assert-AdministratorOwned $PSCommandPath
    $catalogue = [IO.File]::ReadAllText($script:Registration.catalogue_path) | ConvertFrom-Json
    $result = Invoke-PlayniteBridgeAppUpdate $script:Registration.apps_path $catalogue
    @{status=$result; time=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath $status
} catch {
    if ($lock) {
        Assert-NoReparse $status
        @{status='failed'; error=$_.Exception.Message; time=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath $status
    }
    throw
} finally { if ($lock) { $lock.Dispose() } }

param([switch]$LibraryOnly)
$ErrorActionPreference = 'Stop'

function Read-SyncConfig($Path) {
    $config = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    foreach ($field in @('hostname', 'hostKeyAlias')) {
        if ($config.$field -isnot [string] -or $config.$field -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]{0,252}$') {
            throw "Invalid sync configuration: $field"
        }
    }
    return $config
}

function Get-SyncToolPath([string]$Tool,
    [bool]$Is64BitOperatingSystem = [Environment]::Is64BitOperatingSystem,
    [bool]$Is64BitProcess = [Environment]::Is64BitProcess) {
    $systemDirectory = 'System32'
    # A 32-bit Playnite worker must bypass Windows filesystem redirection.
    if ($Is64BitOperatingSystem -and !$Is64BitProcess) { $systemDirectory = 'Sysnative' }
    return Join-Path $env:WINDIR ($systemDirectory + '\OpenSSH\' + $Tool + '.exe')
}

function Invoke-SyncProcess([string]$Tool, [string[]]$Arguments) {
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = Get-SyncToolPath $Tool
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.Arguments = (@(foreach ($argument in $Arguments) {
        if ($argument.Contains('"') -or $argument.Contains("`n") -or $argument.Contains("`r")) { throw 'Unsafe process argument' }
        '"' + $argument + '"'
    }) -join ' ')
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $info
    try {
        $null = $process.Start()
        if (!$process.WaitForExit(30000)) { $process.Kill(); throw "$Tool timed out" }
        if ($process.ExitCode -ne 0) { throw "$Tool failed with exit code $($process.ExitCode)" }
    } finally { $process.Dispose() }
}

function Send-CatalogueSnapshot($Config, [string]$Snapshot) {
    $remote = 'root@' + $Config.hostname
    $destination = '/storage/.kodi/userdata/addon_data/plugin.program.playnitebridge'
    $options = @('-o', 'BatchMode=yes', '-o', 'ConnectTimeout=5', '-o', 'StrictHostKeyChecking=yes',
                 '-o', ('HostKeyAlias=' + $Config.hostKeyAlias))
    Invoke-SyncProcess 'ssh' ($options + @($remote, ('mkdir -p ' + $destination + '/artwork')))
    # Legacy SCP is supported by CoreELEC Dropbear without an SFTP server.
    Invoke-SyncProcess 'scp' ($options + @('-O', '-r', (Join-Path $Snapshot 'artwork'), ($remote + ':' + $destination + '/')))
    Invoke-SyncProcess 'scp' ($options + @('-O', (Join-Path $Snapshot 'catalogue.json'), ($remote + ':' + $destination + '/catalogue.json.new')))
    Invoke-SyncProcess 'ssh' ($options + @($remote, ('mv -f ' + $destination + '/catalogue.json.new ' + $destination + '/catalogue.json')))
}

function Get-SyncLock([string]$Path, [int]$TimeoutMilliseconds = 140000) {
    $timer = [Diagnostics.Stopwatch]::StartNew()
    while ($true) {
        try { return [IO.File]::Open($Path, 'OpenOrCreate', 'ReadWrite', 'None') }
        catch [IO.IOException] {
            if ($timer.ElapsedMilliseconds -ge $TimeoutMilliseconds) { throw 'Timed out waiting for catalogue sync lock' }
            Start-Sleep -Milliseconds 200
        }
    }
}

function Sync-PlayniteBridgeCatalogue([string]$Directory = $PSScriptRoot) {
    $lock = $null
    $snapshot = $null
    try {
        $lock = Get-SyncLock (Join-Path $Directory 'sync.lock')
        $config = Read-SyncConfig (Join-Path $Directory 'sync-config.json')
        $snapshot = Join-Path $Directory ('sync-snapshot-' + [guid]::NewGuid())
        $null = [IO.Directory]::CreateDirectory((Join-Path $snapshot 'artwork'))
        $source = Join-Path $Directory 'catalogue'
        $json = [IO.File]::ReadAllText((Join-Path $source 'catalogue.json'))
        $document = ConvertFrom-Json $json
        if ($document.schema_version -ne 1) { throw 'Unsupported catalogue schema' }
        foreach ($game in $document.games) {
            if ($game.cover) {
                if ($game.cover -notmatch '^artwork/[0-9a-fA-F-]{36}\.(jpg|jpeg|png|webp|gif|bmp)$') { throw 'Invalid artwork path' }
                [IO.File]::Copy((Join-Path $source $game.cover), (Join-Path $snapshot $game.cover), $true)
            }
        }
        [IO.File]::WriteAllText((Join-Path $snapshot 'catalogue.json'), $json, (New-Object Text.UTF8Encoding($false)))
        Send-CatalogueSnapshot $config $snapshot
        [IO.File]::WriteAllText((Join-Path $Directory 'sync-status.txt'), ('OK ' + [datetime]::UtcNow.ToString('o')))
    } catch {
        $message = 'PlayniteBridge sync failed: ' + $_.Exception.Message
        Write-Warning $message
        [IO.File]::WriteAllText((Join-Path $Directory 'sync-status.txt'), $message)
    } finally {
        if ($snapshot -and [IO.Directory]::Exists($snapshot)) { [IO.Directory]::Delete($snapshot, $true) }
        if ($lock) { $lock.Dispose() }
    }
}

if (!$LibraryOnly) { Sync-PlayniteBridgeCatalogue }

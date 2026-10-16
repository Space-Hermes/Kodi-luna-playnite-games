$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Sync-Catalogue.ps1') -LibraryOnly
function Assert($value, $message) { if (!$value) { throw $message } }
Assert ((Get-SyncToolPath 'ssh' $true $false) -eq (Join-Path $env:WINDIR 'Sysnative\OpenSSH\ssh.exe')) '32-bit worker must bypass redirection'
Assert ((Get-SyncToolPath 'scp' $true $true) -eq (Join-Path $env:WINDIR 'System32\OpenSSH\scp.exe')) '64-bit worker uses System32'
Assert ((Get-SyncToolPath 'ssh' $false $false) -eq (Join-Path $env:WINDIR 'System32\OpenSSH\ssh.exe')) '32-bit OS uses System32'
$directory = Join-Path $PSScriptRoot ('test-output-' + [guid]::NewGuid())
$null = [IO.Directory]::CreateDirectory($directory)
$path = Join-Path $directory 'config.json'
foreach ($bad in @('host;touch x', '-option', 'user@host', 'host/path', "host`ncommand", '')) {
    @{hostname=$bad;hostKeyAlias='test-host'} | ConvertTo-Json | Set-Content -LiteralPath $path
    $failed = $false
    try { Read-SyncConfig $path | Out-Null } catch { $failed = $true }
    Assert $failed 'Unsafe hostname accepted'
}
@{hostname='example.invalid';hostKeyAlias='test-host'} | ConvertTo-Json | Set-Content -LiteralPath $path
$config = Read-SyncConfig $path
$script:calls = @()
$script:failAt = 0
function Invoke-SyncProcess($Tool, $Arguments) {
    $script:calls += ,@($Tool, $Arguments)
    if ($script:calls.Count -eq $script:failAt) { throw 'Mock transfer failure' }
}
Send-CatalogueSnapshot $config $directory
Assert ($script:calls.Count -eq 4) 'Expected mkdir, artwork, catalogue, publication'
Assert ($script:calls[3][1][-1] -like 'mv -f *catalogue.json.new *catalogue.json') 'Atomic publication last'
foreach ($failure in @(1, 2, 3)) {
    $script:calls = @(); $script:failAt = $failure
    $failed = $false
    try { Send-CatalogueSnapshot $config $directory } catch { $failed = $true }
    Assert $failed 'Transfer error was swallowed'
    Assert ($script:calls.Count -eq $failure) 'Publication attempted after failure'
}
$lockPath = Join-Path $directory 'held.lock'
$held = [IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None')
try {
    $failed = $false
    try { Get-SyncLock $lockPath 0 | Out-Null } catch { $failed = $_.Exception.Message -like '*Timed out*' }
    Assert $failed 'Lock timeout must report failure'
} finally { $held.Dispose() }
$released = Get-SyncLock $lockPath 0
$released.Dispose()

# Simulate an export finishing while this worker waits for the earlier transfer.
$source = Join-Path $directory 'catalogue'
$null = [IO.Directory]::CreateDirectory($source)
$config | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $directory 'sync-config.json')
[IO.File]::WriteAllText((Join-Path $source 'catalogue.json'), '{"schema_version":1,"games":[],"generated_at":"old"}')
function Get-SyncLock($Path) {
    [IO.File]::WriteAllText((Join-Path $source 'catalogue.json'), '{"schema_version":1,"games":[],"generated_at":"latest"}')
    return [IO.File]::Open($Path, 'OpenOrCreate', 'ReadWrite', 'None')
}
$script:observed = $null
function Send-CatalogueSnapshot($Config, $Snapshot) {
    $script:observed = (Get-Content -LiteralPath (Join-Path $Snapshot 'catalogue.json') -Raw | ConvertFrom-Json).generated_at
}
Sync-PlayniteBridgeCatalogue $directory
Assert ($script:observed -eq 'latest') 'Snapshot must be read after acquiring the lock'
Assert ((Get-Content -LiteralPath (Join-Path $directory 'sync-status.txt') -Raw) -like 'OK *') 'Successful sync status'
Write-Output 'PASS: configuration, transfer order, failure preservation, lock timeout/release, latest snapshot after wait'

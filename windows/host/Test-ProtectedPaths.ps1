$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Update-PlayniteBridgeApps.ps1') -LibraryOnly
function Assert-NoReparse($Path) { }
$script:acl = New-Object Security.AccessControl.FileSecurity
$admins = New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')
$users = New-Object Security.Principal.SecurityIdentifier('S-1-5-32-545')
$script:acl.SetOwner($admins)
function Get-Acl { return $script:acl }
Assert-AdministratorOwned 'C:\fixture'
$script:acl.SetOwner($users)
$failed=$false; try { Assert-AdministratorOwned 'C:\fixture' } catch { $failed=$true }
if (!$failed) { throw 'Untrusted owner accepted' }
$script:acl.SetOwner($admins)
$script:acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($users,'Write','Allow')))
$failed=$false; try { Assert-AdministratorOwned 'C:\fixture' } catch { $failed=$true }
if (!$failed) { throw 'User-writable elevated target accepted' }
Write-Output 'PASS: administrator-owned target accepted; unsafe owner and user write rejected without changing ACLs'

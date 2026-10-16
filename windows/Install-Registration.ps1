param([Parameter(Mandatory=$true)][string]$RegistrationConfig)
$ErrorActionPreference='Stop'
$destination=Join-Path $env:ProgramFiles 'PlayniteBridge'
$source=Join-Path $PSScriptRoot 'host/Update-PlayniteBridgeApps.ps1'
. $source -LibraryOnly
$config = Read-RegistrationConfig $RegistrationConfig
if ((Invoke-RestMethod 'http://127.0.0.1:47989/serverinfo').root.currentgame -ne '0') { throw 'Streaming active; installation cancelled' }
if (!(Test-Path -LiteralPath $source)) { throw 'Updater source is missing' }
foreach($path in @($destination,"$destination/Update-PlayniteBridgeApps.ps1","$destination/registration.json")) {
    if((Test-Path -LiteralPath $path) -and ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Reparse destination rejected'}
}
function Set-ProtectedAcl($Path, [bool]$Directory) {
    $acl = if($Directory){New-Object Security.AccessControl.DirectorySecurity}else{New-Object Security.AccessControl.FileSecurity}
    $acl.SetAccessRuleProtection($true,$false)
    $acl.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))
    $inherit = if($Directory){[Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit'}else{[Security.AccessControl.InheritanceFlags]::None}
    foreach($entry in @(@('S-1-5-18','FullControl'),@('S-1-5-32-544','FullControl'),@('S-1-5-32-545','ReadAndExecute'))) {
        $sid=New-Object Security.Principal.SecurityIdentifier($entry[0])
        $rule=New-Object Security.AccessControl.FileSystemAccessRule($sid,$entry[1],$inherit,[Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AccessControlType]::Allow)
        $acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $Path -AclObject $acl
}
$null=New-Item -ItemType Directory -Path $destination -Force
# Elevated task code must not be writable by ordinary processes.
Set-ProtectedAcl $destination $true
Copy-Item -LiteralPath $source -Destination "$destination/Update-PlayniteBridgeApps.ps1" -Force
Set-ProtectedAcl "$destination/Update-PlayniteBridgeApps.ps1" $false
[IO.File]::WriteAllText((Join-Path $destination 'registration.json'), ($config | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
Set-ProtectedAcl (Join-Path $destination 'registration.json') $false
$action=New-ScheduledTaskAction -Execute "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument ('-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $destination + '\Update-PlayniteBridgeApps.ps1"')
$identity=[Security.Principal.WindowsIdentity]::GetCurrent().Name
$principal=New-ScheduledTaskPrincipal -UserId $identity -LogonType Interactive -RunLevel Highest
$settings=New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 2) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
$null=Register-ScheduledTask -TaskName 'PlayniteBridge Update Games' -Action $action -Principal $principal -Settings $settings -Force
Start-ScheduledTask -TaskName 'PlayniteBridge Update Games'
Write-Output 'Registered PlayniteBridge Update Games. Inspect task result before enabling extension requests.'

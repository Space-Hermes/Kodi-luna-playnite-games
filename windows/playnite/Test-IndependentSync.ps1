$ErrorActionPreference = 'Stop'
$module = Import-Module (Join-Path $PSScriptRoot 'PlayniteBridgeCatalogue.psm1') -Force -PassThru
& $module {
    function Assert($value, $message) { if (!$value) { throw $message } }
    $directory = Join-Path $PSScriptRoot ('test-output-' + [guid]::NewGuid())
    $null = [IO.Directory]::CreateDirectory($directory)
    $markerPath = Join-Path $directory 'marker.json'
    Assert (!(Test-PlayniteBridgeProcessMarker $markerPath)) 'Absent marker must use ordinary launch'
    $marker = @{close_on_game_stop=$true;playnite_pid=$PID;playnite_start_ticks=[Diagnostics.Process]::GetCurrentProcess().StartTime.ToUniversalTime().Ticks.ToString()}
    $marker | ConvertTo-Json | Set-Content -LiteralPath $markerPath
    Assert (Test-PlayniteBridgeProcessMarker $markerPath) 'Owned marker must use independent launch'
    $marker.close_on_game_stop = $false
    $marker | ConvertTo-Json | Set-Content -LiteralPath $markerPath
    Assert (Test-PlayniteBridgeProcessMarker $markerPath) 'Owned browse session must also use independent sync'
    $marker.playnite_start_ticks = 'old'
    $marker | ConvertTo-Json | Set-Content -LiteralPath $markerPath
    Assert (!(Test-PlayniteBridgeProcessMarker $markerPath)) 'Stale marker must not match'
    $script:createdCommand = ''
    $script:returnCode = 0
    $script:session = [Diagnostics.Process]::GetCurrentProcess().SessionId
    $script:terminated = $false
    function New-CimInstance($Namespace, $ClassName, [switch]$ClientOnly, $Property) {
        Assert ($Property.ShowWindow -eq 0 -and $ClientOnly) 'Worker must be hidden and local'
        return [pscustomobject]@{ShowWindow=0}
    }
    function Invoke-CimMethod($ClassName, $MethodName, $Arguments, $InputObject) {
        switch ($MethodName) {
            Create { $script:createdCommand = $Arguments.CommandLine; return @{ReturnValue=$script:returnCode;ProcessId=123} }
            GetOwnerSid { return @{ReturnValue=0;Sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value} }
            Terminate { $script:terminated = $true; return @{ReturnValue=0} }
        }
    }
    function Get-CimInstance($ClassName, $Filter) { return @{SessionId=$script:session} }
    Start-IndependentPlayniteBridgeSync 'C:\test folder\Sync-Catalogue.ps1'
    Assert ($script:createdCommand -like '*-File "C:\test folder\Sync-Catalogue.ps1"') 'Worker path must remain quoted'
    $script:session = -1
    $failed = $false
    try { Start-IndependentPlayniteBridgeSync 'C:\worker.ps1' } catch { $failed = $true }
    Assert ($failed -and $script:terminated) 'Wrong session must be rejected and terminated'
    $script:returnCode = 2
    $failed = $false
    try { Start-IndependentPlayniteBridgeSync 'C:\worker.ps1' } catch { $failed = $true }
    Assert $failed 'WMI launch failure must propagate to warning handler'
    $script:sequence = @()
    function Export-PlayniteBridgeCatalogue { $script:sequence += 'export' }
    function Request-PlayniteBridgeRegistration { }
    function Test-Path { return $true }
    function Test-PlayniteBridgeProcessMarker { return $true }
    function Start-IndependentPlayniteBridgeSync { $script:sequence += 'independent'; throw 'mock WMI failure' }
    Update-PlayniteBridgeCatalogue -WarningAction SilentlyContinue
    Assert (($script:sequence -join ',') -eq 'export,independent') 'Export must survive independent launch failure'
    function Test-PlayniteBridgeProcessMarker { return $false }
    function Start-Process { $script:sequence += 'ordinary' }
    Update-PlayniteBridgeCatalogue
    Assert ($script:sequence[-1] -eq 'ordinary') 'Ordinary Playnite retains normal background launch'
}
Write-Output 'PASS: hidden local WMI launch, quoted paths, session rejection, failure preservation, ordinary-session behavior'

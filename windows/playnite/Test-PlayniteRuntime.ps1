$ErrorActionPreference = 'Stop'
$state = [Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
$state.ThreadOptions = [Management.Automation.Runspaces.PSThreadOptions]::UseCurrentThread
$runtime = [Management.Automation.PowerShell]::Create($state)
try {
    $runtime.Runspace.SessionStateProxy.SetVariable('ErrorActionPreference', 'Stop')
    $module = $runtime.AddCommand('Import-Module').AddParameter('PassThru').AddArgument(
        (Join-Path $PSScriptRoot 'PlayniteBridgeCatalogue.psm1')).Invoke()[0]
    if (!$module) { throw 'Module import failed' }
    $runtime.Commands.Clear()
    foreach ($helper in @('Complete-PlayniteBridgeSession','Request-PlayniteBridgeShutdown','Test-PlayniteBridgeProcessMarker','Start-IndependentPlayniteBridgeSync','Request-PlayniteBridgeRegistration')) {
        if (!$module.ExportedCommands.ContainsKey($helper)) { throw "Runtime helper is not exported: $helper" }
    }
    # Keep actual stop/session functions, but replace export and shutdown side effects.
    $null = $runtime.AddScript(@'
function Update-PlayniteBridgeCatalogue { $global:ExportObserved = $true }
function Test-Path { return $false }
'@).Invoke()
    $runtime.Commands.Clear()
    $event = [pscustomobject]@{Game=[pscustomobject]@{Id=[guid]::NewGuid()};ManuallyStopped=$false}
    # Matches Playnite PowerShellRuntime.InvokeFunction: AddCommand(CommandInfo).
    $null = $runtime.AddCommand($module.ExportedCommands['OnGameStopped']).AddArgument($event).Invoke()
    if ($runtime.HadErrors) { throw ($runtime.Streams.Error | Out-String) }
    if (!$runtime.Runspace.SessionStateProxy.GetVariable('ExportObserved')) { throw 'Export handler was not invoked' }
    $runtime.Commands.Clear()
    # Also exercise detached function text without its module session state.
    $runtime.Runspace.SessionStateProxy.SetVariable('stopEvent', $event)
    $body = $module.ExportedFunctions['OnGameStopped'].ScriptBlock.ToString()
    $null = $runtime.AddScript('& { ' + $body + ' } $stopEvent').Invoke()
    if ($runtime.HadErrors) { throw ($runtime.Streams.Error | Out-String) }
} finally { $runtime.Dispose() }
Write-Output 'PASS: Playnite CommandInfo invocation and detached event script resolve exported helpers'

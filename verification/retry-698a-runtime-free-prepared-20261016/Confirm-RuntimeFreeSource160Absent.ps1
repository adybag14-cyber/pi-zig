param([Parameter(Mandatory)][string]$RunDirectory)
. (Join-Path $PSScriptRoot 'RuntimeFreeSource160.Common.ps1')
$workspace=Get-S160Workspace
$run=Assert-S160Contained $RunDirectory (Join-Path $workspace.evidence 'retry698a-runtime-free-captures')
if(Test-Path -LiteralPath (Join-Path $run 'external-handoff.json')){throw 'Refuse external handoff replay'}
$self=Read-S160Json (Join-Path $run 'supervisor-self.json');$terminal=Read-S160Json (Join-Path $run 'supervisor-terminal.json')
$launch=Read-S160Json (Join-Path (Split-Path -Parent $run) ((Split-Path -Leaf $run)+'.launch.json'))
if(!$launch.terminal_kernel_handle -or !$launch.pipes_settled -or !$launch.identity -or $launch.identity.pid -ne $self.identity.pid -or $launch.identity.command_line -cne $self.identity.command_line){throw 'Original external launch/kernel identity/terminal required'}
if($self.identity.pid -eq $PID){throw 'Independent external observer required'}
$absence=Get-S160Absence (@($self.identity)+@($terminal.known_owned_identities)) @($terminal.partial_observations)
$changed=@()
if(Test-Path -LiteralPath (Join-Path $run 'capture-artifact-manifest.json')){
    foreach($row in (Read-S160Json (Join-Path $run 'capture-artifact-manifest.json')).rows){if((Get-S160Sha $row.path) -cne $row.sha256){$changed+=@($row.path)}}
}
Write-S160Json (Join-Path $run 'external-absence.json') $absence
$files=@(Get-ChildItem -LiteralPath $run -File -Recurse|ForEach-Object {@{path=$_.FullName;bytes=$_.Length;sha256=Get-S160Sha $_.FullName}})
foreach($suffix in @('.launch.json','.supervisor.stdout.log','.supervisor.stderr.log')){
    $path=Join-Path (Split-Path -Parent $run) ((Split-Path -Leaf $run)+$suffix)
    if(Test-Path -LiteralPath $path){$item=Get-Item -LiteralPath $path;$files+=@(@{path=$path;bytes=$item.Length;sha256=Get-S160Sha $path})}
}
Write-S160Json (Join-Path $run 'external-artifact-manifest.json') @{rows=$files;files=$files.Count;all_terminal_outputs_frozen=$true;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}
Write-S160Json (Join-Path $run 'external-handoff.json') @{supervisor_status=$terminal.status;present_or_unknown=$absence.present_or_unknown;original_artifact_drift=$changed;source160_acceptance_pending=$true;expected_created=$false;global_hold_lifted=$false;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}
if($absence.present_or_unknown -or $changed.Count){throw 'External absence/artifact gate negative; no handoff'}

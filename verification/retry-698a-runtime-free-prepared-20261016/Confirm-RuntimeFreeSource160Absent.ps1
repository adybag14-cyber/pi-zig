param([Parameter(Mandatory)][string]$RunDirectory)
. (Join-Path $PSScriptRoot 'RuntimeFreeSource160.Common.ps1')
$workspace=Get-S160Workspace
$run=Assert-S160Contained $RunDirectory (Join-Path $workspace.evidence 'retry698a-runtime-free-captures')
$outputRoot=if(Test-Path -LiteralPath $run){$run}else{$run+'.launcher'}
if(Test-Path -LiteralPath (Join-Path $outputRoot 'external-handoff.json')){throw 'Refuse external handoff replay'}
$metadataErrors=[Collections.Generic.List[string]]::new();$self=$null;$terminal=$null;$launch=$null
foreach($name in @('supervisor-self.json','supervisor-terminal.json')){
    $path=Join-Path $run $name
    if(Test-Path -LiteralPath $path){if($name -eq 'supervisor-self.json'){$self=Read-S160Json $path}else{$terminal=Read-S160Json $path}}else{$metadataErrors.Add('Missing '+$name)}
}
$launchPath=Join-Path ($run+'.launcher') 'supervisor-terminal.json'
if(Test-Path -LiteralPath $launchPath){$launch=Read-S160Json $launchPath}else{$metadataErrors.Add('Missing launcher retained supervisor terminal')}
if(!$launch -or !$launch.terminal_kernel_handle -or !$launch.pipes_settled -or !$launch.identity -or !$self -or $launch.identity.pid -ne $self.identity.pid -or $launch.identity.command_line -cne $self.identity.command_line -or $launch.identity.parent_pid -ne $self.identity.parent_pid){$metadataErrors.Add('Original external launch/kernel/parent identity/terminal not qualified')}
if($self -and $self.identity.pid -eq $PID){throw 'Independent external observer required'}
$union=Get-S160LaunchUnion $run
$absence=Get-S160Absence $union.known $union.partial
$changed=@()
if(Test-Path -LiteralPath (Join-Path $run 'capture-artifact-manifest.json')){
    foreach($row in (Read-S160Json (Join-Path $run 'capture-artifact-manifest.json')).rows){if((Get-S160Sha $row.path) -cne $row.sha256){$changed+=@($row.path)}}
}
Write-S160Json (Join-Path $outputRoot 'external-absence.json') $absence
$files=@()
if(Test-Path -LiteralPath $run){$files=@(Get-ChildItem -LiteralPath $run -File -Recurse|ForEach-Object {@{path=$_.FullName;bytes=$_.Length;sha256=Get-S160Sha $_.FullName}})}
foreach($item in @(Get-ChildItem -LiteralPath ($run+'.launcher') -File -Recurse)){$files+=@(@{path=$item.FullName;bytes=$item.Length;sha256=Get-S160Sha $item.FullName})}
Write-S160Json (Join-Path $outputRoot 'external-artifact-manifest.json') @{rows=$files;files=$files.Count;all_terminal_outputs_frozen=$true;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}
Write-S160Json (Join-Path $outputRoot 'external-handoff.json') @{supervisor_status=if($terminal){$terminal.status}else{'preflight_negative'};metadata_errors=$metadataErrors.ToArray();present_or_unknown=$absence.present_or_unknown;all_launch_ledger_paths=$union.launch_ledger_paths;original_artifact_drift=$changed;source160_acceptance_pending=$true;expected_created=$false;global_hold_lifted=$false;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}
if($absence.present_or_unknown -or $changed.Count -or $metadataErrors.Count){throw 'External absence/artifact or metadata gate negative; packet retained'}

param([Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{40}$')][string]$CandidateHead,[Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9-]{1,70}$')][string]$RunId,[Parameter(Mandatory)][string]$RootGrant)
. (Join-Path $PSScriptRoot 'RuntimeFreeSource160.Common.ps1')
$workspace=Get-S160Workspace
Assert-S160Contained $RootGrant $workspace.evidence|Out-Null
$grant=Read-S160Json $RootGrant;$now=[DateTimeOffset]::UtcNow
$supervisor=Join-Path $PSScriptRoot 'Run-RuntimeFreeSource160.ps1'
if($grant.authorized -isnot [bool] -or !$grant.authorized -or $grant.manual_fresh_16gib -isnot [bool] -or !$grant.manual_fresh_16gib -or $grant.scope -cne 'runtime-free-source160-only' -or $grant.run_id -cne $RunId -or $grant.candidate_head -cne $CandidateHead -or $grant.tool_sha256.'Start-RuntimeFreeSource160.ps1' -cne (Get-S160Sha $PSCommandPath) -or $grant.tool_sha256.'Run-RuntimeFreeSource160.ps1' -cne (Get-S160Sha $supervisor) -or ([DateTimeOffset]$grant.issued_utc) -gt $now -or ($now-([DateTimeOffset]$grant.issued_utc)).TotalSeconds -gt 300 -or ([DateTimeOffset]$grant.expires_utc) -le $now -or (([DateTimeOffset]$grant.expires_utc)-([DateTimeOffset]$grant.issued_utc)).TotalSeconds -gt 300){throw 'Exact fresh Root launcher grant required; no child started'}
$runs=Join-Path $workspace.evidence 'retry698a-runtime-free-captures';$run=Assert-S160Contained (Join-Path $runs $RunId) $runs
$journal=$run+'.launcher'
if((Test-Path -LiteralPath $run) -or (Test-Path -LiteralPath $journal)){throw 'Refuse any original run/launcher replay'}
[void][IO.Directory]::CreateDirectory($runs)
[void][IO.Directory]::CreateDirectory($journal)
$context=New-S160Context $run 'launcher' $journal
$self=Convert-S160Identity (Get-S160Live $PID)
if(!$self){throw 'External launcher self identity required before any child'}
Write-S160Json (Join-Path $journal 'launcher-self.json') $self
$child=$null;$failure=$null
try{
    $claim=New-S160LaunchClaim $run $RunId $CandidateHead $RootGrant $self
    $child=Start-S160Process $context 'supervisor' $s160Pwsh @('-NoLogo','-NoProfile','-NonInteractive','-File',$supervisor,'-CandidateHead',$CandidateHead,'-RunId',$RunId,'-RootGrant',$RootGrant,'-LaunchClaim',$claim.path,'-LaunchClaimSha256',$claim.sha256)
    # Common wait observes descendants during the wait, not merely on timeout.
    Wait-S160Process $context $child 1340|Out-Null
}catch{$failure=$_.Exception.Message}finally{
    try{
        $union=Get-S160LaunchUnion $run
        $absence=Get-S160Absence @($union.known|Where-Object {$_.pid -ne $PID}) @($union.partial|Where-Object {$_.pid -ne $PID})
        Write-S160Json (Join-Path $journal 'launcher-descendants-absence.json') $absence
        if($absence.present_or_unknown){$failure='Launcher descendants remain present/unknown'}
    }catch{$failure=$_.Exception.Message}
    Write-S160Json (Join-Path $journal 'launcher-terminal.json') @{status=if($failure){'negative'}else{'terminal_pending_external_absence'};failure=$failure;all_launch_ledger_paths=@($union.launch_ledger_paths);expected_created=$false;parent_environment_modified=$false;hard_wait_seconds=1340;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}
}
if($failure){exit 1}

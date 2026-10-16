param([Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{40}$')][string]$CandidateHead,[Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9-]{1,70}$')][string]$RunId,[Parameter(Mandatory)][string]$RootGrant)
. (Join-Path $PSScriptRoot 'RuntimeFreeSource160.Common.ps1')
$workspace=Get-S160Workspace
Assert-S160Contained $RootGrant $workspace.evidence|Out-Null
$grant=Read-S160Json $RootGrant;$now=[DateTimeOffset]::UtcNow
$supervisor=Join-Path $PSScriptRoot 'Run-RuntimeFreeSource160.ps1'
if($grant.authorized -isnot [bool] -or !$grant.authorized -or $grant.manual_fresh_16gib -isnot [bool] -or !$grant.manual_fresh_16gib -or $grant.scope -cne 'runtime-free-source160-only' -or $grant.run_id -cne $RunId -or $grant.candidate_head -cne $CandidateHead -or $grant.tool_sha256.'Start-RuntimeFreeSource160.ps1' -cne (Get-S160Sha $PSCommandPath) -or $grant.tool_sha256.'Run-RuntimeFreeSource160.ps1' -cne (Get-S160Sha $supervisor) -or ([DateTimeOffset]$grant.issued_utc) -gt $now -or ($now-([DateTimeOffset]$grant.issued_utc)).TotalSeconds -gt 300 -or ([DateTimeOffset]$grant.expires_utc) -le $now){throw 'Exact fresh Root launcher grant required; no child started'}
$runs=Join-Path $workspace.evidence 'retry698a-runtime-free-captures';$run=Assert-S160Contained (Join-Path $runs $RunId) $runs
$launchPath=Join-Path $runs ($RunId+'.launch.json')
if((Test-Path -LiteralPath $run) -or (Test-Path -LiteralPath $launchPath)){throw 'Refuse any original run/launcher replay'}
[void][IO.Directory]::CreateDirectory($runs)
$free=(Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 3).FreePhysicalMemory
if($free -lt 16MB){throw 'Launcher automatic fresh16GiB admission denied'}
$info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=$s160Pwsh;$info.WorkingDirectory=$PSScriptRoot
$info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
$info.Environment.Clear();$safe=Get-S160Environment $run
foreach($name in $safe.Keys){$info.Environment[$name]=[string]$safe[$name]}
foreach($arg in @('-NoLogo','-NoProfile','-NonInteractive','-File',$supervisor,'-CandidateHead',$CandidateHead,'-RunId',$RunId,'-RootGrant',$RootGrant)){$info.ArgumentList.Add($arg)}
$process=[Diagnostics.Process]::new();$process.StartInfo=$info
if(!$process.Start()){throw 'Cleared hidden supervisor did not start'}
$created=$process.StartTime.ToUniversalTime();$out=$process.StandardOutput.ReadToEndAsync();$err=$process.StandardError.ReadToEndAsync()
$identity=$null
try{$identity=Convert-S160Identity (Get-S160Live $process.Id)}catch{$identity=$null}
$record=[ordered]@{pid=$process.Id;retained_created_utc=$created.ToString('o');executable=$s160Pwsh;arguments=@($info.ArgumentList);identity=$identity;environment_names=@($safe.Keys|Sort-Object);environment_cleared=$true;parent_environment_modified=$false;initial_free_kib=$free;required_free_kib=16MB;hard_seconds=1340;settle_seconds=20;status='running';run=$run}
Write-S160Json $launchPath $record
$timedOut=!$process.WaitForExit(1340000)
if($timedOut){
    $record.status='hard_timeout';Write-S160Json $launchPath $record
    $until=[DateTimeOffset]::UtcNow.AddSeconds(20)
    $identities=@()
    foreach($name in @('supervisor-identities.json','controller-identities.json')){if(Test-Path -LiteralPath (Join-Path $run $name)){$identities+=@(Read-S160Json (Join-Path $run $name))}}
    $identities+=@($identity)
    foreach($owned in @($identities|Where-Object {$_}|Sort-Object created_utc -Descending)){
        if([DateTimeOffset]::UtcNow -ge $until){break}
        Stop-S160Verified $owned|Out-Null
    }
}
$pipes=$process.HasExited -and $out.Wait(2000) -and $err.Wait(2000)
if($pipes){[IO.File]::WriteAllText((Join-Path $runs ($RunId+'.supervisor.stdout.log')),$out.Result);[IO.File]::WriteAllText((Join-Path $runs ($RunId+'.supervisor.stderr.log')),$err.Result)}
$record.status=if($timedOut){'hard_timeout'}elseif(!$process.HasExited -or !$pipes){'terminal_or_pipe_unknown'}elseif($process.ExitCode -ne 0){'negative'}else{'supervisor_terminal_pending_external_absence'}
$record.terminal_kernel_handle=$process.HasExited;$record.exit_code=if($process.HasExited){$process.ExitCode}else{$null};$record.pipes_settled=$pipes;$record.completed_utc=[DateTimeOffset]::UtcNow.ToString('o')
Write-S160Json $launchPath $record
$process.Dispose()
if($timedOut -or !$pipes -or $record.exit_code -ne 0){exit 1}

param([Parameter(Mandatory)][string]$RunDirectory)
$ErrorActionPreference='Stop'
$taskRun=[IO.Path]::GetFullPath($RunDirectory)
$taskOwnedRoot='C:\Users\adyba\pi-zig-update-evidence-20261003\latest4dd-source-captures\'
if(!$taskRun.StartsWith($taskOwnedRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'Exact owned capture run required'}
if(Test-Path -LiteralPath (Join-Path $taskRun 'supervisor-handoff.json')){throw 'Refuse supervisor receipt replay'}
$taskOuter=Get-Content -LiteralPath (Join-Path $taskRun 'outer-owner.json') -Raw|ConvertFrom-Json
$taskTerminal=Get-Content -LiteralPath (Join-Path $taskRun 'terminal.json') -Raw|ConvertFrom-Json
$taskAll=@(Get-CimInstance Win32_Process -OperationTimeoutSec 3)
$taskRows=@(foreach($taskIdentity in @($taskOuter.identity)+@($taskTerminal.known_owned_identities)){
    $taskLive=$taskAll|Where-Object ProcessId -eq $taskIdentity.pid|Select-Object -First 1
    $taskSame=$taskLive -and $taskLive.ExecutablePath -ceq $taskIdentity.executable -and $taskLive.CommandLine -ceq $taskIdentity.command_line -and [Math]::Abs((([DateTimeOffset]$taskLive.CreationDate)-([DateTimeOffset]$taskIdentity.created_utc)).TotalMilliseconds) -le 1
    @{identity=$taskIdentity;original_identity_absent=!$taskSame;pid_reused=($taskLive -and !$taskSame)}
})
$taskPresent=@($taskRows|Where-Object {!$_.original_identity_absent})
$taskReceipt=@{rows=$taskRows;present=$taskPresent.Count;candidate_head=$taskTerminal.candidate_head;source_terminal_status=$taskTerminal.status;expected_files_created=$false;outer_and_observed_descendants_absent=($taskPresent.Count -eq 0);observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}
$taskReceipt|ConvertTo-Json -Depth 16|Set-Content -LiteralPath (Join-Path $taskRun 'supervisor-handoff.json') -Encoding utf8NoBOM
if($taskPresent.Count){throw 'Outer/observed child identities still present; no handoff'}
Write-Output 'LATEST4DD_OUTER_AND_OBSERVED_DESCENDANTS_ABSENT'

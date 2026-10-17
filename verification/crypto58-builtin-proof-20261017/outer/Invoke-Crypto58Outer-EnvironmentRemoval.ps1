param(
 [Parameter(Mandatory)][ValidatePattern('^[a-zA-Z0-9-]{1,60}$')][string]$RunId,
 [Parameter(Mandatory)][string]$RootGrant,
 [Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$PreparedSha256
)
# SOURCE-ONLY PREPARED: no execution grant is included with this helper.
# The outer process never resets its environment. Only the exact -File child
# contains the separately reviewed dedicated-process environment reset.
$ErrorActionPreference='Stop'
if(!$IsWindows -or [Environment]::Version.ToString() -cne '10.0.12'){throw 'Reviewed Windows .NET10.0.12 launcher runtime required'}
$taskClock=[Diagnostics.Stopwatch]::StartNew()
$taskStarted=[DateTimeOffset]::UtcNow
$taskDeadline=$taskStarted.AddSeconds(900)
$taskContainer='C:\Users\adyba\pi-zig'
if([IO.Path]::GetFullPath($PSScriptRoot) -ine [IO.Path]::GetFullPath((Join-Path $taskContainer 'evidence/root-crypto58-outer-prepared-20261016'))){throw 'Exact prepared evidence helper location required'}
$taskRoot=[IO.Path]::GetFullPath((Join-Path $taskContainer 'worktrees/semver'))
$taskRunner=[IO.Path]::GetFullPath((Join-Path $taskRoot 'verification/node-crypto-sha256-package-sourceonly-20261016/Run-StandaloneOriginal58.ps1'))
$taskHead='c64aa31cb8726b9da66afea2c76aed34f626a402'
$taskRunnerSha='D29070CD3D8C0D3723FDC231732DBADC49590FF289DF1059AC7D8FBB3073F8E1'
$taskNode='C:\Program Files\nodejs\node.exe'
$taskNodeSha='63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088'
$taskPwsh='C:\Program Files\PowerShell\7\pwsh.exe'
$taskCiOwner=Join-Path $taskContainer 'main/tools/ci/native_qualification_ci.ps1'
$taskInner=[IO.Path]::GetFullPath((Join-Path $taskContainer ('evidence/crypto-sha256-original58/'+$RunId)))
$taskProof=Join-Path $PSScriptRoot $RunId
if((Get-FileHash -LiteralPath $PSCommandPath).Hash -cne $PreparedSha256.ToUpperInvariant() -or (Get-FileHash -LiteralPath $taskRunner).Hash -cne $taskRunnerSha -or (Get-FileHash -LiteralPath $taskCiOwner).Hash -cne '607BEDBB91FE318D214CD2C3B9C83D80437335C0062C320C0EACB3A745B38285'){throw 'Reviewed helper/runner/CI607 bytes differ'}
if((Get-FileHash -LiteralPath $taskNode).Hash -cne $taskNodeSha){throw 'Pinned original Node differs'}
# The immutable inner runner checks its exact clean candidate head before Node.
$taskGrantPath=[IO.Path]::GetFullPath($RootGrant)
if(!$taskGrantPath.StartsWith((Join-Path $taskContainer 'evidence')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Root grant must be contained evidence metadata'}
$taskGrant=Get-Content -LiteralPath $taskGrantPath -Raw|ConvertFrom-Json
$taskNow=[DateTimeOffset]::UtcNow
$taskIssued=[DateTimeOffset]$taskGrant.issued_utc
$taskExpires=[DateTimeOffset]$taskGrant.expires_utc
if($taskGrant.authorized -isnot [bool] -or !$taskGrant.authorized -or $taskGrant.manual_fresh_16gib -isnot [bool] -or !$taskGrant.manual_fresh_16gib -or $taskGrant.builtin_only_no_deleted_runtime -isnot [bool] -or !$taskGrant.builtin_only_no_deleted_runtime -or $taskGrant.run_id -cne $RunId -or $taskGrant.candidate_head -cne $taskHead -or $taskGrant.launcher_sha256 -cne $taskRunnerSha -or $taskIssued -gt $taskNow -or ($taskNow-$taskIssued).TotalSeconds -gt 300 -or $taskExpires -le $taskNow -or $taskExpires -gt $taskIssued.AddSeconds(300)){throw 'Exact fresh Root grant with at-most300s expiry required'}
if((Test-Path -LiteralPath $taskProof) -or (Test-Path -LiteralPath $taskInner)){throw 'Refuse outer or inner run replay'}
[void][IO.Directory]::CreateDirectory($taskProof)
. $taskCiOwner
function Save-Outer { $taskRecord|ConvertTo-Json -Depth 12|Set-Content -LiteralPath (Join-Path $taskProof 'outer.json') -Encoding utf8NoBOM }
function Remaining-Milliseconds([int]$StageMaximum=0){
 $taskRemaining=[int][Math]::Floor(900000-$taskClock.Elapsed.TotalMilliseconds)
 if($taskRemaining -le 0){throw 'Shared900s monotonic deadline exhausted; cleanup state unknown'}
 return $(if($StageMaximum -gt 0){[Math]::Min($StageMaximum,$taskRemaining)}else{$taskRemaining})
}
function Cim-Seconds {
 $taskRemaining=Remaining-Milliseconds
 if($taskRemaining -lt 1000){throw 'No remaining whole second for bounded identity lookup'}
 return [int][Math]::Min(3,[Math]::Floor($taskRemaining/1000))
}
# CIM DMTF creation dates carry six decimal second digits. Compare exact UTC
# microsecond buckets by truncating the kernel's seventh (100ns) decimal digit.
# This is precision normalization, never an epsilon/tolerance comparison.
function Microsecond-Ticks($Value){
 $taskTicks=([DateTimeOffset]$Value).UtcDateTime.Ticks
 return [long]($taskTicks-($taskTicks%10))
}
function Reject-Outer([string]$Stage,[string]$Reason,$Identity=$null){
 $taskRecord.rejections+=@(@{stage=$Stage;reason=$Reason;identity=$Identity;utc=[DateTimeOffset]::UtcNow.ToString('o')})
 Save-Outer
 throw $Reason
}
function Live-Identity([Diagnostics.Process]$Process,[long]$Handle){
 if(!$Handle -or $Process.Handle.ToInt64() -ne $Handle){Reject-Outer 'live_identity' 'Held native handle differs before metadata capture'}
 $taskKernelBirth=$Process.StartTime.ToUniversalTime()
 $taskKernelExe=$Process.MainModule.FileName
 $taskCapture=[ordered]@{pid=$Process.Id;retained_handle=$Handle;kernel_created_utc_raw=$taskKernelBirth.ToString('o');kernel_microsecond_ticks=Microsecond-Ticks $taskKernelBirth;kernel_executable=$taskKernelExe;status='kernel_captured_cim_pending'}
 $taskRecord.identity_captures+=@($taskCapture);Save-Outer
 try{$taskRows=@(Get-CimInstance Win32_Process -Filter "ProcessId=$($Process.Id)" -OperationTimeoutSec (Cim-Seconds) -ErrorAction Stop)}catch{$taskCapture.status='cim_failed';$taskCapture.error=$_.Exception.Message;Save-Outer;throw}
 $taskCapture.cim_rows=@($taskRows|Select-Object ProcessId,ParentProcessId,Name,ExecutablePath,CommandLine,CreationDate);Save-Outer
 if($taskRows.Count -ne 1 -or !$taskRows[0].ExecutablePath -or !$taskRows[0].CommandLine -or !$taskRows[0].CreationDate){Reject-Outer 'live_identity' 'Complete bounded live identity unavailable' $taskCapture}
 $taskCim=$taskRows[0]
 $taskCapture.cim_created_utc_raw=([DateTimeOffset]$taskCim.CreationDate).UtcDateTime.ToString('o')
 $taskCapture.cim_microsecond_ticks=Microsecond-Ticks $taskCim.CreationDate
 if($taskCim.ProcessId -ne $Process.Id -or $taskCim.ExecutablePath -ine $taskKernelExe -or $taskCapture.cim_microsecond_ticks -ne $taskCapture.kernel_microsecond_ticks -or $Process.Handle.ToInt64() -ne $Handle){Reject-Outer 'live_identity' 'Fresh CIM PID/executable/UTC microsecond birth differs from held native process' $taskCapture}
 $taskCapture.status='agreed';Save-Outer
 return @{pid=$Process.Id;executable=$taskKernelExe;created_utc=$taskKernelBirth.ToString('o');command_line=$taskCim.CommandLine;command_line_method='Win32_Process.CommandLine';parent_pid=[int]$taskCim.ParentProcessId;retained_handle=$Handle;cim_created_utc_raw=$taskCapture.cim_created_utc_raw;created_microsecond_ticks=$taskCapture.kernel_microsecond_ticks}
}
function Same-Identity($Expected,$Actual){return $Expected.pid -eq $Actual.pid -and $Expected.executable -ieq $Actual.executable -and ([DateTimeOffset]$Expected.created_utc).UtcDateTime.Ticks -eq ([DateTimeOffset]$Actual.created_utc).UtcDateTime.Ticks -and $Expected.command_line -ceq $Actual.command_line -and $Expected.command_line_method -ceq $Actual.command_line_method}
function Descendant-Snapshot([string]$Stage,$VerifiedRunner=$null,[long]$HeldRunnerHandle=0){
 $taskSnapshot=[ordered]@{stage=$Stage;status='cim_pending';utc=[DateTimeOffset]::UtcNow.ToString('o');descendants=@();node_hints=@();kill_authority='none for census children/descendants'}
 $taskRecord.child_snapshots+=@($taskSnapshot);Save-Outer
 try{$taskRows=@(Get-CimInstance Win32_Process -OperationTimeoutSec (Cim-Seconds) -ErrorAction Stop)}catch{$taskSnapshot.status='cim_failed';$taskSnapshot.error=$_.Exception.Message;Save-Outer;throw}
 $taskSnapshot.census_count=$taskRows.Count
 $taskSnapshot.root_rows=@($taskRows|Where-Object {$_.ProcessId -eq $taskProcess.Id}|Select-Object ProcessId,ParentProcessId,Name,ExecutablePath,CommandLine,CreationDate)
 $taskSnapshot.verified_runner=$VerifiedRunner
 $taskSnapshot.held_runner_handle=$HeldRunnerHandle
 Save-Outer
 $taskSnapshot.incomplete_ancestry_rows=@($taskRows|Where-Object {$null -eq $_.ProcessId -or $null -eq $_.ParentProcessId}|Select-Object ProcessId,ParentProcessId,Name,ExecutablePath,CommandLine,CreationDate)
 # One census only. Resolve all descendant levels in memory, including git.
 $taskParents=[Collections.Generic.HashSet[int]]::new();[void]$taskParents.Add($taskProcess.Id)
 $taskDescendants=[Collections.Generic.List[object]]::new()
 for($taskPass=0;$taskPass -lt $taskRows.Count;$taskPass++){
  $taskChanged=$false
  foreach($taskRow in $taskRows){if($null -ne $taskRow.ProcessId -and $null -ne $taskRow.ParentProcessId -and $taskRow.ProcessId -ne $taskProcess.Id -and $taskParents.Contains([int]$taskRow.ParentProcessId) -and $taskParents.Add([int]$taskRow.ProcessId)){$taskDescendants.Add($taskRow);$taskChanged=$true}}
  if(!$taskChanged){break}
 }
 $taskSnapshot.descendants=@($taskDescendants|Select-Object ProcessId,ParentProcessId,Name,ExecutablePath,CommandLine,CreationDate)
 $taskSnapshot.direct_children=@($taskSnapshot.descendants|Where-Object {$_.ParentProcessId -eq $taskProcess.Id})
 $taskSnapshot.node_hints=@($taskSnapshot.descendants|Where-Object {$_.Name -ieq 'node.exe' -or $_.ExecutablePath -ieq $taskNode -or ([string]$_.CommandLine).Contains('--owned-original58') -or (!$_.Name -and !$_.ExecutablePath -and !$_.CommandLine)})
 $taskSnapshot.status='captured';Save-Outer
 if(!$taskRows.Count -or $taskSnapshot.incomplete_ancestry_rows.Count){Reject-Outer $Stage 'Nonempty complete ancestry census required' $taskSnapshot}
 if($Stage -ceq 'before_runner_stop'){
  if(!$VerifiedRunner -or !$HeldRunnerHandle -or $taskProcess.Handle.ToInt64() -ne $HeldRunnerHandle -or $taskSnapshot.root_rows.Count -ne 1){Reject-Outer $Stage 'Known live runner absent, duplicated or no longer bound to retained handle in stop census' $taskSnapshot}
  $taskRootRow=$taskSnapshot.root_rows[0]
  if($taskRootRow.ProcessId -ne $VerifiedRunner.pid -or $taskRootRow.ExecutablePath -ine $VerifiedRunner.executable -or !$taskRootRow.CreationDate -or (Microsecond-Ticks $taskRootRow.CreationDate) -ne (Microsecond-Ticks $VerifiedRunner.created_utc) -or ($taskRootRow.CommandLine -and $taskRootRow.CommandLine -cne $VerifiedRunner.command_line)){Reject-Outer $Stage 'Stop census runner PID/executable/UTC microsecond birth or present command line differs from held runner' $taskSnapshot}
 }
 return $taskSnapshot
}
function Stop-Exact([Diagnostics.Process]$Process,$Expected,[long]$Handle,[string]$ExeSha,[bool]$Runner=$false){
 if($Process.HasExited){return}
 [void](Remaining-Milliseconds)
 $taskLive=Live-Identity $Process $Handle
 if($Process.Id -eq $PID -or !(Same-Identity $Expected $taskLive) -or (Get-FileHash -LiteralPath $Expected.executable).Hash -cne $ExeSha -or $Expected.executable -match 'codex'){Reject-Outer 'stop_identity' 'Exact owned stop identity mismatch; preserve process' $taskLive}
 if($Runner){
  $taskChildren=Descendant-Snapshot 'before_runner_stop' $taskLive $Handle
  if($taskChildren.descendants.Count){Reject-Outer 'before_runner_stop' 'Runner has unreconciled children/descendants; no authority to stop them or runner' $taskChildren}
 }
 # No tree/name kill. All evidence and the same held handle precede this stop.
 [void](Remaining-Milliseconds)
 if($Process.Handle.ToInt64() -ne $Handle){Reject-Outer 'stop_handle' 'Held handle changed immediately before owned stop' $taskLive}
 $Process.Kill($false)
 if(!$Process.WaitForExit((Remaining-Milliseconds 10000))){Reject-Outer 'stop_settle' 'Exact owned stop failed ten-second settlement' $taskLive}
}
function Original-Absent($Expected){
 [void](Remaining-Milliseconds)
 $taskObservation=[ordered]@{expected=$Expected;status='kernel_pending';kernel_absent=$false;cim_absent=$false}
 $taskRecord.absence_captures+=@($taskObservation);Save-Outer
 $taskCurrent=$null
 try{
  try{$taskCurrent=[Diagnostics.Process]::GetProcessById([int]$Expected.pid)}catch [ArgumentException]{$taskObservation.kernel_absent=$true}catch{if($_.Exception.InnerException -is [ArgumentException]){$taskObservation.kernel_absent=$true}else{throw}}
  if($taskCurrent){
   # Open and retain before *any* Node birth/executable metadata read.
   $taskCurrentHandle=$taskCurrent.Handle.ToInt64();$taskObservation.inspection_handle=$taskCurrentHandle
   if($taskCurrent.HasExited){$taskObservation.kernel_absent=$true}else{
    $taskBirth=$taskCurrent.StartTime.ToUniversalTime();$taskExe=$taskCurrent.MainModule.FileName
    $taskObservation.kernel_created_utc_raw=$taskBirth.ToString('o');$taskObservation.kernel_executable=$taskExe
    $taskObservation.kernel_absent=$taskBirth.Ticks -ne ([DateTimeOffset]$Expected.created_utc).UtcDateTime.Ticks
    $taskObservation.kernel_microsecond_ticks=Microsecond-Ticks $taskBirth
   }
  }
  $taskObservation.status='cim_pending';Save-Outer
  try{$taskRows=@(Get-CimInstance Win32_Process -Filter "ProcessId=$($Expected.pid)" -OperationTimeoutSec (Cim-Seconds) -ErrorAction Stop)}catch{$taskObservation.status='cim_failed';$taskObservation.error=$_.Exception.Message;Save-Outer;throw}
  $taskObservation.cim_rows=@($taskRows|Select-Object ProcessId,ParentProcessId,Name,ExecutablePath,CommandLine,CreationDate);Save-Outer
  if(!$taskRows.Count){$taskObservation.cim_absent=$true}else{
   if($taskRows.Count -ne 1 -or !$taskRows[0].CreationDate -or !$taskRows[0].ExecutablePath){Reject-Outer 'absence_identity' 'PID absence identity ambiguous' $taskObservation}
   $taskObservation.cim_created_utc_raw=([DateTimeOffset]$taskRows[0].CreationDate).UtcDateTime.ToString('o')
   $taskObservation.cim_microsecond_ticks=Microsecond-Ticks $taskRows[0].CreationDate
   if($taskCurrent -and !$taskCurrent.HasExited -and ($taskRows[0].ExecutablePath -ine $taskObservation.kernel_executable -or $taskObservation.cim_microsecond_ticks -ne $taskObservation.kernel_microsecond_ticks -or $taskCurrent.Handle.ToInt64() -ne $taskCurrentHandle)){Reject-Outer 'absence_identity' 'Fresh absence CIM disagrees with held process executable/UTC microsecond birth' $taskObservation}
   $taskObservation.cim_absent=$taskObservation.cim_microsecond_ticks -ne (Microsecond-Ticks $Expected.created_utc)
  }
  $taskObservation.status='captured';$taskObservation.absent=$taskObservation.kernel_absent -and $taskObservation.cim_absent;Save-Outer
  return $taskObservation.absent
 }finally{if($taskCurrent){$taskCurrent.Dispose()}}
}
function Reconcile-Node([bool]$Terminate){
 $taskOwnerPath=Join-Path $taskInner 'owner.json'
 $taskReceipt=[ordered]@{path=$taskOwnerPath;status='read_pending';canonical=$null;utc=[DateTimeOffset]::UtcNow.ToString('o')}
 $taskRecord.canonical_receipt_reads+=@($taskReceipt);Save-Outer
 try{
  if(Test-Path -LiteralPath $taskOwnerPath){$taskReceipt.canonical=Get-Content -LiteralPath $taskOwnerPath -Raw|ConvertFrom-Json;$taskReceipt.status='read'}else{$taskReceipt.status='absent'}
 }catch{$taskReceipt.status='read_failed';$taskReceipt.error=$_.Exception.Message;Save-Outer}
 Save-Outer
 $taskSnapshot=Descendant-Snapshot 'node_reconciliation'
 if($taskReceipt.status -ceq 'read_failed'){Reject-Outer 'canonical_receipt' 'Canonical CI607 receipt read failed; preserve live runner/Node' $taskReceipt}
 $taskCanonical=$taskReceipt.canonical
 if(!$taskCanonical){Reject-Outer 'canonical_receipt' 'Canonical CI607 receipt absent; preserve live runner/Node; independent recovery required' $taskReceipt}
 if($taskCanonical.executable -ine $taskNode -or $taskCanonical.executable_sha256 -cne $taskNodeSha -or $taskCanonical.working_directory -ine $taskInner -or $taskCanonical.timeout_seconds -ne 300 -or !$taskCanonical.live_identity -or $taskCanonical.live_identity.pid -ne $taskCanonical.pid -or $taskCanonical.live_identity.created_utc -cne $taskCanonical.created_utc -or $taskCanonical.live_identity.executable -ine $taskNode -or $taskCanonical.live_identity.command_line_method -cne 'Win32_Process.CommandLine' -or !$taskCanonical.live_identity.command_line){Reject-Outer 'canonical_receipt' 'Canonical Node owner identity incomplete or mismatched' $taskCanonical}
 $taskCaptureDir=Split-Path -Parent $taskRunner
 $taskDriver=Join-Path $taskCaptureDir 'capture-original.mjs'
 $taskInput=Join-Path $taskRoot 'src/extensions/fixtures/node-crypto-sha256-package.input.txt'
 $taskControls=Join-Path $taskCaptureDir 'source-only-controls.json'
 $taskArguments=@('--max-old-space-size=256','--permission',('--allow-fs-read='+[IO.Path]::GetDirectoryName($taskNode)),('--allow-fs-read='+$taskDriver),('--allow-fs-read='+$taskInput),('--allow-fs-read='+$taskControls),$taskDriver,'--owned-original58')
 if(([string]::Join([char]0,[string[]]$taskCanonical.arguments)) -cne ([string]::Join([char]0,[string[]]$taskArguments))){Reject-Outer 'canonical_arguments' 'Canonical Node argument tuple differs from immutable runner' $taskCanonical}
 $taskExpected=$taskCanonical.live_identity
 if(Original-Absent $taskExpected){if($taskSnapshot.node_hints.Count){Reject-Outer 'node_hints' 'Unexpected surviving Node child differs from recorded original' $taskSnapshot};return @{absent=$true;canonical=$taskCanonical}}
 $taskNodeProcess=[Diagnostics.Process]::GetProcessById([int]$taskCanonical.pid)
 try{
  $taskNodeHandle=$taskNodeProcess.Handle.ToInt64()
  $taskRecord.node_inspection_handles+=@(@{pid=$taskCanonical.pid;retained_handle=$taskNodeHandle;utc=[DateTimeOffset]::UtcNow.ToString('o')});Save-Outer
  $taskLive=Live-Identity $taskNodeProcess $taskNodeHandle
  if(!(Same-Identity $taskExpected $taskLive) -or $taskLive.parent_pid -ne $taskProcess.Id){Reject-Outer 'node_live_identity' 'Canonical Node ancestry/live identity differs' $taskLive}
  if(!$Terminate){return @{absent=$false;canonical=$taskCanonical;live=$taskLive}}
  Stop-Exact $taskNodeProcess $taskExpected $taskNodeHandle $taskNodeSha
  if(!(Original-Absent $taskExpected)){Reject-Outer 'node_absence' 'Stopped canonical Node original still present' $taskLive}
  return @{absent=$true;canonical=$taskCanonical;stopped=$true;outer_retained_handle=$taskNodeHandle;cleanup_identity=$taskLive}
 }finally{
  # Only an independently opened inspection handle is closed; this is not an
  # absence assertion. CI607 retains its own Node handle/timer and pipe custody.
  $taskNodeProcess.Dispose()
 }
}
$taskStart=[Diagnostics.ProcessStartInfo]::new($taskPwsh)
$taskStart.WorkingDirectory=$taskRoot;$taskStart.UseShellExecute=$false;$taskStart.CreateNoWindow=$true
# .NET10.0.12 sets STARTF_USESTDHANDLES if any redirect is true. Input-only
# redirection explicitly passes GetStdHandle stdout/stderr to the hidden child.
$taskStart.RedirectStandardInput=$true
$taskStart.RedirectStandardOutput=$false;$taskStart.RedirectStandardError=$false
foreach($taskArg in @('-NoLogo','-NoProfile','-NonInteractive','-File',$taskRunner,'-CandidateHead',$taskHead,'-RunId',$RunId,'-RootGrant',$taskGrantPath)){$taskStart.ArgumentList.Add($taskArg)}
# StartInfo.Environment and the outer process environment are untouched.
$taskProcess=[Diagnostics.Process]::new();$taskProcess.StartInfo=$taskStart
$taskRecord=[ordered]@{status='prepared_launch';runner_launched=$false;run_id=$RunId;candidate_head=$taskHead;runner_sha256=$taskRunnerSha;helper_sha256=$PreparedSha256.ToUpperInvariant();deadline_utc=$taskDeadline.ToString('o');execution_wait_seconds=810;shared_cleanup_reserve_seconds=90;total_monotonic_seconds=900;settlement_seconds_per_stage_cap=10;environment_reset=$false;root_grant_sha256=(Get-FileHash -LiteralPath $taskGrantPath).Hash;runner_absent=$false;node_absent=$false;descendants_absent=$false;absence_state='unknown';capture_accepted=$false;expected_created=$false;outer_console_logs_saved=$false;output_custody='Underlying tool stdout/stderr handles inherited; no outer readers/copy tasks/sinks. CI607 Node raws/result and outer.json are durable authority.';identity_captures=@();absence_captures=@();canonical_receipt_reads=@();child_snapshots=@();node_inspection_handles=@();rejections=@()}
$taskHandle=0;$taskExpected=$null
try{
 [void](Remaining-Milliseconds)
 if(!$taskProcess.Start()){throw 'Dedicated -File runner did not start'}
 $taskRecord.runner_launched=$true
 $taskHandle=$taskProcess.Handle.ToInt64()
 # Persist complete known launch identity before unused-stdin close can fail.
 $taskRecord.pid=$taskProcess.Id;$taskRecord.retained_handle=$taskHandle;$taskRecord.executable=$taskPwsh;$taskRecord.executable_sha256=(Get-FileHash -LiteralPath $taskPwsh).Hash;$taskRecord.created_utc=$taskProcess.StartTime.ToUniversalTime().ToString('o');$taskRecord.arguments=@($taskStart.ArgumentList);$taskRecord.status='running_identity_pending';Save-Outer
 try{$taskProcess.StandardInput.Close()}catch{$taskRecord.stdin_close_error=$_.Exception.Message;Save-Outer;throw}
 $taskExpected=Live-Identity $taskProcess $taskHandle
 if($taskExpected.created_utc -cne $taskRecord.created_utc -or $taskExpected.executable -ine $taskPwsh){Reject-Outer 'runner_launch' 'Dedicated runner launch identity differs' $taskExpected}
 $taskRecord.live_identity=$taskExpected;$taskRecord.status='running';Save-Outer
 $taskExecutionRemaining=[int][Math]::Max(0,[Math]::Floor(810000-$taskClock.Elapsed.TotalMilliseconds))
 if(!$taskProcess.WaitForExit([Math]::Min($taskExecutionRemaining,(Remaining-Milliseconds)))){
  $taskRecord.status='deadline_negative';Save-Outer
  $taskRecord.node_reconciliation=Reconcile-Node $true;Save-Outer
  if(!$taskRecord.node_reconciliation.absent){Reject-Outer 'runner_stop' 'Node still active; runner termination forbidden'}
  if(!$taskProcess.WaitForExit((Remaining-Milliseconds 10000))){
   $taskRecord.node_reconciliation=Reconcile-Node $true;Save-Outer
   if(!$taskRecord.node_reconciliation.absent){Reject-Outer 'runner_stop' 'Node still active; runner termination forbidden'}
   Stop-Exact $taskProcess $taskExpected $taskHandle $taskRecord.executable_sha256 $true
  }
 }else{$taskRecord.status=if($taskProcess.ExitCode -eq 0){'runner_terminal0_pending_audit'}else{'runner_negative'}}
}catch{$taskRecord.status='negative_or_cleanup_blocked';$taskRecord.error=$_.Exception.Message;Save-Outer}
finally{
 try{
  if($taskRecord.runner_launched){
   $taskRecord.node_reconciliation=Reconcile-Node $false
   $taskRecord.node_absent=$taskRecord.node_reconciliation.absent
   if($taskExpected){$taskRecord.runner_absent=Original-Absent $taskExpected}
   if($taskProcess.HasExited){$taskRecord.runner_exit_code=$taskProcess.ExitCode}
   $taskFinalChildren=Descendant-Snapshot 'final_descendant_absence'
   $taskRecord.descendants_absent=$taskFinalChildren.descendants.Count -eq 0
  }else{$taskRecord.runner_absent=$true;$taskRecord.node_absent=$true;$taskRecord.descendants_absent=$true}
  if(!$taskRecord.runner_absent -or !$taskRecord.node_absent -or !$taskRecord.descendants_absent){Reject-Outer 'final_absence' 'Exact runner/Node/descendant absence unavailable; no handoff'}
  $taskRecord.absence_state='verified_originals_absent'
 }catch{$taskRecord.status='negative_or_cleanup_blocked';$taskRecord.absence_state='unknown';$taskRecord.cleanup_error=$_.Exception.Message}
 $taskRecord.expected_created=Test-Path -LiteralPath (Join-Path $taskRoot 'src/extensions/fixtures/node-crypto-sha256-package.json')
 if($taskRecord.expected_created){$taskRecord.status='negative_or_cleanup_blocked';$taskRecord.expected_error='Expected appeared before independent capture acceptance'}
 if($taskClock.Elapsed.TotalMilliseconds -ge 900000){$taskRecord.status='negative_or_cleanup_blocked';$taskRecord.absence_state='unknown';$taskRecord.deadline_error='Total900s monotonic budget exhausted; no acceptance'}
 $taskRecord.monotonic_elapsed_ms=$taskClock.Elapsed.TotalMilliseconds;$taskRecord.completed_utc=[DateTimeOffset]::UtcNow.ToString('o');Save-Outer
 # No output readers/tasks/sinks exist. Inherited tool handles remain tool-owned.
 # A blocked/unknown survivor is preserved; it is never released-as-absence.
 # The tool's pipe lifetime may extend until the child closes inherited handles.
 if(!$taskRecord.runner_launched -or $taskProcess.HasExited){$taskProcess.Dispose()}
}
$taskRecord|ConvertTo-Json -Depth 12
if($taskRecord.status -cne 'runner_terminal0_pending_audit' -or $taskRecord.absence_state -cne 'verified_originals_absent'){throw 'Outer capture supervisor negative; no expected publication'}
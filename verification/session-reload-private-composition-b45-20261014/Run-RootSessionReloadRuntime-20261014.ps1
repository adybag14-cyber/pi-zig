param([ValidateSet('Debug','ReleaseSafe')][string]$Mode='Debug',[string]$Attempt='first')
$ErrorActionPreference='Stop'
$taskEvidence=$PSScriptRoot
$taskPrivate='C:/Users/adyba/pi-zig-native-session-factory-composition-20261013'
$taskName="root-sdk-session-reload-runtime-$($Mode.ToLowerInvariant())-$Attempt-20261014"
$taskTargets=@('test-native-sdk-session-reload')
$taskZig='C:/Users/adyba/pi-zig-toolchain-20261003/zig-x86_64-windows-0.16.0/zig.exe'
function Source-Rows {
 @(git -C $taskPrivate ls-files --cached --others --exclude-standard|Sort-Object -Unique|Where-Object{Test-Path -LiteralPath (Join-Path $taskPrivate $_) -PathType Leaf}|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath (Join-Path $taskPrivate $_)).Hash}})
}
function Tool-Drift($rows){
 $mismatches=[Collections.Generic.List[string]]::new()
 foreach($row in $rows){
  if(!(Test-Path -LiteralPath $row.path -PathType Leaf)){$mismatches.Add($row.path);continue}
  $stream=[IO.File]::OpenRead($row.path)
  try{$actual=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream))}finally{$stream.Dispose()}
  if($actual -cne $row.sha256){$mismatches.Add($row.path)}
 }
 return @($mismatches)
}
$taskBefore=Source-Rows
$taskBefore|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-source-before.json") -Encoding utf8NoBOM
$taskTools=(Get-Content -LiteralPath (Join-Path $taskEvidence 'durable-latest89-full-inspect-53ae-tool-prehash-20261011.json') -Raw|ConvertFrom-Json).inputs
$taskDrift=@(Tool-Drift $taskTools)
if($taskDrift.Count){throw 'Native tool prehash mismatch'}
if((Get-FileHash -LiteralPath $taskZig).Hash -cne '086CE9D47BA42F33A514E1A6E04EB1D4A8FA1D75E0868E0213CAAD447C91E864'){throw 'Pinned Zig SHA256 changed'}
$taskOwnedHeapBefore=[GC]::GetTotalMemory($false)
$taskOwnedWorkingSetBefore=[Diagnostics.Process]::GetCurrentProcess().WorkingSet64
[GC]::Collect()
[GC]::WaitForPendingFinalizers()
[GC]::Collect()
[ordered]@{scope='Only this owned PowerShell wrapper managed heap; retained frozen source/tool arrays unchanged';heap_before=$taskOwnedHeapBefore;heap_after=[GC]::GetTotalMemory($false);working_set_before=$taskOwnedWorkingSetBefore;working_set_after=[Diagnostics.Process]::GetCurrentProcess().WorkingSet64;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-owned-wrapper-gc.json") -Encoding utf8NoBOM
$taskFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
$taskOtherNative=@(Get-CimInstance Win32_Process -Filter "Name = 'zig.exe'"|Select-Object ProcessId,ParentProcessId,ExecutablePath,CommandLine,@{n='created_utc';e={([DateTimeOffset]$_.CreationDate).UtcDateTime.ToString('o')}})
$taskBuildRoots=@($taskOtherNative|Where-Object{$_.CommandLine -match '\sbuild\s'})
if($taskBuildRoots.Count -ge 2){[ordered]@{status='admission_failed_native_capacity';max_native_jobs=2;other_build_roots=$taskBuildRoots;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 6|Tee-Object -FilePath (Join-Path $taskEvidence "$taskName-admission.json");exit 3}
$taskThreshold=16MB
$taskAdmission=[ordered]@{status=if($taskFree -lt $taskThreshold){'admission_failed'}else{'admitted'};free_kib=$taskFree;threshold_kib=$taskThreshold;single_job_threshold_kib=16MB;concurrent_job_threshold_kib=16MB;policy_authority='Root normal16GiB admission; maximum two coordinated native reservations';calibration='Normal16GiB floor; no calibrated8GiB fallback';calibration_evidence=(Join-Path $taskEvidence 'root-rs-install-compile-20261013.stderr.log');other_native=$taskOtherNative;source=$taskBefore.Count;tools=$taskTools.Count;native_launched=$false;llvm='true';jobs=1;test_timeout_seconds=120;outer_timeout_seconds=300;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}
$taskAdmission|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-admission.json") -Encoding utf8NoBOM
if($taskFree -lt $taskThreshold){
 $taskAdmission|ConvertTo-Json -Depth 6
 exit 2
}
& (Join-Path $taskEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1') -Name $taskName -Executable $taskZig -WorkingDirectory $taskPrivate -Arguments (@('build')+$taskTargets+@("-Doptimize=$Mode",'-Duse-llvm=true','-j1','--test-timeout','120s','--summary','all')) -TimeoutSeconds 300
$taskAfter=Source-Rows
$taskSourceDrift=@(Compare-Object ($taskBefore|ForEach-Object{"$($_.path):$($_.sha256)"}) ($taskAfter|ForEach-Object{"$($_.path):$($_.sha256)"}))
$taskDrift=@(Tool-Drift $taskTools)
[ordered]@{source=$taskBefore.Count;source_after=$taskAfter.Count;source_drift=$taskSourceDrift.Count;tools=$taskTools.Count;tool_drift=$taskDrift.Count;admitted_free_kib=$taskFree;threshold_kib=$taskThreshold;admission_policy='normal16GiB with coordinated maximum two native reservations';completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Tee-Object -FilePath (Join-Path $taskEvidence "$taskName-posthash.json")
if($taskSourceDrift.Count -or $taskDrift.Count){throw 'Native posthash mismatch'}
$taskResult=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName.json") -Raw|ConvertFrom-Json
if($taskResult.status -cne 'passed'){throw "Native terminal $($taskResult.status)"}

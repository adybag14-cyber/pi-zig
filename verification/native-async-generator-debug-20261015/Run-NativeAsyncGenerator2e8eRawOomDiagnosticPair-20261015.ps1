$ErrorActionPreference='Stop'
$taskEvidence=$PSScriptRoot
$taskPrivate='C:/Users/adyba/pi-zig-ai-native-async-generator-20261015'
$taskExpectedHead='2e8e6dbe1e2f8c4d0359ef81990373fd23fff254'
$taskName='native-async-generator-2e8e6dbe-debug-raw-oom-diagnostic-20261015'
$taskZig='C:/Users/adyba/pi-zig-toolchain-20261003/zig-x86_64-windows-0.16.0/zig.exe'
$taskOwner=Join-Path $taskEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1'
$taskToolReference=Join-Path $taskEvidence 'durable-latest89-full-inspect-53ae-tool-prehash-20261011.json'
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
if((git -C $taskPrivate rev-parse HEAD) -cne $taskExpectedHead -or (git -C $taskPrivate status --porcelain)){throw 'Exact clean candidate required'}
$taskBefore=Source-Rows
$taskTools=(Get-Content -LiteralPath $taskToolReference -Raw|ConvertFrom-Json).inputs
if($taskTools.Count -ne 19546){throw 'Full compiler manifest required'}
$taskControls=@($PSCommandPath,$taskOwner,$taskToolReference)|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}}
if((Get-FileHash -LiteralPath $taskZig).Hash -cne '086CE9D47BA42F33A514E1A6E04EB1D4A8FA1D75E0868E0213CAAD447C91E864'){throw 'Pinned Zig SHA256 changed'}
$taskBefore|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-source-before.json") -Encoding utf8NoBOM
$taskControls|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-controls-before.json") -Encoding utf8NoBOM
if(@(Tool-Drift $taskTools).Count){throw 'Compiler prehash drift'}
if(@(Tool-Drift $taskControls).Count){throw 'Control prehash drift'}
[GC]::Collect();[GC]::WaitForPendingFinalizers();[GC]::Collect()
$taskFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
$taskOtherNative=@(Get-CimInstance Win32_Process -Filter "Name = 'zig.exe'"|Select-Object ProcessId,ParentProcessId,ExecutablePath,CommandLine,@{n='created_utc';e={([DateTimeOffset]$_.CreationDate).UtcDateTime.ToString('o')}})
$taskBuildRoots=@($taskOtherNative|Where-Object{$_.CommandLine -match '\sbuild\s'})
$taskAdmission=[ordered]@{status=if($taskFree -lt 16MB -or $taskBuildRoots.Count -ge 4){'admission_failed'}else{'admitted'};candidate=$taskExpectedHead;slot=1;free_kib=$taskFree;threshold_kib=16MB;max_native_roots=4;other_native=$taskOtherNative;source=$taskBefore.Count;tools=$taskTools.Count;controls=$taskControls.Count;jobs=1;llvm=$true;compile_timeout_seconds=1320;runtime_outer_timeout_seconds=300;test_timeout_seconds=120;host_await_timeout_seconds=10;native_launched=$false;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}
$taskAdmission|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-admission.json") -Encoding utf8NoBOM
if($taskAdmission.status -cne 'admitted'){$taskAdmission|ConvertTo-Json -Depth 6;exit 2}
& $taskOwner -Name "$taskName-compile" -Executable $taskZig -WorkingDirectory $taskPrivate -Arguments @('build','build-native-async-generator-oom-diagnostic','-Doptimize=Debug','-Duse-llvm=true','-j1','--test-timeout','120s','--summary','all') -TimeoutSeconds 1320
$taskCompile=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName-compile.json") -Raw|ConvertFrom-Json
$taskRuntime=$null
if($taskCompile.status -ceq 'passed'){
 $taskBetween=Source-Rows
 if(@(Compare-Object ($taskBefore|ForEach-Object{"$($_.path):$($_.sha256)"}) ($taskBetween|ForEach-Object{"$($_.path):$($_.sha256)"})).Count -or @(Tool-Drift $taskTools).Count -or @(Tool-Drift $taskControls).Count){throw 'Frozen pair drift before runtime'}
 $taskRuntimeFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
 if($taskRuntimeFree -lt 16MB){throw 'Fresh runtime admission below normal16GiB'}
 & $taskOwner -Name "$taskName-runtime" -Executable (Join-Path $taskPrivate 'zig-out/bin/native-generator-oom-diagnostic.exe') -WorkingDirectory $taskPrivate -Arguments @('--seed','0') -TimeoutSeconds 120
 $taskRuntime=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName-runtime.json") -Raw|ConvertFrom-Json
}
$taskAfter=Source-Rows
$taskSourceDrift=@(Compare-Object ($taskBefore|ForEach-Object{"$($_.path):$($_.sha256)"}) ($taskAfter|ForEach-Object{"$($_.path):$($_.sha256)"}))
$taskToolDrift=@(Tool-Drift $taskTools)
$taskControlDrift=@(Tool-Drift $taskControls)
[ordered]@{candidate=$taskExpectedHead;source=$taskBefore.Count;source_after=$taskAfter.Count;source_drift=$taskSourceDrift.Count;tools=$taskTools.Count;tool_drift=$taskToolDrift.Count;controls=$taskControls.Count;control_drift=$taskControlDrift.Count;compile=$taskCompile.status;runtime=if($taskRuntime){$taskRuntime.status}else{'not_run'};completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Tee-Object -FilePath (Join-Path $taskEvidence "$taskName-posthash.json")
if($taskSourceDrift.Count -or $taskToolDrift.Count -or $taskControlDrift.Count){throw 'Frozen pair terminal posthash mismatch'}
if($taskCompile.status -cne 'passed' -or !$taskRuntime -or $taskRuntime.status -cne 'passed'){exit 1}

param([Parameter(Mandatory)][string]$ExpectedHead,[ValidateSet('unit','process')][string]$Stage='unit',[string]$Attempt='first')
$ErrorActionPreference='Stop'
$taskEvidence='C:/Users/adyba/pi-zig-update-evidence-20261003'
$taskPrivate='C:/Users/adyba/pi-zig-ui-overlay-ae7-20261015'
$taskExpectedHead=$ExpectedHead
$taskName="ui-overlay-ae7-$Stage-$Attempt-debug-20261015"
$taskBuildTarget=if($Stage -ceq 'unit'){'build-ui-overlay-ae7'}else{'build-ui-overlay-ae7-process'}
$taskTestTarget=if($Stage -ceq 'unit'){'test-ui-overlay-ae7'}else{'test-ui-overlay-ae7-process'}
$taskZig='C:/Users/adyba/pi-zig-toolchain-20261003/zig-x86_64-windows-0.16.0/zig.exe'
$taskOwner=Join-Path $taskEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1'
$taskToolReference=Join-Path $taskEvidence 'durable-latest89-full-inspect-53ae-tool-prehash-20261011.json'
$taskOriginal=Join-Path $taskEvidence 'ui-overlay-ae7-source12-first-20261015-output.json'
$taskSourcePost=Join-Path $taskEvidence 'ui-overlay-ae7-source12-first-20261015-posthash.json'
$taskSourceOwner=Join-Path $taskEvidence 'ui-overlay-ae7-source12-first-20261015.json'
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
if((Get-FileHash -LiteralPath $taskOriginal).Hash -cne 'CBC8607F5645ABB7B277F99C9D5A03C0AF46721700576213728CEDA280BDEF50' -or (Get-FileHash -LiteralPath (Join-Path $taskPrivate 'src/extensions/fixtures/ui-overlay-ae7-original.json')).Hash -cne (Get-FileHash -LiteralPath $taskOriginal).Hash){throw 'Genuine original Source12 identity changed'}
$taskProof=Get-Content -LiteralPath $taskSourcePost -Raw|ConvertFrom-Json
if(@($taskProof.manifests|Where-Object drift -ne 0).Count -or @($taskProof.extra_control_drift).Count -or $taskProof.control_manifest_drift -or @($taskProof.absent_dependency_drift).Count -or (Get-Content -LiteralPath $taskSourceOwner -Raw|ConvertFrom-Json).status -cne 'passed'){throw 'Original Source12 terminal posthash proof missing'}
$taskBefore=Source-Rows
$taskTools=(Get-Content -LiteralPath $taskToolReference -Raw|ConvertFrom-Json).inputs
if($taskTools.Count -ne 19546){throw 'Full compiler manifest required'}
$taskControls=@($PSCommandPath,$taskOwner,$taskToolReference,$taskOriginal,$taskSourcePost,$taskSourceOwner)|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}}
if((Get-FileHash -LiteralPath $taskZig).Hash -cne '086CE9D47BA42F33A514E1A6E04EB1D4A8FA1D75E0868E0213CAAD447C91E864'){throw 'Pinned Zig SHA256 changed'}
$taskBefore|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-source-before.json") -Encoding utf8NoBOM
$taskControls|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-controls-before.json") -Encoding utf8NoBOM
if(@(Tool-Drift $taskTools).Count){throw 'Compiler prehash drift'}
if(@(Tool-Drift $taskControls).Count){throw 'Control prehash drift'}
[GC]::Collect();[GC]::WaitForPendingFinalizers();[GC]::Collect()
$taskFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
$taskOtherNative=@(Get-CimInstance Win32_Process -Filter "Name = 'zig.exe'"|Select-Object ProcessId,ParentProcessId,ExecutablePath,CommandLine,@{n='created_utc';e={([DateTimeOffset]$_.CreationDate).UtcDateTime.ToString('o')}})
$taskBuildRoots=@($taskOtherNative|Where-Object{$_.CommandLine -match '\sbuild\s'})
$taskAdmission=[ordered]@{status=if($taskFree -lt 16MB -or $taskBuildRoots.Count -ge 4){'admission_failed'}else{'admitted'};candidate=$taskExpectedHead;slot=4;free_kib=$taskFree;threshold_kib=16MB;max_native_roots=4;other_native=$taskOtherNative;source=$taskBefore.Count;tools=$taskTools.Count;controls=$taskControls.Count;jobs=1;llvm=$true;compile_timeout_seconds=1320;runtime_outer_timeout_seconds=300;test_timeout_seconds=120;host_await_timeout_seconds=10;native_launched=$false;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}
$taskAdmission|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-admission.json") -Encoding utf8NoBOM
if($taskAdmission.status -cne 'admitted'){$taskAdmission|ConvertTo-Json -Depth 6;exit 2}
& $taskOwner -Name "$taskName-compile" -Executable $taskZig -WorkingDirectory $taskPrivate -Arguments @('build',$taskBuildTarget,'-Doptimize=Debug','-Duse-llvm=true','-j1','--test-timeout','120s','--summary','all') -TimeoutSeconds 1320
$taskCompile=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName-compile.json") -Raw|ConvertFrom-Json
$taskRuntime=$null
if($taskCompile.status -ceq 'passed'){
 $taskBetween=Source-Rows
 if(@(Compare-Object ($taskBefore|ForEach-Object{"$($_.path):$($_.sha256)"}) ($taskBetween|ForEach-Object{"$($_.path):$($_.sha256)"})).Count -or @(Tool-Drift $taskTools).Count -or @(Tool-Drift $taskControls).Count){throw 'Frozen pair drift before runtime'}
 $taskRuntimeFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
 if($taskRuntimeFree -lt 16MB){throw 'Fresh runtime admission below normal16GiB'}
 & $taskOwner -Name "$taskName-runtime" -Executable $taskZig -WorkingDirectory $taskPrivate -Arguments @('build',$taskTestTarget,'-Doptimize=Debug','-Duse-llvm=true','-j1','--test-timeout','120s','--summary','all') -TimeoutSeconds 300
 $taskRuntime=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName-runtime.json") -Raw|ConvertFrom-Json
}
$taskAfter=Source-Rows
$taskSourceDrift=@(Compare-Object ($taskBefore|ForEach-Object{"$($_.path):$($_.sha256)"}) ($taskAfter|ForEach-Object{"$($_.path):$($_.sha256)"}))
$taskToolDrift=@(Tool-Drift $taskTools)
$taskControlDrift=@(Tool-Drift $taskControls)
[ordered]@{candidate=$taskExpectedHead;source=$taskBefore.Count;source_after=$taskAfter.Count;source_drift=$taskSourceDrift.Count;tools=$taskTools.Count;tool_drift=$taskToolDrift.Count;controls=$taskControls.Count;control_drift=$taskControlDrift.Count;compile=$taskCompile.status;runtime=if($taskRuntime){$taskRuntime.status}else{'not_run'};completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Tee-Object -FilePath (Join-Path $taskEvidence "$taskName-posthash.json")
if($taskSourceDrift.Count -or $taskToolDrift.Count -or $taskControlDrift.Count){throw 'Frozen pair terminal posthash mismatch'}
if($taskCompile.status -cne 'passed' -or !$taskRuntime -or $taskRuntime.status -cne 'passed'){exit 1}

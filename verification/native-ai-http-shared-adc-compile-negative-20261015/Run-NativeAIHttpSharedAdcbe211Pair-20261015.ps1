$ErrorActionPreference='Stop'
$taskEvidence=$PSScriptRoot
$taskPrivate='C:/Users/adyba/pi-zig-ai-http-followup-20261015'
$taskExpectedHead='adcbe211b60d4910819185c5cb74459583fbf4eb'
$taskName='native-ai-http-shared-adcbe211-debug-20261015'
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
$taskReferenceSpecs=@(
 @{name='sourceae7';file='sourceae7-full-manifest-20261015.json';count=1968},
 @{name='dependencies';file='sourceae7-runtime-manifest-20261015.json';count=31064},
 @{name='node_tools';file='sourceae7-node-tools-before-20261015.json';count=1774}
)
$taskReferences=@()
foreach($taskSpec in $taskReferenceSpecs){
 $taskRows=@(Get-Content -LiteralPath (Join-Path $taskEvidence $taskSpec.file) -Raw|ConvertFrom-Json)
 if($taskRows.Count -ne $taskSpec.count -or @(Tool-Drift $taskRows).Count){throw "Exact reference prehash mismatch $($taskSpec.name)"}
 $taskReferences+=@{name=$taskSpec.name;rows=$taskRows}
}
$taskDependencyAudit=Join-Path $taskEvidence 'sourceae7-dependency-contract-audit-20261015.json'
$taskAudit=Get-Content -LiteralPath $taskDependencyAudit -Raw|ConvertFrom-Json
if($taskAudit.latestHead -cne 'ae7b16d43b7c78c5b6fa3213fdd1215bb339729d' -or $taskAudit.installed_metadata_verified -ne 281 -or $taskAudit.platform_optional_absent_records -ne 80 -or $taskAudit.historical_missing_records_retained -ne 4){throw 'Exact ae7 dependency authority mismatch'}
$taskRuntimeRoot='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012'
$taskAbsences=@($taskAudit.pins|Where-Object status -eq 'platform_optional_absent'|ForEach-Object{Join-Path $taskRuntimeRoot $_.path})+@($taskAudit.mismatches|ForEach-Object{Join-Path $taskRuntimeRoot $_.path})
if($taskAbsences.Count -ne 84 -or @($taskAbsences|Where-Object{Test-Path -LiteralPath $_}).Count){throw 'Historical absence mismatch'}
$taskProof=Join-Path $taskEvidence 'event-stream-live-ae7-source27-first-20261015-output.json'
if((Get-FileHash -LiteralPath $taskProof).Hash -cne 'B74A17B8334C000C8A9BD595A0C3273C58DF82A9BBC644BB200F982E5942C31F' -or (Get-FileHash -LiteralPath (Join-Path $taskPrivate 'src/extensions/fixtures/event-stream-live-ae7-source27.json')).Hash -cne 'B74A17B8334C000C8A9BD595A0C3273C58DF82A9BBC644BB200F982E5942C31F'){throw 'Actual Source27 fixture changed'}
if((Get-FileHash -LiteralPath (Join-Path $taskPrivate 'vendor/quickjs/quickjs.c')).Hash -cne 'ED1F3A59AD13DE57B32CCA164FC42D347C463632F0B8A1921DC79621E79DE69E' -or (Get-FileHash -LiteralPath (Join-Path $taskPrivate 'vendor/quickjs/quickjs.h')).Hash -cne '91A39801056D4B4DA6A1B357AD09A20BA61AD3C669D3EEE219F781B4A56ACA28'){throw 'Reviewed C/header changed'}
$taskControlPaths=@($PSCommandPath,$taskOwner,$taskToolReference,$taskDependencyAudit,$taskProof,(Join-Path $taskEvidence 'sourceae7-observe-20261015.mjs'),(Join-Path $taskEvidence 'Run-EventStreamLiveAe7Source27-20261015.ps1'),(Join-Path $taskEvidence 'event-stream-live-ae7-source27-first-20261015-extra-before.json'),(Join-Path $taskEvidence 'event-stream-live-ae7-source27-first-20261015.json'),(Join-Path $taskEvidence 'event-stream-live-ae7-source27-first-20261015-posthash.json'),(Join-Path $taskEvidence 'event-stream-live-surface-ae7-source27-observe-20261015.mjs'),(Join-Path $taskEvidence 'sourceae7-preparation-controls-20261015.json'),(Join-Path $taskEvidence 'sourceae7-preparation-readiness-20261015.json'))+@($taskReferenceSpecs|ForEach-Object{Join-Path $taskEvidence $_.file})
$taskControls=@($taskControlPaths|Sort-Object -Unique|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})
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
& $taskOwner -Name "$taskName-compile" -Executable $taskZig -WorkingDirectory $taskPrivate -Arguments @('build','build-native-ai-http','-Doptimize=Debug','-Duse-llvm=true','-j1','--test-timeout','120s','--summary','all') -TimeoutSeconds 1320
$taskCompile=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName-compile.json") -Raw|ConvertFrom-Json
$taskRuntime=$null
if($taskCompile.status -ceq 'passed'){
 $taskBetween=Source-Rows
 if(@(Compare-Object ($taskBefore|ForEach-Object{"$($_.path):$($_.sha256)"}) ($taskBetween|ForEach-Object{"$($_.path):$($_.sha256)"})).Count -or @(Tool-Drift $taskTools).Count -or @(Tool-Drift $taskControls).Count){throw 'Frozen pair drift before runtime'}
 foreach($taskRef in $taskReferences){if(@(Tool-Drift $taskRef.rows).Count){throw "Reference pair drift before runtime $($taskRef.name)"}}
 if(@($taskAbsences|Where-Object{Test-Path -LiteralPath $_}).Count){throw 'Historical absence changed before runtime'}
 $taskRuntimeFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
 if($taskRuntimeFree -lt 16MB){throw 'Fresh runtime admission below normal16GiB'}
 & $taskOwner -Name "$taskName-runtime" -Executable $taskZig -WorkingDirectory $taskPrivate -Arguments @('build','test-native-ai-http','-Doptimize=Debug','-Duse-llvm=true','-j1','--test-timeout','120s','--summary','all') -TimeoutSeconds 300
 $taskRuntime=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName-runtime.json") -Raw|ConvertFrom-Json
}
$taskAfter=Source-Rows
$taskSourceDrift=@(Compare-Object ($taskBefore|ForEach-Object{"$($_.path):$($_.sha256)"}) ($taskAfter|ForEach-Object{"$($_.path):$($_.sha256)"}))
$taskToolDrift=@(Tool-Drift $taskTools)
$taskControlDrift=@(Tool-Drift $taskControls)
$taskReferencePost=@(foreach($taskRef in $taskReferences){@{name=$taskRef.name;files=$taskRef.rows.Count;drift=@(Tool-Drift $taskRef.rows).Count}})
$taskAbsenceDrift=@($taskAbsences|Where-Object{Test-Path -LiteralPath $_})
$taskReferencePost|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-reference-posthash.json") -Encoding utf8NoBOM
if(@($taskReferencePost|Where-Object drift -ne 0).Count -or $taskAbsenceDrift.Count){throw 'Frozen reference/absence posthash mismatch'}
[ordered]@{candidate=$taskExpectedHead;source=$taskBefore.Count;source_after=$taskAfter.Count;source_drift=$taskSourceDrift.Count;tools=$taskTools.Count;tool_drift=$taskToolDrift.Count;controls=$taskControls.Count;control_drift=$taskControlDrift.Count;compile=$taskCompile.status;runtime=if($taskRuntime){$taskRuntime.status}else{'not_run'};completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Tee-Object -FilePath (Join-Path $taskEvidence "$taskName-posthash.json")
if($taskSourceDrift.Count -or $taskToolDrift.Count -or $taskControlDrift.Count){throw 'Frozen pair terminal posthash mismatch'}
if($taskCompile.status -cne 'passed' -or !$taskRuntime -or $taskRuntime.status -cne 'passed'){exit 1}

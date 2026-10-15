$ErrorActionPreference='Stop'
$taskEvidence=$PSScriptRoot
$taskPrivate='C:/Users/adyba/pi-zig-native-responses-ws-20261015'
$taskExpectedHead='b58822549ce99645cfe137f0b48148cfd2ea57da'
$taskName='native-ai-responses-socket-b5882254-debug-first-20261015'
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
if(Test-Path -LiteralPath (Join-Path $taskEvidence "$taskName-admission.json")){throw 'Refuse replay of immutable owned pair name'}
$taskBefore=Source-Rows
$taskTools=(Get-Content -LiteralPath $taskToolReference -Raw|ConvertFrom-Json).inputs
if($taskTools.Count -ne 19546){throw 'Full compiler manifest required'}
$taskSourceRoot='C:/Users/adyba/pi-upstream-source-5ab7fe7-20261015'
$taskRuntimeRoot='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012'
if((git -C $taskSourceRoot rev-parse HEAD) -cne '5ab7fe74c400097b386662205cd93900695b8a71'){throw 'Original Source head drift'}
$taskReferenceSpecs=@(
 @{name='original_source';file='source5ab-full-manifest-20261015.json';count=1967},
 @{name='dependencies';file='durable-19cb534-reference-20261012-all-built-runtime.json';count=31064},
 @{name='node_tools';file='root-current8a-npm-tools-before.json';count=1774}
)
$taskReferences=[ordered]@{}
foreach($spec in $taskReferenceSpecs){
 $rows=@(Get-Content -LiteralPath (Join-Path $taskEvidence $spec.file) -Raw|ConvertFrom-Json)
 if($rows.Count -ne $spec.count -or @(Tool-Drift $rows).Count){throw "Full reference prehash/count drift $($spec.name)"}
 $taskReferences[$spec.name]=$rows
}
$taskVendor=@($taskBefore|Where-Object{$_.path -like 'vendor/*'}|ForEach-Object{[ordered]@{path=(Join-Path $taskPrivate $_.path);sha256=$_.sha256}})
if($taskVendor.Count -ne 1316 -or @(Tool-Drift $taskVendor).Count){throw 'Complete candidate vendor inventory drift'}
$taskReferences['vendor']=$taskVendor
$taskAudit=Join-Path $taskEvidence 'source5ab-dependency-contract-audit-20261015.json'
$taskContract=Get-Content -LiteralPath $taskAudit -Raw|ConvertFrom-Json
if($taskContract.latestHead -cne '5ab7fe74c400097b386662205cd93900695b8a71' -or $taskContract.installed_metadata_verified -ne 281 -or $taskContract.platform_optional_absent_records -ne 80 -or $taskContract.historical_missing_records_retained -ne 4){throw 'Dependency authority drift'}
$taskAbsent=@($taskContract.pins|Where-Object status -eq 'platform_optional_absent'|ForEach-Object{Join-Path $taskRuntimeRoot $_.path})+@($taskContract.mismatches|ForEach-Object{Join-Path $taskRuntimeRoot $_.path})
if($taskAbsent.Count -ne 84 -or @($taskAbsent|Where-Object{Test-Path -LiteralPath $_}).Count){throw 'Historical dependency absence drift'}
$taskProofPaths=@(Get-ChildItem -LiteralPath (Join-Path $taskPrivate 'verification/native-codex-socket10-source-20261015') -File|ForEach-Object{$_.FullName})
$taskControlPaths=@($PSCommandPath,$taskOwner,$taskToolReference,$taskAudit,(Join-Path $taskEvidence 'ai-codex-socket10-owned-timers-5ab-source10-first-20261015-output.json'),(Join-Path $taskEvidence 'ai-codex-socket10-owned-timers-5ab-source10-first-20261015-posthash.json'),(Join-Path $taskEvidence 'source5ab-codex-socket-owned-timers-capture-20261015.mjs'),(Join-Path $taskEvidence 'Run-AiCodexSocket10OwnedTimersSource-20261015.ps1'))+@($taskReferenceSpecs|ForEach-Object{Join-Path $taskEvidence $_.file})+$taskProofPaths
$taskControls=@($taskControlPaths|Sort-Object -Unique|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})
if((Get-FileHash -LiteralPath (Join-Path $taskPrivate 'src/extensions/fixtures/ai-codex-socket10-5ab.protocol.json')).Hash -cne 'ED00FFEF9641555184F3244E68138DF6EDCA4449FC35814E6E0E31E7A61CE1DE'){throw 'Genuine Socket10 fixture changed'}
if((Get-FileHash -LiteralPath 'C:/Program Files/nodejs/node.exe').Hash -cne '63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088'){throw 'Pinned Node changed'}
if((Get-FileHash -LiteralPath $taskZig).Hash -cne '086CE9D47BA42F33A514E1A6E04EB1D4A8FA1D75E0868E0213CAAD447C91E864'){throw 'Pinned Zig SHA256 changed'}
$taskBefore|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-source-before.json") -Encoding utf8NoBOM
$taskControls|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-controls-before.json") -Encoding utf8NoBOM
$taskReferences|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-references-before.json") -Encoding utf8NoBOM
$taskAbsent|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-absences-before.json") -Encoding utf8NoBOM
if(@(Tool-Drift $taskTools).Count){throw 'Compiler prehash drift'}
if(@(Tool-Drift $taskControls).Count){throw 'Control prehash drift'}
[GC]::Collect();[GC]::WaitForPendingFinalizers();[GC]::Collect()
$taskFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
$taskOtherNative=@(Get-CimInstance Win32_Process -Filter "Name = 'zig.exe'"|Select-Object ProcessId,ParentProcessId,ExecutablePath,CommandLine,@{n='created_utc';e={([DateTimeOffset]$_.CreationDate).UtcDateTime.ToString('o')}})
$taskBuildRoots=@($taskOtherNative|Where-Object{$_.CommandLine -match '\sbuild\s'})
$taskAdmission=[ordered]@{status=if($taskFree -lt 16MB -or $taskBuildRoots.Count -ge 4){'admission_failed'}else{'admitted'};candidate=$taskExpectedHead;slot=1;free_kib=$taskFree;threshold_kib=16MB;max_native_roots=4;other_native=$taskOtherNative;source=$taskBefore.Count;tools=$taskTools.Count;vendor=$taskVendor.Count;original_source=1967;dependencies=31064;node_tools=1774;absences=84;controls=$taskControls.Count;jobs=1;llvm=$true;compile_timeout_seconds=1320;runtime_outer_timeout_seconds=300;test_timeout_seconds=120;host_await_timeout_seconds=10;native_launched=$false;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}
$taskAdmission|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-admission.json") -Encoding utf8NoBOM
if($taskAdmission.status -cne 'admitted'){$taskAdmission|ConvertTo-Json -Depth 6;exit 2}
$taskAdmission.native_launched=$true
$taskAdmission|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-admission.json") -Encoding utf8NoBOM
& $taskOwner -Name "$taskName-compile" -Executable $taskZig -WorkingDirectory $taskPrivate -Arguments @('build','build-native-ai-responses','build-native-ai-codex-socket-wire','-Doptimize=Debug','-Duse-llvm=true','-j1','--test-timeout','120s','--summary','all') -TimeoutSeconds 1320
$taskCompile=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName-compile.json") -Raw|ConvertFrom-Json
$taskRuntime=$null
if($taskCompile.status -ceq 'passed'){
 $taskBetween=Source-Rows
 $taskBetweenDrift=@(Compare-Object ($taskBefore|ForEach-Object{"$($_.path):$($_.sha256)"}) ($taskBetween|ForEach-Object{"$($_.path):$($_.sha256)"})).Count+@(Tool-Drift $taskTools).Count+@(Tool-Drift $taskControls).Count
 foreach($rows in $taskReferences.Values){$taskBetweenDrift+=@(Tool-Drift $rows).Count}
 $taskBetweenDrift+=@($taskAbsent|Where-Object{Test-Path -LiteralPath $_}).Count
 $taskRuntimeFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
 [ordered]@{slot=1;free_kib=$taskRuntimeFree;minimum_kib=16MB;between_drift=$taskBetweenDrift;status=if($taskRuntimeFree -lt 16MB -or $taskBetweenDrift){'admission_failed'}else{'admitted'}}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-runtime-admission.json") -Encoding utf8NoBOM
 if($taskRuntimeFree -ge 16MB -and !$taskBetweenDrift){
  & $taskOwner -Name "$taskName-runtime" -Executable $taskZig -WorkingDirectory $taskPrivate -Arguments @('build','test-native-ai-responses','test-native-ai-codex-socket-wire','-Doptimize=Debug','-Duse-llvm=true','-j1','--test-timeout','120s','--summary','all') -TimeoutSeconds 300
  $taskRuntime=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName-runtime.json") -Raw|ConvertFrom-Json
 }
}
$taskAfter=Source-Rows
$taskSourceDrift=@(Compare-Object ($taskBefore|ForEach-Object{"$($_.path):$($_.sha256)"}) ($taskAfter|ForEach-Object{"$($_.path):$($_.sha256)"}))
$taskToolDrift=@(Tool-Drift $taskTools)
$taskControlDrift=@(Tool-Drift $taskControls)
$taskReferencePost=@();foreach($key in $taskReferences.Keys){$drift=@(Tool-Drift $taskReferences[$key]);$taskReferencePost+=@{group=$key;count=$taskReferences[$key].Count;drift=$drift.Count;changed=$drift}}
$taskAbsentDrift=@($taskAbsent|Where-Object{Test-Path -LiteralPath $_})
[ordered]@{candidate=$taskExpectedHead;slot=1;source=$taskBefore.Count;source_after=$taskAfter.Count;source_drift=$taskSourceDrift.Count;tools=$taskTools.Count;tool_drift=$taskToolDrift.Count;references=$taskReferencePost;absences=$taskAbsent.Count;absence_drift=$taskAbsentDrift.Count;controls=$taskControls.Count;control_drift=$taskControlDrift.Count;compile=$taskCompile.status;runtime=if($taskRuntime){$taskRuntime.status}else{'not_run'};source_lifecycle_qualified=$false;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 6|Tee-Object -FilePath (Join-Path $taskEvidence "$taskName-posthash.json")
if($taskSourceDrift.Count -or $taskToolDrift.Count -or $taskControlDrift.Count -or @($taskReferencePost|Where-Object drift -ne 0).Count -or $taskAbsentDrift.Count){throw 'Frozen pair terminal posthash mismatch'}
if($taskCompile.status -cne 'passed' -or !$taskRuntime -or $taskRuntime.status -cne 'passed'){exit 1}

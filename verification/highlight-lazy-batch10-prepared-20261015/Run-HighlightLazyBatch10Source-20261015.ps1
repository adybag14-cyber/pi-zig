param([Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{40}$')][string]$CandidateHead,[string]$Evidence='C:/Users/adyba/pi-zig-update-evidence-20261003')
$ErrorActionPreference='Stop'
$taskEvidence=$Evidence
$taskPrivate='C:/Users/adyba/pi-zig-highlight-lazy-batch10-20261015'
$taskNode='C:/Program Files/nodejs/node.exe'
$taskSource='C:/Users/adyba/pi-upstream-source-5ab7fe7-20261015'
$taskName='highlight-lazy-batch10-source113-first-20261015'
$taskInput=Join-Path $taskPrivate 'src/extensions/fixtures/sdk-highlight-lazy-batch10-10_7_3.input.txt'
$taskDriver=Join-Path $PSScriptRoot 'capture-highlight-lazy-batch10-20261015.mjs'
$taskObserver=Join-Path $taskEvidence 'source5ab-observe-20261015.mjs'
$taskOutput=Join-Path $taskEvidence "$taskName-output.json"
$taskClock=[Diagnostics.Stopwatch]::StartNew()
function Check-Deadline {if($taskClock.Elapsed.TotalSeconds -gt 600){throw 'Source owner ten-minute operation deadline reached'}}
function Check-Rows($rows){
 @($rows|Where-Object{Check-Deadline;!(Test-Path -LiteralPath $_.path -PathType Leaf) -or (Get-FileHash -LiteralPath $_.path).Hash -ine $_.sha256})
}
function Candidate-Rows {
 @(git -c gc.auto=0 -c maintenance.auto=false -c pack.threads=2 -c pack.windowMemory=64m -C $taskPrivate ls-files --cached --others --exclude-standard|Sort-Object -Unique|Where-Object{Test-Path -LiteralPath (Join-Path $taskPrivate $_) -PathType Leaf}|ForEach-Object{@{path=(Join-Path $taskPrivate $_);relative=$_;sha256=(Get-FileHash -LiteralPath (Join-Path $taskPrivate $_)).Hash}})
}
$taskAbsenceManifest=Join-Path $taskEvidence 'highlight-lazy-batch8-source106-absences84-20261015.json'
$taskAbsent=@(Get-Content -LiteralPath $taskAbsenceManifest -Raw|ConvertFrom-Json)
function Present-Absent {@($taskAbsent|Where-Object{(Test-Path -LiteralPath $_.source) -or (Test-Path -LiteralPath $_.runtime)})}
if($taskAbsent.Count -ne 84 -or @(Present-Absent).Count){throw 'Exact84 original absence records required'}
if((git -c gc.auto=0 -c maintenance.auto=false -c pack.threads=2 -c pack.windowMemory=64m -C $taskPrivate rev-parse HEAD) -cne $CandidateHead){throw 'Exact sealed batch10 candidate required'}
if(@(git -c gc.auto=0 -c maintenance.auto=false -c pack.threads=2 -c pack.windowMemory=64m -C $taskPrivate status --porcelain).Count){throw 'Clean sealed native candidate required'}
$taskSourceHead=git -c gc.auto=0 -c maintenance.auto=false -c pack.threads=2 -c pack.windowMemory=64m -C $taskSource rev-parse HEAD
if($taskSourceHead -cne '5ab7fe74c400097b386662205cd93900695b8a71'){throw 'Exact old5ab Source authority required'}
if(Test-Path -LiteralPath (Join-Path $taskPrivate 'src/extensions/fixtures/sdk-highlight-lazy-batch10-10_7_3.json')){throw 'Expected must remain absent before genuine capture'}
$taskNativeBefore=Candidate-Rows
$taskNativeManifest=Join-Path $taskEvidence "$taskName-native-before.json"
$taskNativeBefore|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $taskNativeManifest -Encoding utf8NoBOM
$taskHighlightPackage='C:/Users/adyba/pi-upstream-source-b45e0eb-20261014/node_modules/highlight.js/package.json'
if((Get-Content -LiteralPath $taskHighlightPackage -Raw|ConvertFrom-Json).version -cne '10.7.3'){throw 'Actual highlight.js10.7.3 authority required'}
if(Test-Path -LiteralPath $taskOutput){throw 'Fresh Source113 output required'}
if((Get-FileHash -LiteralPath $taskNode).Hash -cne '63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088'){throw 'Node24.14 pin mismatch'}
$taskSpecs=@(
 @{name='source';file='source5ab-full-manifest-20261015.json';count=1967},
 @{name='dependencies';file='durable-19cb534-reference-20261012-all-built-runtime.json';count=31064},
 @{name='node_tools';file='root-current8a-npm-tools-before.json';count=1774}
)
$taskFrozen=@()
foreach($taskSpec in $taskSpecs){
 $taskRows=@(Get-Content -LiteralPath (Join-Path $taskEvidence $taskSpec.file) -Raw|ConvertFrom-Json)
 if($taskRows.Count -ne $taskSpec.count -or @(Check-Rows $taskRows).Count){throw "Full $($taskSpec.name) manifest prehash mismatch"}
 $taskFrozen+=@{name=$taskSpec.name;rows=$taskRows;manifest=$taskSpec.file}
}
$taskControls=@($PSCommandPath,(Join-Path $taskEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1'),$taskDriver,$taskInput,$taskObserver,$taskAbsenceManifest,$taskNativeManifest,$taskHighlightPackage,(Join-Path $taskEvidence 'source5ab-dependency-contract-audit-20261015.json'))+@($taskSpecs|ForEach-Object{Join-Path $taskEvidence $_.file})
$taskControls=@($taskControls|ForEach-Object{@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})
$taskControlManifest=Join-Path $taskEvidence "$taskName-controls-before.json"
$taskControls|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $taskControlManifest -Encoding utf8NoBOM
$taskPathsBefore=@(Get-ChildItem -LiteralPath $taskSource -File -Force -Recurse|ForEach-Object{[IO.Path]::GetRelativePath($taskSource,$_.FullName)}|Sort-Object)
$taskFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
if($taskFree -lt 2MB){throw 'Normal Source2GiB admission denied'}
Check-Deadline
@{status='admitted';slot='LIGHT6';free_kib=$taskFree;required_kib=2MB;heap_mb=128;timeout_seconds=300;owner_deadline_seconds=600;cases=113;candidate_head=$CandidateHead;source_head=$taskSourceHead;source_files=1967;dependency_files=31064;node_tool_files=1774;absence_records=84;native_candidate_files=$taskNativeBefore.Count;control_files=$taskControls.Count;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-admission.json") -Encoding utf8NoBOM
try{
 & (Join-Path $taskEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1') -Name $taskName -Executable $taskNode -WorkingDirectory $taskSource -Arguments @('--max-old-space-size=128','--conditions=source','--import',([Uri]$taskObserver).AbsoluteUri,$taskDriver,$taskOutput,$taskInput) -TimeoutSeconds 300 -EnvironmentOverrides @{NODE_OPTIONS='';NODE_PATH='';PI_SOURCE_ORACLE_CONTROL_MANIFEST=$taskControlManifest}
}finally{
 $taskPost=@()
 foreach($taskItem in $taskFrozen){$taskPost+=@{name=$taskItem.name;files=$taskItem.rows.Count;drift=@(Check-Rows $taskItem.rows).Count}}
 $taskControlDrift=@(Check-Rows $taskControls)
 $taskPathsAfter=@(Get-ChildItem -LiteralPath $taskSource -File -Force -Recurse|ForEach-Object{[IO.Path]::GetRelativePath($taskSource,$_.FullName)}|Sort-Object)
 $taskPathDrift=@(Compare-Object $taskPathsBefore $taskPathsAfter)
 $taskNativeAfter=Candidate-Rows
 $taskNativeDrift=@(Compare-Object @($taskNativeBefore|ForEach-Object{"$($_.relative):$($_.sha256)"}) @($taskNativeAfter|ForEach-Object{"$($_.relative):$($_.sha256)"}))
 $taskAbsenceDrift=@(Present-Absent)
 $taskNativeHeadAfter=git -c gc.auto=0 -c maintenance.auto=false -c pack.threads=2 -c pack.windowMemory=64m -C $taskPrivate rev-parse HEAD
 $taskSourceHeadAfter=git -c gc.auto=0 -c maintenance.auto=false -c pack.threads=2 -c pack.windowMemory=64m -C $taskSource rev-parse HEAD
 @{manifests=$taskPost;control_files=$taskControls.Count;control_drift=$taskControlDrift.Count;source_paths_before=$taskPathsBefore.Count;source_paths_after=$taskPathsAfter.Count;source_path_drift=$taskPathDrift.Count;native_before=$taskNativeBefore.Count;native_after=$taskNativeAfter.Count;native_drift=$taskNativeDrift.Count;absence_records=84;absence_drift=$taskAbsenceDrift.Count;native_head_before=$CandidateHead;native_head_after=$taskNativeHeadAfter;source_head_before=$taskSourceHead;source_head_after=$taskSourceHeadAfter;elapsed_seconds=$taskClock.Elapsed.TotalSeconds;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-posthash.json") -Encoding utf8NoBOM
 if(@($taskPost|Where-Object drift -ne 0).Count -or $taskControlDrift.Count -or $taskPathDrift.Count -or $taskNativeDrift.Count -or $taskAbsenceDrift.Count -or $taskNativeHeadAfter -cne $CandidateHead -or $taskSourceHeadAfter -cne $taskSourceHead){throw 'Source113 immutable input drift'}
}
$taskOwner=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName.json") -Raw|ConvertFrom-Json
if($taskOwner.status -cne 'passed' -or $taskOwner.exit_code -ne 0 -or $taskOwner.executable_sha256 -cne '63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088' -or !$taskOwner.identity_captured){throw 'Source113 terminal failure or actual Node identity missing'}
$taskResult=Get-Content -LiteralPath $taskOutput -Raw|ConvertFrom-Json
if($taskResult.cases -ne 113 -or @($taskResult.rows).Count -ne 113){throw 'Genuine Source113 result absent'}
$taskModuleLog=Join-Path $taskEvidence "source5ab-modules-$($taskOwner.pid)-0-20261015.jsonl"
$taskObserved=@(Get-Content -LiteralPath $taskModuleLog|ForEach-Object{$_|ConvertFrom-Json}|Where-Object kind -eq 'observed-module')
$taskCanonical='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012/node_modules/highlight.js/lib/'
$taskLanguages='python java go javascript json cpp typescript php ruby c csharp nix bash rust scala kotlin swift dart groovy perl lua xml livecodeserver livescript lsl mathematica maxima mel nsis pgsql reasonml scss sqf sql_more stan stata stylus vbnet verilog vim x86asm xquery'.Split(' ')
$taskRequiredModules=@([IO.Path]::GetFullPath($taskCanonical+'core.js'))+@($taskLanguages|ForEach-Object{[IO.Path]::GetFullPath($taskCanonical+'languages/'+$_+'.js')})
$taskMissingModules=@($taskRequiredModules|Where-Object{$required=$_;!@($taskObserved|Where-Object{[IO.Path]::GetFullPath($_.path) -ieq $required}).Count})
if($taskLanguages.Count -ne 42 -or $taskMissingModules.Count){throw 'Canonical actual highlight.js core and all42 grammar module observations required'}
@{status='qualified_genuine_source113';source_head=$taskSourceHead;candidate_head=$CandidateHead;cases=113;rows=@($taskResult.rows).Count;actual_node=$taskOwner;highlight_version='10.7.3';required_highlight_modules=$taskRequiredModules.Count;observed_modules=$taskObserved;missing_modules=$taskMissingModules;output_sha256=(Get-FileHash -LiteralPath $taskOutput).Hash;module_log_sha256=(Get-FileHash -LiteralPath $taskModuleLog).Hash;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 7|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-qualified.json") -Encoding utf8NoBOM
Write-Output 'GENUINE_HIGHLIGHT_LAZY_BATCH10_SOURCE113_CAPTURED'

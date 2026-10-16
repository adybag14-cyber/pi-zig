param([ValidateSet('success','lookup_failure','safe_factory_failure')][string]$Mode='success',[Parameter(Mandatory)][string]$CandidateHead)
$taskExpected=if($Mode -ceq 'success'){419}else{13}
$ErrorActionPreference='Stop'
$taskEvidence=$PSScriptRoot
$taskPrivate='C:/Users/adyba/pi-zig-highlight-complete191-root55-20261015'
$taskNode='C:/Program Files/nodejs/node.exe'
$taskSource='C:/Users/adyba/pi-upstream-source-5ab7fe7-20261015'
$taskName="highlight-complete191-source-$Mode-first-20261015"
$taskInput=Join-Path $taskPrivate 'src/extensions/fixtures/sdk-highlight-complete191-10_7_3.input.txt'
$taskDriver=Join-Path $taskEvidence 'capture-highlight-complete191-20261015.mjs'
$taskObserver=Join-Path $taskEvidence 'source5ab-observe-20261015.mjs'
$taskOutput=Join-Path $taskEvidence "$taskName-output.json"
function Check-Rows($rows){
 @($rows|Where-Object{!(Test-Path -LiteralPath $_.path -PathType Leaf) -or (Get-FileHash -LiteralPath $_.path).Hash -ine $_.sha256})
}
function Candidate-Rows {
 @(git -C $taskPrivate ls-files --cached --others --exclude-standard|Sort-Object -Unique|Where-Object{Test-Path -LiteralPath (Join-Path $taskPrivate $_) -PathType Leaf}|ForEach-Object{@{path=(Join-Path $taskPrivate $_);relative=$_;sha256=(Get-FileHash -LiteralPath (Join-Path $taskPrivate $_)).Hash}})
}
$taskAbsenceManifest=Join-Path $taskEvidence 'highlight-lazy-batch8-source106-absences84-20261015.json'
$taskAbsent=@(Get-Content -LiteralPath $taskAbsenceManifest -Raw|ConvertFrom-Json)
function Present-Absent {@($taskAbsent|Where-Object{(Test-Path -LiteralPath $_.source) -or (Test-Path -LiteralPath $_.runtime)})}
if($taskAbsent.Count -ne 84 -or @(Present-Absent).Count){throw 'Exact84 original absence records required'}
if((git -C $taskPrivate rev-parse HEAD) -cne $CandidateHead){throw 'Exact sealed all191 candidate required'}
if(Test-Path -LiteralPath (Join-Path $taskPrivate "src/extensions/fixtures/sdk-highlight-complete191-10_7_3.$Mode.json")){throw 'Expected must remain absent before genuine capture'}
$taskNativeBefore=Candidate-Rows
$taskNativeManifest=Join-Path $taskEvidence "$taskName-native-before.json"
$taskNativeBefore|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $taskNativeManifest -Encoding utf8NoBOM
$taskHighlightPackage='C:/Users/adyba/pi-upstream-source-b45e0eb-20261014/node_modules/highlight.js/package.json'
if((Get-Content -LiteralPath $taskHighlightPackage -Raw|ConvertFrom-Json).version -cne '10.7.3'){throw 'Actual highlight.js10.7.3 authority required'}
if(Test-Path -LiteralPath $taskOutput){throw 'Fresh Complete191Source output required'}
if((Get-FileHash -LiteralPath $taskNode).Hash -cne '63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088'){throw 'Node24.14 pin mismatch'}
$taskSpecs=@(
 @{name='source';file='source5ab-full-manifest-20261015.json';count=1967},
 @{name='dependencies';file='durable-19cb534-reference-20261012-all-built-runtime.json';count=31064},
 @{name='node_tools';file='root-current8a-npm-tools-before.json';count=1774},
 @{name='canonical_hljs';file='highlight-complete191-canonical195-20261015.json';count=195}
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
@{status='admitted';free_kib=$taskFree;required_kib=2MB;heap_mb=256;max_coordinated_jobs=4;cases=$taskExpected;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-admission.json") -Encoding utf8NoBOM
try{
 & (Join-Path $taskEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1') -Name $taskName -Executable $taskNode -WorkingDirectory $taskSource -Arguments @('--max-old-space-size=256','--conditions=source','--import',([Uri]$taskObserver).AbsoluteUri,$taskDriver,$taskOutput,$taskInput,$Mode) -TimeoutSeconds 300 -EnvironmentOverrides @{NODE_OPTIONS='';NODE_PATH='';PI_SOURCE_ORACLE_CONTROL_MANIFEST=$taskControlManifest}
}finally{
 $taskPost=@()
 foreach($taskItem in $taskFrozen){$taskPost+=@{name=$taskItem.name;files=$taskItem.rows.Count;drift=@(Check-Rows $taskItem.rows).Count}}
 $taskControlDrift=@(Check-Rows $taskControls)
 $taskPathsAfter=@(Get-ChildItem -LiteralPath $taskSource -File -Force -Recurse|ForEach-Object{[IO.Path]::GetRelativePath($taskSource,$_.FullName)}|Sort-Object)
 $taskPathDrift=@(Compare-Object $taskPathsBefore $taskPathsAfter)
 $taskNativeAfter=Candidate-Rows
 $taskNativeDrift=@(Compare-Object @($taskNativeBefore|ForEach-Object{"$($_.relative):$($_.sha256)"}) @($taskNativeAfter|ForEach-Object{"$($_.relative):$($_.sha256)"}))
 $taskAbsenceDrift=@(Present-Absent)
 @{manifests=$taskPost;control_drift=$taskControlDrift.Count;source_path_drift=$taskPathDrift.Count;native_before=$taskNativeBefore.Count;native_after=$taskNativeAfter.Count;native_drift=$taskNativeDrift.Count;absence_records=84;absence_drift=$taskAbsenceDrift.Count;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-posthash.json") -Encoding utf8NoBOM
 if(@($taskPost|Where-Object drift -ne 0).Count -or $taskControlDrift.Count -or $taskPathDrift.Count -or $taskNativeDrift.Count -or $taskAbsenceDrift.Count){throw 'Complete191Source immutable input drift'}
}
$taskOwner=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName.json") -Raw|ConvertFrom-Json
if($taskOwner.status -cne 'passed'){throw 'Complete191Source terminal failure'}
$taskResult=Get-Content -LiteralPath $taskOutput -Raw|ConvertFrom-Json
if($taskResult.cases -ne $taskExpected -or @($taskResult.rows).Count -ne $taskExpected){throw 'Genuine Complete191Source result absent'}
Write-Output 'GENUINE_HIGHLIGHT_COMPLETE191_SOURCE_CAPTURED'

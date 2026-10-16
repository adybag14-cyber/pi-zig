param([string]$Attempt='first')
$ErrorActionPreference='Stop'
$taskName="model-schemas-partial-4954-source52-$Attempt-20261015"
$taskEvidence=$PSScriptRoot
$taskTree='C:/Users/adyba/pi-zig-native-model-schemas-partial-4954-20261015'
$taskSource='C:/Users/adyba/pi-upstream-source-4954d76-20261015'
$taskRuntime='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012'
$taskNode='C:/Program Files/nodejs/node.exe'
$taskDriver=Join-Path $taskEvidence 'source4954-model-schemas-partial-capture-20261015.mjs'
$taskObserver=Join-Path $taskEvidence 'source4954-observe-20261015.mjs'
$taskReadiness=Join-Path $taskEvidence 'source4954-preparation-readiness-20261015.json'
$taskAudit=Join-Path $taskEvidence 'source4954-dependency-contract-audit-20261015.json'
$taskOwner=Join-Path $taskEvidence 'Invoke-OwnedModelsPersistenceSource-20261015.ps1'
$taskInput=Join-Path $taskTree 'src/extensions/fixtures/ai-model-schemas-partial-4954.input.mjs'
$taskExpected=Join-Path $taskTree 'src/extensions/fixtures/ai-model-schemas-partial-4954.json'
if(Test-Path -LiteralPath $taskExpected){throw 'Refuse expected replay'}
if((Get-FileHash -LiteralPath $taskNode).Hash -cne '63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088'){throw 'Pinned Node drift'}
& $taskOwner -Name "$taskName-syntax" -Executable $taskNode -WorkingDirectory $taskSource -Arguments @('--max-old-space-size=256','--check',$taskDriver) -TimeoutSeconds 30 -EnvironmentOverrides @{NODE_OPTIONS='';NODE_PATH=''}
function Check-Rows($taskRows){$taskChanged=[Collections.Generic.List[string]]::new();foreach($taskRow in $taskRows){if(!(Test-Path -LiteralPath $taskRow.path -PathType Leaf) -or (Get-FileHash -LiteralPath $taskRow.path).Hash -cne $taskRow.sha256){$taskChanged.Add($taskRow.path)}};return @($taskChanged)}
function Candidate-Paths {@(git -c gc.auto=0 -c maintenance.auto=false -c pack.threads=2 -c pack.windowMemory=64m -C $taskTree ls-files --cached --others --exclude-standard|Sort-Object -Unique|ForEach-Object {Join-Path $taskTree $_})}
$taskCompilerRoot='C:/Users/adyba/pi-zig-toolchain-20261003/zig-x86_64-windows-0.16.0'
function Compiler-Paths {@(rg --files -uuu -- $taskCompilerRoot|Sort-Object)}
if((Get-FileHash -LiteralPath (Join-Path $taskCompilerRoot 'zig.exe')).Hash -cne '086CE9D47BA42F33A514E1A6E04EB1D4A8FA1D75E0868E0213CAAD447C91E864'){throw 'Pinned Zig0.16 executable drift'}
$taskCompilerPaths=@(Compiler-Paths)
if($taskCompilerPaths.Count -ne 19546){throw 'Complete19546 compiler distribution inventory required'}
$taskCompilerRows=@($taskCompilerPaths|ForEach-Object {@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})
$taskCandidatePaths=@(Candidate-Paths)
$taskCandidateRows=@($taskCandidatePaths|ForEach-Object {@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})
@{compiler=$taskCompilerRows;candidate=$taskCandidateRows;candidate_head=(git -c gc.auto=0 -c maintenance.auto=false -C $taskTree rev-parse HEAD);observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-candidate-compiler-before.json") -Encoding utf8NoBOM
$taskSpecs=@(@{name='source';file='source4954-full-manifest-20261015.json';count=1970},@{name='dependencies';file='source4954-runtime-manifest-20261015.json';count=31064},@{name='node_tools';file='source4954-node-tools-before-20261015.json';count=1774})
$taskFrozen=@()
foreach($taskSpec in $taskSpecs){$taskRows=@(Get-Content -Raw -LiteralPath (Join-Path $taskEvidence $taskSpec.file)|ConvertFrom-Json);if($taskRows.Count -ne $taskSpec.count -or @(Check-Rows $taskRows).Count){throw "Original latest manifest inventory/hash mismatch: $($taskSpec.name)"};$taskFrozen+=@{name=$taskSpec.name;rows=$taskRows}}
if((git -c gc.auto=0 -c maintenance.auto=false -C $taskSource rev-parse HEAD) -cne '4954d760504c11df9b2cbdc040346107b6a8153d'){throw 'Pinned Source4954 head drift'}
$taskPrepared=Get-Content -Raw -LiteralPath $taskReadiness|ConvertFrom-Json
if($taskPrepared.source_full_files -ne 1970 -or $taskPrepared.source_head -cne '4954d760504c11df9b2cbdc040346107b6a8153d' -or @($taskPrepared.controls).Count -ne 5 -or @(Check-Rows $taskPrepared.controls).Count){throw 'Pinned latest preparation controls drift'}
$taskContract=Get-Content -Raw -LiteralPath $taskAudit|ConvertFrom-Json
if($taskContract.latestHead -cne '4954d760504c11df9b2cbdc040346107b6a8153d' -or $taskContract.installed_metadata_verified -ne 281 -or $taskContract.platform_optional_absent_records -ne 80 -or $taskContract.historical_missing_records_retained -ne 4){throw 'Actual dependency contract drift'}
$taskAbsent=@($taskContract.pins|Where-Object status -eq 'platform_optional_absent'|ForEach-Object {Join-Path $taskRuntime $_.path})+@($taskContract.mismatches|ForEach-Object {Join-Path $taskRuntime $_.path})
if($taskAbsent.Count -ne 84 -or @($taskAbsent|Where-Object {Test-Path -LiteralPath $_}).Count){throw 'Historical dependency absences changed'}
$taskPaths=@($taskInput,$taskDriver,$taskObserver,$taskReadiness,$taskAudit,$taskOwner,$PSCommandPath,(Join-Path $taskEvidence "$taskName-candidate-compiler-before.json"))+@($taskSpecs|ForEach-Object {Join-Path $taskEvidence $_.file})
$taskExtra=@($taskPaths|ForEach-Object {@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})
$taskControls=Join-Path $taskEvidence "$taskName-extra-before.json"
$taskExtra|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $taskControls -Encoding utf8NoBOM
$taskControlHash=(Get-FileHash -LiteralPath $taskControls).Hash
$taskFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
if($taskFree -lt 2MB){throw 'Fresh2GiB Source admission denied'}
@{status='admitted';free_kib=$taskFree;required_kib=2MB;heap_mb=256;outer_seconds=300;coordinated_with='Root LIGHT grant required';observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-admission.json") -Encoding utf8NoBOM
$taskOutput=Join-Path $taskEvidence "$taskName-output.json"
& $taskOwner -Name $taskName -Executable $taskNode -WorkingDirectory $taskSource -Arguments @('--max-old-space-size=256','--expose-gc','--conditions=source','--experimental-transform-types','--import',([Uri]$taskObserver).AbsoluteUri,$taskDriver,$taskOutput) -TimeoutSeconds 300 -EnvironmentOverrides @{NODE_OPTIONS='';NODE_PATH='';PI_SOURCE_ORACLE_CONTROL_MANIFEST=$taskControls;NODE_USE_ENV_PROXY='';HTTP_PROXY='';HTTPS_PROXY='';ALL_PROXY='';NO_PROXY='127.0.0.1,localhost';PI_PACKAGE_DIR='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012/packages/coding-agent'}
$taskPost=@();foreach($taskItem in $taskFrozen){$taskChanged=@(Check-Rows $taskItem.rows);$taskPost+=@{name=$taskItem.name;files=$taskItem.rows.Count;drift=$taskChanged.Count;changed=$taskChanged}}
$taskExtraChanged=@(Check-Rows $taskExtra);$taskAbsentChanged=@($taskAbsent|Where-Object {Test-Path -LiteralPath $_});$taskControlChanged=(Get-FileHash -LiteralPath $taskControls).Hash -cne $taskControlHash
$taskCompilerChanged=@(Check-Rows $taskCompilerRows);$taskCandidateChanged=@(Check-Rows $taskCandidateRows)
$taskCompilerInventoryChanged=@(Compare-Object $taskCompilerPaths @(Compiler-Paths));$taskCandidateInventoryChanged=@(Compare-Object $taskCandidatePaths @(Candidate-Paths))
@{manifests=$taskPost;extra_control_drift=$taskExtraChanged;control_manifest_drift=$taskControlChanged;absent_dependency_drift=$taskAbsentChanged;historical_absence_records=$taskAbsent.Count;compiler_files=$taskCompilerRows.Count;compiler_drift=$taskCompilerChanged;compiler_inventory_drift=$taskCompilerInventoryChanged;candidate_files=$taskCandidateRows.Count;candidate_drift=$taskCandidateChanged;candidate_inventory_drift=$taskCandidateInventoryChanged;expected_still_absent=!(Test-Path -LiteralPath $taskExpected);completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 7|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-posthash.json") -Encoding utf8NoBOM
if(@($taskPost|Where-Object drift -ne 0).Count -or $taskExtraChanged.Count -or $taskAbsentChanged.Count -or $taskControlChanged -or $taskCompilerChanged.Count -or $taskCandidateChanged.Count -or $taskCompilerInventoryChanged.Count -or $taskCandidateInventoryChanged.Count -or (Test-Path -LiteralPath $taskExpected)){throw 'Full original Source4954 candidate/compiler/control posthash drift'}
$taskTerminal=Get-Content -Raw -LiteralPath (Join-Path $taskEvidence "$taskName.json")|ConvertFrom-Json
if($taskTerminal.status -cne 'passed' -or $taskTerminal.exit_code -ne 0){throw 'Actual Source capture did not pass'}
$taskResult=Get-Content -Raw -LiteralPath $taskOutput|ConvertFrom-Json
if($taskResult.count -ne 52 -or @($taskResult.rows).Count -ne 52 -or $taskResult.runtime -cne 'v24.14.0' -or $taskResult.sourceHead -cne '4954d760504c11df9b2cbdc040346107b6a8153d' ){throw 'Source43 output inventory/ownership mismatch'}
Copy-Item -LiteralPath $taskOutput -Destination $taskExpected
@{source_cases=52;source_pid=$taskTerminal.pid;expected_sha256=(Get-FileHash -LiteralPath $taskExpected).Hash;expected_published_after_terminal_and_full_posthash=$true;native_qualified=$false;full_pi_qualified=$false;public_activation=$false}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-validation.json") -Encoding utf8NoBOM
Write-Output 'ORIGINAL_4954_MODEL_SCHEMAS_PARTIAL_CASES=52'

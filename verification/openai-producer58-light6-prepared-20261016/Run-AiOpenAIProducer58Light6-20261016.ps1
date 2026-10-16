param([string]$Attempt='first',[Parameter(Mandatory)][string]$CandidateHead)
$ErrorActionPreference='Stop'
$taskEvidence=$PSScriptRoot
$taskName="ai-openai-producer58-ae7-light6-$Attempt-20261016"
$taskNode='C:/Program Files/nodejs/node.exe'
$taskSource='C:/Users/adyba/pi-upstream-source-4954d76-20261015'
$taskExecutedSource='C:/Users/adyba/pi-upstream-source-ae7b16d-20261015'
$taskRuntime='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012'
$taskNative='C:/Users/adyba/pi-zig-ai-openai-http58-composition-20261016'
$taskCompilerRoot='C:/Users/adyba/pi-zig-toolchain-20261003/zig-x86_64-windows-0.16.0'
$taskDriver=Join-Path $taskEvidence 'ai-openai-full58-producer-ae7-source-capture-20261016.mjs'
$taskObserver=Join-Path $taskEvidence 'sourceae7-observe-20261015.mjs'
$taskJobOwner=Join-Path $taskEvidence 'Invoke-OwnedCredentialStoreSource-20261016.ps1'
$taskBaseline=Join-Path $taskEvidence 'ai-openai-full58-ae7-source-first-20261016-output.json'
$taskAudit=Join-Path $taskEvidence 'source4954-dependency-contract-audit-20261015.json'
$taskSealedControls=Join-Path $taskNative 'verification/openai-producer58-light6-prepared-20261016'
$taskExpected=Join-Path $taskNative 'src/extensions/fixtures/ai-openai-producer58-ae7.json'
$taskControlNames=@('Run-AiOpenAIProducer58Light6-20261016.ps1','Invoke-OwnedCredentialStoreSource-20261016.ps1','ai-openai-full58-producer-ae7-source-capture-20261016.mjs','sourceae7-observe-20261015.mjs')
function Check-Rows($Rows){$changed=[Collections.Generic.List[string]]::new();foreach($row in $Rows){if(!(Test-Path -LiteralPath $row.path -PathType Leaf) -or (Get-FileHash -LiteralPath $row.path).Hash -cne $row.sha256){$changed.Add($row.path)}};return @($changed)}
function Scoped-Paths([string]$Root){$paths=[Collections.Generic.List[string]]::new();$dirs=[Collections.Generic.Stack[string]]::new();$dirs.Push($Root);while($dirs.Count){foreach($entry in [IO.DirectoryInfo]::new($dirs.Pop()).EnumerateFileSystemInfos()){if($entry.Name -ceq '.git' -or ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint)){continue};if($entry.Attributes -band [IO.FileAttributes]::Directory){$dirs.Push($entry.FullName)}else{$paths.Add($entry.FullName)}}};return @($paths|Sort-Object)}
function Candidate-Paths {@(& git -c gc.auto=0 -c maintenance.auto=false -C $taskNative ls-files --cached --others --exclude-standard|Sort-Object -Unique|ForEach-Object {Join-Path $taskNative $_})}
function Candidate-Rows($Paths){@($Paths|ForEach-Object {@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})}
if((git -C $taskNative rev-parse HEAD) -cne $CandidateHead -or @(git -C $taskNative status --porcelain).Count){throw 'Exact clean sealed candidate required'}
if(Test-Path -LiteralPath $taskExpected){throw 'Refuse producer58 expected replay'}
if(Test-Path -LiteralPath (Join-Path $taskEvidence "$taskName.json")){throw 'Refuse Source job record replay'}
foreach($name in $taskControlNames){if((Get-FileHash -LiteralPath (Join-Path $taskEvidence $name)).Hash -cne (Get-FileHash -LiteralPath (Join-Path $taskSealedControls $name)).Hash){throw "Sealed control differs: $name"}}
if((Get-FileHash -LiteralPath $taskDriver).Hash -cne 'DF4B11133D4CAF456DE583F099AB6EBBECCCCDDEDD040482714AE2452134DB49'){throw 'Original transparent driver changed'}
if((Get-FileHash -LiteralPath $taskBaseline).Hash -cne '6349299A388CBEB1F1086DFA58317AE4F296A26D6B620BB5A7987B6D44D82852'){throw 'Original consumer58 baseline changed'}
if((Get-FileHash -LiteralPath $taskNode).Hash -cne '63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088'){throw 'Pinned Node changed'}
$taskSpecs=@(@{name='source4954';file='source4954-full-manifest-20261015.json';count=1970;root=$taskSource},@{name='executed_ae7';file='sourceae7-full-manifest-20261015.json';count=1968;root=$taskExecutedSource},@{name='dependencies';file='source4954-runtime-manifest-20261015.json';count=31064;root=$taskRuntime},@{name='node_tools';file='source4954-node-tools-before-20261015.json';count=1774;root='C:/Program Files/nodejs/node_modules/npm'})
$taskFrozen=@();$taskInventories=@()
foreach($spec in $taskSpecs){$rows=@(Get-Content -Raw -LiteralPath (Join-Path $taskEvidence $spec.file)|ConvertFrom-Json);if($rows.Count -ne $spec.count -or @(Check-Rows $rows).Count){throw "Full prehash differs: $($spec.name)"};$paths=@(Scoped-Paths $spec.root);if($spec.name -ceq 'node_tools'){$paths=@([IO.Path]::GetFullPath($taskNode))+$paths};if(@(Compare-Object @($rows.path|Sort-Object) @($paths|Sort-Object)).Count){throw "Full inventory differs: $($spec.name)"};$taskFrozen+=@{name=$spec.name;rows=$rows};$taskInventories+=@{name=$spec.name;root=$spec.root;paths=$paths}}
$taskCandidatePaths=@(Candidate-Paths);$taskCandidate=@(Candidate-Rows $taskCandidatePaths)
$taskCompilerPaths=@(Scoped-Paths $taskCompilerRoot);if($taskCompilerPaths.Count -ne 19546){throw 'Pinned compiler19546 inventory required'}
$taskCompiler=@(Candidate-Rows $taskCompilerPaths)
$taskCandidateManifest=Join-Path $taskEvidence "$taskName-candidate-before.json";$taskCandidate|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $taskCandidateManifest -Encoding utf8NoBOM
$taskCompilerManifest=Join-Path $taskEvidence "$taskName-compiler-before.json";$taskCompiler|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $taskCompilerManifest -Encoding utf8NoBOM
$taskInventoryManifest=Join-Path $taskEvidence "$taskName-inventories-before.json";$taskInventories|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $taskInventoryManifest -Encoding utf8NoBOM
if((git -C $taskSource rev-parse HEAD) -cne '4954d760504c11df9b2cbdc040346107b6a8153d' -or (git -C $taskExecutedSource rev-parse HEAD) -cne 'ae7b16d43b7c78c5b6fa3213fdd1215bb339729d'){throw 'Pinned Source heads changed'}
$taskRuntimeDelta=@(git -C $taskSource diff ae7b16d43b7c78c5b6fa3213fdd1215bb339729d 4954d760504c11df9b2cbdc040346107b6a8153d --name-only -- packages/ai/src packages/agent-core/src)
if($LASTEXITCODE -ne 0 -or $taskRuntimeDelta.Count){throw 'Source runtime closure differs; original ae7 driver authority must remain actual'}
$taskContract=Get-Content -Raw -LiteralPath $taskAudit|ConvertFrom-Json
if($taskContract.latestHead -cne '4954d760504c11df9b2cbdc040346107b6a8153d' -or $taskContract.installed_metadata_verified -ne 281 -or $taskContract.platform_optional_absent_records -ne 80 -or $taskContract.historical_missing_records_retained -ne 4){throw 'Dependency contract scope changed'}
$taskAbsent=@($taskContract.pins|Where-Object status -ceq 'platform_optional_absent'|ForEach-Object {Join-Path $taskRuntime $_.path})+@($taskContract.mismatches|ForEach-Object {Join-Path $taskRuntime $_.path})
if($taskAbsent.Count -ne 84 -or @($taskAbsent|Where-Object {Test-Path -LiteralPath $_}).Count){throw 'Declared84 absences changed'}
$taskExtraPaths=@($taskDriver,$taskObserver,$taskJobOwner,$PSCommandPath,$taskBaseline,$taskAudit,$taskCandidateManifest,$taskCompilerManifest,$taskInventoryManifest,(Join-Path $taskEvidence 'source4954-reference-controls-20261015.json'),(Join-Path $taskEvidence 'source4954-preparation-readiness-20261015.json'),(Join-Path $taskEvidence 'sourceae7-dependency-contract-audit-20261015.json'),(Join-Path $taskEvidence 'sourceae7-runtime-manifest-20261015.json'))+@($taskSpecs|ForEach-Object {Join-Path $taskEvidence $_.file})
$taskPreparation=Join-Path $taskEvidence 'source4954-reference-controls-20261015.json';$taskReadiness=Join-Path $taskEvidence 'source4954-preparation-readiness-20261015.json'
if((Get-FileHash -LiteralPath $taskPreparation).Hash -cne 'A11A87511B15B6AEDF4FFC94EA541DE986FCCC4334BA9A47C2BED3ED0A5094D0' -or (Get-FileHash -LiteralPath $taskReadiness).Hash -cne '0EDB3EA87CF7AE1FF8B51A02A1D3698DC610BA23F66257D60AA5C788557E82D7'){throw 'Pinned4954 preparation authority changed'}
$taskAe7Preparation=Join-Path $taskEvidence 'sourceae7-preparation-controls-20261015.json';$taskAe7Readiness=Join-Path $taskEvidence 'sourceae7-preparation-readiness-20261015.json'
if((Get-FileHash -LiteralPath $taskAe7Preparation).Hash -cne '3C84A2C828A906617A50E5C568BA9DA9CAEC7FD79D202C20CA7D6087DD02637C' -or (Get-FileHash -LiteralPath $taskAe7Readiness).Hash -cne 'BA4C270D341C7B8651573A2DE0B9478B1CEAE1D32D680A4EB26068D2DF08389E'){throw 'Pinned executedae7 preparation authority changed'}
$taskAe7Controls=Get-Content -Raw -LiteralPath $taskAe7Preparation|ConvertFrom-Json
if(@($taskAe7Controls).Count -ne 5 -or @(Check-Rows $taskAe7Controls).Count){throw 'Executedae7 preparation controls changed'}
$taskExtraPaths+=@($taskAe7Preparation,$taskAe7Readiness)
$taskReferenceControls=Get-Content -Raw -LiteralPath (Join-Path $taskEvidence 'source4954-reference-controls-20261015.json')|ConvertFrom-Json
if(@($taskReferenceControls).Count -ne 5 -or @(Check-Rows $taskReferenceControls).Count){throw 'Five pinned4954 preparation controls changed'}
$taskExtra=@(Candidate-Rows @($taskExtraPaths|Sort-Object -Unique));$taskControlManifest=Join-Path $taskEvidence "$taskName-extra-before.json";$taskExtra|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $taskControlManifest -Encoding utf8NoBOM;$taskControlManifestHash=(Get-FileHash -LiteralPath $taskControlManifest).Hash
foreach($name in $taskControlNames){if((Get-FileHash -LiteralPath (Join-Path $taskEvidence $name)).Hash -cne (Get-FileHash -LiteralPath (Join-Path $taskSealedControls $name)).Hash){throw "Sealed control drift before launch: $name"}}
$taskFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
if($taskFree -lt 2MB){@{status='admission_denied';free_kib=$taskFree;required_kib=2MB;source_child_launched=$false}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-admission.json") -Encoding utf8NoBOM;exit 2}
@{status='admitted';grant='Root LIGHT6 producer58';free_kib=$taskFree;required_kib=2MB;heap_mb=256;timeout_seconds=300;candidate_head=$CandidateHead;source4954_files=1970;executed_ae7_files=1968;dependencies=31064;node_tools=1774;compiler=$taskCompiler.Count;candidate=$taskCandidate.Count;historical_absences=$taskAbsent.Count;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-admission.json") -Encoding utf8NoBOM
$taskOutput=Join-Path $taskEvidence "$taskName-output.json";$taskOwnerFailure=$null
try{& $taskJobOwner -Name $taskName -Executable $taskNode -WorkingDirectory $taskExecutedSource -Arguments @('--max-old-space-size=256','--expose-gc','--conditions=source','--experimental-transform-types','--import',([Uri]$taskObserver).AbsoluteUri,$taskDriver,$taskOutput) -TimeoutSeconds 300 -SettleSeconds 10 -EnvironmentOverrides @{NODE_OPTIONS='';NODE_PATH='';PI_SOURCE_ORACLE_CONTROL_MANIFEST=$taskControlManifest;NODE_USE_ENV_PROXY='';HTTP_PROXY='';HTTPS_PROXY='';ALL_PROXY='';NO_PROXY='127.0.0.1,localhost';OPENAI_API_KEY='';OPENAI_ORG_ID='';OPENAI_PROJECT_ID='';OPENAI_BASE_URL='';KIMI_API_KEY='';PI_PACKAGE_DIR=''}}catch{$taskOwnerFailure=$_.Exception.Message}
$taskPost=@(foreach($frozen in $taskFrozen){$changed=@(Check-Rows $frozen.rows);@{name=$frozen.name;files=$frozen.rows.Count;drift=$changed.Count;changed=$changed}})
$taskInventoryPost=@(foreach($inventory in $taskInventories){$paths=@(Scoped-Paths $inventory.root);if($inventory.name -ceq 'node_tools'){$paths=@([IO.Path]::GetFullPath($taskNode))+$paths};@{name=$inventory.name;files=$paths.Count;drift=@(Compare-Object @($inventory.paths|Sort-Object) @($paths|Sort-Object))}})
$taskExtraChanged=@(Check-Rows $taskExtra);$taskCandidateChanged=@(Check-Rows $taskCandidate);$taskCandidateInventoryChanged=@(Compare-Object $taskCandidatePaths @(Candidate-Paths));$taskCompilerChanged=@(Check-Rows $taskCompiler);$taskCompilerInventoryChanged=@(Compare-Object $taskCompilerPaths @(Scoped-Paths $taskCompilerRoot));$taskAbsentChanged=@($taskAbsent|Where-Object {Test-Path -LiteralPath $_});$taskControlChanged=(Get-FileHash -LiteralPath $taskControlManifest).Hash -cne $taskControlManifestHash
$taskHeadChanged=(git -C $taskNative rev-parse HEAD) -cne $CandidateHead;$taskSourceHeadChanged=(git -C $taskSource rev-parse HEAD) -cne '4954d760504c11df9b2cbdc040346107b6a8153d' -or (git -C $taskExecutedSource rev-parse HEAD) -cne 'ae7b16d43b7c78c5b6fa3213fdd1215bb339729d'
@{manifests=$taskPost;inventories=$taskInventoryPost;candidate_files=$taskCandidate.Count;candidate_drift=$taskCandidateChanged;candidate_inventory_drift=$taskCandidateInventoryChanged;compiler_files=$taskCompiler.Count;compiler_drift=$taskCompilerChanged;compiler_inventory_drift=$taskCompilerInventoryChanged;extra_control_drift=$taskExtraChanged;control_manifest_drift=$taskControlChanged;absent_dependency_drift=$taskAbsentChanged;candidate_head_drift=$taskHeadChanged;source_head_drift=$taskSourceHeadChanged;expected_still_absent=!(Test-Path -LiteralPath $taskExpected);owner_failure=$taskOwnerFailure;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-posthash.json") -Encoding utf8NoBOM
if(@($taskPost|Where-Object drift -ne 0).Count -or @($taskInventoryPost|Where-Object {$_.drift.Count}).Count -or $taskExtraChanged.Count -or $taskControlChanged -or $taskCandidateChanged.Count -or $taskCandidateInventoryChanged.Count -or $taskCompilerChanged.Count -or $taskCompilerInventoryChanged.Count -or $taskAbsentChanged.Count -or $taskHeadChanged -or $taskSourceHeadChanged -or (Test-Path -LiteralPath $taskExpected)){throw 'Full posthash/inventory failure; preserve raw negative'}
if($taskOwnerFailure){throw $taskOwnerFailure}
$taskOwner=Get-Content -Raw -LiteralPath (Join-Path $taskEvidence "$taskName.json")|ConvertFrom-Json
if($taskOwner.status -cne 'passed' -or !$taskOwner.independent_pid_absent -or !$taskOwner.terminal_kernel_handle){throw 'Source process terminal/absence failure; preserve raw negative'}
$taskResult=Get-Content -Raw -LiteralPath $taskOutput|ConvertFrom-Json
if($taskResult.cases -ne 58 -or @($taskResult.rows).Count -ne 58 -or @($taskResult.producerRows).Count -ne 58 -or @($taskResult.deep).Count -ne 6 -or @($taskResult.split).Count -ne 2 -or $taskResult.sourceHead -cne 'ae7b16d43b7c78c5b6fa3213fdd1215bb339729d' -or $taskResult.actualNode.version -cne 'v24.14.0' -or $taskResult.driverSha256.ToUpperInvariant() -cne 'DF4B11133D4CAF456DE583F099AB6EBBECCCCDDEDD040482714AE2452134DB49'){throw 'Actual Producer58 inventory/authority differs'}
if(!$taskResult.instrumentation.allOriginalRowsUnchanged -or @($taskResult.instrumentation.unchangedRows).Count -ne 58 -or @($taskResult.instrumentation.unchangedRows|Where-Object same -ne $true).Count){throw 'Observer altered original consumer/wire rows; no positive producer golden'}
if(@($taskResult.producerRows|Where-Object {$_.diagnostics.Count -or $_.throws.Count -or $_.before.Count -ne $_.after.Count -or $_.before.Count -ne $_.returns.Count}).Count){throw 'Observer diagnostics/throw/paired push mismatch; no positive producer golden'}
$taskOriginal=Get-Content -Raw -LiteralPath $taskBaseline|ConvertFrom-Json
if(($taskResult.deep|ConvertTo-Json -Depth 100) -cne ($taskOriginal.deep|ConvertTo-Json -Depth 100) -or ($taskResult.split|ConvertTo-Json -Depth 100) -cne ($taskOriginal.split|ConvertTo-Json -Depth 100)){throw 'Original deep/split observations changed'}
$taskDescriptor=$taskResult.instrumentation.originalDescriptor
if($taskDescriptor.name -cne 'push' -or $taskDescriptor.length -ne 1 -or !$taskDescriptor.writable -or $taskDescriptor.enumerable -or !$taskDescriptor.configurable -or $taskResult.instrumentation.baselineSha256.ToUpperInvariant() -cne '6349299A388CBEB1F1086DFA58317AE4F296A26D6B620BB5A7987B6D44D82852'){throw 'Original push descriptor/baseline identity changed'}
Copy-Item -LiteralPath $taskOutput -Destination $taskExpected
@{status='accepted';source_cases=58;producer_cases=58;original_consumer58_unchanged=$true;expected_sha256=(Get-FileHash -LiteralPath $taskExpected).Hash;published_after_terminal_and_full_posthash=$true;source_authority='actual ae7; full4954 parallel seal and runtime closure equivalence';native_qualified=$false;producer_native_qualified=$false;full_pi_qualified=$false}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-validation.json") -Encoding utf8NoBOM
Write-Output ('ACTUAL_TRANSPARENT_PRODUCER58='+$taskResult.producerRows.Count)

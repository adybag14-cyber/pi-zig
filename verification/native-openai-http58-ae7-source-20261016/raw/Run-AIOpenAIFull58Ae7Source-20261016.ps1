param([string]$Attempt='first')
$ErrorActionPreference='Stop'
$taskEvidence=$PSScriptRoot
$taskName="ai-openai-full58-ae7-source-$Attempt-20261016"
$taskNode='C:/Program Files/nodejs/node.exe'
$taskSource='C:/Users/adyba/pi-upstream-source-ae7b16d-20261015'
$taskRuntime='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012'
$taskDriver=Join-Path $taskEvidence 'ai-openai-full58-ae7-source-capture-20261015.mjs'
$taskObserver=Join-Path $taskEvidence 'sourceae7-observe-20261015.mjs'
$taskCandidate='C:/Users/adyba/pi-zig-ai-openai-producer-ae7-20261015'
$taskCandidateHead='e818b83995540fd76f62c027d9cacb9b6e692758'
$taskCompilerReference=Join-Path $taskEvidence 'durable-latest89-full-inspect-53ae-tool-prehash-20261011.json'
function Candidate-Rows {
 @(git -C $taskCandidate ls-files --cached --others --exclude-standard|Sort-Object -Unique|Where-Object{Test-Path -LiteralPath (Join-Path $taskCandidate $_) -PathType Leaf}|ForEach-Object{[ordered]@{path=(Join-Path $taskCandidate $_);sha256=(Get-FileHash -LiteralPath (Join-Path $taskCandidate $_)).Hash}})
}
$taskAudit=Join-Path $taskEvidence 'sourceae7-dependency-contract-audit-20261015.json'
$taskJobOwner=Join-Path $taskEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1'
if((Get-FileHash -LiteralPath $taskNode).Hash -cne '63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088'){throw 'Pinned Node changed before syntax check'}
& $taskJobOwner -Name "$taskName-syntax-check" -Executable $taskNode -WorkingDirectory $taskSource -Arguments @('--check',$taskDriver) -TimeoutSeconds 30
$taskSyntax=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName-syntax-check.json") -Raw|ConvertFrom-Json
if($taskSyntax.status -cne 'passed'){throw 'Source58 driver syntax check failed before prehash'}
$taskSpecs=@(
 @{name='source';file='sourceae7-full-manifest-20261015.json';count=1968},
 @{name='dependencies';file='sourceae7-runtime-manifest-20261015.json';count=31064},
 @{name='node_tools';file='sourceae7-node-tools-before-20261015.json';count=1774}
)
function Check-Rows($taskRows){
 $taskChanged=[Collections.Generic.List[string]]::new()
 foreach($taskRow in $taskRows){
  if(!(Test-Path -LiteralPath $taskRow.path -PathType Leaf) -or (Get-FileHash -LiteralPath $taskRow.path).Hash -cne $taskRow.sha256){$taskChanged.Add($taskRow.path)}
 }
 return @($taskChanged)
}
$taskFrozen=@()
foreach($taskSpec in $taskSpecs){
 $taskRows=@(Get-Content -LiteralPath (Join-Path $taskEvidence $taskSpec.file) -Raw|ConvertFrom-Json)
 if($taskRows.Count -ne $taskSpec.count){throw "Full manifest inventory mismatch $($taskSpec.name)"}
 if(@(Check-Rows $taskRows).Count){throw "Reference prehash drift $($taskSpec.name)"}
 $taskFrozen+=@{name=$taskSpec.name;manifest=$taskSpec.file;rows=$taskRows}
}
$taskCompilerRows=@((Get-Content -LiteralPath $taskCompilerReference -Raw|ConvertFrom-Json).inputs)
if($taskCompilerRows.Count -ne 19546 -or @(Check-Rows $taskCompilerRows).Count){throw 'Full compiler19546 prehash mismatch'}
$taskFrozen+=@{name='compiler';manifest=$taskCompilerReference;rows=$taskCompilerRows}
if((git -C $taskCandidate rev-parse HEAD) -cne $taskCandidateHead -or (git -C $taskCandidate status --porcelain)){throw 'Exact clean SDK candidate required'}
$taskCandidateRows=Candidate-Rows
$taskFrozen+=@{name='candidate';manifest='owned candidate inventory';rows=$taskCandidateRows}
$taskCandidateRows|ConvertTo-Json -Depth 4|Set-Content (Join-Path $taskEvidence "$taskName-candidate-before.json") -Encoding utf8NoBOM
$taskAuthorityPath=Join-Path $taskEvidence "$taskName-authority.json"
$taskLatestRoot='C:/Users/adyba/pi-upstream-source-4954d76-20261015'
$taskLatestHead='4954d760504c11df9b2cbdc040346107b6a8153d'
$taskRuntimeDelta=@(git -C $taskLatestRoot diff 'ae7b16d43b7c78c5b6fa3213fdd1215bb339729d' $taskLatestHead --name-only -- packages/ai/src packages/agent-core/src)
if($LASTEXITCODE -ne 0 -or $taskRuntimeDelta.Count){throw 'Latest runtime Source delta requires new declared cohort'}
[ordered]@{executed_source='ae7b16d43b7c78c5b6fa3213fdd1215bb339729d';compared_source=$taskLatestHead;compared_paths=@('packages/ai/src','packages/agent-core/src');runtime_git_delta=@($taskRuntimeDelta);scope='Exact ae7 full1968 cohort retained; no newer package metadata relabel'}|ConvertTo-Json -Depth 5|Set-Content $taskAuthorityPath -Encoding utf8NoBOM
if((git -C $taskSource rev-parse HEAD) -cne 'ae7b16d43b7c78c5b6fa3213fdd1215bb339729d'){throw 'PinnedAe7Source head changed'}
if((Get-FileHash -LiteralPath $taskNode).Hash -cne '63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088'){throw 'Pinned Node changed'}
$taskContract=Get-Content -LiteralPath $taskAudit -Raw|ConvertFrom-Json
if($taskContract.latestHead -cne 'ae7b16d43b7c78c5b6fa3213fdd1215bb339729d' -or $taskContract.installed_metadata_verified -ne 281 -or $taskContract.platform_optional_absent_records -ne 80 -or $taskContract.historical_missing_records_retained -ne 4){throw 'Dependency contract scope changed'}
$taskAbsent=@($taskContract.pins|Where-Object status -eq 'platform_optional_absent'|ForEach-Object {Join-Path $taskRuntime $_.path})+@($taskContract.mismatches|ForEach-Object {Join-Path $taskRuntime $_.path})
if($taskAbsent.Count -ne 84 -or @($taskAbsent|Where-Object {Test-Path -LiteralPath $_}).Count){throw 'Historical absent dependency state changed'}
$taskPreparation=Join-Path $taskEvidence 'sourceae7-preparation-controls-20261015.json'
$taskReadiness=Join-Path $taskEvidence 'sourceae7-preparation-readiness-20261015.json'
if((Get-FileHash -LiteralPath $taskPreparation).Hash -cne '3C84A2C828A906617A50E5C568BA9DA9CAEC7FD79D202C20CA7D6087DD02637C' -or (Get-FileHash -LiteralPath $taskReadiness).Hash -cne 'BA4C270D341C7B8651573A2DE0B9478B1CEAE1D32D680A4EB26068D2DF08389E'){throw 'Pinned ae7 preparation controls changed'}
$taskPreparationRows=@(Get-Content -LiteralPath $taskPreparation -Raw|ConvertFrom-Json)
if($taskPreparationRows.Count -ne 5 -or @(Check-Rows $taskPreparationRows).Count){throw 'Exact five ae7 preparation controls required'}
$taskExtraPaths=@($taskDriver,$taskObserver,$taskAudit,$taskJobOwner,$PSCommandPath,$taskPreparation,$taskReadiness)+@($taskSpecs|ForEach-Object {Join-Path $taskEvidence $_.file})
$taskExtraPaths+=@($taskCompilerReference,$taskAuthorityPath)
$taskExtra=@($taskExtraPaths|ForEach-Object {@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})
$taskControlManifest=Join-Path $taskEvidence "$taskName-extra-before.json"
$taskExtra|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $taskControlManifest -Encoding utf8NoBOM
$taskControlManifestHash=(Get-FileHash -LiteralPath $taskControlManifest).Hash
$taskFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
if($taskFree -lt 2MB){@{status='admission_denied';free_kib=$taskFree;required_kib=2MB;node_launched=$false}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-admission.json");exit 2}
@{status='admitted';free_kib=$taskFree;required_kib=2MB;heap_mb=256;coordinated_with='Root queued latest-ae7 Source58; explicit LIGHT grant required before invocation';observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-admission.json")
$taskOutput=Join-Path $taskEvidence "$taskName-output.json"
& $taskJobOwner -Name $taskName -Executable $taskNode -WorkingDirectory $taskSource -Arguments @('--max-old-space-size=256','--expose-gc','--conditions=source','--experimental-transform-types','--import',([Uri]$taskObserver).AbsoluteUri,$taskDriver,$taskOutput) -TimeoutSeconds 300 -EnvironmentOverrides @{NODE_OPTIONS='';NODE_PATH='';PI_SOURCE_ORACLE_CONTROL_MANIFEST=$taskControlManifest;NODE_USE_ENV_PROXY='';HTTP_PROXY='';HTTPS_PROXY='';ALL_PROXY='';NO_PROXY='127.0.0.1,localhost';OPENAI_API_KEY='';OPENAI_ORG_ID='';OPENAI_PROJECT_ID='';OPENAI_BASE_URL='';KIMI_API_KEY='';PI_PACKAGE_DIR='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012/packages/coding-agent'}
$taskPost=@()
foreach($taskItem in $taskFrozen){$taskChanged=@(Check-Rows $taskItem.rows);$taskPost+=@{name=$taskItem.name;files=$taskItem.rows.Count;drift=$taskChanged.Count;changed=$taskChanged}}
$taskCandidateAfter=Candidate-Rows
$taskCandidatePathDrift=@(Compare-Object @($taskCandidateRows.path) @($taskCandidateAfter.path))
if($taskCandidatePathDrift.Count -or (git -C $taskCandidate rev-parse HEAD) -cne $taskCandidateHead){throw 'Candidate path/head drift during Source capture'}
$taskExtraChanged=@(Check-Rows $taskExtra)
$taskAbsentChanged=@($taskAbsent|Where-Object {Test-Path -LiteralPath $_})
$taskControlManifestChanged=(Get-FileHash -LiteralPath $taskControlManifest).Hash -cne $taskControlManifestHash
@{manifests=$taskPost;extra_control_drift=$taskExtraChanged;control_manifest_drift=$taskControlManifestChanged;absent_dependency_drift=$taskAbsentChanged;historical_absence_records=$taskAbsent.Count;driver_sha256=(Get-FileHash -LiteralPath $taskDriver).Hash;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-posthash.json")
if(@($taskPost|Where-Object drift -ne 0).Count -or $taskExtraChanged.Count -or $taskAbsentChanged.Count -or $taskControlManifestChanged){throw 'Reference posthash drift'}
$taskOwner=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName.json") -Raw|ConvertFrom-Json
if($taskOwner.status -cne 'passed'){throw "Source oracle terminal $($taskOwner.status)"}
$taskResult=Get-Content -LiteralPath $taskOutput -Raw|ConvertFrom-Json
if($taskResult.cases -ne 58 -or @($taskResult.rows).Count -ne 58 -or @($taskResult.deep).Count -ne 6 -or @($taskResult.split).Count -ne 2 -or $taskResult.sourceHead -cne 'ae7b16d43b7c78c5b6fa3213fdd1215bb339729d' -or $taskResult.actualNode.version -cne 'v24.14.0'){throw 'OriginalAe7Source58 output missing'}
Write-Output ('ORIGINAL_AE7_OPENAI_FULL_CASES='+$taskResult.rows.Count)

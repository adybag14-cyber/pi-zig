param([switch]$RootSourceGrant,[ValidatePattern('^[A-Za-z0-9_-]+$')][string]$Attempt='first')
$ErrorActionPreference='Stop'
if(!$RootSourceGrant){throw 'Provider factory Source capture requires an explicit Root LIGHT grant'}
$taskReference='C:/Users/adyba/pi-zig-update-evidence-20261003'
$taskEvidence=$PSScriptRoot
$taskWorktree=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$taskUnique=[DateTimeOffset]::UtcNow.ToString('yyyyMMddTHHmmssfffffffZ')+'-'+[Guid]::NewGuid().ToString('N')
$taskName="ai-provider-factories-models-ae7-source-$Attempt-$taskUnique"
$taskNode='C:/Program Files/nodejs/node.exe'
$taskSource='C:/Users/adyba/pi-upstream-source-ae7b16d-20261015'
$taskRuntime='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012'
$taskDriver=Join-Path $taskEvidence 'source-observer.mjs'
$taskObserver=Join-Path $taskReference 'sourceae7-observe-20261015.mjs'
$taskAudit=Join-Path $taskReference 'sourceae7-dependency-contract-audit-20261015.json'
$taskPreparation=Join-Path $taskReference 'sourceae7-preparation-controls-20261015.json'
$taskJobOwner=Join-Path $taskReference 'Invoke-OwnedEeSourceJob-20261012.ps1'
$taskOutput=Join-Path $taskEvidence "$taskName-output.json"
$taskOwnedFixture=Join-Path $taskEvidence "$taskName-owned-fixture"
$taskSpecs=@(
    @{name='source';file='sourceae7-full-manifest-20261015.json';count=1968},
    @{name='dependencies';file='sourceae7-runtime-manifest-20261015.json';count=31064},
    @{name='node_tools';file='sourceae7-node-tools-before-20261015.json';count=1774}
)
function Test-FrozenRows($taskRows){
    $taskChanged=[Collections.Generic.List[string]]::new()
    foreach($taskRow in $taskRows){if(!(Test-Path -LiteralPath $taskRow.path -PathType Leaf) -or (Get-FileHash -LiteralPath $taskRow.path).Hash -cne $taskRow.sha256){$taskChanged.Add($taskRow.path)}}
    return @($taskChanged)
}
if(Test-Path -LiteralPath $taskOutput){throw 'Refuse Source output replay'}
if(Test-Path -LiteralPath $taskOwnedFixture){throw 'Refuse owned input replay'}
$taskPrep=@(Get-Content -LiteralPath $taskPreparation -Raw|ConvertFrom-Json)
if($taskPrep.Count -ne 5 -or @(Test-FrozenRows $taskPrep).Count){throw 'Immutable ae7 preparation controls changed'}
$taskFrozen=@()
foreach($taskSpec in $taskSpecs){
    $taskRows=@(Get-Content -LiteralPath (Join-Path $taskReference $taskSpec.file) -Raw|ConvertFrom-Json)
    if($taskRows.Count -ne $taskSpec.count){throw "Full manifest inventory mismatch $($taskSpec.name)"}
    if(@(Test-FrozenRows $taskRows).Count){throw "Reference prehash drift $($taskSpec.name)"}
    $taskFrozen+=@{name=$taskSpec.name;rows=$taskRows}
}
$taskHead=(git -C $taskSource rev-parse HEAD)
if($taskHead -cne 'ae7b16d43b7c78c5b6fa3213fdd1215bb339729d'){throw 'Pinned ae7 Source head changed'}
if((Get-FileHash -LiteralPath $taskNode).Hash -cne '63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088'){throw 'Pinned actual Node executable changed'}
$taskContract=Get-Content -LiteralPath $taskAudit -Raw|ConvertFrom-Json
if($taskContract.latestHead -cne $taskHead -or $taskContract.installed_metadata_verified -ne 281 -or $taskContract.platform_optional_absent_records -ne 80 -or $taskContract.historical_missing_records_retained -ne 4){throw 'Dependency contract scope changed'}
$taskAbsent=@($taskContract.pins|Where-Object status -eq 'platform_optional_absent'|ForEach-Object {Join-Path $taskRuntime $_.path})+@($taskContract.mismatches|ForEach-Object {Join-Path $taskRuntime $_.path})
if($taskAbsent.Count -ne 84 -or @($taskAbsent|Where-Object {Test-Path -LiteralPath $_}).Count){throw 'Historical absent dependency state changed'}
$taskCandidatePaths=@(git -C $taskWorktree ls-files)|ForEach-Object {Join-Path $taskWorktree $_}
$taskExtraPaths=@((Join-Path $PSScriptRoot 'source-factory-inventory.json'),$taskDriver,$taskObserver,$taskAudit,$taskPreparation,$taskJobOwner,$PSCommandPath)+$taskCandidatePaths+@($taskSpecs|ForEach-Object {Join-Path $taskReference $_.file})
$taskExtra=@($taskExtraPaths|ForEach-Object {@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})
$taskControlManifest=Join-Path $taskEvidence "$taskName-extra-before.json"
$taskExtra|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $taskControlManifest -Encoding utf8NoBOM
$taskControlHash=(Get-FileHash -LiteralPath $taskControlManifest).Hash
$taskFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
if($taskFree -lt 2MB){@{status='admission_denied';free_kib=$taskFree;required_kib=2MB;node_launched=$false}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-admission.json");exit 2}
@{status='admitted';free_kib=$taskFree;required_kib=2MB;heap_mb=256;timeout_seconds=300;source_head=$taskHead;coordinated_with='Explicit Root LIGHT Source slot grant';observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-admission.json")
$taskLaunchFailure=$null
$taskOwnerExit=$null
try {
    & $taskJobOwner -Name $taskName -Executable $taskNode -WorkingDirectory $taskSource -Arguments @('--max-old-space-size=256','--conditions=source','--experimental-transform-types','--import',([Uri]$taskObserver).AbsoluteUri,$taskDriver,$taskOwnedFixture,$taskOutput) -TimeoutSeconds 300 -EnvironmentOverrides @{
        NODE_OPTIONS='';NODE_PATH='';PI_SOURCE_ORACLE_CONTROL_MANIFEST=$taskControlManifest;NODE_USE_ENV_PROXY='';HTTP_PROXY='';HTTPS_PROXY='';ALL_PROXY='';NO_PROXY='127.0.0.1,localhost';
        ANTHROPIC_API_KEY='';ANTHROPIC_AUTH_TOKEN='';ANTHROPIC_OAUTH_TOKEN='';ANTHROPIC_PROFILE='';ANTHROPIC_CONFIG_DIR='';ANTHROPIC_FEDERATION_RULE_ID='';ANTHROPIC_ORGANIZATION_ID='';ANTHROPIC_WORKSPACE_ID='';ANTHROPIC_SERVICE_ACCOUNT_ID='';ANTHROPIC_IDENTITY_TOKEN_FILE='';ANTHROPIC_IDENTITY_TOKEN='';ANTHROPIC_BASE_URL='';
        OPENAI_API_KEY='';OPENAI_ORG_ID='';OPENAI_PROJECT_ID='';OPENAI_BASE_URL='';KIMI_API_KEY='';PI_PACKAGE_DIR='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012/packages/coding-agent'
    }
    $taskOwnerExit=$LASTEXITCODE
} catch { $taskLaunchFailure=$_ }
finally {
    $taskPost=@()
    foreach($taskItem in $taskFrozen){$taskChanged=@(Test-FrozenRows $taskItem.rows);$taskPost+=@{name=$taskItem.name;files=$taskItem.rows.Count;drift=$taskChanged.Count;changed=$taskChanged}}
    $taskExtraChanged=@(Test-FrozenRows $taskExtra)
    $taskPrepChanged=@(Test-FrozenRows $taskPrep)
    $taskAbsentChanged=@($taskAbsent|Where-Object {Test-Path -LiteralPath $_})
    $taskControlChanged=(Get-FileHash -LiteralPath $taskControlManifest).Hash -cne $taskControlHash
    $taskHeadAfter=(git -C $taskSource rev-parse HEAD)
    @{manifests=$taskPost;extra_control_drift=$taskExtraChanged;preparation_control_drift=$taskPrepChanged;control_manifest_drift=$taskControlChanged;absent_dependency_drift=$taskAbsentChanged;historical_absence_records=$taskAbsent.Count;source_head_before=$taskHead;source_head_after=$taskHeadAfter;output_path=$taskOutput;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-posthash.json")
}
if(@($taskPost|Where-Object drift -ne 0).Count -or $taskExtraChanged.Count -or $taskPrepChanged.Count -or $taskAbsentChanged.Count -or $taskControlChanged -or $taskHeadAfter -cne $taskHead){throw 'Reference posthash drift'}
if($taskLaunchFailure){throw $taskLaunchFailure}
$taskOwner=Get-Content -LiteralPath (Join-Path $taskReference "$taskName.json") -Raw|ConvertFrom-Json
if($taskOwner.status -cne 'passed' -or $taskOwnerExit -ne 0){throw "Provider factory Source capture terminal $($taskOwner.status), exit $taskOwnerExit"}
$taskResult=Get-Content -LiteralPath $taskOutput -Raw|ConvertFrom-Json
if($taskResult.actualNode.version -cne 'v24.14.0' -or $taskResult.factoryCount -ne 42 -or @($taskResult.rows).Count -ne $taskResult.cases -or $taskResult.cases -le 42){throw 'Actual Source helper capture inventory missing'}
Write-Output ('ACTUAL_PROVIDER_FACTORY_SOURCE_CAPTURE='+$taskOutput)

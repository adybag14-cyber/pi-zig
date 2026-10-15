param(
    [switch]$RootLight5Grant,
    [ValidatePattern('^[A-Za-z0-9_-]+$')][string]$Attempt='first'
)
$ErrorActionPreference='Stop'
if(!$RootLight5Grant){throw 'Federation SDK Source capture is queued LIGHT5 after Navigate56; explicit Root slot grant required before execution'}
$taskReference='C:/Users/adyba/pi-zig-update-evidence-20261003'
$taskEvidence=$PSScriptRoot
$taskUnique=[DateTimeOffset]::UtcNow.ToString('yyyyMMddTHHmmssfffffffZ')+'-'+[Guid]::NewGuid().ToString('N')
$taskName="ai-anthropic-federation-sdk-source-$Attempt-$taskUnique"
$taskNode='C:/Program Files/nodejs/node.exe'
$taskSource='C:/Users/adyba/pi-upstream-source-5ab7fe7-20261015'
$taskRuntime='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012'
$taskSdk=Join-Path $taskRuntime 'node_modules/@anthropic-ai/sdk'
$taskDriver=Join-Path $taskEvidence 'source-observer.mjs'
$taskFixture=[IO.Path]::GetFullPath((Join-Path $taskEvidence '../../src/extensions/native_ai_anthropic_federation_fixture.mjs'))
$taskNative=[IO.Path]::GetFullPath((Join-Path $taskEvidence '../../src/extensions/native_ai_anthropic_federation.zig'))
$taskObserver=Join-Path $taskReference 'source5ab-observe-20261015.mjs'
$taskAudit=Join-Path $taskReference 'source5ab-dependency-contract-audit-20261015.json'
$taskJobOwner=Join-Path $taskReference 'Invoke-OwnedEeSourceJob-20261012.ps1'
$taskOutput=Join-Path $taskEvidence "$taskName-output.json"
$taskOwnedFixture=Join-Path $taskEvidence "$taskName-owned-fixture"
$taskPostPath=Join-Path $taskEvidence "$taskName-posthash.json"
$taskSpecs=@(
    @{name='source';file='source5ab-full-manifest-20261015.json';count=1967},
    @{name='dependencies';file='durable-19cb534-reference-20261012-all-built-runtime.json';count=31064},
    @{name='node_tools';file='root-current8a-npm-tools-before.json';count=1774}
)
function Test-FrozenRows($taskRows){
    $taskChanged=[Collections.Generic.List[string]]::new()
    foreach($taskRow in $taskRows){
        if(!(Test-Path -LiteralPath $taskRow.path -PathType Leaf) -or (Get-FileHash -LiteralPath $taskRow.path).Hash -cne $taskRow.sha256){$taskChanged.Add($taskRow.path)}
    }
    return @($taskChanged)
}
if(Test-Path -LiteralPath $taskOutput){throw 'Refuse Source output replay'}
if(Test-Path -LiteralPath $taskOwnedFixture){throw 'Refuse owned fake credential fixture replay'}
$taskFrozen=@()
foreach($taskSpec in $taskSpecs){
    $taskRows=@(Get-Content -LiteralPath (Join-Path $taskReference $taskSpec.file) -Raw|ConvertFrom-Json)
    if($taskRows.Count -ne $taskSpec.count){throw "Full manifest inventory mismatch $($taskSpec.name)"}
    if(@(Test-FrozenRows $taskRows).Count){throw "Reference prehash drift $($taskSpec.name)"}
    $taskFrozen+=@{name=$taskSpec.name;manifest=$taskSpec.file;rows=$taskRows}
}
$taskHead=(git -C $taskSource rev-parse HEAD)
if($taskHead -cne '5ab7fe74c400097b386662205cd93900695b8a71'){throw 'Pinned Source head changed'}
if((Get-FileHash -LiteralPath $taskNode).Hash -cne '63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088'){throw 'Pinned actual Node executable changed'}
$taskContract=Get-Content -LiteralPath $taskAudit -Raw|ConvertFrom-Json
if($taskContract.latestHead -cne $taskHead -or $taskContract.installed_metadata_verified -ne 281 -or $taskContract.platform_optional_absent_records -ne 80 -or $taskContract.historical_missing_records_retained -ne 4){throw 'Dependency contract scope changed'}
$taskAbsent=@($taskContract.pins|Where-Object status -eq 'platform_optional_absent'|ForEach-Object {Join-Path $taskRuntime $_.path})+@($taskContract.mismatches|ForEach-Object {Join-Path $taskRuntime $_.path})
if($taskAbsent.Count -ne 84 -or @($taskAbsent|Where-Object {Test-Path -LiteralPath $_}).Count){throw 'Historical absent dependency state changed'}
$taskExtraPaths=@($taskDriver,$taskFixture,$taskNative,$taskObserver,$taskAudit,$taskJobOwner,$PSCommandPath)+@($taskSpecs|ForEach-Object {Join-Path $taskReference $_.file})
$taskExtra=@($taskExtraPaths|ForEach-Object {@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})
$taskControlManifest=Join-Path $taskEvidence "$taskName-extra-before.json"
$taskExtra|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $taskControlManifest -Encoding utf8NoBOM
$taskControlManifestHash=(Get-FileHash -LiteralPath $taskControlManifest).Hash
$taskFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
if($taskFree -lt 2MB){
    @{status='admission_denied';free_kib=$taskFree;required_kib=2MB;node_launched=$false}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-admission.json")
    exit 2
}
@{status='admitted';free_kib=$taskFree;required_kib=2MB;heap_mb=256;timeout_seconds=300;coordinated_with='Root explicitly granted queued LIGHT5 after Navigate56';source_head=$taskHead;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-admission.json")
$taskLaunchFailure=$null
$taskOwnerExit=$null
try {
    & $taskJobOwner -Name $taskName -Executable $taskNode -WorkingDirectory $taskSource -Arguments @('--max-old-space-size=256','--conditions=source','--experimental-transform-types','--import',([Uri]$taskObserver).AbsoluteUri,$taskDriver,$taskSdk,$taskOwnedFixture,$taskOutput) -TimeoutSeconds 300 -EnvironmentOverrides @{
        NODE_OPTIONS='';NODE_PATH='';PI_SOURCE_ORACLE_CONTROL_MANIFEST=$taskControlManifest;
        NODE_USE_ENV_PROXY='';HTTP_PROXY='';HTTPS_PROXY='';ALL_PROXY='';NO_PROXY='127.0.0.1,localhost';
        ANTHROPIC_API_KEY='';ANTHROPIC_AUTH_TOKEN='';ANTHROPIC_OAUTH_TOKEN='';ANTHROPIC_PROFILE='';ANTHROPIC_CONFIG_DIR='';
        ANTHROPIC_FEDERATION_RULE_ID='';ANTHROPIC_ORGANIZATION_ID='';ANTHROPIC_WORKSPACE_ID='';ANTHROPIC_SERVICE_ACCOUNT_ID='';
        ANTHROPIC_IDENTITY_TOKEN_FILE='';ANTHROPIC_IDENTITY_TOKEN='';ANTHROPIC_BASE_URL='';ANTHROPIC_SCOPE='';
        OPENAI_API_KEY='';OPENAI_ORG_ID='';OPENAI_PROJECT_ID='';OPENAI_BASE_URL='';KIMI_API_KEY='';
        PI_PACKAGE_DIR='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012/packages/coding-agent'
    }
    $taskOwnerExit=$LASTEXITCODE
} catch { $taskLaunchFailure=$_ }
finally {
    $taskPost=@()
    foreach($taskItem in $taskFrozen){$taskChanged=@(Test-FrozenRows $taskItem.rows);$taskPost+=@{name=$taskItem.name;files=$taskItem.rows.Count;drift=$taskChanged.Count;changed=$taskChanged}}
    $taskExtraChanged=@(Test-FrozenRows $taskExtra)
    $taskAbsentChanged=@($taskAbsent|Where-Object {Test-Path -LiteralPath $_})
    $taskControlManifestChanged=(Get-FileHash -LiteralPath $taskControlManifest).Hash -cne $taskControlManifestHash
    $taskHeadAfter=(git -C $taskSource rev-parse HEAD)
    @{manifests=$taskPost;extra_control_drift=$taskExtraChanged;control_manifest_drift=$taskControlManifestChanged;absent_dependency_drift=$taskAbsentChanged;historical_absence_records=$taskAbsent.Count;source_head_before=$taskHead;source_head_after=$taskHeadAfter;driver_sha256=(Get-FileHash -LiteralPath $taskDriver).Hash;guest_fixture_sha256=(Get-FileHash -LiteralPath $taskFixture).Hash;native_candidate_sha256=(Get-FileHash -LiteralPath $taskNative).Hash;output_path=$taskOutput;owned_fake_fixture_directory=$taskOwnedFixture;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $taskPostPath
}
if(@($taskPost|Where-Object drift -ne 0).Count -or $taskExtraChanged.Count -or $taskAbsentChanged.Count -or $taskControlManifestChanged -or $taskHeadAfter -cne $taskHead){throw 'Reference posthash drift'}
if($taskLaunchFailure){throw $taskLaunchFailure}
$taskOwner=Get-Content -LiteralPath (Join-Path $taskReference "$taskName.json") -Raw|ConvertFrom-Json
if($taskOwner.status -cne 'passed' -or $taskOwnerExit -ne 0){throw "SDK Source capture terminal $($taskOwner.status), exit $taskOwnerExit"}
$taskResult=Get-Content -LiteralPath $taskOutput -Raw|ConvertFrom-Json
if($taskResult.sdkVersion -cne '0.129.0' -or $taskResult.actualNode.version -cne 'v24.14.0' -or @($taskResult.dependencyCapture.captures).Count -ne 12 -or @($taskResult.loopback.received).Count -ne 1 -or @($taskResult.loopback.tokens).Count -ne 2){throw 'Actual SDK Source capture inventory missing'}
$taskResult.dependencyCapture.exchanges|ForEach-Object {
    if($_.headers.'User-Agent' -cne 'Anthropic/JS 0.129.0'){throw 'SDK original diagnostic User-Agent was rewritten'}
    if($_.headers.'anthropic-beta' -cne 'oauth-2025-04-20,oidc-federation-2026-04-01' -or $_.method -cne 'POST' -or $_.hasSignal -ne $false){throw 'SDK functional token-exchange contract changed'}
}
if($taskResult.loopback.received[0].headers.'user-agent' -cne 'Anthropic/JS 0.129.0'){throw 'SDK original loopback User-Agent was rewritten'}
Write-Output ('ACTUAL_SDK_FEDERATION_SOURCE_CAPTURE='+$taskOutput)

param([string]$Attempt='first')
$ErrorActionPreference='Stop'
$taskEvidence=$PSScriptRoot
$taskName="oauth-callback-ae7-source16-$Attempt-20261015"
$taskNode='C:/Program Files/nodejs/node.exe'
$taskSource='C:/Users/adyba/pi-upstream-source-ae7b16d-20261015'
$taskRuntime='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012'
$taskDriver=Join-Path $taskEvidence 'ai-oauth-callback-source-20261015.mjs'
$taskObserver=Join-Path $taskEvidence 'sourceae7-observe-20261015.mjs'
$taskAudit=Join-Path $taskEvidence 'sourceae7-dependency-contract-audit-20261015.json'
$taskJobOwner=Join-Path $taskEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1'
if((Get-FileHash -LiteralPath $taskNode).Hash -cne '63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088'){throw 'Pinned Node changed before syntax check'}
& $taskJobOwner -Name "$taskName-syntax-check" -Executable $taskNode -WorkingDirectory $taskSource -Arguments @('--check',$taskDriver) -TimeoutSeconds 30
$taskSyntax=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName-syntax-check.json") -Raw|ConvertFrom-Json
if($taskSyntax.status -cne 'passed'){throw 'Source16 driver syntax check failed before prehash'}
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
$taskInput='C:/Users/adyba/pi-zig-native-oauth-callback-20261015/src/extensions/fixtures/ai-oauth-callback-ae7.input.txt'
$taskNative='C:/Users/adyba/pi-zig-native-oauth-callback-20261015'
if((git -C $taskNative rev-parse HEAD) -cne '961149b6'){if((git -C $taskNative rev-parse --short=8 HEAD) -cne '961149b6'){throw 'Frozen native checkpoint changed'}}
if(Test-Path -LiteralPath "$taskNative/src/extensions/fixtures/ai-oauth-callback-ae7.json"){throw 'Expected must remain absent through original terminal posthash'}
$taskNativeControls=@('build.zig','src/extensions/engine.zig','src/extensions/native_ai_oauth_callback_server.zig','src/extensions/native_ai_oauth_callback_page.html','src/native_ai_oauth_callback_test.zig')|ForEach-Object {Join-Path $taskNative $_}
$taskExtraPaths=@($taskInput,$taskDriver,$taskObserver,$taskAudit,$taskJobOwner,$PSCommandPath,$taskPreparation,$taskReadiness)+@($taskSpecs|ForEach-Object {Join-Path $taskEvidence $_.file})+@($taskNativeControls)
$taskExtra=@($taskExtraPaths|ForEach-Object {@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})
$taskControlManifest=Join-Path $taskEvidence "$taskName-extra-before.json"
$taskExtra|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $taskControlManifest -Encoding utf8NoBOM
$taskControlManifestHash=(Get-FileHash -LiteralPath $taskControlManifest).Hash
$taskFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
if($taskFree -lt 2MB){@{status='admission_denied';free_kib=$taskFree;required_kib=2MB;node_launched=$false}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-admission.json");exit 2}
@{root_slot=6;status='admitted';free_kib=$taskFree;required_kib=2MB;heap_mb=256;coordinated_with='Root explicit LIGHT6 Source16 granted; no native launch';observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-admission.json")
$taskOutput=Join-Path $taskEvidence "$taskName-output.json"
try { & $taskJobOwner -Name $taskName -Executable $taskNode -WorkingDirectory $taskSource -Arguments @('--max-old-space-size=256','--expose-gc','--conditions=source','--experimental-transform-types','--import',([Uri]$taskObserver).AbsoluteUri,$taskDriver,$taskOutput) -TimeoutSeconds 300 -EnvironmentOverrides @{NODE_OPTIONS='';NODE_PATH='';PI_SOURCE_ORACLE_CONTROL_MANIFEST=$taskControlManifest;NODE_USE_ENV_PROXY='';HTTP_PROXY='';HTTPS_PROXY='';ALL_PROXY='';NO_PROXY='127.0.0.1,localhost';OPENAI_API_KEY='';OPENAI_ORG_ID='';OPENAI_PROJECT_ID='';OPENAI_BASE_URL='';KIMI_API_KEY='';PI_PACKAGE_DIR='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012/packages/coding-agent'} } finally {
$taskPost=@()
foreach($taskItem in $taskFrozen){$taskChanged=@(Check-Rows $taskItem.rows);$taskPost+=@{name=$taskItem.name;files=$taskItem.rows.Count;drift=$taskChanged.Count;changed=$taskChanged}}
$taskExtraChanged=@(Check-Rows $taskExtra)
$taskAbsentChanged=@($taskAbsent|Where-Object {Test-Path -LiteralPath $_})
$taskControlManifestChanged=(Get-FileHash -LiteralPath $taskControlManifest).Hash -cne $taskControlManifestHash
@{manifests=$taskPost;extra_control_drift=$taskExtraChanged;control_manifest_drift=$taskControlManifestChanged;absent_dependency_drift=$taskAbsentChanged;historical_absence_records=$taskAbsent.Count;driver_sha256=(Get-FileHash -LiteralPath $taskDriver).Hash;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-posthash.json")
}
if(@($taskPost|Where-Object drift -ne 0).Count -or $taskExtraChanged.Count -or $taskAbsentChanged.Count -or $taskControlManifestChanged){throw 'Reference posthash drift'}
$taskOwner=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName.json") -Raw|ConvertFrom-Json
if($taskOwner.status -cne 'passed'){throw "Source oracle terminal $($taskOwner.status)"}
$taskDescendants=@(Get-CimInstance Win32_Process -Filter "ParentProcessId = $($taskOwner.pid)");if($taskDescendants.Count){throw 'Owned Source forest descendant remains'}
$taskResult=Get-Content -LiteralPath $taskOutput -Raw|ConvertFrom-Json
if(@($taskResult.ownedListeners).Count -ne 9 -or @($taskResult.ownedListeners|Where-Object {-not $_.closed -or $_.listening}).Count){throw 'Nine actual owned ephemeral callback listeners must close'}
if($taskResult.lifecycle.requestsStarted -ne $taskResult.lifecycle.requestsClosed -or $taskResult.lifecycle.acceptedSocketsRemaining -ne 0 -or $taskResult.lifecycle.requestSocketsRemaining -ne 0 -or $taskResult.lifecycle.activeOwnedHandles -ne 0){throw 'Actual Node builtin request connection lifecycle remains open'}
if($taskResult.count -ne 16 -or @($taskResult.rows).Count -ne 16 -or $taskResult.sourceHead -cne 'ae7b16d43b7c78c5b6fa3213fdd1215bb339729d' -or $taskResult.runtime -cne 'v24.14.0'){throw 'OriginalAe7 Source16 output missing'}
Write-Output ('ORIGINAL_AE7_CALLBACK_CASES='+$taskResult.rows.Count)
$taskExpected='C:/Users/adyba/pi-zig-native-oauth-callback-20261015/src/extensions/fixtures/ai-oauth-callback-ae7.json'
if(Test-Path -LiteralPath $taskExpected){throw 'Refuse expected replay'}
Copy-Item -LiteralPath $taskOutput -Destination $taskExpected
@{source_cases=16;expected_sha256=(Get-FileHash -LiteralPath $taskExpected).Hash;expected_published_after_terminal_and_full_posthash=$true;full_pi_qualified=$false}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-validation.json") -Encoding utf8NoBOM

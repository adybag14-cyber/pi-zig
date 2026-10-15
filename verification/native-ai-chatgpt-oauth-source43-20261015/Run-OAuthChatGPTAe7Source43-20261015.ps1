param([string]$Attempt='first')
$ErrorActionPreference='Stop'
$taskEvidence=$PSScriptRoot
$taskName="oauth-chatgpt-ae7-source43-$Attempt-20261015"
$taskNode='C:/Program Files/nodejs/node.exe'
$taskSource='C:/Users/adyba/pi-upstream-source-ae7b16d-20261015'
$taskRuntime='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012'
$taskDriver=Join-Path $taskEvidence 'sourceae7-oauth-chatgpt-capture-20261015.mjs'
$taskObserver=Join-Path $taskEvidence 'sourceae7-observe-20261015.mjs'
$taskAudit=Join-Path $taskEvidence 'sourceae7-dependency-contract-audit-20261015.json'
$taskJobOwner=Join-Path $taskEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1'
if((Get-FileHash -LiteralPath $taskNode).Hash -cne '63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088'){throw 'Pinned Node changed before syntax check'}
& $taskJobOwner -Name "$taskName-syntax-check" -Executable $taskNode -WorkingDirectory $taskSource -Arguments @('--check',$taskDriver) -TimeoutSeconds 30
$taskSyntax=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName-syntax-check.json") -Raw|ConvertFrom-Json
if($taskSyntax.status -cne 'passed'){throw 'Source43 driver syntax check failed before prehash'}
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
$taskInput='C:/Users/adyba/pi-zig-native-oauth-chatgpt-20261015/src/extensions/fixtures/ai-oauth-chatgpt-ae7.input.mjs'
$taskExtraPaths=@($taskInput,$taskDriver,$taskObserver,$taskAudit,$taskJobOwner,$PSCommandPath,$taskPreparation,$taskReadiness)+@($taskSpecs|ForEach-Object {Join-Path $taskEvidence $_.file})
$taskExtra=@($taskExtraPaths|ForEach-Object {@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})
$taskControlManifest=Join-Path $taskEvidence "$taskName-extra-before.json"
$taskExtra|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $taskControlManifest -Encoding utf8NoBOM
$taskControlManifestHash=(Get-FileHash -LiteralPath $taskControlManifest).Hash
$taskFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
if($taskFree -lt 2MB){@{status='admission_denied';free_kib=$taskFree;required_kib=2MB;node_launched=$false}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-admission.json");exit 2}
@{status='admitted';free_kib=$taskFree;required_kib=2MB;heap_mb=256;coordinated_with='Root explicit ChatGPT LIGHT Source43 grant required; no native launch';observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-admission.json")
$taskExistingListener=@(Get-NetTCPConnection -LocalPort 1455 -State Listen -ErrorAction SilentlyContinue)
if($taskExistingListener.Count){throw 'Source callback port1455 occupied; preserve unrelated listener'}
$taskPortProbe=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,1455)
try{
 $taskPortProbe.Start()
 @{port=1455;address='127.0.0.1';probe_bound=$true;probe_owner_pid=$PID;source_child_must_own_each_actual_listener=$true;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-callback-port-preflight.json") -Encoding utf8NoBOM
}finally{$taskPortProbe.Stop()}
$taskOutput=Join-Path $taskEvidence "$taskName-output.json"
& $taskJobOwner -Name $taskName -Executable $taskNode -WorkingDirectory $taskSource -Arguments @('--max-old-space-size=256','--expose-gc','--conditions=source','--experimental-transform-types','--import',([Uri]$taskObserver).AbsoluteUri,$taskDriver,$taskOutput) -TimeoutSeconds 300 -EnvironmentOverrides @{NODE_OPTIONS='';NODE_PATH='';PI_SOURCE_ORACLE_CONTROL_MANIFEST=$taskControlManifest;NODE_USE_ENV_PROXY='';HTTP_PROXY='';HTTPS_PROXY='';ALL_PROXY='';NO_PROXY='127.0.0.1,localhost';OPENAI_API_KEY='';OPENAI_ORG_ID='';OPENAI_PROJECT_ID='';OPENAI_BASE_URL='';KIMI_API_KEY='';PI_PACKAGE_DIR='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012/packages/coding-agent'}
$taskPost=@()
foreach($taskItem in $taskFrozen){$taskChanged=@(Check-Rows $taskItem.rows);$taskPost+=@{name=$taskItem.name;files=$taskItem.rows.Count;drift=$taskChanged.Count;changed=$taskChanged}}
$taskExtraChanged=@(Check-Rows $taskExtra)
$taskAbsentChanged=@($taskAbsent|Where-Object {Test-Path -LiteralPath $_})
$taskControlManifestChanged=(Get-FileHash -LiteralPath $taskControlManifest).Hash -cne $taskControlManifestHash
@{manifests=$taskPost;extra_control_drift=$taskExtraChanged;control_manifest_drift=$taskControlManifestChanged;absent_dependency_drift=$taskAbsentChanged;historical_absence_records=$taskAbsent.Count;driver_sha256=(Get-FileHash -LiteralPath $taskDriver).Hash;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-posthash.json")
if(@($taskPost|Where-Object drift -ne 0).Count -or $taskExtraChanged.Count -or $taskAbsentChanged.Count -or $taskControlManifestChanged){throw 'Reference posthash drift'}
$taskOwner=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName.json") -Raw|ConvertFrom-Json
if($taskOwner.status -cne 'passed'){throw "Source oracle terminal $($taskOwner.status)"}
$taskResult=Get-Content -LiteralPath $taskOutput -Raw|ConvertFrom-Json
if(@($taskResult.ownedListeners).Count -ne 6){throw 'Six actual source-owned callback listener observations required'}
if(!(@($taskResult.rows|Where-Object name -eq 'login-success')[0].value.credential.clientId -ceq 'issued + client')){throw 'Source43 owned callback port was unavailable or login failed'}; if($taskResult.count -ne 43 -or @($taskResult.rows).Count -ne 43 -or $taskResult.sourceHead -cne 'ae7b16d43b7c78c5b6fa3213fdd1215bb339729d' -or $taskResult.runtime -cne 'v24.14.0'){throw 'Original5abSource43 output missing'}
Write-Output ('ORIGINAL_AE7_CHATGPT_OAUTH_CASES='+$taskResult.rows.Count)
$taskExpected='C:/Users/adyba/pi-zig-native-oauth-chatgpt-20261015/src/extensions/fixtures/ai-oauth-chatgpt-ae7.json'
if(Test-Path -LiteralPath $taskExpected){throw 'Refuse expected replay'}
Copy-Item -LiteralPath $taskOutput -Destination $taskExpected
@{source_cases=43;expected_sha256=(Get-FileHash -LiteralPath $taskExpected).Hash;expected_published_after_terminal_and_full_posthash=$true;full_pi_qualified=$false}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-validation.json") -Encoding utf8NoBOM

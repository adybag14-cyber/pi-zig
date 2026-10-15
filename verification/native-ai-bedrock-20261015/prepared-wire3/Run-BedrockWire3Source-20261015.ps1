param([string]$Attempt='first')
$ErrorActionPreference='Stop'
$taskLightGrant=$false
$taskLightSlot=0
if(!$taskLightGrant){throw 'Prepared credential Source owner: Root light grant required before prehash or launch'}
$taskEvidence=$PSScriptRoot
$taskName="bedrock-wire3-5ab-source3-$Attempt-20261015"
foreach($taskSuffix in @('.json','-output.json','-posthash.json','-extra-before.json','-candidate-before.json')){if(Test-Path -LiteralPath (Join-Path $taskEvidence "$taskName$taskSuffix")){throw 'Refuse credential Source control/output replay'}}
$taskNode='C:/Program Files/nodejs/node.exe'
$taskSource='C:/Users/adyba/pi-upstream-source-5ab7fe7-20261015'
$taskRuntime='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012'
$taskDriver=Join-Path $taskEvidence 'bedrock-wire-source3-20261015.mjs'
$taskCandidate='C:/Users/adyba/pi-zig-ai-bedrock-aws-chain-20261015'
$taskObserver=Join-Path $taskEvidence 'source5ab-observe-20261015.mjs'
$taskAudit=Join-Path $taskEvidence 'source5ab-dependency-contract-audit-20261015.json'
$taskJobOwner=Join-Path $taskEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1'
& $taskNode --check $taskDriver
if($LASTEXITCODE -ne 0){throw 'Credential Source driver syntax check failed before freeze'}
$taskParseTokens=$null;$taskParseErrors=$null
[Management.Automation.Language.Parser]::ParseFile($PSCommandPath,[ref]$taskParseTokens,[ref]$taskParseErrors)|Out-Null
if(@($taskParseErrors).Count){throw 'Credential Source wrapper parse failed before freeze'}
if(@(git -C $taskCandidate status --porcelain).Count){throw 'Source control candidate must be clean before freeze'}
$taskCandidateHead=git -C $taskCandidate rev-parse HEAD
$taskCandidateRows=@(git -C $taskCandidate ls-files --cached --others --exclude-standard | ForEach-Object {$taskPath=Join-Path $taskCandidate $_;@{path=$taskPath;sha256=(Get-FileHash -LiteralPath $taskPath).Hash}})
$taskCandidateManifest=Join-Path $taskEvidence "$taskName-candidate-before.json"
$taskCandidateRows|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $taskCandidateManifest -Encoding utf8NoBOM
$taskSpecs=@(
 @{name='source';file='source5ab-full-manifest-20261015.json';count=1967},
 @{name='dependencies';file='durable-19cb534-reference-20261012-all-built-runtime.json';count=31064},
 @{name='node_tools';file='root-current8a-npm-tools-before.json';count=1774}
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
if((git -C $taskSource rev-parse HEAD) -cne '5ab7fe74c400097b386662205cd93900695b8a71'){throw 'Pinned5abSource head changed'}
if((Get-FileHash -LiteralPath $taskNode).Hash -cne '63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088'){throw 'Pinned Node changed'}
$taskContract=Get-Content -LiteralPath $taskAudit -Raw|ConvertFrom-Json
if($taskContract.latestHead -cne '5ab7fe74c400097b386662205cd93900695b8a71' -or $taskContract.installed_metadata_verified -ne 281 -or $taskContract.platform_optional_absent_records -ne 80 -or $taskContract.historical_missing_records_retained -ne 4){throw 'Dependency contract scope changed'}
$taskAbsent=@($taskContract.pins|Where-Object status -eq 'platform_optional_absent'|ForEach-Object {Join-Path $taskRuntime $_.path})+@($taskContract.mismatches|ForEach-Object {Join-Path $taskRuntime $_.path})
if($taskAbsent.Count -ne 84 -or @($taskAbsent|Where-Object {Test-Path -LiteralPath $_}).Count){throw 'Historical absent dependency state changed'}
$taskInput=Join-Path $taskEvidence 'bedrock-wire-input3-20261015.json'
$taskExtraPaths=@('C:/Users/adyba/pi-zig-update-evidence-20261003/bedrock-empty-aws-20261015/config','C:/Users/adyba/pi-zig-update-evidence-20261003/bedrock-empty-aws-20261015/credentials',$taskInput,$taskDriver,$taskObserver,$taskAudit,$taskJobOwner,$PSCommandPath,$taskCandidateManifest)+@($taskSpecs|ForEach-Object {Join-Path $taskEvidence $_.file})
$taskExtra=@($taskExtraPaths|ForEach-Object {@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})
$taskControlManifest=Join-Path $taskEvidence "$taskName-extra-before.json"
$taskExtra|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $taskControlManifest -Encoding utf8NoBOM
$taskControlManifestHash=(Get-FileHash -LiteralPath $taskControlManifest).Hash
$taskFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
if($taskFree -lt 2MB){@{status='admission_denied';free_kib=$taskFree;required_kib=2MB;node_launched=$false}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-admission.json");exit 2}
@{status='admitted';slot=$taskLightSlot;free_kib=$taskFree;required_kib=2MB;heap_mb=256;candidate=$taskCandidateHead;candidate_files=$taskCandidateRows.Count;coordinated_with='Root grant required for focused full-header wire Source3';observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-admission.json")
$taskOutput=Join-Path $taskEvidence "$taskName-output.json"
& $taskJobOwner -Name $taskName -Executable $taskNode -WorkingDirectory $taskSource -Arguments @('--max-old-space-size=256','--conditions=source','--experimental-transform-types','--import',([Uri]$taskObserver).AbsoluteUri,$taskDriver,$taskOutput,$taskInput,'C:/Users/adyba/pi-zig-update-evidence-20261003/bedrock-credential-owned-work-20261015') -TimeoutSeconds 300 -EnvironmentOverrides @{NODE_OPTIONS='';NODE_PATH='';PI_SOURCE_ORACLE_CONTROL_MANIFEST=$taskControlManifest;NODE_USE_ENV_PROXY='';HTTP_PROXY='';HTTPS_PROXY='';ALL_PROXY='';NO_PROXY='127.0.0.1,localhost';OPENAI_API_KEY='';OPENAI_ORG_ID='';OPENAI_PROJECT_ID='';OPENAI_BASE_URL='';KIMI_API_KEY='';AWS_PROFILE='';AWS_DEFAULT_PROFILE='';AWS_ACCESS_KEY_ID='';AWS_SECRET_ACCESS_KEY='';AWS_SESSION_TOKEN='';AWS_BEARER_TOKEN_BEDROCK='';AWS_WEB_IDENTITY_TOKEN_FILE='';AWS_ROLE_ARN='';AWS_CONTAINER_CREDENTIALS_RELATIVE_URI='';AWS_CONTAINER_CREDENTIALS_FULL_URI='';AWS_CONTAINER_AUTHORIZATION_TOKEN='';AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE='';AWS_CONFIG_FILE='C:/Users/adyba/pi-zig-update-evidence-20261003/bedrock-empty-aws-20261015/config';AWS_SHARED_CREDENTIALS_FILE='C:/Users/adyba/pi-zig-update-evidence-20261003/bedrock-empty-aws-20261015/credentials';AWS_EC2_METADATA_DISABLED='true';PI_PACKAGE_DIR='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012/packages/coding-agent'}
$taskPost=@()
$taskCandidateChanged=@(Check-Rows $taskCandidateRows)
$taskCandidateCurrentRows=@(git -C $taskCandidate ls-files --cached --others --exclude-standard)
$taskCandidateInventoryChanged=($taskCandidateCurrentRows.Count -ne $taskCandidateRows.Count) -or ((git -C $taskCandidate rev-parse HEAD) -cne $taskCandidateHead) -or (@(git -C $taskCandidate status --porcelain).Count -ne 0)
$taskPost+=@{name='candidate';files=$taskCandidateRows.Count;drift=$taskCandidateChanged.Count;changed=$taskCandidateChanged;inventory_drift=$taskCandidateInventoryChanged;head=$taskCandidateHead}
foreach($taskItem in $taskFrozen){$taskChanged=@(Check-Rows $taskItem.rows);$taskPost+=@{name=$taskItem.name;files=$taskItem.rows.Count;drift=$taskChanged.Count;changed=$taskChanged}}
$taskExtraChanged=@(Check-Rows $taskExtra)
$taskAbsentChanged=@($taskAbsent|Where-Object {Test-Path -LiteralPath $_})
$taskControlManifestChanged=(Get-FileHash -LiteralPath $taskControlManifest).Hash -cne $taskControlManifestHash
@{manifests=$taskPost;extra_control_drift=$taskExtraChanged;control_manifest_drift=$taskControlManifestChanged;absent_dependency_drift=$taskAbsentChanged;historical_absence_records=$taskAbsent.Count;driver_sha256=(Get-FileHash -LiteralPath $taskDriver).Hash;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-posthash.json")
if(@($taskPost|Where-Object drift -ne 0).Count -or $taskExtraChanged.Count -or $taskAbsentChanged.Count -or $taskControlManifestChanged -or $taskCandidateInventoryChanged){throw 'Reference posthash drift'}
$taskOwner=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName.json") -Raw|ConvertFrom-Json
if($taskOwner.status -cne 'passed'){throw "Source oracle terminal $($taskOwner.status)"}
$taskResult=Get-Content -LiteralPath $taskOutput -Raw|ConvertFrom-Json
if( $taskResult.cases -ne 3 -or @($taskResult.rows).Count -ne 3 -or $taskResult.sourceHead -cne '5ab7fe74c400097b386662205cd93900695b8a71' -or $taskResult.actualNode.version -cne 'v24.14.0'){throw 'Original5abSource25 credentials output missing'}
if(@($taskResult.blocked).Count){throw 'Fixture attempted a non-loopback request'}
foreach($taskRow in $taskResult.rows){
 if(!$taskRow.home.StartsWith($taskResult.workspace,[StringComparison]::OrdinalIgnoreCase) -or !@($taskRow.beforeOwnedFiles).Count){throw 'Credential fixture owned inputs missing'}
 foreach($taskRequest in $taskRow.requests){if(([Uri]$taskRequest.url).Host -cne '127.0.0.1' -or ([Uri]$taskRequest.url).PathAndQuery -cne $taskRequest.path){throw 'Credential fixture wire URL/path escaped owned loopback'}}
}
$taskDerivedFiles=@($taskResult.rows|ForEach-Object {$_.afterOwnedFiles})
$taskDerivedDrift=@($taskDerivedFiles|Where-Object {!(Test-Path -LiteralPath $_.path -PathType Leaf) -or (Get-FileHash -LiteralPath $_.path).Hash -ine $_.sha256})
$taskInitialChanges=@($taskResult.rows|ForEach-Object {$taskAfter=@{};foreach($taskFile in $_.afterOwnedFiles){$taskAfter[$taskFile.path]=$taskFile.sha256};foreach($taskFile in $_.beforeOwnedFiles){if($taskAfter[$taskFile.path] -ine $taskFile.sha256){@{path=$taskFile.path;before=$taskFile.sha256;after=$taskAfter[$taskFile.path]}}}})
@{initial_files=@($taskResult.rows|ForEach-Object {$_.beforeOwnedFiles}).Count;observed_files=$taskDerivedFiles.Count;post_drift=$taskDerivedDrift.Count;observed_initial_changes=$taskInitialChanges;output_sha256=(Get-FileHash -LiteralPath $taskOutput).Hash;candidate=$taskCandidateHead;slot=$taskLightSlot}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-owned-files-post.json")
if($taskDerivedDrift.Count){throw 'Owned fake credential file post-capture drift'}
if(@($taskInitialChanges|Where-Object {$_.path -notmatch '[\\/]cache[\\/]' -and $_.path -notmatch '[\\/]login-cache[\\/]'}).Count){throw 'Unexpected fixture input mutation'}
Write-Output ('ORIGINAL_5AB_BEDROCK_WIRE3_CASES='+$taskResult.rows.Count)








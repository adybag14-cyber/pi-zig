param([string]$Attempt='first',[Parameter(Mandatory)][string]$CandidateHead)
$ErrorActionPreference='Stop'
$taskEvidence=$PSScriptRoot
$taskName="oauth-codex-radius-browser-ae7-source7-$Attempt-20261015"
$taskNode='C:/Program Files/nodejs/node.exe'
$taskSource='C:/Users/adyba/pi-upstream-source-ae7b16d-20261015'
$taskRuntime='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012'
$taskNative='C:/Users/adyba/pi-zig-native-oauth-codex-radius-20261015'
$taskDriver=Join-Path $taskEvidence 'oauth-codex-radius-browser-source-owner-20261015.mjs'
$taskHarness=Join-Path $taskEvidence 'oauth-codex-radius-browser-ae7-cases-20261015.mjs'
$taskObserver=Join-Path $taskEvidence 'sourceae7-observe-20261015.mjs'
$taskAudit=Join-Path $taskEvidence 'sourceae7-dependency-contract-audit-20261015.json'
$taskJobOwner=Join-Path $taskEvidence 'Invoke-OwnedOAuthBrowserSourceJob-20261015.ps1'
$taskSealedControls=Join-Path $taskNative 'verification/oauth-codex-radius-browser-ae7-source7-prepared-20261015'
if((git -c gc.auto=0 -c maintenance.auto=false -C $taskNative rev-parse HEAD) -cne $CandidateHead -or @(git -c gc.auto=0 -c maintenance.auto=false -C $taskNative status --porcelain).Count){throw 'Exact sealed clean candidate head required'}
$taskFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
if($taskFree -lt 2MB){throw 'Fresh2GiB admission required before Source syntax checks'}
if((Get-FileHash -LiteralPath $taskNode).Hash -cne '63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088'){throw 'Pinned Node changed before syntax check'}
foreach($taskSyntaxFile in @($taskDriver,$taskHarness)){
 $taskSyntaxName="$taskName-syntax-check-$([IO.Path]::GetFileNameWithoutExtension($taskSyntaxFile))"
 & $taskJobOwner -Name $taskSyntaxName -Executable $taskNode -WorkingDirectory $taskSource -Arguments @('--max-old-space-size=256','--check',$taskSyntaxFile) -TimeoutSeconds 30 -SettleSeconds 10 -EnvironmentOverrides @{NODE_OPTIONS='';NODE_PATH=''}
 $taskSyntax=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskSyntaxName.json") -Raw|ConvertFrom-Json
 if($taskSyntax.status -cne 'passed'){throw 'Source7 syntax check failed before prehash'}
}
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
function Candidate-Paths {
 @(& git -c gc.auto=0 -c maintenance.auto=false -C $taskNative ls-files --cached --others --exclude-standard | ForEach-Object {Join-Path $taskNative $_})
}
function Scoped-Paths([string]$taskRoot){
 $taskPaths=[Collections.Generic.List[string]]::new()
 $taskDirs=[Collections.Generic.Stack[string]]::new();$taskDirs.Push($taskRoot)
 while($taskDirs.Count){foreach($taskEntry in [IO.DirectoryInfo]::new($taskDirs.Pop()).EnumerateFileSystemInfos()){
  if($taskEntry.Name -ceq '.git' -or ($taskEntry.Attributes -band [IO.FileAttributes]::ReparsePoint)){continue}
  if($taskEntry.Attributes -band [IO.FileAttributes]::Directory){$taskDirs.Push($taskEntry.FullName)}else{$taskPaths.Add($taskEntry.FullName)}
 }}
 return @($taskPaths|Sort-Object)
}
$taskCandidatePaths=@(Candidate-Paths)
$taskCandidate=@($taskCandidatePaths|ForEach-Object {@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})
$taskCandidateManifest=Join-Path $taskEvidence "$taskName-candidate-before.json"
$taskCandidate|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $taskCandidateManifest -Encoding utf8NoBOM
$taskFrozen=@()
foreach($taskSpec in $taskSpecs){
 $taskRows=@(Get-Content -LiteralPath (Join-Path $taskEvidence $taskSpec.file) -Raw|ConvertFrom-Json)
 if($taskRows.Count -ne $taskSpec.count){throw "Full manifest inventory mismatch $($taskSpec.name)"}
 if(@(Check-Rows $taskRows).Count){throw "Reference prehash drift $($taskSpec.name)"}
 $taskFrozen+=@{name=$taskSpec.name;manifest=$taskSpec.file;rows=$taskRows}
}
$taskInventories=@(
 @{name='source';paths=@(Scoped-Paths $taskSource)},
 @{name='dependencies';paths=@(Scoped-Paths $taskRuntime)},
 @{name='node_tools';paths=@([IO.Path]::GetFullPath($taskNode))+@(Scoped-Paths 'C:/Program Files/nodejs/node_modules/npm')}
)
foreach($taskInventory in $taskInventories){
 $taskExpectedPaths=@(($taskFrozen|Where-Object name -ceq $taskInventory.name).rows.path|Sort-Object)
 $taskPathDrift=@(Compare-Object $taskExpectedPaths @($taskInventory.paths|Sort-Object))
 if($taskPathDrift.Count){@{status='preparation_failed';inventory=$taskInventory.name;drift=$taskPathDrift;source_child_launched=$false;expected_absent=!(Test-Path -LiteralPath (Join-Path $taskNative 'src/extensions/fixtures/oauth-codex-radius-browser-ae7-source.json'))}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-preparation-failure.json") -Encoding utf8NoBOM;throw "Full path inventory differs before Source: $($taskInventory.name)"}
}
$taskInventoryManifest=Join-Path $taskEvidence "$taskName-inventories-before.json"
$taskInventories|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $taskInventoryManifest -Encoding utf8NoBOM
if((git -c gc.auto=0 -c maintenance.auto=false -C $taskSource rev-parse HEAD) -cne 'ae7b16d43b7c78c5b6fa3213fdd1215bb339729d'){throw 'PinnedAe7Source head changed'}
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
$taskInput=Join-Path $taskNative 'src/extensions/fixtures/oauth-codex-radius-browser-ae7-cases.input.txt'
if((Get-FileHash -LiteralPath $taskInput).Hash -cne (Get-FileHash -LiteralPath $taskHarness).Hash){throw 'Source/native harness bytes differ'}
$taskExpected=Join-Path $taskNative 'src/extensions/fixtures/oauth-codex-radius-browser-ae7-source.json'
if(Test-Path -LiteralPath $taskExpected){throw 'Refuse expected replay'}
$taskExtraPaths=@($taskInput,$taskHarness,$taskDriver,$taskObserver,$taskAudit,$taskJobOwner,$PSCommandPath,$taskPreparation,$taskReadiness,
 (Join-Path $taskEvidence 'oauth-codex-radius-browser-source-owner-20261015.json'),
 (Join-Path $taskNative 'src/extensions/fixtures/oauth-codex-radius-ae7-native.input.txt'),
 (Join-Path $taskNative 'src/extensions/native_ai_oauth_codex.zig'),
 (Join-Path $taskNative 'src/extensions/native_ai_oauth_radius.zig'),
 (Join-Path $taskNative 'src/native_ai_oauth_codex_radius_test.zig'),
 (Join-Path $taskNative 'src/native_ai_oauth_codex_radius_browser_test.zig'),
 (Join-Path $taskNative 'build.zig'),$taskCandidateManifest,$taskInventoryManifest)+@($taskSpecs|ForEach-Object {Join-Path $taskEvidence $_.file})
foreach($taskControlName in @('Run-OAuthCodexRadiusBrowserAe7Source7-20261015.ps1','Invoke-OwnedOAuthBrowserSourceJob-20261015.ps1','oauth-codex-radius-browser-source-owner-20261015.mjs','oauth-codex-radius-browser-source-owner-20261015.json','oauth-codex-radius-browser-ae7-cases-20261015.mjs')){
 if((Get-FileHash -LiteralPath (Join-Path $taskEvidence $taskControlName)).Hash -cne (Get-FileHash -LiteralPath (Join-Path $taskSealedControls $taskControlName)).Hash){throw "Sealed owner control differs: $taskControlName"}
}
$taskExtra=@($taskExtraPaths|ForEach-Object {@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})
$taskControlManifest=Join-Path $taskEvidence "$taskName-extra-before.json"
$taskExtra|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $taskControlManifest -Encoding utf8NoBOM
$taskControlManifestHash=(Get-FileHash -LiteralPath $taskControlManifest).Hash
$taskFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
if($taskFree -lt 2MB){@{status='admission_denied';free_kib=$taskFree;required_kib=2MB;node_launched=$false}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-admission.json");exit 2}
@{status='admitted';free_kib=$taskFree;required_kib=2MB;heap_mb=256;coordinated_with='Root LIGHT6 and callback1455/1456 explicit resume';native_head=$CandidateHead;candidate_files=$taskCandidate.Count;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-admission.json")
$taskPorts=@(1455,1456)
foreach($taskPort in $taskPorts){
 if(@(Get-NetTCPConnection -LocalPort $taskPort -State Listen -ErrorAction SilentlyContinue).Count){throw "Source callback port $taskPort occupied; preserve unrelated listener"}
 $taskProbe=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,$taskPort)
 try{$taskProbe.Start()}finally{$taskProbe.Stop()}
}
@{ports=$taskPorts;probes_bound=$true;probe_owner_pid=$PID;source_child_must_own_each_actual_listener=$true;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-callback-port-preflight.json") -Encoding utf8NoBOM
$taskOutput=Join-Path $taskEvidence "$taskName-output.json"
$taskOwnerFailure=$null
try{& $taskJobOwner -Name $taskName -Executable $taskNode -WorkingDirectory $taskSource -Arguments @('--max-old-space-size=256','--expose-gc','--conditions=source','--experimental-transform-types','--import',([Uri]$taskObserver).AbsoluteUri,$taskDriver,$taskOutput) -TimeoutSeconds 300 -SettleSeconds 10 -EnvironmentOverrides @{NODE_OPTIONS='';NODE_PATH='';PI_SOURCE_ORACLE_CONTROL_MANIFEST=$taskControlManifest;NODE_USE_ENV_PROXY='';HTTP_PROXY='';HTTPS_PROXY='';ALL_PROXY='';NO_PROXY='127.0.0.1,localhost';OPENAI_API_KEY='';OPENAI_ORG_ID='';OPENAI_PROJECT_ID='';OPENAI_BASE_URL='';KIMI_API_KEY='';PI_OAUTH_CALLBACK_HOST='127.0.0.1';PI_PACKAGE_DIR='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012/packages/coding-agent'}}catch{$taskOwnerFailure=$_.Exception.Message}
$taskPost=@()
foreach($taskItem in $taskFrozen){$taskChanged=@(Check-Rows $taskItem.rows);$taskPost+=@{name=$taskItem.name;files=$taskItem.rows.Count;drift=$taskChanged.Count;changed=$taskChanged}}
$taskExtraChanged=@(Check-Rows $taskExtra)
$taskAbsentChanged=@($taskAbsent|Where-Object {Test-Path -LiteralPath $_})
$taskControlManifestChanged=(Get-FileHash -LiteralPath $taskControlManifest).Hash -cne $taskControlManifestHash
$taskCandidateChanged=@(Check-Rows $taskCandidate)
$taskCandidateInventoryChanged=@(Compare-Object $taskCandidatePaths @(Candidate-Paths))
$taskCurrentInventories=@(@{name='source';paths=@(Scoped-Paths $taskSource)},@{name='dependencies';paths=@(Scoped-Paths $taskRuntime)},@{name='node_tools';paths=@([IO.Path]::GetFullPath($taskNode))+@(Scoped-Paths 'C:/Program Files/nodejs/node_modules/npm')})
$taskInventoryPost=@(foreach($taskInventory in $taskInventories){$taskCurrent=($taskCurrentInventories|Where-Object name -ceq $taskInventory.name).paths;@{name=$taskInventory.name;count=$taskInventory.paths.Count;drift=@(Compare-Object @($taskInventory.paths|Sort-Object) @($taskCurrent|Sort-Object))}})
$taskHeadChanged=(git -c gc.auto=0 -c maintenance.auto=false -C $taskNative rev-parse HEAD) -cne $CandidateHead
$taskSourceHeadChanged=(git -c gc.auto=0 -c maintenance.auto=false -C $taskSource rev-parse HEAD) -cne 'ae7b16d43b7c78c5b6fa3213fdd1215bb339729d'
$taskExpectedAbsent=!(Test-Path -LiteralPath $taskExpected)
@{manifests=$taskPost;candidate_files=$taskCandidate.Count;candidate_drift=$taskCandidateChanged;candidate_inventory_drift=$taskCandidateInventoryChanged;path_inventories=$taskInventoryPost;candidate_head_drift=$taskHeadChanged;source_head_drift=$taskSourceHeadChanged;expected_still_absent=$taskExpectedAbsent;extra_control_drift=$taskExtraChanged;control_manifest_drift=$taskControlManifestChanged;absent_dependency_drift=$taskAbsentChanged;historical_absence_records=$taskAbsent.Count;driver_sha256=(Get-FileHash -LiteralPath $taskDriver).Hash;owner_failure=$taskOwnerFailure;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-posthash.json")
if(@($taskPost|Where-Object drift -ne 0).Count -or $taskExtraChanged.Count -or $taskAbsentChanged.Count -or $taskControlManifestChanged -or $taskCandidateChanged.Count -or $taskCandidateInventoryChanged.Count -or @($taskInventoryPost|Where-Object {$_.drift.Count}).Count -or $taskHeadChanged -or $taskSourceHeadChanged -or !$taskExpectedAbsent){throw 'Reference or full candidate posthash drift'}
if($taskOwnerFailure){throw $taskOwnerFailure}
$taskOwner=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName.json") -Raw|ConvertFrom-Json
if($taskOwner.status -cne 'passed' -or !$taskOwner.independent_pid_absent -or !$taskOwner.terminal_kernel_handle){throw "Source oracle terminal/absence $($taskOwner.status)"}
$taskResult=Get-Content -LiteralPath $taskOutput -Raw|ConvertFrom-Json
if($taskResult.count -ne 7 -or @($taskResult.rows).Count -ne 7 -or @($taskResult.caseIds).Count -ne 7 -or $taskResult.sourceHead -cne 'ae7b16d43b7c78c5b6fa3213fdd1215bb339729d' -or $taskResult.runtime -cne 'v24.14.0'){throw 'Original ae7 Source7 output missing'}
if(@($taskResult.listeners).Count -ne 7 -or @($taskResult.listeners|Where-Object {$_.pid -ne $taskOwner.pid -or !$_.actualServer}).Count){throw 'Seven actual source-owned listeners required'}
if($taskResult.ownedSockets.accepted -ne 2 -or $taskResult.ownedSockets.closed -ne 2 -or $taskResult.ownedSockets.remaining -ne 0 -or @($taskResult.rawEvents|Where-Object type -ceq 'auth_url').Count -ne 7 -or @($taskResult.rawDiagnostics).Count -ne 3){throw 'Exact genuine raw effect/socket inventory required'}
if(!$taskResult.rows[0].ok -or !$taskResult.rows[1].ok -or !$taskResult.rows[2].ok -or $taskResult.rows[3].error.message -cne 'State mismatch' -or $taskResult.rows[4].error.message -cne 'Missing authorization code' -or $taskResult.rows[5].value.page.status -ne 200 -or $taskResult.rows[6].value.page.status -ne 502){throw 'Browser7 actual expected control branches did not complete'}
foreach($taskPort in $taskPorts){if(@(Get-NetTCPConnection -LocalPort $taskPort -State Listen -ErrorAction SilentlyContinue).Count){throw "Source callback port $taskPort still listening after terminal"}}
for($taskCase=0;$taskCase -lt 7;$taskCase++){if($taskResult.rows[$taskCase].id -cne $taskResult.caseIds[$taskCase]){throw 'Source7 strict ordered inventory drift'}}
if(Test-Path -LiteralPath $taskExpected){throw 'Refuse expected replay after Source'}
$taskResult.rows|ConvertTo-Json -Depth 100|Set-Content -LiteralPath $taskExpected -Encoding utf8NoBOM
@{source_cases=7;expected_sha256=(Get-FileHash -LiteralPath $taskExpected).Hash;expected_published_after_terminal_and_full_posthash=$true;full_pi_qualified=$false}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-validation.json") -Encoding utf8NoBOM
Write-Output ('ORIGINAL_AE7_CODEX_RADIUS_OAUTH_CASES='+$taskResult.rows.Count)

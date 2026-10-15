$ErrorActionPreference='Stop'
$taskEvidence='C:/Users/adyba/pi-zig-update-evidence-20261003'
$taskPrivate='C:/Users/adyba/pi-zig-ai-anthropic-bedrock-20261015'
$taskExpectedHead='3f8be060ad40b3e13ad445366cbd26c46c3c6eed'
$taskName='native-ai-claude5ab-3f8be060-debug-extended-fourth-slot1-20261015'
$taskZig='C:/Users/adyba/pi-zig-toolchain-20261003/zig-x86_64-windows-0.16.0/zig.exe'
$taskOwner=Join-Path $taskEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1'
$taskToolReference=Join-Path $taskEvidence 'durable-latest89-full-inspect-53ae-tool-prehash-20261011.json'
function Source-Rows {
 @(git -C $taskPrivate ls-files --cached --others --exclude-standard|Sort-Object -Unique|Where-Object{Test-Path -LiteralPath (Join-Path $taskPrivate $_) -PathType Leaf}|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath (Join-Path $taskPrivate $_)).Hash}})
}
function Vendor-Rows {
 @(Get-ChildItem -LiteralPath (Join-Path $taskPrivate 'vendor') -File -Recurse -Force|Sort-Object FullName|ForEach-Object{[ordered]@{path=$_.FullName;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}})
}
function Tool-Drift($rows){
 $mismatches=[Collections.Generic.List[string]]::new()
 foreach($row in $rows){
  if(!(Test-Path -LiteralPath $row.path -PathType Leaf)){$mismatches.Add($row.path);continue}
  $stream=[IO.File]::OpenRead($row.path)
  try{$actual=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream))}finally{$stream.Dispose()}
  if($actual -cne $row.sha256){$mismatches.Add($row.path)}
 }
 return @($mismatches)
}
function Metadata-SelectedNames($taskFile,$taskFilter){
 foreach($taskMatch in [regex]::Matches([IO.File]::ReadAllText((Join-Path $taskPrivate "src/$taskFile.zig")),'(?m)^test "([^"]+)"')){if($taskMatch.Groups[1].Value -match $taskFilter){$taskFile+'.test.'+$taskMatch.Groups[1].Value}}
}
function Metadata-Gate {
 . (Join-Path $taskPrivate 'tools/ci/native_qualification_ci.ps1')
 $taskArtifacts=@(Get-ChildItem -LiteralPath (Join-Path $taskPrivate '.zig-cache/o') -Filter test.exe -Recurse -File|Where-Object FullName -NotIn $taskBinariesBefore)
 if($taskArtifacts.Count -ne 2){throw 'Exactly two newly compiled actual test artifacts required'}
 $taskPrimary=@(Metadata-SelectedNames 'native_ai_claude_request_test' '^native Claude5ab (Anthropic|request owner)')+@('extensions.native_durable_storage.test_0')
 $taskExtended=@(Metadata-SelectedNames 'native_ai_claude_extended_test' '^native Claude5ab extended')+@(Metadata-SelectedNames 'native_ai_constrained_sampling_test' '^native constrained sampling')+@(Metadata-SelectedNames 'native_ai_sdk_headers_test' '^native SDK nullable headers')+@(Metadata-SelectedNames 'native_node_function_exception_test' '^native node function preserves caught getter')+@(Metadata-SelectedNames 'native_ai_anthropic_api_error_test' '^native Anthropic SDK errors')+@(Metadata-SelectedNames 'native_ai_anthropic_sdk_boundary_test' '^native Claude5ab extended')+@('extensions.native_durable_storage.test_0')
 if($taskPrimary.Count -ne 5 -or $taskExtended.Count -ne 9){throw 'Exact source-selected14 array required'}
 $taskSelected=@()
 foreach($taskArtifact in $taskArtifacts){
  # Binary text chooses only the expected component size. Actual metadata
  # independently supplies every selected name and the protocol version.
  $taskIsExtended=[Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($taskArtifact.FullName)).Contains('native_ai_claude_extended_test.test.native Claude5ab extended')
  $taskExpected=if($taskIsExtended){$taskExtended}else{$taskPrimary}
  $taskId=if($taskIsExtended){'extended9'}else{'source25-five'}
  $taskInventory=Read-CiTestMetadata $taskArtifact.FullName $taskPrivate (Join-Path $taskEvidence "$taskName-metadata-$taskId") $taskExpected.Count
  if(@(Compare-Object ($taskInventory.tests|Sort-Object -CaseSensitive) ($taskExpected|Sort-Object -CaseSensitive) -CaseSensitive).Count){throw 'Exact actual selected metadata names mismatch'}
  if((Get-FileHash -LiteralPath $taskArtifact.FullName).Hash -cne $taskInventory.binary_sha256){throw 'Actual metadata artifact changed during query'}
  $taskSelected+=@{id=$taskId;count=$taskExpected.Count;metadata=$taskInventory}
 }
 if(@($taskSelected|Where-Object id -eq 'extended9').Count -ne 1 -or @($taskSelected|Where-Object id -eq 'source25-five').Count -ne 1){throw 'Exact two selected components required'}
 @{candidate=$taskExpectedHead;selected=$taskSelected;queries_only=$true;run_test_commands=0;status='passed';completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-metadata-selected.json") -Encoding utf8NoBOM
 return $taskSelected
}
function Fresh-Admission([string]$phase){
 [GC]::Collect();[GC]::WaitForPendingFinalizers();[GC]::Collect()
 $free=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
 $other=@(Get-CimInstance Win32_Process -Filter "Name = 'zig.exe'"|Select-Object ProcessId,ParentProcessId,ExecutablePath,CommandLine,@{n='created_utc';e={([DateTimeOffset]$_.CreationDate).UtcDateTime.ToString('o')}})
 $roots=@($other|Where-Object{$_.CommandLine -match '\sbuild\s'})
 $record=[ordered]@{status=if($free -lt 16MB -or $roots.Count -ge 4){'admission_failed'}else{'admitted'};phase=$phase;candidate=$taskExpectedHead;slot=1;free_kib=$free;threshold_kib=16MB;max_native_roots=4;other_native=$other;source=$taskBefore.Count;tools=$taskTools.Count;controls=$taskControls.Count;jobs=1;llvm=$true;compile_timeout_seconds=1320;runtime_outer_timeout_seconds=300;test_timeout_seconds=120;host_await_timeout_seconds=10;native_launched=$false;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}
 $record|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-$phase-admission.json") -Encoding utf8NoBOM
 return $record.status -ceq 'admitted'
}
if($taskExpectedHead -eq '__FROZEN_CANDIDATE__' -or $taskName -eq '__UNIQUE_OWNER_NAME__'){throw 'Draft must freeze exact new candidate and unique owner first'}
if((git -C $taskPrivate rev-parse HEAD) -cne $taskExpectedHead -or (git -C $taskPrivate status --porcelain)){throw 'Exact clean candidate required'}
$taskBefore=Source-Rows
$taskTools=(Get-Content -LiteralPath $taskToolReference -Raw|ConvertFrom-Json).inputs
if($taskTools.Count -ne 19546){throw 'Full compiler manifest required'}
$taskSource='C:/Users/adyba/pi-upstream-source-5ab7fe7-20261015'
$taskRuntime='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012'
$taskAuditPath=Join-Path $taskEvidence 'source5ab-dependency-contract-audit-20261015.json'
$taskReferenceSpecs=@(
 @{name='Source5ab';file='source5ab-full-manifest-20261015.json';count=1967},
 @{name='dependencies';file='durable-19cb534-reference-20261012-all-built-runtime.json';count=31064},
 @{name='NodeTools';file='root-current8a-npm-tools-before.json';count=1774}
)
$taskReferences=@()
foreach($taskSpec in $taskReferenceSpecs){
 $taskRows=@(Get-Content -LiteralPath (Join-Path $taskEvidence $taskSpec.file) -Raw|ConvertFrom-Json)
 if($taskRows.Count -ne $taskSpec.count){throw "Complete reference inventory missing $($taskSpec.name)"}
 $taskReferences+=@{name=$taskSpec.name;rows=$taskRows}
}
$taskAudit=Get-Content -LiteralPath $taskAuditPath -Raw|ConvertFrom-Json
if($taskAudit.latestHead -cne '5ab7fe74c400097b386662205cd93900695b8a71' -or $taskAudit.installed_metadata_verified -ne 281 -or $taskAudit.platform_optional_absent_records -ne 80 -or $taskAudit.historical_missing_records_retained -ne 4){throw 'Complete dependency contract changed'}
$taskAbsent=@($taskAudit.pins|Where-Object status -eq 'platform_optional_absent'|ForEach-Object {Join-Path $taskRuntime $_.path})+@($taskAudit.mismatches|ForEach-Object {Join-Path $taskRuntime $_.path})
if($taskAbsent.Count -ne 84 -or @($taskAbsent|Where-Object {Test-Path -LiteralPath $_}).Count){throw 'Dependency absence state changed'}
if((git -C $taskSource rev-parse HEAD) -cne '5ab7fe74c400097b386662205cd93900695b8a71'){throw 'Pinned Source head changed'}
$taskNode='C:/Program Files/nodejs/node.exe'
if((Get-FileHash -LiteralPath $taskNode).Hash -cne '63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088'){throw 'Pinned Source Node executable changed'}
$taskReferenceControls=@($taskNode,$taskAuditPath,(Join-Path $taskEvidence 'source5ab-observe-20261015.mjs'))+@($taskReferenceSpecs|ForEach-Object {Join-Path $taskEvidence $_.file})+@(
 (Join-Path $taskEvidence 'ai-anthropic25-5ab-source-capture-20261015.mjs'),
 (Join-Path $taskEvidence 'Run-AiAnthropic25Source-20261015.ps1'),
 (Join-Path $taskEvidence 'ai-anthropic25-5ab-source25-first-20261015-output.json'),
 (Join-Path $taskEvidence 'ai-anthropic25-5ab-source25-first-20261015-posthash.json'),
 (Join-Path $taskEvidence 'ai-anthropic16-extended-5ab-source-capture-20261015.mjs'),
 (Join-Path $taskEvidence 'Run-AiAnthropic16ExtendedSource-20261015.ps1'),
 (Join-Path $taskEvidence 'ai-anthropic16-extended-5ab-source16-first-20261015-output.json'),
 (Join-Path $taskEvidence 'ai-anthropic16-extended-5ab-source16-first-20261015-posthash.json'),
 (Join-Path $taskEvidence 'ai-anthropic14-sdk-boundaries-5ab-source-capture-20261015.mjs'),
 (Join-Path $taskEvidence 'Run-AiAnthropic14SdkBoundariesSource-20261015.ps1'),
 (Join-Path $taskEvidence 'Invoke-AiAnthropic14SourceCandidate-1b1ec5c1-20261015.ps1'),
 (Join-Path $taskEvidence 'ai-anthropic14-sdk-boundaries-5ab-source14-first-20261015-output.json'),
 (Join-Path $taskEvidence 'ai-anthropic14-sdk-boundaries-5ab-source14-first-20261015-posthash.json'),
 (Join-Path $taskEvidence 'ai-anthropic14-sdk-boundaries-5ab-source14-first-20261015-candidate-caller-posthash.json')
)
$taskVendor=Vendor-Rows
if($taskVendor.Count -lt 1){throw 'Full candidate vendor inventory missing'}
$taskVendor|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-vendor-before.json") -Encoding utf8NoBOM
$taskControls=@($PSCommandPath,$taskOwner,$taskToolReference)+$taskReferenceControls|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}}
if((Get-FileHash -LiteralPath $taskZig).Hash -cne '086CE9D47BA42F33A514E1A6E04EB1D4A8FA1D75E0868E0213CAAD447C91E864'){throw 'Pinned Zig SHA256 changed'}
if((Get-FileHash -LiteralPath (Join-Path $taskPrivate 'src/extensions/fixtures/ai-anthropic5ab-extended.json')).Hash -cne 'E2FA67CE930C77660DF95A45E8219760B5895C12FAAFE41B3353F36782FCFA34'){throw 'Genuine Source16 expected bytes changed'}
if((Get-FileHash -LiteralPath (Join-Path $taskPrivate 'src/extensions/fixtures/ai-anthropic5ab.json')).Hash -cne '2B189725271DED510340599DEAC4DEC37E7AB7CE22458F35571A2B6434380DBE'){throw 'Genuine Source25 expected bytes changed'}
if((Get-FileHash -LiteralPath (Join-Path $taskPrivate 'src/extensions/fixtures/ai-anthropic5ab-sdk-boundaries.json')).Hash -cne '11DB0369FF96B0CBB0EBFBF69AF7BFE645160C541387B1EE8E0ECC3CDF074A0E'){throw 'Genuine Source14 expected bytes changed'}
$taskBefore|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-source-before.json") -Encoding utf8NoBOM
$taskControls|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-controls-before.json") -Encoding utf8NoBOM
if(@(Tool-Drift $taskTools).Count){throw 'Compiler prehash drift'}
if(@(Tool-Drift $taskControls).Count){throw 'Control prehash drift'}
foreach($taskReference in $taskReferences){if(@(Tool-Drift $taskReference.rows).Count){throw "Reference prehash drift $($taskReference.name)"}}
$taskCompile=$null;$taskRuntime=$null;$taskFailure=$null;$taskAdmitted=$false;$taskMetadataResults=@()
$taskBinariesBefore=@(Get-ChildItem -LiteralPath (Join-Path $taskPrivate '.zig-cache/o') -Filter test.exe -Recurse -File|ForEach-Object FullName)
$taskEnvironment=@{NODE_OPTIONS='';NODE_PATH='';NODE_USE_ENV_PROXY='';HTTP_PROXY='';HTTPS_PROXY='';ALL_PROXY='';NO_PROXY='127.0.0.1,localhost';ANTHROPIC_API_KEY='';ANTHROPIC_AUTH_TOKEN='';ANTHROPIC_BASE_URL='';ANTHROPIC_DEFAULT_HEADERS='';ANTHROPIC_PROFILE='';ANTHROPIC_FEDERATION_RULE_ID='';ANTHROPIC_ORGANIZATION_ID='';ANTHROPIC_IDENTITY_TOKEN_FILE='';ANTHROPIC_WORKSPACE_ID='';ANTHROPIC_SERVICE_ACCOUNT_ID=''}
try {
 $taskAdmitted=Fresh-Admission 'compile'
 if($taskAdmitted){
  & $taskOwner -Name "$taskName-compile" -Executable $taskZig -WorkingDirectory $taskPrivate -Arguments @('build','build-native-ai-claude5ab','build-native-ai-claude5ab-extended','-Doptimize=Debug','-Duse-llvm=true','-j1','--test-timeout','120s','--summary','all') -TimeoutSeconds 1320 -EnvironmentOverrides $taskEnvironment
  $taskCompile=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName-compile.json") -Raw|ConvertFrom-Json
  if($taskCompile.status -ceq 'passed'){
   $taskBetween=Source-Rows
   if(@(Compare-Object ($taskBefore|ForEach-Object{"$($_.path):$($_.sha256)"}) ($taskBetween|ForEach-Object{"$($_.path):$($_.sha256)"})).Count -or @(Tool-Drift $taskTools).Count -or @(Tool-Drift $taskControls).Count){throw 'Frozen pair drift before runtime'}
   foreach($taskReference in $taskReferences){if(@(Tool-Drift $taskReference.rows).Count){throw "Reference drift before runtime $($taskReference.name)"}}
   if(@($taskAbsent|Where-Object {Test-Path -LiteralPath $_}).Count){throw 'Dependency absence drift before runtime'}
   $taskVendorBetween=Vendor-Rows
   if(@(Compare-Object ($taskVendor|ForEach-Object{"$($_.path):$($_.sha256)"}) ($taskVendorBetween|ForEach-Object{"$($_.path):$($_.sha256)"})).Count){throw 'Full vendor drift after compilation'}
   $taskMetadataResults=@(Metadata-Gate)
   $taskMetadataAfter=Source-Rows
   if(@(Compare-Object ($taskBefore|ForEach-Object{"$($_.path):$($_.sha256)"}) ($taskMetadataAfter|ForEach-Object{"$($_.path):$($_.sha256)"})).Count -or @(Tool-Drift $taskTools).Count -or @(Tool-Drift $taskControls).Count){throw 'Frozen full candidate compiler controls drift after metadata'}
   foreach($taskReference in $taskReferences){if(@(Tool-Drift $taskReference.rows).Count){throw "Full reference drift after metadata $($taskReference.name)"}}
   $taskVendorMetadata=Vendor-Rows
   if(@(Compare-Object ($taskVendor|ForEach-Object{"$($_.path):$($_.sha256)"}) ($taskVendorMetadata|ForEach-Object{"$($_.path):$($_.sha256)"})).Count -or @($taskAbsent|Where-Object {Test-Path -LiteralPath $_}).Count){throw 'Full vendor or84absences drift after metadata'}
   if(Fresh-Admission 'runtime'){
    & $taskOwner -Name "$taskName-runtime" -Executable $taskZig -WorkingDirectory $taskPrivate -Arguments @('build','test-native-ai-claude5ab','test-native-ai-claude5ab-extended','-Doptimize=Debug','-Duse-llvm=true','-j1','--test-timeout','120s','--summary','all') -TimeoutSeconds 300 -EnvironmentOverrides $taskEnvironment
    $taskRuntime=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName-runtime.json") -Raw|ConvertFrom-Json
   }
  }
 }
}catch{$taskFailure=$_.Exception.Message}finally{
 $taskAfter=Source-Rows
 $taskSourceDrift=@(Compare-Object ($taskBefore|ForEach-Object{"$($_.path):$($_.sha256)"}) ($taskAfter|ForEach-Object{"$($_.path):$($_.sha256)"}))
 $taskToolDrift=@(Tool-Drift $taskTools)
 $taskControlDrift=@(Tool-Drift $taskControls)
 $taskReferencePost=@($taskReferences|ForEach-Object {$taskChanged=@(Tool-Drift $_.rows);@{name=$_.name;files=$_.rows.Count;drift=$taskChanged.Count;changed=$taskChanged}})
 $taskReferenceDrift=@($taskReferencePost|Where-Object drift -ne 0)
 $taskAbsentDrift=@($taskAbsent|Where-Object {Test-Path -LiteralPath $_})
 $taskSourceHeadMatches=(git -C $taskSource rev-parse HEAD) -ceq '5ab7fe74c400097b386662205cd93900695b8a71'
 $taskVendorAfter=Vendor-Rows
 $taskVendorDrift=@(Compare-Object ($taskVendor|ForEach-Object{"$($_.path):$($_.sha256)"}) ($taskVendorAfter|ForEach-Object{"$($_.path):$($_.sha256)"}))
 [ordered]@{candidate=$taskExpectedHead;source=$taskBefore.Count;source_after=$taskAfter.Count;source_drift=$taskSourceDrift.Count;tools=$taskTools.Count;tool_drift=$taskToolDrift.Count;controls=$taskControls.Count;control_drift=$taskControlDrift.Count;vendor=$taskVendor.Count;vendor_after=$taskVendorAfter.Count;vendor_drift=$taskVendorDrift.Count;references=$taskReferencePost;absences=$taskAbsent.Count;absence_drift=$taskAbsentDrift.Count;source_head_match=$taskSourceHeadMatches;admitted=$taskAdmitted;compile=if($taskCompile){$taskCompile.status}else{'not_run'};runtime=if($taskRuntime){$taskRuntime.status}else{'not_run'};metadata_selected=$taskMetadataResults;failure=$taskFailure;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 8|Tee-Object -FilePath (Join-Path $taskEvidence "$taskName-posthash.json")
}
if($taskSourceDrift.Count -or $taskToolDrift.Count -or $taskControlDrift.Count -or $taskVendorDrift.Count -or $taskReferenceDrift.Count -or $taskAbsentDrift.Count -or !$taskSourceHeadMatches){throw 'Frozen pair terminal posthash mismatch'}
if($taskFailure){throw $taskFailure}
if(!$taskAdmitted){exit 2}
if(!$taskCompile -or $taskCompile.status -cne 'passed' -or !$taskRuntime -or $taskRuntime.status -cne 'passed'){exit 1}





if($taskMetadataResults.Count -ne 2){throw 'Actual5+9 metadata must precede runtime'}
$taskRuntimeLog=[IO.File]::ReadAllText((Join-Path $taskEvidence "$taskName-runtime.stderr.log"))
if($taskRuntimeLog -notmatch '(?m)^Build Summary:.*\b14/14 tests passed' -or $taskRuntimeLog -notmatch 'run test 5 pass \(5 total\)' -or $taskRuntimeLog -notmatch 'run test 9 pass \(9 total\)'){throw 'All actual14 selected tests must execute without skips'}
foreach($taskSelected in $taskMetadataResults){if((Get-FileHash -LiteralPath $taskSelected.metadata.binary).Hash -cne $taskSelected.metadata.binary_sha256){throw 'Actual compiled artifact changed after matching runtime'}}

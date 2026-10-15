param([string]$Attempt='first',[Parameter(Mandatory)][string]$RootLightGrant)
$ErrorActionPreference='Stop'
$taskEvidence='C:/Users/adyba/pi-zig-update-evidence-20261003'
$taskName="file-revision-source4954-$Attempt-20261015"
$taskNode='C:/Program Files/nodejs/node.exe'
$taskSource='C:/Users/adyba/pi-upstream-source-4954d76-20261015'
$taskRuntime='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012'
$taskDriver=Join-Path $taskEvidence 'file-revision-source4954-capture-20261015.mjs'
$taskObserver=Join-Path $taskEvidence 'source4954-observe-20261015.mjs'
$taskAudit=Join-Path $taskEvidence 'source4954-dependency-contract-audit-20261015.json'
$taskJobOwner=Join-Path $taskEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1'
if((Get-FileHash -LiteralPath $taskNode).Hash -cne '63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088'){throw 'Pinned Node changed before syntax check'}
& $taskJobOwner -Name "$taskName-syntax-check" -Executable $taskNode -WorkingDirectory $taskSource -Arguments @('--check',$taskDriver) -TimeoutSeconds 30
$taskSyntax=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName-syntax-check.json") -Raw|ConvertFrom-Json
if($taskSyntax.status -cne 'passed'){throw 'File revision driver syntax check failed before prehash'}
$taskSpecs=@(
 @{name='source';file='source4954-full-manifest-20261015.json';count=1970},
 @{name='dependencies';file='source4954-runtime-manifest-20261015.json';count=31064},
 @{name='node_tools';file='source4954-node-tools-before-20261015.json';count=1774}
)
function Check-Rows($taskRows){
 $taskChanged=[Collections.Generic.List[string]]::new()
 foreach($taskRow in $taskRows){
  if(!(Test-Path -LiteralPath $taskRow.path -PathType Leaf) -or (Get-FileHash -LiteralPath $taskRow.path).Hash -cne $taskRow.sha256){$taskChanged.Add($taskRow.path)}
 }
 return @($taskChanged)
}
$taskPrehashFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
if($taskPrehashFree -lt 2MB){throw '2GiB free memory required before full prehash'} 
$taskFrozen=@()
$taskCandidate='C:/Users/adyba/pi-zig-native-file-revision-20261015'
$taskCandidateHead=(git -c gc.auto=0 -c maintenance.auto=false -c pack.threads=2 -c pack.windowMemory=64m -C $taskCandidate rev-parse HEAD).Trim()
if($taskCandidateHead -cne '1f0008ef475b5325ce15192f6a9a20a1b2e64616' -or @(git -c gc.auto=0 -c maintenance.auto=false -c pack.threads=2 -c pack.windowMemory=64m -C $taskCandidate status --porcelain).Count){throw 'Clean exact file revision candidate required'}
$taskCandidatePaths=@(git -c gc.auto=0 -c maintenance.auto=false -c pack.threads=2 -c pack.windowMemory=64m -C $taskCandidate ls-files|ForEach-Object {Join-Path $taskCandidate $_})
if($taskCandidatePaths.Count -ne 7682){throw 'Exact candidate7682 inventory required'}
$taskCandidateRows=@($taskCandidatePaths|ForEach-Object {@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})
$taskCompilerReference=Join-Path $taskEvidence 'one-shot-native-proof-stage-20261015/pinned-compiler19546-reference.json'
$taskCompilerPacket=Get-Content -LiteralPath $taskCompilerReference -Raw|ConvertFrom-Json
$taskCompilerRows=@($taskCompilerPacket.inputs)
if($taskCompilerRows.Count -ne 19546 -or @(Check-Rows $taskCompilerRows).Count){throw 'Exact pinned compiler19546 digest inventory required'}
$taskCandidateCompilerBefore=Join-Path $taskEvidence "$taskName-candidate-compiler-before.json"
@{candidate_head=$taskCandidateHead;candidate=$taskCandidateRows;compiler=$taskCompilerRows}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $taskCandidateCompilerBefore -Encoding utf8NoBOM
$taskFrozen+=@{name='candidate';manifest=$taskCandidateCompilerBefore;rows=$taskCandidateRows}
$taskFrozen+=@{name='compiler';manifest=$taskCompilerReference;rows=$taskCompilerRows}
foreach($taskSpec in $taskSpecs){
 $taskRows=@(Get-Content -LiteralPath (Join-Path $taskEvidence $taskSpec.file) -Raw|ConvertFrom-Json)
 if($taskRows.Count -ne $taskSpec.count){throw "Full manifest inventory mismatch $($taskSpec.name)"}
 if(@(Check-Rows $taskRows).Count){throw "Reference prehash drift $($taskSpec.name)"}
 $taskFrozen+=@{name=$taskSpec.name;manifest=$taskSpec.file;rows=$taskRows}
}
$taskPreCompilerPaths=@(Get-ChildItem -LiteralPath $taskCompilerPacket.root -Recurse -File|ForEach-Object FullName)
$taskPreSourcePaths=@(rg --files --hidden --no-ignore -g '!.git' -g '!node_modules' $taskSource|ForEach-Object {[IO.Path]::GetFullPath($_)})
$taskExpectedSourcePaths=@(($taskFrozen|Where-Object name -eq 'source').rows|ForEach-Object {[IO.Path]::GetFullPath($_.path)})
if(@(Compare-Object @($taskCompilerRows|ForEach-Object path|Sort-Object) @($taskPreCompilerPaths|Sort-Object)).Count -or @(Compare-Object @($taskExpectedSourcePaths|Sort-Object) @($taskPreSourcePaths|Sort-Object)).Count){throw 'Fresh compiler/Source path inventory mismatch before launch'}
if((git -C $taskSource rev-parse HEAD) -cne '4954d760504c11df9b2cbdc040346107b6a8153d'){throw 'PinnedAe7Source head changed'}
if((Get-FileHash -LiteralPath $taskNode).Hash -cne '63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088'){throw 'Pinned Node changed'}
$taskContract=Get-Content -LiteralPath $taskAudit -Raw|ConvertFrom-Json
if($taskContract.latestHead -cne '4954d760504c11df9b2cbdc040346107b6a8153d' -or $taskContract.installed_metadata_verified -ne 281 -or $taskContract.platform_optional_absent_records -ne 80 -or $taskContract.historical_missing_records_retained -ne 4){throw 'Dependency contract scope changed'}
$taskAbsent=@($taskContract.pins|Where-Object status -eq 'platform_optional_absent'|ForEach-Object {Join-Path $taskRuntime $_.path})+@($taskContract.mismatches|ForEach-Object {Join-Path $taskRuntime $_.path})
if($taskAbsent.Count -ne 84 -or @($taskAbsent|Where-Object {Test-Path -LiteralPath $_}).Count){throw 'Historical absent dependency state changed'}
$taskPreparation=Join-Path $taskEvidence 'source4954-reference-controls-20261015.json'
$taskReadiness=Join-Path $taskEvidence 'source4954-preparation-readiness-20261015.json'
$taskPreparationRows=@(Get-Content -LiteralPath $taskPreparation -Raw|ConvertFrom-Json)
if($taskPreparationRows.Count -ne 5 -or @(Check-Rows $taskPreparationRows).Count){throw 'Exact five4954 reference controls required'}
$taskInput='C:/Users/adyba/pi-zig-native-file-revision-20261015/src/extensions/fixtures/file-revision-source-4954.input.txt'
$taskNativePaths=@('src/extensions/native_file_revision.zig','src/extensions/native_file_stat.zig','src/native_file_revision_test.zig')|ForEach-Object {Join-Path 'C:/Users/adyba/pi-zig-native-file-revision-20261015' $_}
$taskExtraPaths=@($taskInput,$taskDriver,$taskObserver,$taskAudit,$taskJobOwner,$PSCommandPath,$taskPreparation,$taskReadiness,$taskCompilerReference,$taskCandidateCompilerBefore)+@($taskNativePaths)+@($taskSpecs|ForEach-Object {Join-Path $taskEvidence $_.file})
$taskExtra=@($taskExtraPaths|ForEach-Object {@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})
$taskControlManifest=Join-Path $taskEvidence "$taskName-extra-before.json"
$taskExtra|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $taskControlManifest -Encoding utf8NoBOM
$taskControlManifestHash=(Get-FileHash -LiteralPath $taskControlManifest).Hash
$taskFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
if($taskFree -lt 2MB){@{status='admission_denied';free_kib=$taskFree;required_kib=2MB;node_launched=$false}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-admission.json");exit 2}
@{status='admitted';free_kib=$taskFree;required_kib=2MB;heap_mb=256;coordinated_with=$RootLightGrant;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-admission.json")
$taskOutput=Join-Path $taskEvidence "$taskName-output.json"
& $taskJobOwner -Name $taskName -Executable $taskNode -WorkingDirectory $taskSource -Arguments @('--max-old-space-size=256','--expose-gc','--conditions=source','--experimental-transform-types','--import',([Uri]$taskObserver).AbsoluteUri,$taskDriver,$taskOutput) -TimeoutSeconds 300 -EnvironmentOverrides @{NODE_OPTIONS='';NODE_PATH='';PI_SOURCE_ORACLE_CONTROL_MANIFEST=$taskControlManifest;NODE_USE_ENV_PROXY='';HTTP_PROXY='';HTTPS_PROXY='';ALL_PROXY='';NO_PROXY='127.0.0.1,localhost';OPENAI_API_KEY='';OPENAI_ORG_ID='';OPENAI_PROJECT_ID='';OPENAI_BASE_URL='';KIMI_API_KEY='';PI_PACKAGE_DIR='C:/Users/adyba/pi-upstream-source-4954d76-20261015/packages/coding-agent'}
$taskPost=@()
foreach($taskItem in $taskFrozen){$taskChanged=@(Check-Rows $taskItem.rows);$taskPost+=@{name=$taskItem.name;files=$taskItem.rows.Count;drift=$taskChanged.Count;changed=$taskChanged}}
$taskExtraChanged=@(Check-Rows $taskExtra)
$taskAbsentChanged=@($taskAbsent|Where-Object {Test-Path -LiteralPath $_})
$taskControlManifestChanged=(Get-FileHash -LiteralPath $taskControlManifest).Hash -cne $taskControlManifestHash
@{manifests=$taskPost;extra_control_drift=$taskExtraChanged;control_manifest_drift=$taskControlManifestChanged;absent_dependency_drift=$taskAbsentChanged;historical_absence_records=$taskAbsent.Count;driver_sha256=(Get-FileHash -LiteralPath $taskDriver).Hash;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-posthash.json")
if(@($taskPost|Where-Object drift -ne 0).Count -or $taskExtraChanged.Count -or $taskAbsentChanged.Count -or $taskControlManifestChanged){throw 'Reference posthash drift'}
$taskCandidateCurrent=@(git -c gc.auto=0 -c maintenance.auto=false -c pack.threads=2 -c pack.windowMemory=64m -C $taskCandidate ls-files|ForEach-Object {Join-Path $taskCandidate $_})
$taskCandidateInventoryDrift=@(Compare-Object @($taskCandidateRows|ForEach-Object path|Sort-Object) @($taskCandidateCurrent|Sort-Object))
$taskCompilerCurrent=@(Get-ChildItem -LiteralPath $taskCompilerPacket.root -Recurse -File|ForEach-Object FullName)
$taskCompilerInventoryDrift=@(Compare-Object @($taskCompilerRows|ForEach-Object path|Sort-Object) @($taskCompilerCurrent|Sort-Object))
$taskSourceCurrent=@(rg --files --hidden --no-ignore -g '!.git' -g '!node_modules' $taskSource|ForEach-Object {[IO.Path]::GetFullPath($_)})
$taskSourceExpected=@(($taskFrozen|Where-Object name -eq 'source').rows|ForEach-Object {[IO.Path]::GetFullPath($_.path)})
$taskSourceInventoryDrift=@(Compare-Object @($taskSourceExpected|Sort-Object) @($taskSourceCurrent|Sort-Object))
@{candidate_head=$taskCandidateHead;candidate_files=$taskCandidateRows.Count;candidate_inventory_drift=$taskCandidateInventoryDrift;compiler_files=$taskCompilerRows.Count;compiler_inventory_drift=$taskCompilerInventoryDrift;source_files=$taskSourceExpected.Count;source_inventory_drift=$taskSourceInventoryDrift}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-inventory-post.json") -Encoding utf8NoBOM
if($taskCandidateInventoryDrift.Count -or $taskCompilerInventoryDrift.Count -or $taskSourceInventoryDrift.Count){throw 'Candidate/compiler/Source inventory drift'}
$taskOwner=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName.json") -Raw|ConvertFrom-Json
if($taskOwner.status -cne 'passed'){throw "Source oracle terminal $($taskOwner.status)"}
$taskResult=Get-Content -LiteralPath $taskOutput -Raw|ConvertFrom-Json
if($taskResult.count -notin 30,31 -or @($taskResult.rows).Count -ne $taskResult.count -or $taskResult.sourceHead -cne '4954d760504c11df9b2cbdc040346107b6a8153d' -or $taskResult.runtime -cne 'v24.14.0'){throw 'Original4954 file revision output missing'}
Write-Output ('ORIGINAL_4954_FILE_REVISION_CASES='+$taskResult.rows.Count)
$taskExpected='C:/Users/adyba/pi-zig-native-file-revision-20261015/src/extensions/fixtures/file-revision-source-4954.json'
if(Test-Path -LiteralPath $taskExpected){throw 'Refuse expected replay'}
Copy-Item -LiteralPath $taskOutput -Destination $taskExpected
@{source_cases=$taskResult.count;expected_sha256=(Get-FileHash -LiteralPath $taskExpected).Hash;expected_published_after_terminal_and_full_posthash=$true;full_pi_qualified=$false}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-validation.json") -Encoding utf8NoBOM







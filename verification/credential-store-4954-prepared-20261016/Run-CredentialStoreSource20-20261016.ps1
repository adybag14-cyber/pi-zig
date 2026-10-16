param([string]$Attempt='first',[Parameter(Mandatory)][string]$CandidateHead)
$ErrorActionPreference='Stop'
$taskEvidence=$PSScriptRoot
$taskName="credential-store-4954-source20-$Attempt-20261016"
$taskNode='C:/Program Files/nodejs/node.exe'
$taskSource='C:/Users/adyba/pi-upstream-source-4954d76-20261015'
$taskRuntime='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012'
$taskNative='C:/Users/adyba/pi-zig-native-models-auth-methods-20261016'
$taskCompilerRoot='C:/Users/adyba/pi-zig-toolchain-20261003/zig-x86_64-windows-0.16.0'
$taskDriver=Join-Path $taskEvidence 'credential-store-4954-capture-20261016.mjs'
$taskHarness=Join-Path $taskEvidence 'credential-store-4954-cases-20261016.mjs'
$taskObserver=Join-Path $taskEvidence 'source4954-observe-20261015.mjs'
$taskAudit=Join-Path $taskEvidence 'source4954-dependency-contract-audit-20261015.json'
$taskJobOwner=Join-Path $taskEvidence 'Invoke-OwnedCredentialStoreSource-20261016.ps1'
$taskSealedControls=Join-Path $taskNative 'verification/credential-store-4954-prepared-20261016'
if((git -c gc.auto=0 -c maintenance.auto=false -C $taskNative rev-parse HEAD) -cne $CandidateHead -or @(git -c gc.auto=0 -c maintenance.auto=false -C $taskNative status --porcelain).Count){throw 'Exact sealed clean candidate head required'}
foreach($taskControlName in @('Run-CredentialStoreSource20-20261016.ps1','Invoke-OwnedCredentialStoreSource-20261016.ps1','credential-store-4954-capture-20261016.mjs','credential-store-4954-owner-controls-20261016.json','credential-store-4954-cases-20261016.mjs')){
 if((Get-FileHash -LiteralPath (Join-Path $taskEvidence $taskControlName)).Hash -cne (Get-FileHash -LiteralPath (Join-Path $taskSealedControls $taskControlName)).Hash){throw "Sealed owner control differs before any Node child: $taskControlName"}
}
$taskFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
if($taskFree -lt 2MB){throw 'Fresh2GiB admission required before Source syntax checks'}
if((Get-FileHash -LiteralPath $taskNode).Hash -cne '63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088'){throw 'Pinned Node changed before syntax check'}
foreach($taskSyntaxFile in @($taskDriver,$taskHarness)){
 $taskSyntaxName="$taskName-syntax-check-$([IO.Path]::GetFileNameWithoutExtension($taskSyntaxFile))"
 & $taskJobOwner -Name $taskSyntaxName -Executable $taskNode -WorkingDirectory $taskSource -Arguments @('--max-old-space-size=256','--check',$taskSyntaxFile) -TimeoutSeconds 30 -SettleSeconds 10 -EnvironmentOverrides @{NODE_OPTIONS='';NODE_PATH=''}
 $taskSyntax=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskSyntaxName.json") -Raw|ConvertFrom-Json
 if($taskSyntax.status -cne 'passed'){throw 'Source20 syntax check failed before prehash'}
}
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
$taskCompilerPaths=@(Scoped-Paths $taskCompilerRoot)
if($taskCompilerPaths.Count -ne 19546){throw 'Exact pinned compiler19546 inventory required'}
$taskCompiler=@($taskCompilerPaths|ForEach-Object {@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})
$taskCompilerManifest=Join-Path $taskEvidence "$taskName-compiler-before.json"
$taskCompiler|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $taskCompilerManifest -Encoding utf8NoBOM
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
 if($taskPathDrift.Count){@{status='preparation_failed';inventory=$taskInventory.name;drift=$taskPathDrift;source_child_launched=$false;expected_absent=!(Test-Path -LiteralPath (Join-Path $taskNative 'src/extensions/fixtures/credential-store-4954-source.json'))}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-preparation-failure.json") -Encoding utf8NoBOM;throw "Full path inventory differs before Source: $($taskInventory.name)"}
}
$taskInventoryManifest=Join-Path $taskEvidence "$taskName-inventories-before.json"
$taskInventories|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $taskInventoryManifest -Encoding utf8NoBOM
if((git -c gc.auto=0 -c maintenance.auto=false -C $taskSource rev-parse HEAD) -cne '4954d760504c11df9b2cbdc040346107b6a8153d'){throw 'Pinned4954Source head changed'}
if((Get-FileHash -LiteralPath $taskNode).Hash -cne '63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088'){throw 'Pinned Node changed'}
$taskContract=Get-Content -LiteralPath $taskAudit -Raw|ConvertFrom-Json
if($taskContract.latestHead -cne '4954d760504c11df9b2cbdc040346107b6a8153d' -or $taskContract.installed_metadata_verified -ne 281 -or $taskContract.platform_optional_absent_records -ne 80 -or $taskContract.historical_missing_records_retained -ne 4){throw 'Dependency contract scope changed'}
$taskAbsent=@($taskContract.pins|Where-Object status -eq 'platform_optional_absent'|ForEach-Object {Join-Path $taskRuntime $_.path})+@($taskContract.mismatches|ForEach-Object {Join-Path $taskRuntime $_.path})
if($taskAbsent.Count -ne 84 -or @($taskAbsent|Where-Object {Test-Path -LiteralPath $_}).Count){throw 'Historical absent dependency state changed'}
$taskPreparation=Join-Path $taskEvidence 'source4954-reference-controls-20261015.json'
$taskReadiness=Join-Path $taskEvidence 'source4954-preparation-readiness-20261015.json'
if((Get-FileHash -LiteralPath $taskPreparation).Hash -cne 'A11A87511B15B6AEDF4FFC94EA541DE986FCCC4334BA9A47C2BED3ED0A5094D0' -or (Get-FileHash -LiteralPath $taskReadiness).Hash -cne '0EDB3EA87CF7AE1FF8B51A02A1D3698DC610BA23F66257D60AA5C788557E82D7'){throw 'Pinned4954 preparation controls changed'}
$taskPreparationRows=@(Get-Content -LiteralPath $taskPreparation -Raw|ConvertFrom-Json)
if($taskPreparationRows.Count -ne 5 -or @(Check-Rows $taskPreparationRows).Count){throw 'Exact five4954 preparation controls required'}
$taskInput=Join-Path $taskNative 'src/extensions/fixtures/credential-store-4954-cases.input.txt'
if((Get-FileHash -LiteralPath $taskInput).Hash -cne (Get-FileHash -LiteralPath $taskHarness).Hash){throw 'Source/native harness bytes differ'}
$taskExpected=Join-Path $taskNative 'src/extensions/fixtures/credential-store-4954-source.json'
if(Test-Path -LiteralPath $taskExpected){throw 'Refuse expected replay'}
$taskExtraPaths=@($taskInput,$taskHarness,$taskDriver,$taskObserver,$taskAudit,$taskJobOwner,$PSCommandPath,$taskPreparation,$taskReadiness,
 (Join-Path $taskEvidence 'credential-store-4954-owner-controls-20261016.json'),
 (Join-Path $taskNative 'src/extensions/native_credentials_store.zig'),
 (Join-Path $taskNative 'src/extensions/native_async_body.zig'),
 $taskCandidateManifest,$taskInventoryManifest,$taskCompilerManifest)+@($taskSpecs|ForEach-Object {Join-Path $taskEvidence $_.file})
foreach($taskControlName in @('Run-CredentialStoreSource20-20261016.ps1','Invoke-OwnedCredentialStoreSource-20261016.ps1','credential-store-4954-capture-20261016.mjs','credential-store-4954-owner-controls-20261016.json','credential-store-4954-cases-20261016.mjs')){
 if((Get-FileHash -LiteralPath (Join-Path $taskEvidence $taskControlName)).Hash -cne (Get-FileHash -LiteralPath (Join-Path $taskSealedControls $taskControlName)).Hash){throw "Sealed owner control differs: $taskControlName"}
}
$taskExtra=@($taskExtraPaths|ForEach-Object {@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})
$taskControlManifest=Join-Path $taskEvidence "$taskName-extra-before.json"
$taskExtra|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $taskControlManifest -Encoding utf8NoBOM
$taskControlManifestHash=(Get-FileHash -LiteralPath $taskControlManifest).Hash
$taskFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
if($taskFree -lt 2MB){@{status='admission_denied';free_kib=$taskFree;required_kib=2MB;node_launched=$false}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-admission.json");exit 2}
@{status='admitted';free_kib=$taskFree;required_kib=2MB;heap_mb=256;coordinated_with='Root explicit CredentialStore20 LIGHT6 granted';native_head=$CandidateHead;candidate_files=$taskCandidate.Count;compiler_files=$taskCompiler.Count;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-admission.json")
$taskOutput=Join-Path $taskEvidence "$taskName-output.json"
$taskOwnerFailure=$null
try{& $taskJobOwner -Name $taskName -Executable $taskNode -WorkingDirectory $taskSource -Arguments @('--max-old-space-size=256','--expose-gc','--conditions=source','--experimental-transform-types','--import',([Uri]$taskObserver).AbsoluteUri,$taskDriver,$taskOutput) -TimeoutSeconds 300 -SettleSeconds 10 -EnvironmentOverrides @{NODE_OPTIONS='';NODE_PATH='';PI_SOURCE_ORACLE_CONTROL_MANIFEST=$taskControlManifest;NODE_USE_ENV_PROXY='';HTTP_PROXY='';HTTPS_PROXY='';ALL_PROXY='';NO_PROXY='127.0.0.1,localhost';OPENAI_API_KEY='';OPENAI_ORG_ID='';OPENAI_PROJECT_ID='';OPENAI_BASE_URL='';KIMI_API_KEY='';PI_PACKAGE_DIR=''}}catch{$taskOwnerFailure=$_.Exception.Message}
$taskPost=@()
foreach($taskItem in $taskFrozen){$taskChanged=@(Check-Rows $taskItem.rows);$taskPost+=@{name=$taskItem.name;files=$taskItem.rows.Count;drift=$taskChanged.Count;changed=$taskChanged}}
$taskExtraChanged=@(Check-Rows $taskExtra)
$taskAbsentChanged=@($taskAbsent|Where-Object {Test-Path -LiteralPath $_})
$taskControlManifestChanged=(Get-FileHash -LiteralPath $taskControlManifest).Hash -cne $taskControlManifestHash
$taskCandidateChanged=@(Check-Rows $taskCandidate)
$taskCandidateInventoryChanged=@(Compare-Object $taskCandidatePaths @(Candidate-Paths))
$taskCompilerChanged=@(Check-Rows $taskCompiler)
$taskCompilerInventoryChanged=@(Compare-Object $taskCompilerPaths @(Scoped-Paths $taskCompilerRoot))
$taskCurrentInventories=@(@{name='source';paths=@(Scoped-Paths $taskSource)},@{name='dependencies';paths=@(Scoped-Paths $taskRuntime)},@{name='node_tools';paths=@([IO.Path]::GetFullPath($taskNode))+@(Scoped-Paths 'C:/Program Files/nodejs/node_modules/npm')})
$taskInventoryPost=@(foreach($taskInventory in $taskInventories){$taskCurrent=($taskCurrentInventories|Where-Object name -ceq $taskInventory.name).paths;@{name=$taskInventory.name;count=$taskInventory.paths.Count;drift=@(Compare-Object @($taskInventory.paths|Sort-Object) @($taskCurrent|Sort-Object))}})
$taskHeadChanged=(git -c gc.auto=0 -c maintenance.auto=false -C $taskNative rev-parse HEAD) -cne $CandidateHead
$taskSourceHeadChanged=(git -c gc.auto=0 -c maintenance.auto=false -C $taskSource rev-parse HEAD) -cne '4954d760504c11df9b2cbdc040346107b6a8153d'
$taskExpectedAbsent=!(Test-Path -LiteralPath $taskExpected)
@{manifests=$taskPost;candidate_files=$taskCandidate.Count;candidate_drift=$taskCandidateChanged;candidate_inventory_drift=$taskCandidateInventoryChanged;compiler_files=$taskCompiler.Count;compiler_drift=$taskCompilerChanged;compiler_inventory_drift=$taskCompilerInventoryChanged;path_inventories=$taskInventoryPost;candidate_head_drift=$taskHeadChanged;source_head_drift=$taskSourceHeadChanged;expected_still_absent=$taskExpectedAbsent;extra_control_drift=$taskExtraChanged;control_manifest_drift=$taskControlManifestChanged;absent_dependency_drift=$taskAbsentChanged;historical_absence_records=$taskAbsent.Count;driver_sha256=(Get-FileHash -LiteralPath $taskDriver).Hash;owner_failure=$taskOwnerFailure;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-posthash.json")
if(@($taskPost|Where-Object drift -ne 0).Count -or $taskExtraChanged.Count -or $taskAbsentChanged.Count -or $taskControlManifestChanged -or $taskCandidateChanged.Count -or $taskCandidateInventoryChanged.Count -or $taskCompilerChanged.Count -or $taskCompilerInventoryChanged.Count -or @($taskInventoryPost|Where-Object {$_.drift.Count}).Count -or $taskHeadChanged -or $taskSourceHeadChanged -or !$taskExpectedAbsent){throw 'Reference or full candidate/compiler posthash drift'}
if($taskOwnerFailure){throw $taskOwnerFailure}
$taskOwner=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName.json") -Raw|ConvertFrom-Json
if($taskOwner.status -cne 'passed' -or !$taskOwner.independent_pid_absent -or !$taskOwner.terminal_kernel_handle){throw "Source oracle terminal/absence $($taskOwner.status)"}
$taskResult=Get-Content -LiteralPath $taskOutput -Raw|ConvertFrom-Json
if($taskResult.count -ne 20 -or @($taskResult.rows).Count -ne 20 -or @($taskResult.caseIds).Count -ne 20 -or $taskResult.sourceHead -cne '4954d760504c11df9b2cbdc040346107b6a8153d' -or $taskResult.runtime -cne 'v24.14.0'){throw 'Original4954 Source20 output missing'}
if(@($taskResult.rawErrors).Count -lt 5 -or $taskResult.network -ne $false){throw 'Actual CredentialStore raw errors/network scope missing'}
for($taskCase=0;$taskCase -lt 20;$taskCase++){if($taskResult.rows[$taskCase].id -cne $taskResult.caseIds[$taskCase]){throw 'Source20 strict ordered inventory drift'}}
$taskUnexpected=@($taskResult.rows|Where-Object {$_.ok -ne $true})
if($taskUnexpected.Count){throw 'Unexpected genuine Source20 control failures'}
if(Test-Path -LiteralPath $taskExpected){throw 'Refuse expected replay after Source'}
$taskResult.rows|ConvertTo-Json -Depth 100|Set-Content -LiteralPath $taskExpected -Encoding utf8NoBOM
@{source_cases=20;expected_sha256=(Get-FileHash -LiteralPath $taskExpected).Hash;expected_published_after_terminal_and_full_posthash=$true;native_qualified=$false;full_pi_qualified=$false}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-validation.json") -Encoding utf8NoBOM
Write-Output ('ORIGINAL_4954_CREDENTIAL_STORE_CASES='+$taskResult.rows.Count)



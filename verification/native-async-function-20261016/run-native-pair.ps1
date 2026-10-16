param(
 [Parameter(Mandatory)][string]$ExpectedHead,
 [Parameter(Mandatory)][string]$OwnerPath,
 [Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$ApprovedOwnerSHA256,
 [Parameter(Mandatory)][string]$RootExecutionGrant,
 [string]$Attempt='first',
 [ValidateSet('Debug','ReleaseSafe')][string]$Optimize='Debug',
 [switch]$RevisedSerial12GiB
)
$ErrorActionPreference='Stop'
$PSNativeCommandUseErrorActionPreference=$true
$taskRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$taskEvidence='C:\Users\adyba\pi-zig-update-evidence-20261003'
$taskName="native-async-function-qualification-$Optimize-$Attempt-20261016"
$taskBase=Join-Path $taskEvidence $taskName
$taskZig='C:\Users\adyba\pi-zig-toolchain-20261003\zig-x86_64-windows-0.16.0\zig.exe'
$taskNodeRoot='C:\Program Files\nodejs'
$taskCompilerRoot=Split-Path -Parent $taskZig
$taskNodeManifest=Join-Path $taskEvidence 'source4954-node-tools-before-20261015.json'
$taskCompilerManifest=Join-Path $taskEvidence 'auth-storage-production-4954-source47-first-20261015-compiler-before.json'
$taskHelper=Join-Path $taskRoot 'tools\ci\native_qualification_ci.ps1'
$taskExpectedNamesPath=Join-Path $PSScriptRoot 'expected-tests25.json'
$taskAsyncNamesPath=Join-Path $PSScriptRoot 'expected-async-tests10.json'
$taskAuthorityPinsPath=Join-Path $PSScriptRoot 'source42-authority-pins.json'
$taskPublishedHead='8f97c86ec8aeb7aa37f1de1b9743505fcedb470e'
if(!$IsWindows -or $Attempt -notmatch '^[a-zA-Z0-9_-]+$' -or $RootExecutionGrant.Trim().Length -lt 8){throw 'Explicit Root grant and valid Windows attempt required; preparation is not execution authorization'}
if($RevisedSerial12GiB -and $RootExecutionGrant -notmatch '12GiB'){throw 'Revised12GiB policy requires explicit Root12GiB release in the grant identifier'}
if($ApprovedOwnerSHA256 -in @('9B5A40C1399D6685362DB73AD2086070401C79EB1158BAAC9AD75E144601E4FD','7ADAED73A8FD24E6A7A39175EBD9195BA922B7C14CAF5B565CB8A3D62780F122')){throw 'Historical Body owners remain held after monitor failure; corrected independently reviewed owner required'}
$taskOwner=[IO.Path]::GetFullPath($OwnerPath)
if((Get-FileHash -LiteralPath $taskOwner).Hash -ine $ApprovedOwnerSHA256){throw 'Reviewed owner hash mismatch'}
if(Test-Path -LiteralPath "$taskBase-before.json"){throw 'Refuse native attempt receipt replay'}
if((git -C $taskRoot rev-parse HEAD) -cne $ExpectedHead -or (git -C $taskRoot status --porcelain)){throw 'Exact clean qualification candidate required'}
git -C $taskRoot merge-base --is-ancestor $taskPublishedHead $ExpectedHead
if((Get-FileHash -LiteralPath (Join-Path $taskRoot 'vendor\quickjs\quickjs.c')).Hash -cne '33DFB18C9A930D3967A089DF0B28B65AF88B7665B7ADD725AED30FCB8F046FD2' -or (Get-FileHash -LiteralPath (Join-Path $taskRoot 'vendor\quickjs\quickjs.h')).Hash -cne 'E3189DA8F918993FB567D07DF32E91CECD12C6666D9E9B1D68A6C65A15CEC37E'){throw 'Root approved exact C/H bytes changed'}
. $taskHelper
function Save-Json($path,$value){[IO.File]::WriteAllText($path,($value|ConvertTo-Json -Depth 16).Replace("`r`n","`n")+"`n",[Text.UTF8Encoding]::new($false))}
function File-Rows($paths){@(foreach($path in $paths){[ordered]@{path=[IO.Path]::GetFullPath($path);sha256=(Get-FileHash -LiteralPath $path).Hash}})}
function Check-Rows($rows){@(foreach($row in $rows){if(!(Test-Path -LiteralPath $row.path -PathType Leaf) -or (Get-FileHash -LiteralPath $row.path).Hash -cne $row.sha256){$row.path}})}
function Admit($phase){
 $taskFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory*1024
 $taskNative=@(Get-CimInstance Win32_Process -Filter "Name='zig.exe' OR Name='build.exe' OR Name='test.exe'"|Where-Object {$_.Name -ceq 'zig.exe' -or $_.ExecutablePath -like 'C:\Users\adyba\pi-zig*\*'})
 $taskMinimum=if($RevisedSerial12GiB){12GB}else{16GB}
 $taskRecord=[ordered]@{phase=$phase;minimum_available_bytes=$taskMinimum;available_bytes=$taskFree;zero_other_native_required=$true;other_native=@($taskNative|Select-Object ProcessId,ParentProcessId,ExecutablePath,CommandLine,CreationDate);root_execution_grant=$RootExecutionGrant;revised_policy_explicitly_released=[bool]$RevisedSerial12GiB;jobs=1;owner_sha256=$ApprovedOwnerSHA256;admitted=($taskFree -ge $taskMinimum -and $taskNative.Count -eq 0);utc=[DateTimeOffset]::UtcNow.ToString('o')}
 Save-Json "$taskBase-$phase-admission.json" $taskRecord
 if(!$taskRecord.admitted){throw "Fresh $phase resource admission denied before native launch"}
}
function Source-Authority {
 $taskInput=Join-Path $taskRoot 'src\extensions\fixtures\async-function-body-node24.input.txt'
 $taskExpected=Join-Path $taskRoot 'src\extensions\fixtures\async-function-body-node24.json'
 if((Get-FileHash -LiteralPath $taskInput).Hash -cne '5776BF2FA3CD180CD299DB2295875CADE31A2D3FC6A0403A8BD1B171AA7ACFB2' -or (Get-FileHash -LiteralPath $taskExpected).Hash -cne '52DD975CA6C7CCE1D9BF8BB13B763122862B7849CFAACFAED8906038C3AF9653'){throw 'Immutable Source42 caller or expected bytes changed'}
 $taskData=Get-Content -LiteralPath $taskExpected -Raw|ConvertFrom-Json
 if($taskData.runtime -cne 'v24.14.0' -or $taskData.count -ne 42 -or @($taskData.rows).Count -ne 42 -or @($taskData.rows.name|Sort-Object -Unique).Count -ne 42){throw 'Exact genuine Source42 identity required'}
 foreach($taskAttempt in @('review1','review2')){
  $taskPrefix=Join-Path $taskEvidence "async-function-body-node24-source42-$taskAttempt-20261016"
  $taskCapture=Get-Content -LiteralPath "$taskPrefix-capture.json" -Raw|ConvertFrom-Json
  $taskPost=Get-Content -LiteralPath "$taskPrefix-posthash.json" -Raw|ConvertFrom-Json
  if($taskCapture.status -cne 'passed' -or $taskCapture.exit_code -ne 0 -or !$taskCapture.handle_has_exited -or !$taskCapture.original_identity_absent){throw 'Source42 owned terminal evidence changed'}
  if($taskPost.native_executed -ne $false -or $taskPost.run_failure -or $taskPost.control_manifest_drift -or $taskPost.head_drift -or @($taskPost.candidate_drift).Count -or @($taskPost.candidate_inventory_drift).Count -or @($taskPost.node_drift).Count -or @($taskPost.compiler_drift).Count -or @($taskPost.control_drift).Count){throw 'Source42 posthash authority changed'}
  if((Get-FileHash -LiteralPath "$taskPrefix-output.json").Hash -cne (Get-FileHash -LiteralPath $taskExpected).Hash){throw 'Genuine Source output differs from expected bytes'}
 }
 return @{cases=42;runtime='v24.14.0';captures=2;native_proposal_substituted=$false;drift=0}
}
$taskAuthorityPaths=@((Join-Path $taskRoot 'src\extensions\fixtures\async-function-body-node24.input.txt'),(Join-Path $taskRoot 'src\extensions\fixtures\async-function-body-node24.json'),(Join-Path $taskEvidence 'async-function-body-node24-source42-review1-20261016-original-input-byte-exact.txt'),(Join-Path $taskEvidence 'native-async-function-reviewed-final-c-h-20261016.patch'),(Join-Path $taskEvidence 'native-async-function-source42-8f97c86e-public-readback-20261016.json'))
foreach($taskAttempt in @('review1','review2')){foreach($taskSuffix in @('output.json','capture.json','posthash.json','validation.json','controls-before.json','candidate-before.json','before.json','modules.jsonl')){$taskAuthorityPaths+=Join-Path $taskEvidence "async-function-body-node24-source42-$taskAttempt-20261016-$taskSuffix"}}
$taskControls=File-Rows @($PSCommandPath,$taskOwner,$taskHelper,$taskExpectedNamesPath,$taskAsyncNamesPath,$taskAuthorityPinsPath,$taskNodeManifest,$taskCompilerManifest)
$taskAuthorities=@(Get-Content -LiteralPath $taskAuthorityPinsPath -Raw|ConvertFrom-Json)
if(@(Compare-Object (@($taskAuthorityPaths|ForEach-Object {[IO.Path]::GetFullPath($_)})|Sort-Object) (@($taskAuthorities.path)|Sort-Object)).Count -or @(Check-Rows $taskAuthorities).Count){throw 'Previously sealed exact Source42 authority file paths or hashes changed'}
$taskNodePins=@(Get-Content -LiteralPath $taskNodeManifest -Raw|ConvertFrom-Json)
$taskCompilerPins=@(Get-Content -LiteralPath $taskCompilerManifest -Raw|ConvertFrom-Json)
if($taskNodePins.Count -ne 1774 -or $taskCompilerPins.Count -ne 19546 -or @(Check-Rows $taskNodePins).Count -or @(Check-Rows $taskCompilerPins).Count){throw 'Full pinned Node/compiler inventories changed'}
$taskExpectedNames=@(Get-Content -LiteralPath $taskExpectedNamesPath -Raw|ConvertFrom-Json)
$taskAsyncNames=@(Get-Content -LiteralPath $taskAsyncNamesPath -Raw|ConvertFrom-Json)
if($taskExpectedNames.Count -ne 25 -or $taskAsyncNames.Count -ne 10 -or @($taskAsyncNames|Where-Object {$_ -notin $taskExpectedNames}).Count){throw 'Exact25 cohort and10 async metadata names required'}
$taskScopes=@(
 @{name='candidate';inventory=(Get-CiInventory $taskRoot tree @('.git','.zig-cache','zig-out'))},
 @{name='vendor';inventory=(Get-CiInventory (Join-Path $taskRoot 'vendor') tree)},
 @{name='compiler';inventory=(Get-CiInventory $taskCompilerRoot tree)},
 @{name='node';inventory=(Get-CiInventory $taskNodeRoot tree)}
)
if($taskScopes[1].inventory.rows.Count -ne 1316 -or $taskScopes[2].inventory.rows.Count -ne 19546 -or $taskScopes[3].inventory.rows.Count -ne 1838){throw 'Complete vendor/compiler/Node path inventory count changed'}
foreach($taskScope in $taskScopes){Save-Json "$taskBase-$($taskScope.name)-frozen.json" $taskScope.inventory}
Save-Json "$taskBase-controls-frozen.json" $taskControls
Save-Json "$taskBase-authorities-frozen.json" $taskAuthorities
$taskFrozenFiles=File-Rows @(@($taskScopes|ForEach-Object {"$taskBase-$($_.name)-frozen.json"})+@("$taskBase-controls-frozen.json","$taskBase-authorities-frozen.json"))
$taskArtifacts=@()
function Verify-Frozen($phase){
 $taskErrors=[Collections.Generic.List[string]]::new()
 foreach($taskScope in $taskScopes){try{Assert-CiInventory $taskScope.inventory "$taskBase-$phase-$($taskScope.name).json"}catch{$taskErrors.Add("$($taskScope.name): $($_.Exception.Message)")}}
 $taskControlDrift=@(Check-Rows $taskControls);$taskAuthorityDrift=@(Check-Rows $taskAuthorities);$taskFrozenDrift=@(Check-Rows $taskFrozenFiles);$taskArtifactDrift=@(Check-Rows $taskArtifacts)
 $taskAuthority=$null
 try{$taskAuthority=Source-Authority}catch{$taskErrors.Add($_.Exception.Message)}
 if((git -C $taskRoot rev-parse HEAD) -cne $ExpectedHead -or (git -C $taskRoot status --porcelain)){$taskErrors.Add('Candidate head or tracked state drift')}
 Save-Json "$taskBase-$phase.json" @{candidate_head=$ExpectedHead;inventory_errors=@($taskErrors);control_drift=$taskControlDrift;authority_drift=$taskAuthorityDrift;frozen_registry_drift=$taskFrozenDrift;artifact_drift=$taskArtifactDrift;source_authority=$taskAuthority;candidate_files=$taskScopes[0].inventory.rows.Count;vendor_files=1316;compiler_files=19546;node_pinned_executable_npm_files=1774;node_complete_directory_files=1838;utc=[DateTimeOffset]::UtcNow.ToString('o')}
 if($taskErrors.Count -or $taskControlDrift.Count -or $taskAuthorityDrift.Count -or $taskFrozenDrift.Count -or $taskArtifactDrift.Count){throw "Full $phase frozen qualification failed"}
}
Verify-Frozen 'before'
$taskBuild=$null;$taskRuntime=$null;$taskMetadata=$null;$taskFailure=$null;$taskPostFailure=$null
try{
 Admit 'compile'
 & $taskOwner -Executable $taskZig -WorkingDirectory $taskRoot -Arguments @('build','build-native-async-function-qualification',"-Doptimize=$Optimize",'-Duse-llvm=true','-j1','--test-timeout','120s','--summary','all') -ReceiptBase "$taskBase-compile" -TimeoutSeconds 1320
 $taskBuild=Get-Content -LiteralPath "$taskBase-compile.process.json" -Raw|ConvertFrom-Json
 Verify-Frozen 'between'
 if($taskBuild.status -cne 'passed' -or $taskBuild.exit_code -ne 0){throw 'Exact matching build failed; runtime prohibited'}
 $taskBinary=Join-Path $taskRoot 'zig-out\bin\test.exe'
 if(!(Test-Path -LiteralPath $taskBinary -PathType Leaf)){throw 'Matching installed qualification artifact absent'}
 $taskBinaryHash=(Get-FileHash -LiteralPath $taskBinary).Hash
 $taskCachedMatches=@(Get-ChildItem -LiteralPath (Join-Path $taskRoot '.zig-cache\o') -Filter test.exe -Recurse -File|Where-Object {(Get-FileHash -LiteralPath $_.FullName).Hash -ceq $taskBinaryHash})
 if($taskCachedMatches.Count -ne 1){throw 'Exactly one matching cached qualification binary required'}
 $taskCachedBinary=$taskCachedMatches[0].FullName
 $taskArtifacts=File-Rows @($taskBinary,$taskCachedBinary)
 Save-Json "$taskBase-artifact-frozen.json" $taskArtifacts
 Admit 'metadata'
 $taskMetadata=Read-CiTestMetadata $taskCachedBinary $taskRoot "$taskBase-metadata-owner" 25
 if(@(Compare-Object ($taskExpectedNames|Sort-Object -CaseSensitive) ($taskMetadata.tests|Sort-Object -CaseSensitive) -CaseSensitive).Count){throw 'Actual25 test metadata differs from sealed named cohort'}
 $taskActualAsync=@($taskMetadata.tests|Where-Object {$_ -match '\.test\.native async body proposal'})
 if(@(Compare-Object ($taskAsyncNames|Sort-Object -CaseSensitive) ($taskActualAsync|Sort-Object -CaseSensitive) -CaseSensitive).Count){throw 'Actual10 async metadata names differ from sealed subset'}
 Save-Json "$taskBase-metadata.json" $taskMetadata
 Verify-Frozen 'metadata-between'
 Admit 'runtime'
 & $taskOwner -Executable $taskZig -WorkingDirectory $taskRoot -Arguments @('build','test-native-async-function-qualification',"-Doptimize=$Optimize",'-Duse-llvm=true','-j1','--test-timeout','120s','--summary','all') -ReceiptBase "$taskBase-runtime" -TimeoutSeconds 300
 $taskRuntime=Get-Content -LiteralPath "$taskBase-runtime.process.json" -Raw|ConvertFrom-Json
 if($taskRuntime.status -cne 'passed' -or $taskRuntime.exit_code -ne 0){throw 'Exact matching runtime failed'}
}catch{
 $taskFailure=$_.Exception.Message
 if(!$taskBuild -and (Test-Path -LiteralPath "$taskBase-compile.process.json")){$taskBuild=Get-Content -LiteralPath "$taskBase-compile.process.json" -Raw|ConvertFrom-Json}
 if(!$taskRuntime -and (Test-Path -LiteralPath "$taskBase-runtime.process.json")){$taskRuntime=Get-Content -LiteralPath "$taskBase-runtime.process.json" -Raw|ConvertFrom-Json}
}finally{
 try{Verify-Frozen 'post'}catch{$taskPostFailure=$_.Exception.Message}
 Save-Json "$taskBase-terminal.json" @{status=if($taskFailure -or $taskPostFailure){'failed'}else{'passed'};candidate_head=$ExpectedHead;reviewed_source_checkpoint=$taskPublishedHead;compile=$taskBuild;runtime=$taskRuntime;actual_test_metadata=$taskMetadata;artifacts=$taskArtifacts;failure=$taskFailure;posthash_failure=$taskPostFailure;native_qualified=(!$taskFailure -and !$taskPostFailure -and $null -ne $taskRuntime);full_pi_qualified=$false;root_execution_grant=$RootExecutionGrant;owner_sha256=$ApprovedOwnerSHA256;utc=[DateTimeOffset]::UtcNow.ToString('o')}
}
if($taskFailure -or $taskPostFailure){throw "Qualification failed: $taskFailure $taskPostFailure"}
Write-Output 'GENUINE_ASYNC_SOURCE42_AND_INHERITED_GENERATOR_JSON_SPAN_COHORT25_NATIVE_PASSED'

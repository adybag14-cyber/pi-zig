param([Parameter(Mandatory)][string]$CandidateHead,[string]$Attempt='first',[switch]$RootNativeGrant)
$ErrorActionPreference='Stop'
if(!$RootNativeGrant){throw 'Explicit Root serial native grant required; preparation does not authorize execution'}
$taskPrivate='C:/Users/adyba/pi-zig-actual-models-qualification-root10db-20261016'
$taskEvidence='C:/Users/adyba/pi-zig-update-evidence-20261003'
$taskProof=Join-Path $taskPrivate 'verification/actual-models-root10db-prepared-20261016'
$taskName="actual-models-root10db-$Attempt-20261016"
$taskZig='C:/Users/adyba/pi-zig-toolchain-20261003/zig-x86_64-windows-0.16.0/zig.exe'
$taskOwner=Join-Path $taskProof 'Invoke-OwnedNativeB919.ps1'
$taskMetadataHelper=Join-Path $taskPrivate 'tools/ci/native_qualification_ci.ps1'
$taskSource='C:/Users/adyba/pi-upstream-source-4954d76-20261015'
$taskRuntime='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012'
$taskCompilerRoot=Split-Path $taskZig
$taskToolReference=Join-Path $taskEvidence 'durable-latest89-full-inspect-53ae-tool-prehash-20261011.json'
function Hash-Paths($paths){@($paths|Sort-Object -Unique|ForEach-Object{[ordered]@{path=[IO.Path]::GetFullPath($_);sha256=(Get-FileHash -LiteralPath $_).Hash}})}
function Drift($rows){$changed=[Collections.Generic.List[string]]::new();foreach($row in $rows){if(!(Test-Path -LiteralPath $row.path -PathType Leaf)){$changed.Add($row.path);continue};$stream=[IO.File]::OpenRead($row.path);try{$actual=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream))}finally{$stream.Dispose()};if($actual -ine $row.sha256){$changed.Add($row.path)}};return @($changed)}
function Scoped-Paths([string]$root){$paths=[Collections.Generic.List[string]]::new();$dirs=[Collections.Generic.Stack[string]]::new();$dirs.Push($root);while($dirs.Count){foreach($entry in [IO.DirectoryInfo]::new($dirs.Pop()).EnumerateFileSystemInfos()){if($entry.Name -ceq '.git' -or ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint)){continue};if($entry.Attributes -band [IO.FileAttributes]::Directory){$dirs.Push($entry.FullName)}else{$paths.Add($entry.FullName)}}};@($paths|Sort-Object)}
function Candidate-Rows {Hash-Paths @(git -c gc.auto=0 -c maintenance.auto=false -C $taskPrivate ls-files --cached --others --exclude-standard|Sort-Object -Unique|ForEach-Object{Join-Path $taskPrivate $_})}
function Candidate-Drift {param($before) @(Compare-Object @($before|ForEach-Object{"$($_.path):$($_.sha256)"}) @(Candidate-Rows|ForEach-Object{"$($_.path):$($_.sha256)"}))}
function Native-Roots {@(Get-CimInstance Win32_Process|Where-Object{$_.ExecutablePath-and($_.ExecutablePath.EndsWith('\zig.exe')-or$_.ExecutablePath-like'C:\Users\adyba\pi-zig*\.zig-cache\*\build.exe'-or$_.ExecutablePath-like'C:\Users\adyba\pi-zig*\.zig-cache\*\test.exe')}|Select-Object ProcessId,ParentProcessId,ExecutablePath,CommandLine,@{n='created_utc';e={([DateTimeOffset]$_.CreationDate).UtcDateTime.ToString('o')}})}
function Admission($phase){[GC]::Collect();[GC]::WaitForPendingFinalizers();[GC]::Collect();$free=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory;$roots=@(Native-Roots);$record=[ordered]@{status=if($free -lt 16MB -or $roots.Count){'admission_failed'}else{'admitted'};candidate=$CandidateHead;root_base='10dbf9c069f776c02c4deecf593ff00cf7a536f6';grant='ROOT-SERIAL-ACTUAL-MODELS-QUALIFICATION';phase=$phase;free_kib=$free;threshold_kib=16MB;max_other_native_roots=0;other_native_roots=$roots;jobs=1;llvm=$true;compile_timeout_seconds=1320;runtime_timeout_seconds=300;test_timeout_seconds=120;host_await_timeout_seconds=10;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')};$record|ConvertTo-Json -Depth 7|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-$phase-admission.json") -Encoding utf8NoBOM;return $record.status -ceq 'admitted'}
function Absent-Drift {@($taskAbsent|Where-Object{(Test-Path -LiteralPath (Join-Path $taskRuntime $_))-or(Test-Path -LiteralPath (Join-Path $taskSource $_))})}
function Path-Inventories {@(@{name='source';paths=@(Scoped-Paths $taskSource)},@{name='dependencies';paths=@(Scoped-Paths $taskRuntime)},@{name='node_tools';paths=@([IO.Path]::GetFullPath('C:/Program Files/nodejs/node.exe'))+@(Scoped-Paths 'C:/Program Files/nodejs/node_modules/npm')},@{name='compiler';paths=@(Scoped-Paths $taskCompilerRoot)})}
function Inventory-Drift {param($reference,$current) @($reference|ForEach-Object{$old=$_;$now=($current|Where-Object name -ceq $old.name).paths;[ordered]@{name=$old.name;count=$old.paths.Count;drift=@(Compare-Object @($old.paths|Sort-Object) @($now|Sort-Object)).Count}})}
function Full-Seal($phase){
 $candidate=@(Candidate-Drift $taskBefore);$references=@($taskRefs|ForEach-Object{[ordered]@{name=$_.name;count=$_.rows.Count;drift=@(Drift $_.rows).Count}});$inventories=@(Inventory-Drift $taskInventories (Path-Inventories));$artifacts=@(Drift $taskArtifacts)
 $record=[ordered]@{phase=$phase;candidate=$CandidateHead;candidate_files=$taskBefore.Count;candidate_drift=$candidate.Count;candidate_head_drift=(git -c gc.auto=0 -c maintenance.auto=false -C $taskPrivate rev-parse HEAD) -cne $CandidateHead;vendor_files=$taskVendor.Count;vendor_subset_of_candidate=$true;vendor_drift=@(Drift $taskVendor).Count;compiler_files=$taskTools.Count;compiler_drift=@(Drift $taskTools).Count;references=$references;path_inventories=$inventories;controls=$taskControls.Count;control_drift=@(Drift $taskControls).Count;fixtures=$taskFixtures.Count;fixture_drift=@(Drift $taskFixtures).Count;absence_records=$taskAbsent.Count;absence_drift=@(Absent-Drift).Count;source_head_drift=(git -c gc.auto=0 -c maintenance.auto=false -C $taskSource rev-parse HEAD) -cne '4954d760504c11df9b2cbdc040346107b6a8153d';artifact_drift=$artifacts.Count;artifacts=$taskArtifacts;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}
 $record|ConvertTo-Json -Depth 9|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-$phase-posthash.json") -Encoding utf8NoBOM
 if($record.candidate_drift-or$record.candidate_head_drift-or$record.vendor_drift-or$record.compiler_drift-or$record.control_drift-or$record.fixture_drift-or$record.absence_drift-or$record.source_head_drift-or$record.artifact_drift-or@($references|Where-Object drift -ne 0).Count-or@($inventories|Where-Object drift -ne 0).Count){throw "Full $phase seal drift; next phase prohibited"}
 return $record
}
function Verify-Owner($receipt){if($receipt.status -cne 'passed' -or $receipt.exit_code -ne 0){throw 'Owned native process did not terminate successfully'};if(Get-CimInstance Win32_Process -Filter "ProcessId=$($receipt.pid)"){throw 'Owned native PID must be independently absent'};if(@(Native-Roots).Count){throw 'Native owner children or other native roots remain; serial phase cannot continue'}}
foreach($fresh in @("$taskName-compile.process.json","$taskName-runtime.process.json","$taskName-metadata-probe.json","$taskName-source-before.json")){if(Test-Path -LiteralPath (Join-Path $taskEvidence $fresh)){throw 'Fresh unique attempt required'}}
if((Get-FileHash -LiteralPath $taskOwner).Hash -cne 'B91945EF77F91388BB8792959AB29C3A49505B5381BA0994723AC0FC6E0502AB'){throw 'Exact original proven B919 owner required'}
if((Get-FileHash -LiteralPath $taskZig).Hash -cne '086CE9D47BA42F33A514E1A6E04EB1D4A8FA1D75E0868E0213CAAD447C91E864'){throw 'Pinned Zig0.16 changed'}
if((git -c gc.auto=0 -c maintenance.auto=false -C $taskPrivate rev-parse HEAD) -cne $CandidateHead-or@(git -c gc.auto=0 -c maintenance.auto=false -C $taskPrivate status --porcelain).Count){throw 'Exact clean candidate required'}
if((Get-FileHash -LiteralPath (Join-Path $taskPrivate 'vendor/quickjs/quickjs.c')).Hash -cne '33DFB18C9A930D3967A089DF0B28B65AF88B7665B7ADD725AED30FCB8F046FD2'-or(Get-FileHash -LiteralPath (Join-Path $taskPrivate 'vendor/quickjs/quickjs.h')).Hash -cne 'E3189DA8F918993FB567D07DF32E91CECD12C6666D9E9B1D68A6C65A15CEC37E'-or(Get-FileHash -LiteralPath (Join-Path $taskPrivate 'src/extensions/native_async_function.zig')).Hash -cne '61C4A3302BA8CF6C13CC051D6CA2CA281B4D4BC325A4C105A072182AE8B88819'){throw 'Root qualified C/H/async adapter must remain exact'}
$taskBefore=@(Candidate-Rows);$taskVendor=@($taskBefore|Where-Object path -like '*\vendor\*');if($taskVendor.Count -ne 1316){throw 'Complete vendor1316 subset required'}
$taskTools=@((Get-Content -LiteralPath $taskToolReference -Raw|ConvertFrom-Json).inputs);if($taskTools.Count -ne 19546){throw 'Complete compiler19546 required'}
$taskSpecs=@(@{name='source';file='source4954-full-manifest-20261015.json';count=1970},@{name='dependencies';file='source4954-runtime-manifest-20261015.json';count=31064},@{name='node_tools';file='source4954-node-tools-before-20261015.json';count=1774})
$taskRefs=@();foreach($spec in $taskSpecs){$rows=@(Get-Content -LiteralPath (Join-Path $taskEvidence $spec.file) -Raw|ConvertFrom-Json);if($rows.Count -ne $spec.count){throw 'Complete original reference manifest required'};$taskRefs+=@{name=$spec.name;rows=$rows}}
$taskAuditPath=Join-Path $taskEvidence 'source4954-dependency-contract-audit-20261015.json';$audit=Get-Content -LiteralPath $taskAuditPath -Raw|ConvertFrom-Json
$taskAbsent=@($audit.pins|Where-Object status -eq 'platform_optional_absent'|ForEach-Object{$_.path})+@($audit.mismatches|ForEach-Object{$_.path});if($taskAbsent.Count -ne 84-or$audit.platform_optional_absent_records -ne 80-or$audit.historical_missing_records_retained -ne 4){throw 'Exactly84 explicit historical absences required'}
$taskFixtures=@(Get-Content -LiteralPath (Join-Path $taskProof 'fixture-pins.json') -Raw|ConvertFrom-Json|ForEach-Object{[ordered]@{path=Join-Path $taskPrivate $_.path;sha256=$_.sha256}})
$taskExpectedNames=@(Get-Content -LiteralPath (Join-Path $taskProof 'planned-test-names.json') -Raw|ConvertFrom-Json);if($taskExpectedNames.Count -ne 16){throw 'Prepared exact16 test names required'}
$taskReferencePins=@(
 @{path=(Join-Path $taskEvidence 'source4954-full-manifest-20261015.json');sha256='3229A90AB56E791DCEAC7659C2929BF6D3270C0202F1242F298444BE60A5B42C'},
 @{path=(Join-Path $taskEvidence 'source4954-runtime-manifest-20261015.json');sha256='38223DB79BE24C7F9F5833A662D3C73FF2531F78489699DBF87F9F52A9B4BFBA'},
 @{path=(Join-Path $taskEvidence 'source4954-node-tools-before-20261015.json');sha256='F834312AAC6AC8D79EF4B49CCB806096D80E92FCA403CC650A05E901D4C280DD'},
 @{path=$taskAuditPath;sha256='5E33C04D23181DDAF1D0330651730524CE0EFD6643FD1490F54EF1EFF5ECD745'}
)
if(@(Drift $taskReferencePins).Count){throw 'Pinned original4954 reference manifests or dependency contract changed'}
$taskControls=@(Hash-Paths (@($PSCommandPath,$taskOwner,$taskToolReference,$taskAuditPath,$taskMetadataHelper,(Join-Path $taskProof 'fixture-pins.json'),(Join-Path $taskProof 'planned-test-names.json'),(Join-Path $taskProof 'README.md'))+@($taskSpecs|ForEach-Object{Join-Path $taskEvidence $_.file})))
$taskInventories=@(Path-Inventories)
foreach($ref in $taskRefs){$paths=($taskInventories|Where-Object name -ceq $ref.name).paths;if(@(Compare-Object @($ref.rows.path|Sort-Object) @($paths|Sort-Object)).Count){throw 'Original reference complete path inventory drift'}}
if(@(Compare-Object @($taskTools.path|Sort-Object) @(($taskInventories|Where-Object name -ceq 'compiler').paths|Sort-Object)).Count){throw 'Compiler complete path inventory drift'}
$taskBefore|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-source-before.json") -Encoding utf8NoBOM
$taskControls|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-controls-before.json") -Encoding utf8NoBOM
$taskInventories|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-inventories-before.json") -Encoding utf8NoBOM
$taskArtifacts=@();$taskCompile=$null;$taskRuntime=$null;$taskMetadata=$null;$taskFailure=$null;$taskPost=$null
$taskBinariesBefore=@(if(Test-Path -LiteralPath (Join-Path $taskPrivate '.zig-cache/o')){Get-ChildItem -LiteralPath (Join-Path $taskPrivate '.zig-cache/o') -Filter test.exe -Recurse -File|ForEach-Object FullName})
try{
 $null=Full-Seal 'before'
 if(!(Admission 'compile')){throw 'Fresh16GiB exclusive compile admission denied'}
 & $taskOwner -ReceiptBase (Join-Path $taskEvidence "$taskName-compile") -Executable $taskZig -WorkingDirectory $taskPrivate -Arguments @('build','build-native-actual-models-qualification','-Doptimize=Debug','-Duse-llvm=true','-j1','--test-timeout','120s','--summary','all') -TimeoutSeconds 1320
 $taskCompile=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName-compile.process.json") -Raw|ConvertFrom-Json;Verify-Owner $taskCompile
 $null=Full-Seal 'compile'
 if(!(Admission 'metadata')){throw 'Fresh16GiB exclusive metadata admission denied'}
 $new=@(Get-ChildItem -LiteralPath (Join-Path $taskPrivate '.zig-cache/o') -Filter test.exe -Recurse -File|Where-Object FullName -NotIn $taskBinariesBefore);if($new.Count -ne 1){throw 'Exactly one newly compiled test artifact required'}
 $taskArtifacts=@(Hash-Paths @($new[0].FullName));$taskArtifacts|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-artifacts-before.json") -Encoding utf8NoBOM
 . $taskMetadataHelper
 $taskMetadata=Read-CiTestMetadata $new[0].FullName $taskPrivate (Join-Path $taskEvidence "$taskName-metadata-probe") $taskExpectedNames.Count
 if(@(Compare-Object @($taskExpectedNames|Sort-Object -CaseSensitive) @($taskMetadata.tests|Sort-Object -CaseSensitive) -CaseSensitive).Count){throw 'Exact native test metadata mismatch; preserve discovered names and do not run'}
 $taskMetadata|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-metadata-selected.json") -Encoding utf8NoBOM
 $null=Full-Seal 'metadata'
 if(!(Admission 'runtime')){throw 'Fresh16GiB exclusive runtime admission denied'}
 & $taskOwner -ReceiptBase (Join-Path $taskEvidence "$taskName-runtime") -Executable $taskZig -WorkingDirectory $taskPrivate -Arguments @('build','test-native-actual-models-qualification','-Doptimize=Debug','-Duse-llvm=true','-j1','--test-timeout','120s','--summary','all') -TimeoutSeconds 300
 $taskRuntime=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName-runtime.process.json") -Raw|ConvertFrom-Json;Verify-Owner $taskRuntime
}catch{$taskFailure=$_.Exception.Message}finally{
 if(!$taskCompile-and(Test-Path -LiteralPath (Join-Path $taskEvidence "$taskName-compile.process.json"))){$taskCompile=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName-compile.process.json") -Raw|ConvertFrom-Json}
 if(!$taskRuntime-and(Test-Path -LiteralPath (Join-Path $taskEvidence "$taskName-runtime.process.json"))){$taskRuntime=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName-runtime.process.json") -Raw|ConvertFrom-Json}
 try{$taskPost=Full-Seal 'final'}catch{if(!$taskFailure){$taskFailure=$_.Exception.Message}}
 [ordered]@{candidate=$CandidateHead;root_base='10dbf9c069f776c02c4deecf593ff00cf7a536f6';scope='Actual Models Source18 auth69 refresh60 factory92 CredentialStore20; shared recorder START/resume OOM and rejected allocation identities';original_observations=259;planned_native_tests=$taskExpectedNames.Count;actual_metadata_count=if($taskMetadata){$taskMetadata.tests.Count}else{$null};compile=if($taskCompile){$taskCompile.status}else{'not_run'};runtime=if($taskRuntime){$taskRuntime.status}else{'not_run'};failure=$taskFailure;full_posthash=$taskPost;public_activation=$false;full_pi_qualified=$false;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 12|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-result.json") -Encoding utf8NoBOM
}
if($taskFailure-or!$taskRuntime-or$taskRuntime.status -cne 'passed'){throw "Actual Models qualification failed: $taskFailure"}
Write-Output "ACTUAL_MODELS_QUALIFIED_SOURCE_OBSERVATIONS=259;NATIVE_TESTS=$($taskMetadata.tests.Count)"

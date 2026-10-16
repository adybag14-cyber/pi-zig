param(
 [ValidateSet('functional','gpa')][string]$Suite='functional',
 [Parameter(Mandatory)][ValidateSet('build','metadata','test')][string]$Phase,
 [Parameter(Mandatory)][string]$Attempt,
 [Parameter(Mandatory)][string]$ExpectedHead,
 [Parameter(Mandatory)][string]$RootGrant,
 [string]$BuildAttempt,
 [string]$MetadataAttempt
)
$ErrorActionPreference='Stop'
$taskRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$taskEvidence='C:/Users/adyba/pi-zig-update-evidence-20261003'
$taskSource='C:/Users/adyba/pi-upstream-source-4954d76-20261015'
$taskRuntime='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012'
$taskCompiler='C:/Users/adyba/pi-zig-toolchain-20261003/zig-x86_64-windows-0.16.0'
$taskNodeRoot='C:/Program Files/nodejs'
$taskOwner=Join-Path $PSScriptRoot 'Invoke-ReviewedSerialOwner.ps1'
$taskContractPath=Join-Path $PSScriptRoot 'qualification-contract.json'
$taskContract=Get-Content -LiteralPath $taskContractPath -Raw|ConvertFrom-Json
$taskSuite=$taskContract.suites.$Suite
if(!$taskSuite){throw 'Explicit suite contract required'}
$taskGrant=Get-Content -LiteralPath $RootGrant -Raw|ConvertFrom-Json
# A retained Body owner negative is not an execution grant. A reviewed successor
# and an explicit exact-head Root lane release must be supplied before hashing.
if($taskGrant.status -cne 'root_reviewed_typebox_native_release' -or $taskGrant.candidate_head -cne $ExpectedHead -or $taskGrant.phase -cne $Phase -or $taskGrant.suite -cne $Suite -or !$taskGrant.grant_id -or $taskGrant.owner_sha256 -cne (Get-FileHash -LiteralPath $taskOwner).Hash -or $taskGrant.owner_sha256 -cne 'B91945EF77F91388BB8792959AB29C3A49505B5381BA0994723AC0FC6E0502AB'){throw 'Explicit exact suite Root release and original proven B91945 owner required; historical9B5 owner remains held'}
if((git -C $taskRoot rev-parse HEAD) -cne $ExpectedHead -or @(git -C $taskRoot status --porcelain).Count){throw 'Exact clean sealed qualification candidate required'}
$taskName="typebox-root642-$Suite-$Phase-$Attempt-20261016"
$taskBase=Join-Path $taskEvidence $taskName
if(@(Get-ChildItem -LiteralPath $taskEvidence -Filter "$taskName*" -File).Count){throw 'Fresh unique native qualification attempt required'}
function Hash-Paths($paths){@($paths|Sort-Object -Unique|ForEach-Object{[ordered]@{path=[IO.Path]::GetFullPath($_);sha256=(Get-FileHash -LiteralPath $_).Hash}})}
function Check-Rows($rows){@($rows|Where-Object{!(Test-Path -LiteralPath $_.path -PathType Leaf)-or(Get-FileHash -LiteralPath $_.path).Hash -ine $_.sha256}|ForEach-Object path)}
$taskAuditPath=Join-Path $taskEvidence 'source4954-dependency-contract-audit-20261015.json'
$taskAudit=Get-Content -LiteralPath $taskAuditPath -Raw|ConvertFrom-Json
$taskLinks=@($taskAudit.workspaces|ForEach-Object{[ordered]@{path=[IO.Path]::GetFullPath((Join-Path (Join-Path $taskRuntime 'node_modules') $_.specifier));target=[IO.Path]::GetFullPath((Join-Path $taskRuntime $_.path));type='Junction'}})
$taskAbsences=@($taskAudit.pins|Where-Object status -eq 'platform_optional_absent'|ForEach-Object path)+@($taskAudit.mismatches|ForEach-Object path)
if($taskLinks.Count -ne 16 -or $taskAbsences.Count -ne 84){throw 'Original16 links/84 explicit absences required'}
function Inventory($directory,[string[]]$excluded=@()){
 foreach($entry in Get-ChildItem -LiteralPath $directory -Force){if($entry.Name -in $excluded){continue};if($entry.PSIsContainer){if($entry.Attributes -band [IO.FileAttributes]::ReparsePoint){$link=$taskLinks|Where-Object path -eq $entry.FullName;if(!$link -or $entry.LinkType -cne $link.type -or $entry.Target -cne $link.target){throw "Frozen junction inventory drift $($entry.FullName)"};continue};Inventory $entry.FullName $excluded}else{$entry.FullName}}
}
function Compare-Paths($rows,$actual){@(Compare-Object @($rows.path|Sort-Object) @($actual|Sort-Object)).Count}
function Candidate-Paths(){@(Inventory $taskRoot @('.git','.zig-cache','zig-out'))}
$taskSpecs=@(
 @{name='reference';path=(Join-Path $taskEvidence 'source4954-full-manifest-20261015.json');count=1970;root=$taskSource;excluded=@('.git','node_modules')},
 @{name='runtime';path=(Join-Path $taskEvidence 'source4954-runtime-manifest-20261015.json');count=31064;root=$taskRuntime;excluded=@('.git')},
 @{name='node';path=(Join-Path $taskEvidence 'source4954-node-tools-before-20261015.json');count=1774;root=$taskNodeRoot;excluded=@()},
 @{name='compiler';path=(Join-Path $taskEvidence 'durable-latest89-full-inspect-53ae-tool-prehash-20261011.json');count=19546;root=$taskCompiler;excluded=@()}
)
$taskFrozen=[ordered]@{}
foreach($spec in $taskSpecs){$parsed=Get-Content -LiteralPath $spec.path -Raw|ConvertFrom-Json;$rows=if($spec.name -eq 'compiler'){@($parsed.inputs)}else{@($parsed)};if($rows.Count -ne $spec.count){throw 'Original full reference/tool inventory count mismatch'};$taskFrozen[$spec.name]=$rows}
$taskFrozen.candidate=Hash-Paths (Candidate-Paths)
$taskFrozen.vendor=Hash-Paths @(Inventory (Join-Path $taskRoot 'vendor'))
$taskFrozen.node_complete=Hash-Paths @(Inventory $taskNodeRoot)
if($taskFrozen.node_complete.Count-ne1838){throw 'Complete Node installation1838 inventory changed'}
$taskFrozen.controls=Hash-Paths (@($PSCommandPath,$taskOwner,$taskContractPath,$RootGrant,$taskAuditPath,(Join-Path $taskRoot 'tools/ci/native_qualification_ci.ps1'),(Join-Path $PSScriptRoot 'Read-ActualMetadata.ps1'),(Join-Path $PSScriptRoot 'Measure-ActualStackArtifact.ps1'),'C:/Program Files/LLVM/bin/llvm-pdbutil.exe')+@($taskSpecs.path))
$taskFrozen.fixtures=@($taskContract.fixtures|ForEach-Object{[ordered]@{path=(Join-Path $taskRoot $_.path);sha256=$_.sha256}})
function Verify-Frozen {
 $checks=@()
 foreach($pair in $taskFrozen.GetEnumerator()){$drift=@(Check-Rows $pair.Value);$checks+=@{name=$pair.Key;files=@($pair.Value).Count;drift=$drift.Count;changed=$drift}}
 foreach($spec in $taskSpecs){$paths=if($spec.name -eq 'node'){@((Join-Path $taskNodeRoot 'node.exe'))+@(Inventory (Join-Path $taskNodeRoot 'node_modules/npm'))}else{@(Inventory $spec.root $spec.excluded)};$checks+=@{name=$spec.name+'_inventory';drift=(Compare-Paths $taskFrozen[$spec.name] $paths)}}
 $checks+=@{name='candidate_inventory';drift=(Compare-Paths $taskFrozen.candidate (Candidate-Paths))}
 $checks+=@{name='vendor_inventory';drift=(Compare-Paths $taskFrozen.vendor @(Inventory (Join-Path $taskRoot 'vendor')))}
 $checks+=@{name='node_complete_inventory';drift=(Compare-Paths $taskFrozen.node_complete @(Inventory $taskNodeRoot))}
 $checks+=@{name='explicit84_absences';drift=@($taskAbsences|Where-Object{(Test-Path -LiteralPath (Join-Path $taskRuntime $_))-or(Test-Path -LiteralPath (Join-Path $taskSource $_))}).Count}
 $taskLinkDrift=@(foreach($link in $taskLinks){$entry=Get-Item -LiteralPath $link.path -Force -ErrorAction SilentlyContinue;if(!$entry-or$entry.LinkType -cne $link.type-or$entry.Target -cne $link.target){$link.path}})
 $checks+=@{name='explicit16_workspace_junctions';drift=$taskLinkDrift.Count;changed=$taskLinkDrift}
 $checks+=@{name='candidate_head';drift=[int]((git -C $taskRoot rev-parse HEAD) -cne $ExpectedHead)}
 $checks+=@{name='reference_head';drift=[int]((git -C $taskSource rev-parse HEAD) -cne $taskContract.sourceHead)}
 $checks
}
$taskFrozen|ConvertTo-Json -Depth 7|Set-Content -LiteralPath "$taskBase-frozen.json" -Encoding utf8NoBOM
$taskBefore=@(Verify-Frozen)
$taskBefore|ConvertTo-Json -Depth 6|Set-Content -LiteralPath "$taskBase-before.json" -Encoding utf8NoBOM
if(@($taskBefore|Where-Object drift -ne 0).Count){throw 'Full strict TypeBox prehash/inventory failed'}
$taskFrozenHash=(Get-FileHash -LiteralPath "$taskBase-frozen.json").Hash
$taskFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory*1024
$taskOther=@(Get-CimInstance Win32_Process|Where-Object{$_.ExecutablePath-and($_.ExecutablePath.EndsWith('\zig.exe')-or$_.ExecutablePath-like'C:\Users\adyba\pi-zig*\.zig-cache\*\build.exe'-or$_.ExecutablePath-like'C:\Users\adyba\pi-zig*\.zig-cache\*\test.exe')})
@{minimum_free_bytes=16GB;pressure_stop_policy='Original proven B919 owner per explicit Root grant; held12GiB supervisor not used';free_bytes=$taskFree;other_native=@($taskOther|Select-Object ProcessId,ParentProcessId,ExecutablePath,CommandLine,CreationDate);root_grant=$taskGrant;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 7|Set-Content -LiteralPath "$taskBase-admission.json" -Encoding utf8NoBOM
if($taskFree -lt 16GB -or $taskOther.Count){throw 'Fresh16GiB/zero-other-native admission rejected; no launch'}
$taskBinary=$null
if($Phase -ne 'build'){
 if(!$BuildAttempt){throw 'Matching sealed compile attempt required'}
 $taskBuildBase=Join-Path $taskEvidence "typebox-root642-$Suite-build-$BuildAttempt-20261016"
 $build=Get-Content -LiteralPath "$taskBuildBase-validation.json" -Raw|ConvertFrom-Json
 if($build.status -cne 'passed' -or $build.candidate_head -cne $ExpectedHead -or $build.suite -cne $Suite){throw 'Matching terminal0 full-post0 compile required'}
 $prior=Get-Content -LiteralPath "$taskBuildBase-frozen.json" -Raw|ConvertFrom-Json
 foreach($name in @('candidate','vendor','reference','runtime','node','node_complete','compiler','fixtures')){if(@(Compare-Object @($prior.$name|ForEach-Object{"$($_.path):$($_.sha256)"}) @($taskFrozen[$name]|ForEach-Object{"$($_.path):$($_.sha256)"})).Count){throw "Between compile/runtime frozen drift $name"}}
 $taskBinary=$build.binary
 if(!(Test-Path -LiteralPath $taskBinary.path)-or(Get-FileHash -LiteralPath $taskBinary.path).Hash -cne $taskBinary.sha256-or(Get-FileHash -LiteralPath $taskBinary.installed_path).Hash -cne $taskBinary.sha256){throw 'Exact cached and installed compiled test executable required'}
 if((Get-FileHash -LiteralPath $taskBinary.pdb_path).Hash -cne $taskBinary.pdb_sha256){throw 'Exact compiled PDB required'}
 if($Phase -eq 'test'){$meta=Get-Content -LiteralPath (Join-Path $taskEvidence "typebox-root642-$Suite-metadata-$MetadataAttempt-20261016-validation.json") -Raw|ConvertFrom-Json;if(!$MetadataAttempt-or$meta.status -cne 'passed'-or$meta.candidate_head -cne $ExpectedHead-or$meta.suite -cne $Suite-or$meta.binary.sha256 -cne $taskBinary.sha256){throw 'Exact original test metadata must pass before runtime'}}
}
$taskBeforeBinaries=@(Get-ChildItem -LiteralPath (Join-Path $taskRoot '.zig-cache/o') -Filter test.exe -Recurse -File -ErrorAction SilentlyContinue|ForEach-Object FullName)
$taskBeforeBinaries|ConvertTo-Json -AsArray|Set-Content -LiteralPath "$taskBase-before-binaries.json" -Encoding utf8NoBOM
$taskFailure=$null;$taskMetadata=$null
try{
 if($Phase -eq 'metadata'){
  $taskQueryFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory*1024
  $taskQueryOther=@(Get-CimInstance Win32_Process|Where-Object{$_.ExecutablePath-and($_.ExecutablePath.EndsWith('\zig.exe')-or$_.ExecutablePath-like'C:\Users\adyba\pi-zig*\.zig-cache\*\build.exe'-or$_.ExecutablePath-like'C:\Users\adyba\pi-zig*\.zig-cache\*\test.exe')})
  if($taskQueryFree -lt 16GB-or$taskQueryOther.Count){throw 'Fresh metadata launch16GiB/zero-other-native admission failed'}
  . (Join-Path $taskRoot 'tools/ci/native_qualification_ci.ps1')
  . (Join-Path $PSScriptRoot 'Read-ActualMetadata.ps1')
  $taskMetadata=Read-ActualTypeBoxMetadata $taskBinary.path $taskRoot "$taskBase-query"
  $taskPlanned=@($taskSuite.expectedTests)
  if($taskMetadata.tests.Count -ne $taskPlanned.Count){throw 'Exact actual metadata count required'}
  for($index=0;$index-lt$taskPlanned.Count;$index++){if($taskMetadata.tests[$index] -cne $taskPlanned[$index]){throw 'Exact planned and imported metadata names/order required'}}
 }else{
  $taskLaunchFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory*1024
  $taskLaunchOther=@(Get-CimInstance Win32_Process|Where-Object{$_.ExecutablePath-and($_.ExecutablePath.EndsWith('\zig.exe')-or$_.ExecutablePath-like'C:\Users\adyba\pi-zig*\.zig-cache\*\build.exe'-or$_.ExecutablePath-like'C:\Users\adyba\pi-zig*\.zig-cache\*\test.exe')})
  if($taskLaunchFree-lt16GB-or$taskLaunchOther.Count){throw 'Immediate native launch16GiB/zero-other-native admission failed'}
  & $taskOwner -Executable (Join-Path $taskCompiler 'zig.exe') -WorkingDirectory $taskRoot -Arguments @('build',"$Phase-native-typebox-production-$($taskSuite.targetSuffix)",'-Doptimize=Debug','-Duse-llvm=true','-j1','--test-timeout','120s','--summary','all') -ReceiptBase $taskBase -TimeoutSeconds $(if($Phase -eq 'build'){1320}else{300})
 }
}catch{$taskFailure=[string]$_}finally{
 $taskAfter=@(Verify-Frozen)
 if((Get-FileHash -LiteralPath "$taskBase-frozen.json").Hash -cne $taskFrozenHash){$taskAfter+=@{name='frozen_registry';drift=1}}
 if($taskBinary-and((Get-FileHash -LiteralPath $taskBinary.path).Hash -cne $taskBinary.sha256-or(Get-FileHash -LiteralPath $taskBinary.installed_path).Hash -cne $taskBinary.sha256-or(Get-FileHash -LiteralPath $taskBinary.pdb_path).Hash -cne $taskBinary.pdb_sha256)){$taskAfter+=@{name='compiled_binary_and_pdb';drift=1}}
 $taskLiveProcesses=@(Get-CimInstance Win32_Process)
 $taskOwnedRoots=@(foreach($receipt in @("$taskBase.process.json","$taskBase-query.json")){if(Test-Path -LiteralPath $receipt){$owned=Get-Content -LiteralPath $receipt -Raw|ConvertFrom-Json;$remaining=@($taskLiveProcesses|Where-Object ProcessId -eq $owned.pid);[ordered]@{receipt=$receipt;pid=$owned.pid;executable=$owned.executable;created_utc=$owned.created_utc;terminal_status=$owned.status;pid_present=$remaining.Count;remaining=@($remaining|Select-Object ProcessId,ParentProcessId,ExecutablePath,CommandLine,CreationDate)}}})
 $taskNativeRemaining=@($taskLiveProcesses|Where-Object{$_.ExecutablePath-and($_.ExecutablePath.EndsWith('\zig.exe')-or$_.ExecutablePath-like'C:\Users\adyba\pi-zig*\.zig-cache\*\build.exe'-or$_.ExecutablePath-like'C:\Users\adyba\pi-zig*\.zig-cache\*\test.exe')})
 [ordered]@{observed_utc=[DateTimeOffset]::UtcNow.ToString('o');owned_roots=$taskOwnedRoots;global_native=@($taskNativeRemaining|Select-Object ProcessId,ParentProcessId,ExecutablePath,CommandLine,CreationDate);scope='Fresh root PID absence and global native process snapshot; no cancellation is performed'}|ConvertTo-Json -Depth 7|Set-Content -LiteralPath "$taskBase-after-absence.json" -Encoding utf8NoBOM
 $taskAfter+=@{name='owned_roots_absent_global_native_zero';drift=(@($taskOwnedRoots|Where-Object pid_present -ne 0).Count+$taskNativeRemaining.Count)}
 $taskAfter|ConvertTo-Json -Depth 6|Set-Content -LiteralPath "$taskBase-after.json" -Encoding utf8NoBOM
}
if(@($taskAfter|Where-Object drift -ne 0).Count){throw 'Full strict TypeBox posthash/inventory failed'}
if($taskFailure){throw $taskFailure}
if($Phase -eq 'build'){$installed=Join-Path $taskRoot "zig-out/bin/$($taskSuite.installedBinary)";$hash=(Get-FileHash -LiteralPath $installed).Hash;$new=@(Get-ChildItem -LiteralPath (Join-Path $taskRoot '.zig-cache/o') -Filter test.exe -Recurse -File|Where-Object {(Get-FileHash -LiteralPath $_.FullName).Hash -ceq $hash});if($new.Count -ne 1){throw 'Exactly one matching cached shared graph executable required'};$pdb=[IO.Path]::ChangeExtension($new[0].FullName,'.pdb');$taskBinary=@{path=$new[0].FullName;installed_path=$installed;sha256=$hash;pdb_path=$pdb;pdb_sha256=(Get-FileHash -LiteralPath $pdb).Hash}; & (Join-Path $PSScriptRoot 'Measure-ActualStackArtifact.ps1') -Binary $taskBinary.path -Pdb $pdb -ReceiptBase "$taskBase-stack"}
if($Phase -eq 'test'){$log=[IO.File]::ReadAllText("$taskBase.stderr.log");foreach($marker in @($taskSuite.requiredMarkers)){if(!$log.Contains($marker)){throw 'Missing original suite replay marker'}};$count=@($meta.metadata.tests).Count;if($log -notmatch ([regex]::Escape("$count/$count tests passed")) -or $log -match '\bskip(?:ped)?\b'-or$log -notmatch ('run test '+$count+' pass \('+$count+' total\)')){throw 'All actual metadata-selected native tests must execute and pass without skips'}}
@{status='passed';suite=$Suite;phase=$Phase;candidate_head=$ExpectedHead;binary=$taskBinary;metadata=$taskMetadata;source_replays=@($taskSuite.sourceReplays);full_posthash_drift=0;full_pi_qualified=$false;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath "$taskBase-validation.json" -Encoding utf8NoBOM
Write-Output "TYPEBOX_NATIVE_$($Phase.ToUpper())_PASSED_FULL_POSTHASH0"

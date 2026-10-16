param(
 [Parameter(Mandatory)][ValidateSet('Compile','Runtime')][string]$Phase,
 [Parameter(Mandatory)][string]$Attempt,
 [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{40}$')][string]$CandidateHead,
 [Parameter(Mandatory)][string]$RootGrant
)
$ErrorActionPreference='Stop'
$taskRoot='C:\Users\adyba\pi-zig-sdk-fs-metadata-20261016'
$taskEvidence='C:\Users\adyba\pi-zig-update-evidence-20261003'
$taskProof=Join-Path $taskEvidence 'fs-metadata-native4-20261016'
$taskCompiler='C:\Users\adyba\pi-zig-toolchain-20261003\zig-x86_64-windows-0.16.0'
$taskSource='C:\Users\adyba\pi-upstream-source-5ab7fe7-20261015'
$taskRuntime='C:\Users\adyba\pi-upstream-runtime-19cb534-20261012'
$taskOwner=Join-Path $PSScriptRoot 'Invoke-Native4-OwnedJob.ps1'
$taskMetadataOwner=Join-Path $taskRoot 'tools\ci\native_qualification_ci.ps1'
$taskExpected=Join-Path $taskRoot 'src\extensions\fixtures\node-fs-metadata-24.json'
$taskSourceProof=Join-Path $taskRoot 'verification\node-fs-metadata-source22-20261016'
$taskQualified=Join-Path $taskSourceProof 'qualification.json'
$taskSourceName='node-fs-metadata-24-source-first-0a800f30-20261016'
$taskCompilerFreeze=Join-Path $taskEvidence 'file-revision-source4954-second-20261015-candidate-compiler-before.json'
$taskName="fs-metadata-native4-$($Phase.ToLower())-$Attempt-20261016"
$taskReceipt=Join-Path $taskProof $taskName
$taskPrefix=Join-Path (Join-Path $taskProof 'native-debug') $CandidateHead
$taskArtifactManifest=Join-Path $taskPrefix 'artifacts.json'
function Extended-Path([string]$path){
 # GetFullPath also trims trailing U+0020 on ordinary Win32 paths. The
 # immutable owner inventories supply absolute paths; prefix before any IO.
 if(![IO.Path]::IsPathFullyQualified($path)){throw 'Exact absolute owner path required'}
 $full=$path
 if($full.StartsWith('\\?\',[StringComparison]::Ordinal)){return $full}
 if($full.StartsWith('\\',[StringComparison]::Ordinal)){return '\\?\UNC\'+$full.Substring(2)}
 return '\\?\'+$full
}
function Exact-FileHash([string]$path){
 $stream=[IO.File]::OpenRead((Extended-Path $path))
 try{return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream))}finally{$stream.Dispose()}
}
function Check-Rows($rows){@($rows|Where-Object{![IO.File]::Exists((Extended-Path $_.path))-or(Exact-FileHash $_.path) -ine $_.sha256}|ForEach-Object path)}
function Hash-Paths($paths){@($paths|Sort-Object -Unique|ForEach-Object{[ordered]@{path=[IO.Path]::GetFullPath($_);sha256=Exact-FileHash $_;bytes=[IO.FileInfo]::new((Extended-Path $_)).Length}})}
function Candidate-Paths(){@(& git -c gc.auto=0 -c maintenance.auto=false -C $taskRoot ls-files|ForEach-Object{[IO.Path]::GetFullPath((Join-Path $taskRoot $_))})}
function Source-Paths([string]$directory){foreach($entry in Get-ChildItem -LiteralPath $directory -Force){if($entry.Name -in @('.git','node_modules')){continue};if($entry.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Immutable Source reparse entry'};if($entry.PSIsContainer){Source-Paths $entry.FullName}else{$entry.FullName}}}
function Dependency-Paths(){@(Get-ChildItem -LiteralPath $taskRuntime -Recurse -Force -File|Where-Object {$_.FullName -notmatch '[\\/]\.git[\\/]'}|ForEach-Object FullName)}
function Node-Paths(){@('C:\Program Files\nodejs\node.exe')+@(Get-ChildItem -LiteralPath 'C:\Program Files\nodejs\node_modules\npm' -Recurse -Force -File|ForEach-Object FullName)}
function Inventory-Drift($rows,$actual){@(Compare-Object @($rows|ForEach-Object{[IO.Path]::GetFullPath($_.path)}|Sort-Object) @($actual|ForEach-Object{[IO.Path]::GetFullPath($_)}|Sort-Object)).Count}
function Assert-Candidate(){if((& git -c gc.auto=0 -c maintenance.auto=false -C $taskRoot rev-parse HEAD).Trim() -cne $CandidateHead -or @(& git -c gc.auto=0 -c maintenance.auto=false -C $taskRoot status --porcelain).Count){throw 'Exact clean native successor required'}}
function Assert-Physical {
 $rows=foreach($file in $taskSourceControls|Where-Object {$_.path.StartsWith($taskQualification.physical_fixture_root+'\',[StringComparison]::OrdinalIgnoreCase)}){
  $path=[string]$file.path
  $info=[IO.FileInfo]::new((Extended-Path $path))
  if(!$info.Exists -or ($info.Attributes -band ([IO.FileAttributes]::Directory -bor [IO.FileAttributes]::ReparsePoint))){throw 'Original regular physical Source file required'}
  $mtime=(([Numerics.BigInteger]$info.LastWriteTimeUtc.Ticks-[Numerics.BigInteger]621355968000000000)*100).ToString()
  if((Exact-FileHash $path) -ine $file.sha256){throw 'Physical Source content changed'}
  [ordered]@{path=$path;bytes=$info.Length;mtime_ns=$mtime;birthtime_ticks=$info.CreationTimeUtc.Ticks;sha256=$file.sha256}
 }
 if(@($rows).Count -ne 31){throw 'All31 original Source files required; skips forbidden'}
 $info=Get-Item -LiteralPath $taskQualification.physical_fixture_root -Force
 if(!$info.PSIsContainer-or($info.Attributes-band[IO.FileAttributes]::ReparsePoint)){throw 'Retained original Source fixture root required'}
 return @($rows)
}
function Absence-Drift(){@($taskAbsences|Where-Object{(Test-Path -LiteralPath (Join-Path $taskSource $_))-or(Test-Path -LiteralPath (Join-Path $taskRuntime $_))}).Count}
function Assert-Memory { $free=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory;if($free-lt16MB){[ordered]@{status='admission_denied';free_kib=$free;required_kib=16MB;phase=$Phase;candidate_head=$CandidateHead;root_grant=$RootGrant;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath "$taskReceipt-admission-denied.json" -Encoding utf8NoBOM;throw 'Fresh16GiB native admission denied'};return $free }
function Read-RevisionMetadata($binary,$receipt){
 . $taskMetadataOwner
 $owned=Invoke-CiOwnedProcess $binary @('--listen=-') $taskRoot $receipt 30 ([byte[]](4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
 $bytes=[IO.File]::ReadAllBytes("$receipt.stdout.bin");$offset=0;$version=$null;$names=$null
 while($offset-lt$bytes.Length){
  if($offset+8-gt$bytes.Length){throw 'Truncated actual Zig metadata'}
  $tag=[BitConverter]::ToUInt32($bytes,$offset);$length=[BitConverter]::ToUInt32($bytes,$offset+4);$offset+=8
  if($length-gt1MB-or$offset+$length-gt$bytes.Length){throw 'Invalid actual Zig metadata length'}
  if($tag-eq0){$version=[Text.Encoding]::UTF8.GetString($bytes,$offset,$length)}
  elseif($tag-eq3){
   if($null-ne$names){throw 'Duplicate actual metadata array'}
   $strings=[BitConverter]::ToUInt32($bytes,$offset);$count=[BitConverter]::ToUInt32($bytes,$offset+4)
   if($count-notin1,2-or$length-ne8+8*$count+$strings){throw 'Only Source22 authored comparison plus optional known imported control admitted'}
   $start=$offset+8+8*$count;$names=@()
   for($i=0;$i-lt$count;$i++){$nameOffset=[BitConverter]::ToUInt32($bytes,$offset+8+4*$i);$panic=[BitConverter]::ToUInt32($bytes,$offset+8+4*$count+4*$i);if($panic-ne0-or$nameOffset-ge$strings){throw 'Unexpected panic/offset metadata'};$end=$nameOffset;while($end-lt$strings-and$bytes[$start+$end]-ne0){$end++};if($end-eq$strings){throw 'Unterminated metadata name'};$names+=[Text.Encoding]::UTF8.GetString($bytes,$start+$nameOffset,$end-$nameOffset)}
  }else{throw 'Unexpected metadata-only protocol tag'}
  $offset+=$length
 }
 $expected=@([regex]::Matches([IO.File]::ReadAllText((Join-Path $taskRoot 'src\native_fs_metadata_test.zig')),'(?m)^test "([^"]+)"')|ForEach-Object{'native_fs_metadata_test.test.'+$_.Groups[1].Value})
 if($expected.Count-ne1-or$version-cne'0.16.0'){throw 'One authored Source22 Zig0.16 comparison required'}
 $controls=@($names|Where-Object{$_-cnotin$expected});if($controls.Count-gt1-or@($controls|Where-Object{$_-cne'extensions.native_durable_storage.test_0'}).Count){throw 'Unexpected imported test metadata'}
 if(@(Compare-Object @($expected|Sort-Object -CaseSensitive) @($names|Where-Object{$_-cin$expected}|Sort-Object -CaseSensitive)-CaseSensitive).Count){throw 'Actual authored metadata names differ'}
 return [ordered]@{binary=$binary;binary_sha256=$owned.executable_sha256;version=$version;tests=$names;authored_tests=$expected;authored_count=1;imported_controls=$controls;total_count=$names.Count;method='actual Zig0.16 metadata-only query and clean exit; no run_test command'}
}
New-Item -ItemType Directory -Path $taskProof -Force|Out-Null
if(Test-Path -LiteralPath "$taskReceipt.process.json"){throw 'Fresh immutable phase receipt required'}
Assert-Candidate
if((Get-FileHash -LiteralPath $taskOwner).Hash-cne'7D718FAD6273DF1318B3B6E67430E85048A3D230A4EC512C2EBF7DCD4E3AD5FA'){throw 'Pinned NATIVE4 process owner changed'}
if((Get-FileHash -LiteralPath $taskExpected).Hash-cne'62B7518C5F9E649C366E8D135C8F536910D75DFC0A8F4AA9A65F81335F5B1E89'){throw 'Exact genuine Source22 packet required'}
if((Get-FileHash -LiteralPath $taskCompilerFreeze).Hash-cne'C1DB3E90B328DE5B27A9A472A96541491AFFDE2FF69E9E9D80E890CC913B4DD0'){throw 'Exact Source30 compiler freeze changed'}
$taskPacket=Get-Content -LiteralPath $taskExpected -Raw|ConvertFrom-Json
if($taskPacket.nodeVersion-cne'24.14.0'-or$taskPacket.sourceHead-cne'5ab7fe74c400097b386662205cd93900695b8a71'-or$taskPacket.cases-ne22){throw 'Actual pinned Node24 Source22 authority required'}
$taskQualification=Get-Content -LiteralPath $taskQualified -Raw|ConvertFrom-Json
$taskSourceControls=@(Get-Content -LiteralPath (Join-Path $taskSourceProof "$taskSourceName-controls-before.json") -Raw|ConvertFrom-Json)
if($taskQualification.status-cne'source_qualified'-or$taskQualification.cases-ne22-or$taskSourceControls.Count-ne43-or@(Check-Rows $taskSourceControls).Count){throw 'Actual Source22 qualification/control closure changed'}
$taskPhysical=Assert-Physical
$taskCandidate=Hash-Paths (Candidate-Paths)
$taskReference=@(Get-Content -LiteralPath (Join-Path $taskEvidence 'source5ab-full-manifest-20261015.json') -Raw|ConvertFrom-Json)
$taskDependencies=@(Get-Content -LiteralPath (Join-Path $taskEvidence 'durable-19cb534-reference-20261012-all-built-runtime.json') -Raw|ConvertFrom-Json)
$taskNode=@(Get-Content -LiteralPath (Join-Path $taskEvidence 'root-current8a-npm-tools-before.json') -Raw|ConvertFrom-Json)
$taskCompilerRows=@((Get-Content -LiteralPath $taskCompilerFreeze -Raw|ConvertFrom-Json).compiler)
if($taskReference.Count-ne1967-or$taskDependencies.Count-ne31064-or$taskNode.Count-ne1774-or$taskCompilerRows.Count-ne19546){throw 'Complete frozen source/dependency/node/compiler universes required'}
$taskAudit=Get-Content -LiteralPath (Join-Path $taskEvidence 'source5ab-dependency-contract-audit-20261015.json') -Raw|ConvertFrom-Json
$taskAbsences=@($taskAudit.pins|Where-Object status -eq 'platform_optional_absent'|ForEach-Object path)+@($taskAudit.mismatches|ForEach-Object path)
if($taskAbsences.Count-ne84){throw 'Exactly84 declared package absences required'}
$taskSourceReceipt=Get-Content -LiteralPath (Join-Path $taskSourceProof "$taskSourceName.json") -Raw|ConvertFrom-Json
if($taskSourceReceipt.status-cne'passed'){throw 'Matching genuine Source child did not pass'}
$taskControls=Hash-Paths (@($PSCommandPath,$taskOwner,$taskMetadataOwner,$taskExpected,$taskCompilerFreeze,$taskQualified,(Join-Path $taskRoot 'build.zig'),(Join-Path $taskRoot 'src\native_fs_metadata_test.zig'),(Join-Path $taskRoot 'src\extensions\native_file_stat.zig'),(Join-Path $taskRoot 'src\extensions\node_fs_metadata.zig'),(Join-Path $taskRoot 'src\extensions\fixtures\node-fs-metadata-24.input.txt'),(Join-Path $taskEvidence 'source5ab-full-manifest-20261015.json'),(Join-Path $taskEvidence 'durable-19cb534-reference-20261012-all-built-runtime.json'),(Join-Path $taskEvidence 'root-current8a-npm-tools-before.json'),(Join-Path $taskEvidence 'source5ab-dependency-contract-audit-20261015.json'))+@(Get-ChildItem -LiteralPath $taskSourceProof -File|ForEach-Object FullName)+@($taskSourceControls|ForEach-Object path))
if($Phase-eq'Runtime'){
 $taskArtifacts=Get-Content -LiteralPath $taskArtifactManifest -Raw|ConvertFrom-Json
 if($taskArtifacts.candidate_head-cne$CandidateHead-or@(Check-Rows $taskArtifacts.files).Count){throw 'Exact successful compile executable/PDB identities required'}
 if(($taskArtifacts.physical|ConvertTo-Json -Depth 5 -Compress)-cne($taskPhysical|ConvertTo-Json -Depth 5 -Compress)){throw 'Retained Source physical metadata changed between phases'}
 $taskCompilePost=Get-Content -LiteralPath $taskArtifacts.compile_posthash -Raw|ConvertFrom-Json
 if(@($taskCompilePost.PSObject.Properties|Where-Object{$_.Name-like'*_drift'-and$_.Value-ne0}).Count){throw 'Successful compile full post-zero required'}
 $taskCompileOwner=Get-Content -LiteralPath $taskArtifacts.compile_owner -Raw|ConvertFrom-Json
 if($taskCompileOwner.status-cne'passed'-or!$taskCompileOwner.owned_root_absent){throw 'Compile must be terminal passed and absent'}
 $taskControls=@($taskControls)+@($taskArtifacts.files)+@(Hash-Paths @($taskArtifactManifest,$taskArtifacts.metadata_path,$taskArtifacts.compile_posthash,$taskArtifacts.compile_owner))
}
$taskFrozen=[ordered]@{candidate=$taskCandidate;compiler=$taskCompilerRows;reference=$taskReference;dependencies=$taskDependencies;node=$taskNode;controls=$taskControls;physical=$taskPhysical}
foreach($set in $taskFrozen.Values){if(@(Check-Rows $set).Count){throw 'Fresh complete prehash drift'}}
if((Absence-Drift)-or(Inventory-Drift $taskReference (Source-Paths $taskSource))-or(Inventory-Drift $taskCompilerRows @(Get-ChildItem -LiteralPath $taskCompiler -Recurse -Force -File|ForEach-Object FullName))){throw 'Fresh Source/compiler inventory or absence drift'}
if((Inventory-Drift $taskDependencies (Dependency-Paths))-or(Inventory-Drift $taskNode (Node-Paths))){throw 'Fresh dependency/Node inventory drift'}
if((& git -c gc.auto=0 -c maintenance.auto=false -C $taskSource rev-parse HEAD).Trim()-cne'5ab7fe74c400097b386662205cd93900695b8a71'){throw 'Exact latest Source head changed'}
$taskFrozen|ConvertTo-Json -Depth 7|Set-Content -LiteralPath "$taskReceipt-prehash.json" -Encoding utf8NoBOM
$taskFree=Assert-Memory
[ordered]@{status='admitted';phase=$Phase;slot=4;root_grant=$RootGrant;candidate_head=$CandidateHead;free_kib=$taskFree;required_kib=16MB;max_normal_jobs=4;jobs=1;compile_seconds=1320;runtime_seconds=300;per_test_seconds=120;settle_seconds=10;source_cases=22;physical_paths=31;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath "$taskReceipt-admission.json" -Encoding utf8NoBOM
$taskFailure=$null;$taskMetadata=$null;$taskFiles=$null;$taskPost=$null
try{
 if($Phase-eq'Compile'){
  & $taskOwner -Executable (Join-Path $taskCompiler 'zig.exe') -WorkingDirectory $taskRoot -Arguments @('build','build-native-fs-metadata','-Doptimize=Debug','-j1','--prefix',$taskPrefix,'--summary','all') -ReceiptBase $taskReceipt -TimeoutSeconds 1320
  $taskInstalled=@(Get-ChildItem -LiteralPath (Join-Path $taskPrefix 'bin') -File|Where-Object {$_.Extension -in '.exe','.pdb'}|ForEach-Object FullName)
  if($taskInstalled.Count-ne2-or!(Test-Path -LiteralPath (Join-Path $taskPrefix 'bin\test.exe'))-or!(Test-Path -LiteralPath (Join-Path $taskPrefix 'bin\test.pdb'))){throw 'Exact installed test executable and PDB required'}
  $taskCached=@(Get-ChildItem -LiteralPath (Join-Path $taskRoot '.zig-cache\o') -Recurse -File -Filter test.exe|ForEach-Object FullName)
  if($taskCached.Count-ne1){throw 'Exactly one focused actual cached test executable required'}
  if((Get-FileHash -LiteralPath $taskCached[0]).Hash-cne(Get-FileHash -LiteralPath (Join-Path $taskPrefix 'bin\test.exe')).Hash){throw 'Installed and actual run executable differ'}
  $taskCachedPdb=[IO.Path]::ChangeExtension($taskCached[0],'.pdb');if(!(Test-Path -LiteralPath $taskCachedPdb)){throw 'Actual cached test PDB required'}
  if((Get-FileHash -LiteralPath $taskCachedPdb).Hash-cne(Get-FileHash -LiteralPath (Join-Path $taskPrefix 'bin\test.pdb')).Hash){throw 'Installed and actual run PDB differ'}
  $taskFiles=Hash-Paths @($taskInstalled+$taskCached+@($taskCachedPdb))
  $null=Assert-Memory
  $taskMetadata=Read-RevisionMetadata (Join-Path $taskPrefix 'bin\test.exe') "$taskReceipt-metadata"
  $taskMetadata|ConvertTo-Json -Depth 7|Set-Content -LiteralPath "$taskReceipt-metadata-inventory.json" -Encoding utf8NoBOM
  if(@(Check-Rows $taskFiles).Count){throw 'Actual executable/PDB changed during metadata query'}
 }else{
  & $taskOwner -Executable (Join-Path $taskCompiler 'zig.exe') -WorkingDirectory $taskRoot -Arguments @('build','test-native-fs-metadata','-Doptimize=Debug','-j1','--prefix',$taskPrefix,'--test-timeout','120s','--seed','0','--summary','all') -ReceiptBase $taskReceipt -TimeoutSeconds 300
  if(@(Check-Rows $taskArtifacts.files).Count){throw 'Actual executable/PDB changed during runtime'}
  $taskLog=[IO.File]::ReadAllText("$taskReceipt.stdout.log")+[IO.File]::ReadAllText("$taskReceipt.stderr.log")
  $count=$taskArtifacts.metadata.total_count
  if($taskLog-notmatch("(?m)^Build Summary:.*\b"+$count+'/'+$count+' tests passed')-or$taskLog-match'(?i)\bskip(?:ped)?\b'){throw 'Every actual selected test must execute and pass without a skip'}
 }
}catch{$taskFailure=$_.Exception.Message}
finally{
 $taskPost=[ordered]@{candidate_head=$CandidateHead;phase=$Phase;failure=$taskFailure}
 foreach($pair in $taskFrozen.GetEnumerator()){$taskPost[$pair.Key+'_files']=@($pair.Value).Count;$taskPost[$pair.Key+'_drift']=@(Check-Rows $pair.Value).Count}
 $taskPost.absence_records=84;$taskPost.absence_drift=Absence-Drift
 $taskPost.candidate_inventory_drift=Inventory-Drift $taskCandidate (Candidate-Paths)
 $taskPost.compiler_inventory_drift=Inventory-Drift $taskCompilerRows @(Get-ChildItem -LiteralPath $taskCompiler -Recurse -Force -File|ForEach-Object FullName)
 $taskPost.source_inventory_drift=Inventory-Drift $taskReference (Source-Paths $taskSource)
 $taskPost.dependencies_inventory_drift=Inventory-Drift $taskDependencies (Dependency-Paths)
 $taskPost.node_inventory_drift=Inventory-Drift $taskNode (Node-Paths)
 try{$taskPhysicalAfter=Assert-Physical;if(($taskPhysicalAfter|ConvertTo-Json -Depth 5 -Compress)-cne($taskPhysical|ConvertTo-Json -Depth 5 -Compress)){throw 'Physical metadata changed during phase'};$taskPost.physical_stat_content_guard_drift=0}catch{$taskPost.physical_stat_content_guard_drift=1;$taskPost.physical_error=$_.Exception.Message}
 $taskPost.completed_utc=[DateTimeOffset]::UtcNow.ToString('o')
 $taskPost|ConvertTo-Json -Depth 7|Set-Content -LiteralPath "$taskReceipt-posthash.json" -Encoding utf8NoBOM
}
if(@($taskPost.Keys|Where-Object{$_-like'*_drift'-and$taskPost[$_]-ne0}).Count){throw 'Complete native pair posthash/inventory/physical drift'}
Assert-Candidate
if($taskFailure){throw $taskFailure}
$taskTerminal=Get-Content -LiteralPath "$taskReceipt.process.json" -Raw|ConvertFrom-Json
if($taskTerminal.status-cne'passed'-or!$taskTerminal.owned_root_absent){throw 'Owned phase must pass and be absent'}
if($Phase-eq'Compile'){
 [ordered]@{candidate_head=$CandidateHead;compile_owner="$taskReceipt.process.json";compile_posthash="$taskReceipt-posthash.json";metadata_path="$taskReceipt-metadata-inventory.json";metadata=$taskMetadata;files=$taskFiles;physical=$taskPhysical;created_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $taskArtifactManifest -Encoding utf8NoBOM
}
[ordered]@{status='passed';phase=$Phase;candidate_head=$CandidateHead;owner="$taskReceipt.process.json";posthash="$taskReceipt-posthash.json";artifacts=$taskArtifactManifest;source_cases=22;authored_tests=1;native_tests_executed=if($Phase-eq'Runtime'){$taskArtifacts.metadata.total_count}else{0};skips=0}|ConvertTo-Json -Depth 5



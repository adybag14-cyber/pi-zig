param([Parameter(Mandatory)][ValidateSet('Compile','Runtime')][string]$Phase,[Parameter(Mandatory)][string]$Attempt,[Parameter(Mandatory)][ValidateRange(1,4)][int]$Slot)
$ErrorActionPreference='Stop'
$taskRoot='C:/Users/adyba/pi-zig-sdk-factory-production-20261015'
$taskEvidence='C:/Users/adyba/pi-zig-update-evidence-20261003'
$taskProof=$PSScriptRoot
$taskCompiler='C:/Users/adyba/pi-zig-toolchain-20261003/zig-x86_64-windows-0.16.0'
$taskSource='C:/Users/adyba/pi-upstream-source-4954d76-20261015'
$taskName="sdk-runtime-credentials-$($Phase.ToLower())-$Attempt-20261015"
$taskOwner=Join-Path $taskEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1'
$taskExpected=Join-Path $taskRoot 'src/extensions/fixtures/sdk-runtime-credentials-4954.json'
function Check-Rows($rows){@($rows|Where-Object{!(Test-Path -LiteralPath $_.path -PathType Leaf)-or (Get-FileHash -LiteralPath $_.path).Hash -ine $_.sha256})}
function Hash-Paths($paths){@($paths|Sort-Object -Unique|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})}
function Source-Paths([string]$directory){foreach($entry in Get-ChildItem -LiteralPath $directory -Force){if($entry.PSIsContainer){if($entry.Name -notin @('.git','node_modules')){if($entry.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Unexpected immutable Source reparse point'};Source-Paths $entry.FullName}}else{if($entry.Name -ne '.git'){$entry.FullName}}}}
function Source-Inventory-Drift($reference){$expected=@($reference|ForEach-Object{[IO.Path]::GetFullPath($_.path)}|Sort-Object);$actual=@(Source-Paths $taskSource|Sort-Object);@(Compare-Object $expected $actual).Count}
if(Test-Path -LiteralPath (Join-Path $taskEvidence "$taskName.json")){throw 'Fresh unique owner required'}
if((Get-FileHash -LiteralPath $taskExpected).Hash -cne '8009D51A3681204FFAAD8B44D33E38F21C8A2244A5766C9E09472FDC0B400184'){throw 'Only accepted actual latest Source20 expected is admitted'}
$taskHead=git -C $taskRoot rev-parse HEAD
$taskCandidate=Hash-Paths @(git -C $taskRoot ls-files|ForEach-Object{Join-Path $taskRoot $_})
$taskReference=@(Get-Content -LiteralPath (Join-Path $taskEvidence 'source4954-full-manifest-20261015.json') -Raw|ConvertFrom-Json)
$taskDependencies=@(Get-Content -LiteralPath (Join-Path $taskEvidence 'source4954-runtime-manifest-20261015.json') -Raw|ConvertFrom-Json)
$taskNode=@(Get-Content -LiteralPath (Join-Path $taskEvidence 'source4954-node-tools-before-20261015.json') -Raw|ConvertFrom-Json)
if($taskReference.Count -ne 1970 -or $taskDependencies.Count -ne 31064 -or $taskNode.Count -ne 1774){throw 'Complete actual4954 input universe required'}
$taskAudit=Get-Content -LiteralPath (Join-Path $taskEvidence 'source4954-dependency-contract-audit-20261015.json') -Raw|ConvertFrom-Json
$taskAbsences=@($taskAudit.pins|Where-Object{$_.status -eq 'platform_optional_absent'}|ForEach-Object{$_.path})+@($taskAudit.mismatches|ForEach-Object{$_.path})
if($taskAbsences.Count -ne 84){throw 'Exactly84 declared absent packages required'}
function Absence-Drift(){@($taskAbsences|Where-Object{(Test-Path -LiteralPath (Join-Path $taskSource $_))-or(Test-Path -LiteralPath (Join-Path 'C:/Users/adyba/pi-upstream-runtime-19cb534-20261012' $_))}).Count}
$taskQualificationPath=Join-Path $taskProof 'source-qualification.json'
$taskQualification=Get-Content -LiteralPath $taskQualificationPath -Raw|ConvertFrom-Json
$taskSourceArchive=Join-Path $taskProof 'source-full-prehash.zip'
if((Get-FileHash -LiteralPath $taskSourceArchive).Hash -cne $taskQualification.archive_sha256){throw 'Accepted Source20 full-prehash archive changed'}
$taskZip=[IO.Compression.ZipFile]::OpenRead($taskSourceArchive)
try{$taskEntry=$taskZip.GetEntry('sdk-runtime-credentials-source20-first-7b52ce14-20261015-prehash.json');if(!$taskEntry){throw 'Complete actual Source20 freeze missing'};$taskReader=[IO.StreamReader]::new($taskEntry.Open());try{$taskSourceFreeze=$taskReader.ReadToEnd()|ConvertFrom-Json}finally{$taskReader.Dispose()}}finally{$taskZip.Dispose()}
$taskCompilerRows=@($taskSourceFreeze.compiler)
if($taskCompilerRows.Count -ne 19546 -or @(Check-Rows $taskCompilerRows).Count){throw 'Exact pinned full compiler changed since Source20 freeze'}
$taskControls=Hash-Paths @($PSCommandPath,$taskOwner,$taskExpected,(Join-Path $taskRoot 'src/extensions/fixtures/sdk-runtime-credentials-4954.input.txt'),(Join-Path $taskRoot 'src/extensions/native_sdk_runtime_credentials_production.zig'),(Join-Path $taskRoot 'src/native_sdk_runtime_credentials_production_test.zig'),(Join-Path $taskRoot 'build.zig'),(Join-Path $taskEvidence 'source4954-full-manifest-20261015.json'),(Join-Path $taskEvidence 'source4954-runtime-manifest-20261015.json'),(Join-Path $taskEvidence 'source4954-node-tools-before-20261015.json'),(Join-Path $taskEvidence 'source4954-dependency-contract-audit-20261015.json'))
$taskControls=@($taskControls)+@(Hash-Paths @($taskQualificationPath,$taskSourceArchive))
$taskPrefix=Join-Path (Join-Path $taskProof 'native-debug') $taskHead
$taskArtifactManifest=Join-Path $taskPrefix 'artifacts.json'
if($Phase -eq 'Runtime'){
 $taskArtifacts=Get-Content -LiteralPath $taskArtifactManifest -Raw|ConvertFrom-Json
 if($taskArtifacts.candidate_head -cne $taskHead -or @(Check-Rows $taskArtifacts.files).Count){throw 'Matching exact candidate compile exe/PDB required'}
 $taskControls=@($taskControls)+@($taskArtifacts.files)+@(Hash-Paths @($taskArtifactManifest))
}
foreach($taskSet in @($taskReference,$taskDependencies,$taskNode)){if(@(Check-Rows $taskSet).Count){throw 'Frozen Source/dependency/Node prehash drift'}}
if((Absence-Drift)-or(Source-Inventory-Drift $taskReference)){throw 'Source inventory/absence prehash drift'}
$taskFrozen=[ordered]@{candidate=$taskCandidate;reference=$taskReference;dependencies=$taskDependencies;node=$taskNode;compiler=$taskCompilerRows;controls=$taskControls}
$taskFrozen|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $taskProof "$taskName-prehash.json") -Encoding utf8NoBOM
$taskFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
if($taskFree -lt 16MB){throw 'Fresh16GiB memory admission denied'}
@{status='admitted';phase=$Phase;slot=$Slot;candidate_head=$taskHead;free_kib=$taskFree;required_kib=16MB;max_normal_jobs=4;jobs=1;compile_deadline=1320;runtime_deadline=120;guest_settle_ms=10000;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskProof "$taskName-admission.json") -Encoding utf8NoBOM
try{
 if($Phase -eq 'Compile'){
  & $taskOwner -Name $taskName -Executable (Join-Path $taskCompiler 'zig.exe') -WorkingDirectory $taskRoot -Arguments @('build','build-native-sdk-runtime-credentials-production','-Doptimize=Debug','-j1','--prefix',$taskPrefix) -TimeoutSeconds 1320
 }else{
  & $taskOwner -Name $taskName -Executable (Join-Path $taskPrefix 'bin/sdk-runtime-credentials-production-test.exe') -WorkingDirectory $taskRoot -Arguments @('--seed=0') -TimeoutSeconds 120
 }
}finally{
 $taskPost=[ordered]@{}
 foreach($taskPair in $taskFrozen.GetEnumerator()){$taskPost[$taskPair.Key+'_files']=@($taskPair.Value).Count;$taskPost[$taskPair.Key+'_drift']=@(Check-Rows $taskPair.Value).Count}
 $taskPost.declared_absent_records=84;$taskPost.absence_drift=Absence-Drift;$taskPost.source_inventory_drift=Source-Inventory-Drift $taskReference
 $taskPost.completed_utc=[DateTimeOffset]::UtcNow.ToString('o')
 $taskPost|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskProof "$taskName-posthash.json") -Encoding utf8NoBOM
 foreach($taskKey in $taskPost.Keys){if($taskKey -like '*_drift' -and $taskPost[$taskKey]){throw 'Frozen input drift'}}
}
$taskReceipt=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName.json") -Raw|ConvertFrom-Json
if($taskReceipt.status -cne 'passed'){throw 'Owned native phase failed; preserve its negative'}
if($Phase -eq 'Compile'){
 $taskFiles=Hash-Paths @(Get-ChildItem -LiteralPath (Join-Path $taskPrefix 'bin') -File|ForEach-Object{$_.FullName})
 @{candidate_head=$taskHead;files=$taskFiles}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $taskArtifactManifest -Encoding utf8NoBOM
}
@{status='passed';phase=$Phase;owner=$taskReceipt;posthash=$taskPost;artifact_manifest=$taskArtifactManifest}|ConvertTo-Json -Depth 7

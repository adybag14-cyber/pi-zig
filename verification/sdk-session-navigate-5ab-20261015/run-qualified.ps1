param([Parameter(Mandatory)][ValidateSet('Source','Compile','Runtime')][string]$Phase,[Parameter(Mandatory)][string]$Attempt,[Parameter(Mandatory)][ValidateRange(1,5)][int]$Slot)
$ErrorActionPreference='Stop'
if($Slot -eq 5 -and $Phase -ne 'Source'){throw 'Light slot5 permits Source capture only'}
$taskRoot='C:/Users/adyba/pi-zig-sdk-navigate-20261015'
$taskEvidence='C:/Users/adyba/pi-zig-update-evidence-20261003'
$taskProof=$PSScriptRoot
$taskName="sdk-navigate-$($Phase.ToLower())-$Attempt-20261015"
$taskSource='C:/Users/adyba/pi-upstream-source-5ab7fe7-20261015'
$taskCompiler='C:/Users/adyba/pi-zig-toolchain-20261003/zig-x86_64-windows-0.16.0'
$taskOwner=Join-Path $taskEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1'
function Check-Rows($rows){@($rows|Where-Object{!(Test-Path -LiteralPath $_.path -PathType Leaf)-or (Get-FileHash -LiteralPath $_.path).Hash -ine $_.sha256})}
function Hash-Paths($paths){@($paths|Sort-Object -Unique|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})}
if(Test-Path -LiteralPath (Join-Path $taskProof "$taskName-posthash.json")){throw 'Fresh unique attempt required'}
$taskCandidatePaths=@(git -C $taskRoot ls-files|ForEach-Object{Join-Path $taskRoot $_})+@(Get-ChildItem -LiteralPath (Join-Path $taskRoot 'src') -File -Recurse|Where-Object{$_.Name -match '^native_sdk_(session_navigate|branch_summary)' -or $_.Name -match '^branch_summary_(prompt|preamble)_5ab\.txt$' -or $_.Name -like 'sdk-session-navigate-5ab*'}|ForEach-Object{$_.FullName})+@((Join-Path $taskProof 'capture-source.mjs'),$PSCommandPath)
$taskCandidate=Hash-Paths $taskCandidatePaths
$taskReference=@(Get-Content -LiteralPath (Join-Path $taskEvidence 'source5ab-full-manifest-20261015.json') -Raw|ConvertFrom-Json)
$taskDependencies=@(Get-Content -LiteralPath (Join-Path $taskEvidence 'durable-19cb534-reference-20261012-all-built-runtime.json') -Raw|ConvertFrom-Json)
$taskNode=@(Get-Content -LiteralPath (Join-Path $taskEvidence 'root-current8a-npm-tools-before.json') -Raw|ConvertFrom-Json)
if($taskReference.Count -ne 1967 -or $taskDependencies.Count -ne 31064 -or $taskNode.Count -ne 1774){throw 'Complete pinned input universe required'}
$taskCompilerRows=Hash-Paths @(Get-ChildItem -LiteralPath $taskCompiler -Recurse -File|ForEach-Object{$_.FullName})
$taskControls=Hash-Paths @($PSCommandPath,(Join-Path $taskProof 'capture-source.mjs'),(Join-Path $taskRoot 'src/extensions/fixtures/sdk-session-navigate-5ab.input.txt'),$taskOwner,(Join-Path $taskEvidence 'source5ab-observe-20261015.mjs'),(Join-Path $taskEvidence 'source5ab-full-manifest-20261015.json'),(Join-Path $taskEvidence 'source5ab-dependency-contract-audit-20261015.json'),(Join-Path $taskEvidence 'durable-19cb534-reference-20261012-all-built-runtime.json'),(Join-Path $taskEvidence 'root-current8a-npm-tools-before.json'))
$taskArtifactManifest=Join-Path $taskProof 'native-debug/artifacts.json'
if($Phase -eq 'Runtime'){
 $taskArtifacts=@(Get-Content -LiteralPath $taskArtifactManifest -Raw|ConvertFrom-Json)
 if(!$taskArtifacts.Count -or @(Check-Rows $taskArtifacts).Count){throw 'Matching compile artifact required before runtime'}
 $taskControls=@($taskControls)+@($taskArtifacts)+@(Hash-Paths @($taskArtifactManifest))
}
foreach($taskSet in @($taskReference,$taskDependencies,$taskNode)){if(@(Check-Rows $taskSet).Count){throw 'Pinned reference dependency or Node tool prehash drift'}}
$taskFrozen=[ordered]@{candidate=$taskCandidate;reference=$taskReference;dependencies=$taskDependencies;node=$taskNode;compiler=$taskCompilerRows;controls=$taskControls}
$taskFrozen|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $taskProof "$taskName-prehash.json") -Encoding utf8NoBOM
$taskControls|ConvertTo-Json -Depth 4|Set-Content -LiteralPath (Join-Path $taskProof "$taskName-oracle-controls.json") -Encoding utf8NoBOM
$taskRequiredKiB=if($Phase -eq 'Source'){2MB}else{16MB}
$taskFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
if($taskFree -lt $taskRequiredKiB){throw 'Fresh memory admission denied'}
@{status='admitted';phase=$Phase;slot=$Slot;light_source_slot=($Slot -eq 5);free_kib=$taskFree;required_kib=$taskRequiredKiB;max_normal_jobs=4;heap_mb=if($Phase -eq 'Source'){256}else{$null};observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskProof "$taskName-admission.json") -Encoding utf8NoBOM
$taskExpected=Join-Path $taskRoot 'src/extensions/fixtures/sdk-session-navigate-5ab.json'
$taskOutput=Join-Path $taskProof "$taskName-output.json"
try{
 if($Phase -eq 'Source'){
  & $taskOwner -Name $taskName -Executable 'C:/Program Files/nodejs/node.exe' -WorkingDirectory $taskSource -Arguments @('--max-old-space-size=256','--import',([Uri](Join-Path $taskEvidence 'source5ab-observe-20261015.mjs')).AbsoluteUri,(Join-Path $taskProof 'capture-source.mjs'),$taskOutput,(Join-Path $taskRoot 'src/extensions/fixtures/sdk-session-navigate-5ab.input.txt')) -TimeoutSeconds 300 -EnvironmentOverrides @{NODE_OPTIONS='';NODE_PATH='';PI_SOURCE_ORACLE_CONTROL_MANIFEST=(Join-Path $taskProof "$taskName-oracle-controls.json")}
 }elseif($Phase -eq 'Compile'){
  & $taskOwner -Name $taskName -Executable (Join-Path $taskCompiler 'zig.exe') -WorkingDirectory $taskRoot -Arguments @('build','build-native-sdk-session-navigate','-Doptimize=Debug','-j1','--prefix',(Join-Path $taskProof 'native-debug')) -TimeoutSeconds 1320
 }else{
  $taskExecutable=Join-Path $taskProof 'native-debug/bin/sdk-session-navigate-test.exe'
  $taskBinaryHash=(Get-FileHash -LiteralPath $taskExecutable).Hash
  & $taskOwner -Name $taskName -Executable $taskExecutable -WorkingDirectory $taskRoot -Arguments @('--seed=0') -TimeoutSeconds 120
 }
}finally{
 $taskPost=[ordered]@{}
 foreach($taskPair in $taskFrozen.GetEnumerator()){$taskPost[$taskPair.Key+'_files']=@($taskPair.Value).Count;$taskPost[$taskPair.Key+'_drift']=@(Check-Rows $taskPair.Value).Count}
 $taskPost.completed_utc=[DateTimeOffset]::UtcNow.ToString('o')
 $taskPost|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskProof "$taskName-posthash.json") -Encoding utf8NoBOM
 foreach($taskKey in $taskPost.Keys){if($taskKey -like '*_drift' -and $taskPost[$taskKey]){throw 'Frozen input drift'}}
}
$taskReceipt=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName.json") -Raw|ConvertFrom-Json
if($taskReceipt.status -cne 'passed'){throw 'Owned job did not pass'}
if($Phase -eq 'Source'){
 $taskCapture=Get-Content -LiteralPath $taskOutput -Raw|ConvertFrom-Json
 if($taskCapture.cases -ne 56 -or $taskCapture.sourceHead -cne '5ab7fe74c400097b386662205cd93900695b8a71'){throw 'Incomplete Source artifact'}
 Copy-Item -LiteralPath $taskOutput -Destination $taskExpected
}elseif($Phase -eq 'Compile'){
 $taskArtifacts=Hash-Paths @(Get-ChildItem -LiteralPath (Join-Path $taskProof 'native-debug/bin') -File|ForEach-Object{$_.FullName})
 $taskArtifacts|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $taskArtifactManifest -Encoding utf8NoBOM
}
[ordered]@{status='passed';phase=$Phase;owner=$taskReceipt;input_posthash=$taskPost;output=if($Phase -eq 'Source'){$taskExpected}elseif($Phase -eq 'Runtime'){$taskExecutable}else{Join-Path $taskProof 'native-debug/bin/sdk-session-navigate-test.exe'}}|ConvertTo-Json -Depth 7

param([Parameter(Mandatory)][string]$Attempt)
$ErrorActionPreference='Stop'
$taskRoot='C:/Users/adyba/pi-zig-sdk-boundaries-20261015'
$taskEvidence='C:/Users/adyba/pi-zig-update-evidence-20261003'
$taskSource='C:/Users/adyba/pi-upstream-source-5ab7fe7-20261015'
$taskCompiler='C:/Users/adyba/pi-zig-toolchain-20261003/zig-x86_64-windows-0.16.0'
$taskName="sdk-prototype-5ab-$Attempt-20261015"
$taskDriver=Join-Path $PSScriptRoot 'capture-prototype-5ab.mjs'
$taskHistorical=Join-Path $taskRoot 'src/extensions/fixtures/sdk-session-prototype-original-e622.json'
$taskObserver=Join-Path $taskEvidence 'source5ab-observe-20261015.mjs'
$taskOwner=Join-Path $taskEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1'
function Hash-Paths($paths){@($paths|Sort-Object -Unique|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})}
function Check-Rows($rows){@($rows|Where-Object{!(Test-Path -LiteralPath $_.path -PathType Leaf)-or (Get-FileHash -LiteralPath $_.path).Hash -ine $_.sha256})}
if(Test-Path -LiteralPath (Join-Path $PSScriptRoot "$taskName-posthash.json")){throw 'Fresh unique attempt required'}
if((git -C $taskSource rev-parse HEAD).Trim() -cne '5ab7fe74c400097b386662205cd93900695b8a71'){throw 'Immutable latest Source head mismatch'}
if((Get-FileHash -LiteralPath $taskObserver).Hash -ine '6261264d0a4d3d82b36e12b6675cc59fcc74ace1a1e92a225703a24285dcf017'){throw 'Latest admitted observer mismatch'}
$taskTracked=@(git -C $taskRoot ls-files|ForEach-Object{Join-Path $taskRoot $_})
$taskPrepared=@(Get-ChildItem -LiteralPath (Join-Path $taskRoot 'src') -Recurse -File|Where-Object{$_.Name -like '*boundar*ownership*' -or $_.Name -like 'sdk-session-boundaries-5ab-posix*'}|ForEach-Object{$_.FullName})+@(Get-ChildItem -LiteralPath $PSScriptRoot -File|Where-Object{$_.Extension -eq '.mjs' -or $_.Name -in @('run-prototype-qualified.ps1','integration-not-applied.patch')}|ForEach-Object{$_.FullName})
$taskCandidate=Hash-Paths @($taskTracked+$taskPrepared)
$taskReference=@(Get-Content -LiteralPath (Join-Path $taskEvidence 'source5ab-full-manifest-20261015.json') -Raw|ConvertFrom-Json)
$taskDependencies=@(Get-Content -LiteralPath (Join-Path $taskEvidence 'durable-19cb534-reference-20261012-all-built-runtime.json') -Raw|ConvertFrom-Json)
$taskNode=@(Get-Content -LiteralPath (Join-Path $taskEvidence 'root-current8a-npm-tools-before.json') -Raw|ConvertFrom-Json)
if($taskReference.Count -ne 1967 -or $taskDependencies.Count -ne 31064 -or $taskNode.Count -ne 1774){throw 'Full reference/dependency/Node universe required'}
$taskCompilerRows=Hash-Paths @(Get-ChildItem -LiteralPath $taskCompiler -Recurse -File|ForEach-Object{$_.FullName})
$taskControls=Hash-Paths @($PSCommandPath,$taskDriver,$taskHistorical,$taskObserver,$taskOwner,(Join-Path $taskEvidence 'source5ab-full-manifest-20261015.json'),(Join-Path $taskEvidence 'source5ab-dependency-contract-audit-20261015.json'),(Join-Path $taskEvidence 'durable-19cb534-reference-20261012-all-built-runtime.json'),(Join-Path $taskEvidence 'root-current8a-npm-tools-before.json'))
foreach($taskSet in @($taskReference,$taskDependencies,$taskNode)){if(@(Check-Rows $taskSet).Count){throw 'Reference/dependency/Node prehash drift'}}
$taskFrozen=[ordered]@{candidate=$taskCandidate;reference=$taskReference;dependencies=$taskDependencies;node=$taskNode;compiler=$taskCompilerRows;controls=$taskControls}
$taskFrozen|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $PSScriptRoot "$taskName-prehash.json") -Encoding utf8NoBOM
$taskControls|ConvertTo-Json -Depth 4|Set-Content -LiteralPath (Join-Path $PSScriptRoot "$taskName-oracle-controls.json") -Encoding utf8NoBOM
$taskFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
if($taskFree -lt 2MB){throw 'Fresh2GiB Source admission denied'}
@{status='admitted';slot=3;free_kib=$taskFree;required_kib=2MB;heap_mb=256;outer_seconds=300;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $PSScriptRoot "$taskName-admission.json") -Encoding utf8NoBOM
$taskInventory=Join-Path $PSScriptRoot "$taskName-inventory.raw.json"
$taskDelta=Join-Path $PSScriptRoot "$taskName-delta.raw.json"
try{
 & $taskOwner -Name $taskName -Executable 'C:/Program Files/nodejs/node.exe' -WorkingDirectory $taskSource -Arguments @('--max-old-space-size=256','--import',([Uri]$taskObserver).AbsoluteUri,$taskDriver,$taskInventory,$taskDelta,$taskHistorical,$taskSource,'win32') -TimeoutSeconds 300 -EnvironmentOverrides @{NODE_OPTIONS='';NODE_PATH='';PI_SOURCE_ORACLE_CONTROL_MANIFEST=(Join-Path $PSScriptRoot "$taskName-oracle-controls.json")}
}finally{
 $taskPost=[ordered]@{}
 foreach($taskPair in $taskFrozen.GetEnumerator()){$taskPost[$taskPair.Key+'_files']=@($taskPair.Value).Count;$taskPost[$taskPair.Key+'_drift']=@(Check-Rows $taskPair.Value).Count}
 $taskPost.completed_utc=[DateTimeOffset]::UtcNow.ToString('o')
 $taskPost|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $PSScriptRoot "$taskName-posthash.json") -Encoding utf8NoBOM
 foreach($taskKey in $taskPost.Keys){if($taskKey -like '*_drift' -and $taskPost[$taskKey]){throw 'Frozen prototype input drift'}}
}
$taskReceipt=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName.json") -Raw|ConvertFrom-Json
if($taskReceipt.status -cne 'passed'){throw 'Prototype Source owner did not pass'}
$taskActual=Get-Content -LiteralPath $taskInventory -Raw|ConvertFrom-Json
$taskCompared=Get-Content -LiteralPath $taskDelta -Raw|ConvertFrom-Json
if($taskActual.source -cne '5ab7fe74c400097b386662205cd93900695b8a71' -or $taskCompared.historicalCount -ne 166){throw 'Actual latest/historical prototype authority invalid'}
Copy-Item -LiteralPath $taskInventory -Destination (Join-Path $taskRoot 'src/extensions/fixtures/sdk-session-prototype-original-5ab.json')
Copy-Item -LiteralPath $taskDelta -Destination (Join-Path $PSScriptRoot 'prototype-5ab-versus-e622-delta.json')
[ordered]@{status='passed-post0';owner=$taskReceipt;inventory_sha256=(Get-FileHash -LiteralPath $taskInventory).Hash;delta=$taskCompared;posthash=$taskPost}|ConvertTo-Json -Depth 8

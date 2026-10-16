param(
 [Parameter(Mandatory)][string]$SlotGrant,
 [Parameter(Mandatory)][string]$Attempt,
 [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{40}$')][string]$CandidateHead
)
$ErrorActionPreference='Stop'
$taskPrivate='C:\Users\adyba\pi-zig-sdk-fs-metadata-20261016'
$taskEvidence='C:\Users\adyba\pi-zig-update-evidence-20261003'
$taskCompiler='C:\Users\adyba\pi-zig-toolchain-20261003\zig-x86_64-windows-0.16.0'
$taskSource='C:\Users\adyba\pi-upstream-source-5ab7fe7-20261015'
$taskRuntime='C:\Users\adyba\pi-upstream-runtime-19cb534-20261012'
$taskPrefix=Join-Path $taskEvidence "node-fs-metadata-24-source-$Attempt-20261016-wrapper"
function Candidate-Paths {@(& git -c gc.auto=0 -c maintenance.auto=false -C $taskPrivate ls-files|ForEach-Object{[IO.Path]::GetFullPath((Join-Path $taskPrivate $_))})}
function Compiler-Paths {@(Get-ChildItem -LiteralPath $taskCompiler -Recurse -Force -File|ForEach-Object FullName)}
function Source-Paths([string]$directory){foreach($entry in Get-ChildItem -LiteralPath $directory -Force){if($entry.Name -in @('.git','node_modules')){continue};if($entry.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Source reparse entry'};if($entry.PSIsContainer){Source-Paths $entry.FullName}else{$entry.FullName}}}
function Dependency-Paths {@(Get-ChildItem -LiteralPath $taskRuntime -Recurse -Force -File|Where-Object{$_.FullName-notmatch '[\\/]\.git[\\/]'}|ForEach-Object FullName)}
function Node-Paths {@('C:\Program Files\nodejs\node.exe')+@(Get-ChildItem -LiteralPath 'C:\Program Files\nodejs\node_modules\npm' -Recurse -Force -File|ForEach-Object FullName)}
function Rows($paths){@($paths|Sort-Object -Unique|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})}
function Drift($rows){@($rows|Where-Object{!(Test-Path -LiteralPath $_.path -PathType Leaf)-or(Get-FileHash -LiteralPath $_.path).Hash-ine$_.sha256})}
function Inventory-Drift($rows,$paths){@(Compare-Object @($rows|ForEach-Object path|Sort-Object) @($paths|Sort-Object)).Count}
function Assert-Candidate {if((& git -c gc.auto=0 -c maintenance.auto=false -C $taskPrivate rev-parse HEAD).Trim()-cne$CandidateHead-or@(& git -c gc.auto=0 -c maintenance.auto=false -C $taskPrivate status --porcelain).Count){throw 'Exact clean candidate required'}}
function Absence-Drift {@($taskAbsences|Where-Object{(Test-Path -LiteralPath (Join-Path $taskSource $_))-or(Test-Path -LiteralPath (Join-Path $taskRuntime $_))}).Count}
Assert-Candidate
if(Test-Path -LiteralPath "$taskPrefix-prehash.json"){throw 'Fresh immutable wrapper attempt required'}
$taskFrozen=[ordered]@{
 candidate=Rows (Candidate-Paths)
 compiler=Rows (Compiler-Paths)
 source=@(Get-Content -LiteralPath (Join-Path $taskEvidence 'source5ab-full-manifest-20261015.json') -Raw|ConvertFrom-Json)
 dependencies=@(Get-Content -LiteralPath (Join-Path $taskEvidence 'durable-19cb534-reference-20261012-all-built-runtime.json') -Raw|ConvertFrom-Json)
 node=@(Get-Content -LiteralPath (Join-Path $taskEvidence 'root-current8a-npm-tools-before.json') -Raw|ConvertFrom-Json)
}
if($taskFrozen.compiler.Count-ne19546-or$taskFrozen.source.Count-ne1967-or$taskFrozen.dependencies.Count-ne31064-or$taskFrozen.node.Count-ne1774){throw 'Full frozen universes required'}
$taskAudit=Get-Content -LiteralPath (Join-Path $taskEvidence 'source5ab-dependency-contract-audit-20261015.json') -Raw|ConvertFrom-Json
$taskAbsences=@($taskAudit.pins|Where-Object status -eq 'platform_optional_absent'|ForEach-Object path)+@($taskAudit.mismatches|ForEach-Object path)
if($taskAbsences.Count-ne84-or(Absence-Drift)){throw 'Exactly84 historical absences required'}
foreach($set in $taskFrozen.Values){if(@(Drift $set).Count){throw 'Full reference prehash drift'}}
if((Inventory-Drift $taskFrozen.source (Source-Paths $taskSource))-or(Inventory-Drift $taskFrozen.dependencies (Dependency-Paths))-or(Inventory-Drift $taskFrozen.node (Node-Paths))){throw 'Full reference inventory drift'}
$taskFrozen|ConvertTo-Json -Depth 7|Set-Content -LiteralPath "$taskPrefix-prehash.json" -Encoding utf8NoBOM
$taskSemaphore=[Threading.Semaphore]::new(4,4,'Local\PiZigOwnedValidationRoots20261015')
if(!$taskSemaphore.WaitOne(0)){$taskSemaphore.Dispose();throw 'Four coordinated roots already admitted'}
$taskFailure=$null
try {
 & (Join-Path $PSScriptRoot 'Invoke-NodeFsMetadata24Source.ps1') -SlotGrant $SlotGrant -Attempt $Attempt
}catch{$taskFailure=$_.Exception.Message}
finally {
 $null=$taskSemaphore.Release();$taskSemaphore.Dispose()
 $taskPost=[ordered]@{candidate_head=$CandidateHead;failure=$taskFailure;absence_records=84;absence_drift=Absence-Drift;candidate_inventory_drift=Inventory-Drift $taskFrozen.candidate (Candidate-Paths);compiler_inventory_drift=Inventory-Drift $taskFrozen.compiler (Compiler-Paths);source_inventory_drift=Inventory-Drift $taskFrozen.source (Source-Paths $taskSource);dependencies_inventory_drift=Inventory-Drift $taskFrozen.dependencies (Dependency-Paths);node_inventory_drift=Inventory-Drift $taskFrozen.node (Node-Paths)}
 foreach($pair in $taskFrozen.GetEnumerator()){$taskPost[$pair.Key+'_files']=$pair.Value.Count;$taskPost[$pair.Key+'_drift']=@(Drift $pair.Value).Count}
 $taskPost.completed_utc=[DateTimeOffset]::UtcNow.ToString('o')
 $taskPost|ConvertTo-Json -Depth 7|Set-Content -LiteralPath "$taskPrefix-posthash.json" -Encoding utf8NoBOM
}
if(@($taskPost.Keys|Where-Object{$_-like'*_drift'-and$taskPost[$_]-ne0}).Count){throw 'Full wrapper hash/inventory drift'}
Assert-Candidate
if($taskFailure){throw $taskFailure}
$taskInner=Get-Content -LiteralPath (Join-Path $taskEvidence "node-fs-metadata-24-source-$Attempt-20261016.json") -Raw|ConvertFrom-Json
if($taskInner.status-cne'passed'){throw 'Genuine Source child not terminal passed'}
$taskAfter=Get-CimInstance Win32_Process -Filter "ProcessId = $($taskInner.pid)"
if($taskAfter-and([DateTimeOffset]$taskAfter.CreationDate).UtcDateTime.ToString('o')-ceq$taskInner.created_utc){throw 'Genuine Source child remains owned'}
[ordered]@{status='passed';candidate_head=$CandidateHead;cases=22;owned_child_absent=$true;posthash="$taskPrefix-posthash.json"}|ConvertTo-Json

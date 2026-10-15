param([Parameter(Mandatory)][string]$Attempt,[Parameter(Mandatory)][ValidateRange(1,6)][int]$Slot)
$ErrorActionPreference='Stop'
$taskRoot='C:/Users/adyba/pi-zig-sdk-provider-composer-production-20261015'
$taskEvidence='C:/Users/adyba/pi-zig-update-evidence-20261003'
$taskSource='C:/Users/adyba/pi-upstream-source-4954d76-20261015'
$taskProof=$PSScriptRoot
$taskName="provider-composer-source28-$Attempt-20261015"
$taskOwner=Join-Path $taskEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1'
$taskCompiler='C:/Users/adyba/pi-zig-toolchain-20261003/zig-x86_64-windows-0.16.0'
$taskExpected=Join-Path $taskRoot 'src/extensions/fixtures/provider-composer-production-4954.json'
$taskOutput=Join-Path $taskProof "$taskName-output.json"
function Check-Rows($rows){@($rows|Where-Object{!(Test-Path -LiteralPath $_.path -PathType Leaf)-or (Get-FileHash -LiteralPath $_.path).Hash -ine $_.sha256})}
function Hash-Paths($paths){@($paths|Sort-Object -Unique|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})}
function Source-Paths([string]$directory){foreach($entry in Get-ChildItem -LiteralPath $directory -Force){if($entry.PSIsContainer){if($entry.Name -notin @('.git','node_modules')){if($entry.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Unexpected immutable Source reparse point'};Source-Paths $entry.FullName}}else{if($entry.Name -ne '.git'){$entry.FullName}}}}
function Source-Inventory-Drift($reference){$expected=@($reference|ForEach-Object{[IO.Path]::GetFullPath($_.path)}|Sort-Object);$actual=@(Source-Paths $taskSource|Sort-Object);@(Compare-Object $expected $actual).Count}
if(Test-Path -LiteralPath $taskExpected){throw 'First genuine Source acceptance only; preserve accepted expected and use a new explicit comparison owner for any recapture'}
if(Test-Path -LiteralPath (Join-Path $taskEvidence "$taskName.json")){throw 'Fresh unique attempt required'}
if((git -C $taskSource rev-parse HEAD) -cne '4954d760504c11df9b2cbdc040346107b6a8153d'){throw 'Latest immutable Source identity mismatch'}
$taskCandidatePaths=@(git -C $taskRoot ls-files|ForEach-Object{Join-Path $taskRoot $_})+@(
 (Join-Path $taskRoot 'src/extensions/native_provider_composer_production.zig'),
 (Join-Path $taskRoot 'src/extensions/native_resolve_config_value_production.zig'),
 (Join-Path $taskRoot 'src/extensions/fixtures/provider-composer-production-4954.input.txt')
)+@(Get-ChildItem -LiteralPath $taskProof -File|Where-Object{$_.Name -in @('capture-source.mjs','run-source-qualified.ps1','route-handoff.md')}|ForEach-Object{$_.FullName})
$taskCandidate=Hash-Paths $taskCandidatePaths
$taskReference=@(Get-Content -LiteralPath (Join-Path $taskEvidence 'source4954-full-manifest-20261015.json') -Raw|ConvertFrom-Json)
$taskDependencies=@(Get-Content -LiteralPath (Join-Path $taskEvidence 'source4954-runtime-manifest-20261015.json') -Raw|ConvertFrom-Json)
$taskNode=@(Get-Content -LiteralPath (Join-Path $taskEvidence 'source4954-node-tools-before-20261015.json') -Raw|ConvertFrom-Json)
if($taskReference.Count -ne 1970 -or $taskDependencies.Count -ne 31064 -or $taskNode.Count -ne 1774){throw 'Complete latest4954 input universe required'}
$taskAudit=Get-Content -LiteralPath (Join-Path $taskEvidence 'source4954-dependency-contract-audit-20261015.json') -Raw|ConvertFrom-Json
$taskAbsences=@($taskAudit.pins|Where-Object{$_.status -eq 'platform_optional_absent'}|ForEach-Object{$_.path})+@($taskAudit.mismatches|ForEach-Object{$_.path})
if($taskAbsences.Count -ne 84 -or $taskAudit.platform_optional_absent_records -ne 80 -or $taskAudit.historical_missing_records_retained -ne 4){throw 'Exactly84 declared absent package records required'}
function Absence-Drift(){@($taskAbsences|Where-Object{(Test-Path -LiteralPath (Join-Path $taskSource $_))-or(Test-Path -LiteralPath (Join-Path 'C:/Users/adyba/pi-upstream-runtime-19cb534-20261012' $_))}).Count}
if((Absence-Drift)-or(Source-Inventory-Drift $taskReference)){throw 'Declared absence or complete Source path inventory drift'}
$taskCompilerRows=Hash-Paths @(Get-ChildItem -LiteralPath $taskCompiler -Recurse -File|ForEach-Object{$_.FullName})
if($taskCompilerRows.Count -ne 19546){throw 'Complete19546 pinned Zig compiler universe required'}
$taskControls=Hash-Paths @($PSCommandPath,(Join-Path $taskProof 'capture-source.mjs'),(Join-Path $taskRoot 'src/extensions/fixtures/provider-composer-production-4954.input.txt'),$taskOwner,(Join-Path $taskEvidence 'source4954-observe-20261015.mjs'),(Join-Path $taskEvidence 'source4954-full-manifest-20261015.json'),(Join-Path $taskEvidence 'source4954-dependency-contract-audit-20261015.json'),(Join-Path $taskEvidence 'source4954-runtime-manifest-20261015.json'),(Join-Path $taskEvidence 'source4954-node-tools-before-20261015.json'))
foreach($taskSet in @($taskReference,$taskDependencies,$taskNode)){if(@(Check-Rows $taskSet).Count){throw 'Pinned latest Source/dependency/Node prehash drift'}}
$taskFrozen=[ordered]@{candidate=$taskCandidate;reference=$taskReference;dependencies=$taskDependencies;node=$taskNode;compiler=$taskCompilerRows;controls=$taskControls}
$taskFrozen|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $taskProof "$taskName-prehash.json") -Encoding utf8NoBOM
$taskControlManifest=Join-Path $taskProof "$taskName-oracle-controls.json"
$taskControls|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $taskControlManifest -Encoding utf8NoBOM
$taskCallerHashes=Hash-Paths @((Join-Path $taskProof 'capture-source.mjs'),(Join-Path $taskRoot 'src/extensions/fixtures/provider-composer-production-4954.input.txt'),$taskOwner,$PSCommandPath,'C:/Program Files/nodejs/node.exe',$taskControlManifest)
@{candidate_head=(git -C $taskRoot rev-parse HEAD);source_head=(git -C $taskSource rev-parse HEAD);callers=$taskCallerHashes;declared_absences=$taskAbsences;source_inventory_drift=0;absence_drift=0}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $taskProof "$taskName-launch-identity.json") -Encoding utf8NoBOM
$taskFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
if($taskFree -lt 2MB){throw 'Fresh 2GiB memory admission denied'}
@{status='admitted';slot=$Slot;source_only=$true;free_kib=$taskFree;required_kib=2MB;heap_mb=256;deadline_seconds=300;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskProof "$taskName-admission.json") -Encoding utf8NoBOM
try{
 & $taskOwner -Name $taskName -Executable 'C:/Program Files/nodejs/node.exe' -WorkingDirectory $taskSource -Arguments @('--max-old-space-size=256','--import',([Uri](Join-Path $taskEvidence 'source4954-observe-20261015.mjs')).AbsoluteUri,(Join-Path $taskProof 'capture-source.mjs'),$taskOutput,(Join-Path $taskRoot 'src/extensions/fixtures/provider-composer-production-4954.input.txt')) -TimeoutSeconds 300 -EnvironmentOverrides @{NODE_OPTIONS='';NODE_PATH='';PI_SOURCE_ORACLE_CONTROL_MANIFEST=$taskControlManifest}
}finally{
 $taskPost=[ordered]@{}
 foreach($taskPair in $taskFrozen.GetEnumerator()){$taskPost[$taskPair.Key+'_files']=@($taskPair.Value).Count;$taskPost[$taskPair.Key+'_drift']=@(Check-Rows $taskPair.Value).Count}
 $taskPost.declared_absent_records=84
 $taskPost.absence_drift=Absence-Drift
 $taskPost.source_inventory_drift=Source-Inventory-Drift $taskReference
 $taskPost.caller_identity_drift=@(Check-Rows $taskCallerHashes).Count
 $taskPost.completed_utc=[DateTimeOffset]::UtcNow.ToString('o')
 $taskPost|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskProof "$taskName-posthash.json") -Encoding utf8NoBOM
 foreach($taskKey in $taskPost.Keys){if($taskKey -like '*_drift' -and $taskPost[$taskKey]){throw 'Frozen input drift'}}
}
$taskReceipt=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName.json") -Raw|ConvertFrom-Json
if($taskReceipt.status -cne 'passed'){throw 'Owned Source job did not pass; retain negative without expected acceptance'}
$taskLive=Get-CimInstance Win32_Process -Filter "ProcessId = $($taskReceipt.pid)"
if($taskLive){throw 'Original Source owner PID still present; refuse expected acceptance'}
@{pid=$taskReceipt.pid;original_owner_absent=$true;verified_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskProof "$taskName-process-absence.json") -Encoding utf8NoBOM
Copy-Item -LiteralPath (Join-Path $taskEvidence "$taskName.json") -Destination (Join-Path $taskProof "$taskName-owner.json")
Copy-Item -LiteralPath (Join-Path $taskEvidence "$taskName.stdout.log") -Destination (Join-Path $taskProof "$taskName-stdout.log")
Copy-Item -LiteralPath (Join-Path $taskEvidence "$taskName.stderr.log") -Destination (Join-Path $taskProof "$taskName-stderr.log")
$taskObserved=Get-ChildItem -LiteralPath $taskEvidence -Filter "source4954-modules-$($taskReceipt.pid)-*-20261015.jsonl" -File
if(!$taskObserved){throw 'Missing actual Source loader observation'}
$taskObserved|ForEach-Object{Get-Content -LiteralPath $_.FullName}|Set-Content -LiteralPath (Join-Path $taskProof "$taskName-observed-modules.jsonl") -Encoding utf8NoBOM
$taskCapture=Get-Content -LiteralPath $taskOutput -Raw|ConvertFrom-Json
if($taskCapture.cases -ne 28 -or $taskCapture.sourceHead -cne '4954d760504c11df9b2cbdc040346107b6a8153d'){throw 'Incomplete actual Source28 artifact'}
Copy-Item -LiteralPath $taskOutput -Destination $taskExpected
[ordered]@{status='passed';phase='Source';owner=$taskReceipt;input_posthash=$taskPost;expected_sha256=(Get-FileHash -LiteralPath $taskExpected).Hash;output=$taskExpected}|ConvertTo-Json -Depth 7

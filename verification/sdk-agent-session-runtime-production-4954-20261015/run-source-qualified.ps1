param([Parameter(Mandatory)][string]$Attempt,[Parameter(Mandatory)][ValidateRange(1,4)][int]$RootSlot)
$ErrorActionPreference='Stop'
$taskRoot='C:/Users/adyba/pi-zig-session-runtime-production-20261015'
$taskEvidence='C:/Users/adyba/pi-zig-update-evidence-20261003'
$taskSource='C:/Users/adyba/pi-upstream-source-4954d76-20261015'
$taskProof=$PSScriptRoot
$taskName="runtime-source34-$Attempt-20261015"
$taskOwner=Join-Path $taskEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1'
$taskCompiler='C:/Users/adyba/pi-zig-toolchain-20261003/zig-x86_64-windows-0.16.0'
$taskExpected=Join-Path $taskRoot 'src/extensions/fixtures/sdk-agent-session-runtime-production-4954.json'
$taskInput=Join-Path $taskRoot 'src/extensions/fixtures/sdk-agent-session-runtime-production-4954.input.txt'
$taskOutput=Join-Path $taskProof "$taskName-output.json"
function Hash-Paths($paths){@($paths|Sort-Object -Unique|ForEach-Object{[ordered]@{path=[IO.Path]::GetFullPath($_);sha256=(Get-FileHash -LiteralPath $_).Hash}})}
function Drift($rows){@($rows|Where-Object{!(Test-Path -LiteralPath $_.path -PathType Leaf)-or(Get-FileHash -LiteralPath $_.path).Hash -ine $_.sha256})}
function Candidate-Paths(){@(git -C $taskRoot ls-files --cached --others --exclude-standard|Sort-Object -Unique|ForEach-Object{Join-Path $taskRoot $_}|Where-Object{Test-Path -LiteralPath $_ -PathType Leaf})}
function Source-Paths([string]$directory){foreach($entry in Get-ChildItem -LiteralPath $directory -Force){if($entry.PSIsContainer){if($entry.Name -notin @('.git','node_modules')){if($entry.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Immutable Source reparse point'};Source-Paths $entry.FullName}}else{if($entry.Name -ne '.git'){$entry.FullName}}}}
function Source-Inventory-Drift($reference){$expected=@($reference|ForEach-Object{[IO.Path]::GetFullPath($_.path)}|Sort-Object);$actual=@(Source-Paths $taskSource|Sort-Object);@(Compare-Object $expected $actual).Count}
function Admit(){
 $taskFree=[long](Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory*1024
 $taskBuilds=@(Get-CimInstance Win32_Process -Filter "Name='zig.exe'"|Where-Object{$_.CommandLine -match '\sbuild\s'})
 if($taskFree -lt 2GB -or $taskBuilds.Count -ge 4){throw 'Fresh2GiB/max4 admission denied'}
 [ordered]@{root_slot=$RootSlot;source_only=$true;required_bytes=2GB;free_bytes=$taskFree;other_native_build_roots=$taskBuilds.Count;max_coordinated_jobs=4;heap_mb=256;deadline_seconds=300;host_await_ms=10000;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}
}
if(Test-Path -LiteralPath $taskExpected){throw 'Preserve accepted genuine output; recapture needs a separate explicit comparison owner'}
if((Test-Path -LiteralPath (Join-Path $taskEvidence "$taskName.json"))-or(Test-Path -LiteralPath $taskOutput)){throw 'Unique attempt required'}
if((git -C $taskSource rev-parse HEAD) -cne '4954d760504c11df9b2cbdc040346107b6a8153d'){throw 'Original latest4954 Source identity mismatch'}
$taskInitialAdmission=Admit
$taskReference=@(Get-Content -LiteralPath (Join-Path $taskEvidence 'source4954-full-manifest-20261015.json') -Raw|ConvertFrom-Json)
$taskDependencies=@(Get-Content -LiteralPath (Join-Path $taskEvidence 'source4954-runtime-manifest-20261015.json') -Raw|ConvertFrom-Json)
$taskNode=@(Get-Content -LiteralPath (Join-Path $taskEvidence 'source4954-node-tools-before-20261015.json') -Raw|ConvertFrom-Json)
if($taskReference.Count -ne 1970 -or $taskDependencies.Count -ne 31064 -or $taskNode.Count -ne 1774){throw 'Complete latest4954 universe required'}
$taskAudit=Get-Content -LiteralPath (Join-Path $taskEvidence 'source4954-dependency-contract-audit-20261015.json') -Raw|ConvertFrom-Json
$taskAbsences=@($taskAudit.pins|Where-Object{$_.status -eq 'platform_optional_absent'}|ForEach-Object{$_.path})+@($taskAudit.mismatches|ForEach-Object{$_.path})
if($taskAbsences.Count -ne 84 -or $taskAudit.platform_optional_absent_records -ne 80 -or $taskAudit.historical_missing_records_retained -ne 4){throw 'Exactly84 declared absent package records required'}
function Absence-Drift(){@($taskAbsences|Where-Object{(Test-Path -LiteralPath (Join-Path $taskSource $_))-or(Test-Path -LiteralPath (Join-Path 'C:/Users/adyba/pi-upstream-runtime-19cb534-20261012' $_))}).Count}
if((Absence-Drift)-or(Source-Inventory-Drift $taskReference)){throw 'Declared absence or full Source inventory drift'}
foreach($taskSet in @($taskReference,$taskDependencies,$taskNode)){if(@(Drift $taskSet).Count){throw 'Pinned latest Source/dependency/Node prehash drift'}}
$taskCandidate=Hash-Paths (Candidate-Paths)
$taskCompilerRows=Hash-Paths @(Get-ChildItem -LiteralPath $taskCompiler -Recurse -File|ForEach-Object{$_.FullName})
if($taskCompilerRows.Count -ne 19546){throw 'Pinned stable Zig0.16 full compiler inventory required'}
$taskControls=Hash-Paths @($PSCommandPath,(Join-Path $taskProof 'capture-source.mjs'),$taskInput,$taskOwner,(Join-Path $taskEvidence 'source4954-observe-20261015.mjs'),(Join-Path $taskEvidence 'source4954-full-manifest-20261015.json'),(Join-Path $taskEvidence 'source4954-dependency-contract-audit-20261015.json'),(Join-Path $taskEvidence 'source4954-runtime-manifest-20261015.json'),(Join-Path $taskEvidence 'source4954-node-tools-before-20261015.json'))
$taskFrozen=[ordered]@{candidate=$taskCandidate;reference=$taskReference;dependencies=$taskDependencies;node=$taskNode;compiler=$taskCompilerRows;controls=$taskControls}
$taskFrozen|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $taskProof "$taskName-prehash.json") -Encoding utf8NoBOM
$taskControlManifest=Join-Path $taskProof "$taskName-oracle-controls.json"
$taskControls|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $taskControlManifest -Encoding utf8NoBOM
$taskCallerHashes=Hash-Paths @((Join-Path $taskProof 'capture-source.mjs'),$taskInput,$taskOwner,$PSCommandPath,'C:/Program Files/nodejs/node.exe',$taskControlManifest)
@{candidate_head=(git -C $taskRoot rev-parse HEAD);source_head=(git -C $taskSource rev-parse HEAD);callers=$taskCallerHashes;declared_absences=$taskAbsences;source_inventory_drift=0;absence_drift=0}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $taskProof "$taskName-launch-identity.json") -Encoding utf8NoBOM
$taskAdmission=Admit
$taskAdmission|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskProof "$taskName-admission.json") -Encoding utf8NoBOM
try{
 & $taskOwner -Name $taskName -Executable 'C:/Program Files/nodejs/node.exe' -WorkingDirectory $taskSource -Arguments @('--max-old-space-size=256','--import',([Uri](Join-Path $taskEvidence 'source4954-observe-20261015.mjs')).AbsoluteUri,(Join-Path $taskProof 'capture-source.mjs'),$taskOutput,$taskInput) -TimeoutSeconds 300 -EnvironmentOverrides @{NODE_OPTIONS='';NODE_PATH='';PI_SOURCE_ORACLE_CONTROL_MANIFEST=$taskControlManifest}
}finally{
 $taskPost=[ordered]@{}
 foreach($taskPair in $taskFrozen.GetEnumerator()){$taskPost[$taskPair.Key+'_files']=@($taskPair.Value).Count;$taskPost[$taskPair.Key+'_drift']=@(Drift $taskPair.Value).Count}
 $taskPost.candidate_inventory_drift=@(Compare-Object @($taskCandidate.path|Sort-Object) @(Candidate-Paths|ForEach-Object{[IO.Path]::GetFullPath($_)}|Sort-Object)).Count
 $taskPost.declared_absent_records=84
 $taskPost.absence_drift=Absence-Drift
 $taskPost.source_inventory_drift=Source-Inventory-Drift $taskReference
 $taskPost.caller_identity_drift=@(Drift $taskCallerHashes).Count
 $taskPost.completed_utc=[DateTimeOffset]::UtcNow.ToString('o')
 $taskPost|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskProof "$taskName-posthash.json") -Encoding utf8NoBOM
 foreach($taskKey in $taskPost.Keys){if($taskKey -like '*_drift' -and $taskPost[$taskKey]){throw 'Frozen input drift'}}
}
$taskReceipt=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName.json") -Raw|ConvertFrom-Json
$taskProcess=Get-CimInstance Win32_Process -Filter "ProcessId=$($taskReceipt.pid)"
@{pid=$taskReceipt.pid;observed_utc=[DateTimeOffset]::UtcNow.ToString('o');present=[bool]$taskProcess}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskProof "$taskName-absence.json") -Encoding utf8NoBOM
if($taskProcess){throw 'Owned Source PID remains present; no expected acceptance'}
if($taskReceipt.status -cne 'passed'){throw 'Owned Source did not pass; retain negative without accepting expected'}
$taskCapture=Get-Content -LiteralPath $taskOutput -Raw|ConvertFrom-Json
if($taskCapture.cases -ne 34 -or $taskCapture.sourceHead -cne '4954d760504c11df9b2cbdc040346107b6a8153d'){throw 'Incomplete actual Source34 artifact'}
if($taskCapture.inputSha256 -ine(Get-FileHash -LiteralPath $taskInput).Hash){throw 'Source capture input identity mismatch'}
Copy-Item -LiteralPath $taskOutput -Destination $taskExpected
[ordered]@{status='passed';phase='Source';owner=$taskReceipt;input_posthash=$taskPost;expected_sha256=(Get-FileHash -LiteralPath $taskExpected).Hash;output=$taskExpected}|ConvertTo-Json -Depth 7

param([Parameter(Mandatory)][string]$Attempt)
$ErrorActionPreference='Stop'
$taskRoot='C:/Users/adyba/pi-zig-native-typebox-compile-production-20261015'
$taskProof=$PSScriptRoot
$taskEvidence='C:/Users/adyba/pi-zig-update-evidence-20261003'
$taskSource='C:/Users/adyba/pi-upstream-source-4954d76-20261015'
$taskRuntime='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012'
$taskNode='C:/Program Files/nodejs/node.exe'
$taskName="typebox-compile-source80-$Attempt-20261016"
$taskOwner=Join-Path $taskProof 'Invoke-OwnedSource80.ps1'
$taskDriver=Join-Path $taskProof 'capture-genuine-source.mjs'
$taskInput=Join-Path $taskRoot 'src/extensions/fixtures/typebox-compile-production.input.mjs'
$taskExpected=Join-Path $taskRoot 'src/extensions/fixtures/typebox-compile-production.json'
$taskOutput=Join-Path $taskProof "$taskName-output.json"
$taskObserver=Join-Path $taskEvidence 'source4954-observe-20261015.mjs'
function Hash-Paths($paths){@($paths|Sort-Object -Unique|ForEach-Object{[ordered]@{path=[IO.Path]::GetFullPath($_);sha256=(Get-FileHash -LiteralPath $_).Hash}})}
function Check-Rows($rows){@($rows|Where-Object{!(Test-Path -LiteralPath $_.path -PathType Leaf)-or (Get-FileHash -LiteralPath $_.path).Hash -ine $_.sha256})}
function Inventory([string]$directory,[bool]$skipModules=$false){foreach($entry in Get-ChildItem -LiteralPath $directory -Force){if($entry.Name -eq '.git' -or ($skipModules -and $entry.Name -eq 'node_modules')){continue};if($entry.PSIsContainer){if($entry.Attributes -band [IO.FileAttributes]::ReparsePoint){$taskLink= $taskLinks|Where-Object path -eq $entry.FullName;if(!$taskLink -or $taskLink.target -cne $entry.Target -or $taskLink.type -cne $entry.LinkType){throw "Unexpected frozen reparse point $($entry.FullName)"};continue};Inventory $entry.FullName $skipModules}else{$entry.FullName}}}
function Inventory-Drift($rows,$directory,$skipModules=$false){$expected=@($rows|ForEach-Object{[IO.Path]::GetFullPath($_.path)}|Sort-Object);$actual=if($directory -eq 'C:/Program Files/nodejs'){@([IO.Path]::GetFullPath($taskNode))+@(Inventory (Join-Path $directory 'node_modules/npm'))}else{@(Inventory $directory $skipModules)};$actual=@($actual|Sort-Object);@(Compare-Object $expected $actual).Count}
if(Test-Path -LiteralPath $taskExpected){throw 'Fresh genuine expected acceptance only'}
if(Test-Path -LiteralPath $taskOutput){throw 'Fresh unique Source80 attempt required'}
if((git -C $taskRoot rev-parse HEAD) -cne '3b7a64806f31d63edb110ebcf38e3db401724654'){throw 'Paused candidate head drift'}
if((git -C $taskSource rev-parse HEAD) -cne '4954d760504c11df9b2cbdc040346107b6a8153d'){throw 'Immutable source head drift'}
if((Get-FileHash -LiteralPath $taskDriver).Hash -cne '083E2F74B290C6B910889F8B56E85193A364BC377C478C256C1A91EE0848A51B' -or (Get-FileHash -LiteralPath $taskInput).Hash -cne 'B7DC5B8F18B42E70410438DE323B408D4BB268CF45E19BE923952D9097BE60AB'){throw 'Prepared genuine Source80 controls changed'}
$taskAuditPath=Join-Path $taskEvidence 'source4954-dependency-contract-audit-20261015.json'
$taskAudit=Get-Content -LiteralPath $taskAuditPath -Raw|ConvertFrom-Json
$taskLinks=@($taskAudit.workspaces|ForEach-Object{$taskPath=Join-Path (Join-Path $taskRuntime 'node_modules') $_.specifier;$taskLink=Get-Item -LiteralPath $taskPath -Force;$taskTarget=[IO.Path]::GetFullPath((Join-Path $taskRuntime $_.path));if($taskLink.LinkType -cne 'Junction' -or $taskLink.Target -cne $taskTarget){throw 'Frozen workspace junction identity drift'};@{path=$taskLink.FullName;target=$taskTarget;type='Junction'}})
if($taskLinks.Count -ne 16){throw 'Exactly16 workspace junction authorities required'}
$taskSpecs=@(@{name='source';file='source4954-full-manifest-20261015.json';count=1970;root=$taskSource;skipModules=$true},@{name='runtime';file='source4954-runtime-manifest-20261015.json';count=31064;root=$taskRuntime;skipModules=$false},@{name='node';file='source4954-node-tools-before-20261015.json';count=1774;root='C:/Program Files/nodejs';skipModules=$false})
$taskFrozen=[ordered]@{}
foreach($spec in $taskSpecs){$rows=@(Get-Content -LiteralPath (Join-Path $taskEvidence $spec.file) -Raw|ConvertFrom-Json);if($rows.Count -ne $spec.count -or @(Check-Rows $rows).Count -or (Inventory-Drift $rows $spec.root $spec.skipModules)){throw "Complete frozen prehash/inventory drift $($spec.name)"};$taskFrozen[$spec.name]=$rows}
$taskAbsences=@($taskAudit.pins|Where-Object status -eq 'platform_optional_absent'|ForEach-Object path)+@($taskAudit.mismatches|ForEach-Object path)
if($taskAbsences.Count -ne 84 -or $taskAudit.platform_optional_absent_records -ne 80 -or $taskAudit.historical_missing_records_retained -ne 4){throw '84 explicit historical absences required'}
function Absence-Drift(){@($taskAbsences|Where-Object{(Test-Path -LiteralPath (Join-Path $taskSource $_))-or(Test-Path -LiteralPath (Join-Path $taskRuntime $_))}).Count}
if(Absence-Drift){throw 'Prelaunch explicit absence drift'}
$taskCandidatePaths=@(git -C $taskRoot ls-files|ForEach-Object{Join-Path $taskRoot $_})
$taskFrozen.candidate=Hash-Paths $taskCandidatePaths
# Controls are recorded independently from the actual full source/runtime/Node inventory.
$taskFrozen.controls=Hash-Paths (@($PSCommandPath,$taskOwner,$taskDriver,$taskInput,$taskObserver,$taskAuditPath)+@($taskSpecs|ForEach-Object{Join-Path $taskEvidence $_.file}))
$taskPre=Join-Path $taskProof "$taskName-prehash.json"
$taskFrozen|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $taskPre -Encoding utf8NoBOM
$taskControlManifest=Join-Path $taskProof "$taskName-oracle-controls.json"
$taskFrozen.controls|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $taskControlManifest -Encoding utf8NoBOM
$taskCallers=Hash-Paths @($taskControlManifest,$taskPre)
$taskFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
if($taskFree -lt 2MB){throw 'Fresh 2GiB memory admission denied; Node not launched'}
@{status='admitted';source_only=$true;lane='Root explicit LIGHT3 Source80';candidate_head='3b7a64806f31d63edb110ebcf38e3db401724654';free_kib=$taskFree;required_kib=2MB;heap_mb=256;deadline_seconds=300;parent_settle_seconds=10;declared_absences=$taskAbsences;workspace_junctions=$taskLinks;runner_sha256='083E2F74B290C6B910889F8B56E85193A364BC377C478C256C1A91EE0848A51B';stale_task_summary_runner_sha256='4242EB5456F41B45770BFD6AABFA6EFFEE62D5EA6350319AA6059DAFCE5AD9A1';hash_correction='Root independently verified current committed runner before explicit LIGHT3 grant';compiler_distribution_frozen=$false;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskProof "$taskName-admission.json") -Encoding utf8NoBOM
try{
 & $taskOwner -Name $taskName -Executable $taskNode -WorkingDirectory $taskSource -Arguments @('--max-old-space-size=256','--expose-gc','--import',([Uri]$taskObserver).AbsoluteUri,$taskDriver,$taskOutput) -TimeoutSeconds 300 -EnvironmentOverrides @{NODE_OPTIONS='';NODE_PATH='';PI_SOURCE_ORACLE_CONTROL_MANIFEST=$taskControlManifest}
}finally{
 $taskPost=[ordered]@{}
 foreach($pair in $taskFrozen.GetEnumerator()){$taskPost[$pair.Key+'_files']=@($pair.Value).Count;$taskPost[$pair.Key+'_drift']=@(Check-Rows $pair.Value).Count}
 foreach($spec in $taskSpecs){$taskPost[$spec.name+'_inventory_drift']=Inventory-Drift $taskFrozen[$spec.name] $spec.root $spec.skipModules}
 $taskPost.absence_drift=Absence-Drift
 $taskPost.caller_drift=@(Check-Rows $taskCallers).Count
 $taskPost.candidate_head_drift=(git -C $taskRoot rev-parse HEAD) -cne '3b7a64806f31d63edb110ebcf38e3db401724654'
 $taskPost.source_head_drift=(git -C $taskSource rev-parse HEAD) -cne '4954d760504c11df9b2cbdc040346107b6a8153d'
 $taskPost.completed_utc=[DateTimeOffset]::UtcNow.ToString('o')
 $taskPost|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskProof "$taskName-posthash.json") -Encoding utf8NoBOM
 foreach($key in $taskPost.Keys){if($key -like '*_drift' -and $taskPost[$key]){throw "Frozen Source80 posthash drift $key"}}
}
$taskReceipt=Get-Content -LiteralPath (Join-Path $taskProof "$taskName.json") -Raw|ConvertFrom-Json
if($taskReceipt.status -cne 'passed' -or $taskReceipt.exit_code -ne 0){throw 'Actual Source80 terminal failed; expected absent'}
if(Get-CimInstance Win32_Process -Filter "ProcessId = $($taskReceipt.pid)"){throw 'Actual Source80 PID absence not verified'}
$taskCapture=Get-Content -LiteralPath $taskOutput -Raw|ConvertFrom-Json
if($taskCapture.count -ne 80 -or @($taskCapture.rows).Count -ne 80 -or $taskCapture.runtime -cne 'v24.14.0' -or $taskCapture.sourceHead -cne '4954d760504c11df9b2cbdc040346107b6a8153d' -or $taskCapture.inputSha256 -ine 'B7DC5B8F18B42E70410438DE323B408D4BB268CF45E19BE923952D9097BE60AB'){throw 'Incomplete actual Source80 output'}
Copy-Item -LiteralPath $taskOutput -Destination $taskExpected
@{status='passed';source_cases=80;expected_accepted_only_after_terminal0_and_full_posthash0=$true;expected_sha256=(Get-FileHash -LiteralPath $taskExpected).Hash;native_compiled=$false;native_executed=$false;full_pi_qualified=$false}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskProof "$taskName-validation.json") -Encoding utf8NoBOM
Write-Output 'ACTUAL_SOURCE80_ACCEPTED_AFTER_TERMINAL0_FULL_POSTHASH0'

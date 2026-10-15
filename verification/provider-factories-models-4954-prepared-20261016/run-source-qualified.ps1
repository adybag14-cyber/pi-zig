param([Parameter(Mandatory)][string]$Attempt,[switch]$RootSourceGrant)
$ErrorActionPreference='Stop'
if(!$RootSourceGrant){throw 'Root LIGHT3 Source grant required'}
$taskRoot='C:/Users/adyba/pi-zig-ai-provider-factories-models-20261015'
$taskEvidence='C:/Users/adyba/pi-zig-update-evidence-20261003'
$taskSource='C:/Users/adyba/pi-upstream-source-4954d76-20261015'
$taskRuntime='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012'
$taskProof=$PSScriptRoot
$taskName="provider-factories-models-4954-$Attempt-20261016"
$taskOwner=Join-Path $taskEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1'
$taskCompiler='C:/Users/adyba/pi-zig-toolchain-20261003/zig-x86_64-windows-0.16.0'
$taskNodeExe='C:/Program Files/nodejs/node.exe'
$taskExpected=Join-Path $taskRoot 'src/extensions/fixtures/provider-factories-models-4954-source.json'
$taskOutput=Join-Path $taskProof "$taskName-output.json"
$taskOwnedDirectory=Join-Path $taskProof "$taskName-owned"
$taskReleasePrefix=Join-Path $taskEvidence 'ai-codex-wire16-5ab-source16-first-20261015'
function Check-Rows($rows){@($rows|Where-Object{!(Test-Path -LiteralPath $_.path -PathType Leaf)-or (Get-FileHash -LiteralPath $_.path).Hash -ine $_.sha256})}
function Hash-Paths($paths){@($paths|Sort-Object -Unique|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})}
function Source-Paths([string]$directory){foreach($entry in Get-ChildItem -LiteralPath $directory -Force){if($entry.PSIsContainer){if($entry.Name -notin @('.git','node_modules')){if($entry.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Unexpected immutable Source reparse point'};Source-Paths $entry.FullName}}else{if($entry.Name -ne '.git'){$entry.FullName}}}}
function Source-Inventory-Drift($reference){$expected=@($reference|ForEach-Object{[IO.Path]::GetFullPath($_.path)}|Sort-Object);$actual=@(Source-Paths $taskSource|Sort-Object);@(Compare-Object $expected $actual).Count}
if(Test-Path -LiteralPath $taskExpected){throw 'Expected must remain absent until first terminal genuine Source acceptance'}
foreach($taskFresh in @($taskOutput,$taskOwnedDirectory,(Join-Path $taskEvidence "$taskName.json"))){if(Test-Path -LiteralPath $taskFresh){throw 'Fresh unique attempt required'}}
if(@(git -C $taskRoot status --porcelain).Count){throw 'Clean checkpoint required before freeze'}
$taskHead=(git -C $taskRoot rev-parse HEAD).Trim()
if((git -C $taskSource rev-parse HEAD) -cne '4954d760504c11df9b2cbdc040346107b6a8153d'){throw 'Latest immutable Source identity mismatch'}
$taskRelease=Get-Content -LiteralPath "$taskReleasePrefix-owner-absence.json" -Raw|ConvertFrom-Json
if($taskRelease.source_terminal -cne 'passed' -or !$taskRelease.pid_absent -or $taskRelease.owned_listener_count -ne 0){throw 'Prior LIGHT3 owner release missing'}
if(Get-CimInstance Win32_Process -Filter 'ProcessId=45480'){throw 'Prior LIGHT3 PID is present; identity must be reconciled before admission'}
$taskPins=@(
 @{path=(Join-Path $taskEvidence 'source4954-full-manifest-20261015.json');sha256='3229A90AB56E791DCEAC7659C2929BF6D3270C0202F1242F298444BE60A5B42C'},
 @{path=(Join-Path $taskEvidence 'source4954-runtime-manifest-20261015.json');sha256='38223DB79BE24C7F9F5833A662D3C73FF2531F78489699DBF87F9F52A9B4BFBA'},
 @{path=(Join-Path $taskEvidence 'source4954-node-tools-before-20261015.json');sha256='F834312AAC6AC8D79EF4B49CCB806096D80E92FCA403CC650A05E901D4C280DD'},
 @{path=(Join-Path $taskEvidence 'source4954-dependency-contract-audit-20261015.json');sha256='5E33C04D23181DDAF1D0330651730524CE0EFD6643FD1490F54EF1EFF5ECD745'},
 @{path=(Join-Path $taskEvidence 'source4954-observe-20261015.mjs');sha256='020361966FEA906D9AA07F380F705F1DF6755852CCDC5F9A65BDB75580A7E8A3'},
 @{path=(Join-Path $taskEvidence 'source4954-preparation-readiness-20261015.json');sha256='0EDB3EA87CF7AE1FF8B51A02A1D3698DC610BA23F66257D60AA5C788557E82D7'},
 @{path=(Join-Path $taskSource 'packages/coding-agent/package.json');sha256='83C3BB7619F590C213CC96A24216EB29A819A3EF6DC548607CC037ED276E8DC5'},
 @{path=(Join-Path $taskCompiler 'zig.exe');sha256='086CE9D47BA42F33A514E1A6E04EB1D4A8FA1D75E0868E0213CAAD447C91E864'},
 @{path=$taskNodeExe;sha256='63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088'},
 @{path=$taskOwner;sha256='B553B9A183BD2FB4CFBC7852B98B47E788ADB97AE32723F1E56EE04A8776B2F9'}
)
if(@(Check-Rows $taskPins).Count){throw 'Latest4954 explicit authority/control pin mismatch'}
$taskCandidatePaths=@(git -C $taskRoot ls-files|ForEach-Object{Join-Path $taskRoot $_})
$taskCandidate=Hash-Paths $taskCandidatePaths
$taskReference=@(Get-Content -LiteralPath (Join-Path $taskEvidence 'source4954-full-manifest-20261015.json') -Raw|ConvertFrom-Json)
$taskDependencies=@(Get-Content -LiteralPath (Join-Path $taskEvidence 'source4954-runtime-manifest-20261015.json') -Raw|ConvertFrom-Json)
$taskNode=@(Get-Content -LiteralPath (Join-Path $taskEvidence 'source4954-node-tools-before-20261015.json') -Raw|ConvertFrom-Json)
if($taskReference.Count -ne 1970 -or $taskDependencies.Count -ne 31064 -or $taskNode.Count -ne 1774){throw 'Complete latest4954 input universe required'}
$taskAudit=Get-Content -LiteralPath (Join-Path $taskEvidence 'source4954-dependency-contract-audit-20261015.json') -Raw|ConvertFrom-Json
$taskAbsences=@($taskAudit.pins|Where-Object{$_.status -eq 'platform_optional_absent'}|ForEach-Object{$_.path})+@($taskAudit.mismatches|ForEach-Object{$_.path})
if($taskAbsences.Count -ne 84 -or $taskAudit.platform_optional_absent_records -ne 80 -or $taskAudit.historical_missing_records_retained -ne 4){throw 'Exactly84 declared absent package records required'}
function Absence-Drift(){@($taskAbsences|Where-Object{(Test-Path -LiteralPath (Join-Path $taskSource $_))-or(Test-Path -LiteralPath (Join-Path $taskRuntime $_))}).Count}
if((Absence-Drift)-or(Source-Inventory-Drift $taskReference)){throw 'Declared absence or complete Source path inventory drift'}
$taskCompilerRows=Hash-Paths @(Get-ChildItem -LiteralPath $taskCompiler -Recurse -File|ForEach-Object{$_.FullName})
if($taskCompilerRows.Count -ne 19546){throw 'Complete19546 pinned compiler inventory required'}
$taskControls=(Hash-Paths @($PSCommandPath,(Join-Path $taskProof 'source-observer.mjs'),(Join-Path $taskProof 'source-factory-inventory.json'),(Join-Path $taskRoot 'src/extensions/native_ai_provider_factories_fixture.mjs'),$taskOwner,(Join-Path $taskEvidence 'source4954-reference-controls-20261015.json'),"$taskReleasePrefix.json","$taskReleasePrefix-posthash.json","$taskReleasePrefix-candidate-posthash.json","$taskReleasePrefix-owner-absence.json"))+@(Hash-Paths @($taskPins|ForEach-Object{$_.path}))
foreach($taskSet in @($taskReference,$taskDependencies,$taskNode)){if(@(Check-Rows $taskSet).Count){throw 'Pinned latest Source/dependency/Node prehash drift'}}
$taskFrozen=[ordered]@{candidate=$taskCandidate;reference=$taskReference;dependencies=$taskDependencies;node=$taskNode;compiler=$taskCompilerRows;controls=$taskControls}
$taskFrozen|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $taskProof "$taskName-prehash.json") -Encoding utf8NoBOM
$taskControlManifest=Join-Path $taskProof "$taskName-oracle-controls.json"
$taskControls|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $taskControlManifest -Encoding utf8NoBOM
$taskCallerHashes=Hash-Paths @((Join-Path $taskProof 'source-observer.mjs'),(Join-Path $taskProof 'source-factory-inventory.json'),(Join-Path $taskRoot 'src/extensions/native_ai_provider_factories_fixture.mjs'),$taskOwner,$PSCommandPath,$taskNodeExe,$taskControlManifest)
@{candidate_head=$taskHead;source_head=(git -C $taskSource rev-parse HEAD);callers=$taskCallerHashes;declared_absences=$taskAbsences;source_inventory_drift=0;absence_drift=0;prior_light3_pid_absent=$true;observed_count_contract='42 original provider exports;14 original API constructors;dynamic unique rows and total recorded by actual observer'}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $taskProof "$taskName-launch-identity.json") -Encoding utf8NoBOM
$taskFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
if($taskFree -lt 2MB){throw 'Fresh 2GiB memory admission denied'}
@{status='admitted';slot=3;source_only=$true;free_kib=$taskFree;required_kib=2MB;heap_mb=256;deadline_seconds=300;fixture_deadline_seconds=10;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskProof "$taskName-admission.json") -Encoding utf8NoBOM
try{
 & $taskOwner -Name $taskName -Executable $taskNodeExe -WorkingDirectory $taskSource -Arguments @('--max-old-space-size=256','--import',([Uri](Join-Path $taskEvidence 'source4954-observe-20261015.mjs')).AbsoluteUri,(Join-Path $taskProof 'source-observer.mjs'),$taskOwnedDirectory,$taskOutput) -TimeoutSeconds 300 -EnvironmentOverrides @{NODE_OPTIONS='';NODE_PATH='';PI_PACKAGE_DIR='';PI_SOURCE_ORACLE_CONTROL_MANIFEST=$taskControlManifest}
}finally{
 $taskPost=[ordered]@{}
 foreach($taskPair in $taskFrozen.GetEnumerator()){$taskPost[$taskPair.Key+'_files']=@($taskPair.Value).Count;$taskPost[$taskPair.Key+'_drift']=@(Check-Rows $taskPair.Value).Count}
 $taskPost.declared_absent_records=84
 $taskPost.absence_drift=Absence-Drift
 $taskPost.source_inventory_drift=Source-Inventory-Drift $taskReference
 $taskPost.caller_identity_drift=@(Check-Rows $taskCallerHashes).Count
 $taskPost.candidate_head_drift=[int]((git -C $taskRoot rev-parse HEAD).Trim() -cne $taskHead)
 $taskPost.candidate_path_drift=@(Compare-Object @($taskCandidatePaths|Sort-Object) @(git -C $taskRoot ls-files|ForEach-Object{Join-Path $taskRoot $_}|Sort-Object)).Count
 $taskPost.completed_utc=[DateTimeOffset]::UtcNow.ToString('o')
 $taskPost|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskProof "$taskName-posthash.json") -Encoding utf8NoBOM
 foreach($taskKey in $taskPost.Keys){if($taskKey -like '*_drift' -and $taskPost[$taskKey]){throw 'Frozen input drift'}}
}
$taskReceipt=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName.json") -Raw|ConvertFrom-Json
if($taskReceipt.status -cne 'passed' -or $taskReceipt.exit_code -ne 0){throw 'Owned Source job did not pass; retain negative without expected acceptance'}
if(Get-CimInstance Win32_Process -Filter "ProcessId=$($taskReceipt.pid)"){throw 'Owned Source PID must be absent before acceptance'}
$taskCapture=Get-Content -LiteralPath $taskOutput -Raw|ConvertFrom-Json
$taskRows=@($taskCapture.rows)
if($taskCapture.sourceHead -cne '4954d760504c11df9b2cbdc040346107b6a8153d' -or $taskCapture.actualNode.version -cne 'v24.14.0' -or !$taskCapture.packageOverrideAbsent -or $taskCapture.sourcePackage.version -cne '1.3.0' -or [IO.Path]::GetFullPath($taskCapture.sourcePackage.packageDir) -ine [IO.Path]::GetFullPath((Join-Path $taskSource 'packages/coding-agent'))){throw 'Actual latest default metadata/output authority mismatch'}
if($taskCapture.factoryCount -ne 42 -or @($taskRows|Where-Object{$_.case.StartsWith('factory ')}).Count -ne 42 -or @($taskRows|Where-Object{$_.case.StartsWith('API constructor ')}).Count -ne 14 -or $taskCapture.cases -ne $taskRows.Count -or @($taskRows.case|Sort-Object -Unique).Count -ne $taskRows.Count){throw 'Incomplete actual declarations or duplicate observed rows'}
Copy-Item -LiteralPath $taskOutput -Destination $taskExpected
[ordered]@{status='passed';phase='Source';slot=3;owner=$taskReceipt;observed_cases=$taskRows.Count;provider_exports=42;api_constructors=14;input_posthash=$taskPost;expected_sha256=(Get-FileHash -LiteralPath $taskExpected).Hash;output=$taskExpected;owned_pid_absent=$true}|ConvertTo-Json -Depth 7

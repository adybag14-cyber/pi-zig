#requires -Version 7.0
param([ValidateSet('first','second')][string]$Attempt='first',[switch]$RootLightGrant)
$ErrorActionPreference='Stop'
if(!$RootLightGrant){throw 'Root LIGHT7 grant is required before Source/full-prehash work'}
$taskEvidence=$PSScriptRoot
$taskAuthorities=Split-Path -Parent $taskEvidence
$taskName="sdk-module-policy-source-$Attempt-20261016"
$taskTree='C:/Users/adyba/pi-zig-sdk-default-real-assembly-20261016'
$taskCandidate='c735c1f1b74822f23cca2d79802e27f687ee76e2'
$taskSource='C:/Users/adyba/pi-upstream-source-4954d76-20261015'
$taskRuntime='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012'
$taskNode='C:/Program Files/nodejs/node.exe'
$taskCompilerRoot='C:/Users/adyba/pi-zig-toolchain-20261003/zig-x86_64-windows-0.16.0'
$taskDriver=Join-Path $taskTree 'verification/sdk-default-real-assembly-4954-20261016/capture-module-policy-supplement.mjs'
$taskInput=Join-Path $taskTree 'verification/sdk-default-real-assembly-4954-20261016/capture-module-policy-supplement.mjs'
$taskExpected=Join-Path $taskTree 'src/extensions/fixtures/sdk-module-policy-4954.expected.json'
$taskObserver=Join-Path $taskAuthorities 'source4954-observe-20261015.mjs'
$taskReadiness=Join-Path $taskAuthorities 'source4954-preparation-readiness-20261015.json'
$taskAudit=Join-Path $taskAuthorities 'source4954-dependency-contract-audit-20261015.json'
$taskInventory=Join-Path $taskEvidence 'sdk-module-policy-probe-inventory-20261016.json'
$taskOwner=Join-Path $taskEvidence 'Invoke-OwnedModelsPersistenceSource-20261015.ps1'
$taskOutput=Join-Path $taskEvidence "$taskName-output.json"
$taskSeal=Join-Path $taskEvidence 'sdk-module-policy-prelaunch-seal-20261016.json'
if(Test-Path -LiteralPath ($taskOutput+'.physical-files')){throw 'Refuse prior physical fixture directory'}
if(Test-Path -LiteralPath $taskOutput){throw 'Refuse Source attempt replay'}
if(Test-Path -LiteralPath (Join-Path $taskEvidence "$taskName.json")){throw 'Refuse existing owned Source process receipt'}
if(Test-Path -LiteralPath $taskExpected){throw 'Expected must remain absent until terminal0 and complete posthash acceptance'}
if((git -C $taskTree rev-parse HEAD).Trim() -cne $taskCandidate -or (git -C $taskTree status --porcelain)){throw 'Frozen Source checkpoint must be exact and clean'}
$taskSealed=Get-Content -LiteralPath $taskSeal -Raw|ConvertFrom-Json
if($taskSealed.candidate -cne $taskCandidate -or $taskSealed.cases -ne 39){throw 'Clean seal/case inventory mismatch'}
function Changed($rows){@($rows|Where-Object{!(Test-Path -LiteralPath $_.path -PathType Leaf) -or (Get-FileHash -LiteralPath $_.path).Hash -cne $_.sha256.ToUpperInvariant()}|ForEach-Object path)}
if(@(Changed $taskSealed.controls).Count){throw 'Sealed owner/caller/input/control drift'}
if((Get-FileHash -LiteralPath $taskNode).Hash -cne '63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088'){throw 'Pinned Node drift'}
if((Get-FileHash -LiteralPath (Join-Path $taskCompilerRoot 'zig.exe')).Hash -cne '086CE9D47BA42F33A514E1A6E04EB1D4A8FA1D75E0868E0213CAAD447C91E864'){throw 'Pinned Zig drift'}
function CandidatePaths{@(git -C $taskTree ls-files --cached --others --exclude-standard|Sort-Object -Unique|ForEach-Object{Join-Path $taskTree $_})}
function CompilerPaths{@(rg --files -uuu -- $taskCompilerRoot|Sort-Object)}
function SourcePaths{@(git -C $taskSource ls-files --cached --others --exclude-standard|ForEach-Object{Join-Path $taskSource $_};Get-ChildItem -LiteralPath (Join-Path $taskSource 'packages/ai/src/providers/data') -File -Force|ForEach-Object FullName)|Sort-Object -Unique}
function RuntimePaths{@(rg --files -uuu -g '!.git' -g '!.git/**' -- $taskRuntime|Sort-Object)}
function NodePaths{@($taskNode;Get-ChildItem -LiteralPath 'C:/Program Files/nodejs/node_modules/npm' -Recurse -File -Force|ForEach-Object FullName)|Sort-Object}
function PathKey([string]$path){[IO.Path]::GetFullPath($path).Replace('\','/').ToUpperInvariant()}
function InventoryDrift($rows,$paths){$recorded=@($rows|ForEach-Object{PathKey $_.path}|Sort-Object);$actual=@($paths|ForEach-Object{PathKey $_}|Sort-Object);@(Compare-Object $recorded $actual)}
$taskCandidatePaths=@(CandidatePaths);$taskCompilerPaths=@(CompilerPaths)
if($taskCompilerPaths.Count -ne 19546){throw 'Complete fresh compiler19546 required'}
$taskCandidateRows=@($taskCandidatePaths|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})
$taskCompilerRows=@($taskCompilerPaths|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})
$taskSnapshot=Join-Path $taskEvidence "$taskName-candidate-compiler-before.json"
[ordered]@{candidate_head=$taskCandidate;candidate=$taskCandidateRows;compiler=$taskCompilerRows}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $taskSnapshot -Encoding utf8NoBOM
$taskSpecs=@(@{name='source';file='source4954-full-manifest-20261015.json';count=1970},@{name='dependencies';file='source4954-runtime-manifest-20261015.json';count=31064},@{name='node_tools';file='source4954-node-tools-before-20261015.json';count=1774})
$taskFrozen=@()
foreach($spec in $taskSpecs){$rows=@(Get-Content -LiteralPath (Join-Path $taskAuthorities $spec.file) -Raw|ConvertFrom-Json);$paths=switch($spec.name){'source'{SourcePaths}'dependencies'{RuntimePaths}'node_tools'{NodePaths}};if($rows.Count -ne $spec.count -or @(Changed $rows).Count -or @(InventoryDrift $rows $paths).Count){throw "Full authority prehash/path drift: $($spec.name)"};$taskFrozen+=@{name=$spec.name;rows=$rows;paths=$paths}}
if((git -C $taskSource rev-parse HEAD).Trim() -cne '4954d760504c11df9b2cbdc040346107b6a8153d'){throw 'Actual Source4954 head drift'}
$prepared=Get-Content -LiteralPath $taskReadiness -Raw|ConvertFrom-Json
if($prepared.source_full_files -ne 1970 -or @($prepared.controls).Count -ne 5 -or @(Changed $prepared.controls).Count){throw 'Preparation controls drift'}
$contract=Get-Content -LiteralPath $taskAudit -Raw|ConvertFrom-Json
if($contract.latestHead -cne '4954d760504c11df9b2cbdc040346107b6a8153d' -or $contract.installed_metadata_verified -ne 281 -or $contract.platform_optional_absent_records -ne 80 -or $contract.historical_missing_records_retained -ne 4){throw 'Dependency contract drift'}
$taskAbsent=@($contract.pins|Where-Object status -eq 'platform_optional_absent'|ForEach-Object{Join-Path $taskRuntime $_.path})+@($contract.mismatches|ForEach-Object{Join-Path $taskRuntime $_.path})
if($taskAbsent.Count -ne 84 -or @($taskAbsent|Where-Object{Test-Path -LiteralPath $_}).Count){throw '84 dependency absence contracts drift'}
$taskPaths=@($taskDriver,$taskInput,$taskObserver,$taskReadiness,$taskAudit,$taskInventory,$taskOwner,$PSCommandPath,$taskSeal,$taskSnapshot,(Join-Path $taskTree 'verification/sdk-default-real-assembly-4954-20261016/jiti-primary-cache-lifetime-audit.json'),(Join-Path $taskTree 'verification/sdk-default-real-assembly-4954-20261016/module-policy-source39-inventory.json'),(Join-Path $taskTree 'verification/sdk-default-real-assembly-4954-20261016/fresh-root-module-proposal.md'))+@($taskSpecs|ForEach-Object{Join-Path $taskAuthorities $_.file})
$taskControls=@($taskPaths|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})
$taskControlManifest=Join-Path $taskEvidence "$taskName-controls-before.json"
$taskControls|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $taskControlManifest -Encoding utf8NoBOM
$taskControlHash=(Get-FileHash -LiteralPath $taskControlManifest).Hash
$free=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
if($free -lt 2MB){throw 'Fresh2GiB Source admission denied'}
[ordered]@{status='admitted';free_kib=$free;required_kib=2MB;heap_mb=256;outer_seconds=300;settle_seconds=10;slot='Root LIGHT7';observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-admission.json") -Encoding utf8NoBOM
$taskCallFailure=$null
try{& $taskOwner -Name $taskName -Executable $taskNode -WorkingDirectory $taskSource -Arguments @('--max-old-space-size=256','--expose-gc','--conditions=source','--experimental-transform-types','--import',([Uri]$taskObserver).AbsoluteUri,$taskDriver,$taskOutput,($taskOutput+'.physical-files')) -TimeoutSeconds 300 -EnvironmentOverrides @{PI_TIMING='1';PI_PACKAGE_DIR='C:/Users/adyba/pi-upstream-source-4954d76-20261015/packages/coding-agent/';NODE_OPTIONS='';NODE_PATH='';PI_SOURCE_ORACLE_CONTROL_MANIFEST=$taskControlManifest;NODE_USE_ENV_PROXY='';HTTP_PROXY='';HTTPS_PROXY='';ALL_PROXY='';NO_PROXY='127.0.0.1,localhost'}}catch{$taskCallFailure=$_}
$taskCallExit=$LASTEXITCODE
$post=@(foreach($item in $taskFrozen){$paths=switch($item.name){'source'{SourcePaths}'dependencies'{RuntimePaths}'node_tools'{NodePaths}};[ordered]@{name=$item.name;files=$item.rows.Count;drift=@(Changed $item.rows);path_drift=@(InventoryDrift $item.rows $paths)}})
$candidateChanged=@(Changed $taskCandidateRows);$compilerChanged=@(Changed $taskCompilerRows);$candidatePathDrift=@(InventoryDrift $taskCandidateRows @(CandidatePaths));$compilerPathDrift=@(InventoryDrift $taskCompilerRows @(CompilerPaths));$controlChanged=@(Changed $taskControls);$absenceChanged=@($taskAbsent|Where-Object{Test-Path -LiteralPath $_});$manifestChanged=(Get-FileHash -LiteralPath $taskControlManifest).Hash -cne $taskControlHash
[ordered]@{manifests=$post;candidate_files=$taskCandidateRows.Count;candidate_drift=$candidateChanged;candidate_path_drift=$candidatePathDrift;compiler_files=$taskCompilerRows.Count;compiler_drift=$compilerChanged;compiler_path_drift=$compilerPathDrift;control_drift=$controlChanged;control_manifest_drift=$manifestChanged;absence_contracts=84;absence_drift=$absenceChanged;expected_still_absent=!(Test-Path -LiteralPath $taskExpected);completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 7|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-posthash.json") -Encoding utf8NoBOM
if(@($post|Where-Object{$_.drift.Count -or $_.path_drift.Count}).Count -or $candidateChanged.Count -or $compilerChanged.Count -or $candidatePathDrift.Count -or $compilerPathDrift.Count -or $controlChanged.Count -or $absenceChanged.Count -or $manifestChanged -or (Test-Path -LiteralPath $taskExpected)){throw 'Full Source posthash/path/control drift'}
if($taskCallFailure -or $taskCallExit -ne 0){throw "Owned Source capture failure retained after full posthash: $taskCallFailure"}
$terminal=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName.json") -Raw|ConvertFrom-Json
if($terminal.status -cne 'passed' -or $terminal.exit_code -ne 0){throw 'Actual Source process did not pass'}
$result=Get-Content -LiteralPath $taskOutput -Raw|ConvertFrom-Json
foreach($physical in $result.physicalFinal){
    if(!(Test-Path -LiteralPath $physical.path -PathType Leaf) -or (Get-FileHash -LiteralPath $physical.path).Hash -cne $physical.sha256.ToUpperInvariant()){throw 'Original retained physical body drift'}
}
if($result.jitiVersion -cne '2.7.0' -or @($result.physical).Count -ne 39 -or @($result.physicalFinal).Count -lt 24){throw 'Genuine jiti/physical control universe incomplete'}
$inventory=Get-Content -LiteralPath $taskInventory -Raw|ConvertFrom-Json
if($result.typeboxPackageSha256 -cne 'c59ddfd977ce941f1e8ee8b0a0b14396c332fa27cc5fa6fa165227ffd5a3992f' -or $result.typeboxVersion -cne '1.3.27' -or $result.packageVersion -cne '1.3.0' -or $result.cases -ne 39 -or @($result.rows).Count -ne 39 -or $result.driverSha256.ToUpperInvariant() -cne $inventory.input_sha256.ToUpperInvariant()){throw 'Actual full Source probe inventory/identity mismatch'}
for($i=0;$i -lt 39;$i++){if($result.rows[$i].name -cne $inventory.cases[$i]){throw "Missing, duplicate or reordered actual Source case $i"}}
$moduleLog=Join-Path $taskAuthorities "source4954-modules-$($terminal.pid)-0-20261015.jsonl"
if(!(Test-Path -LiteralPath $moduleLog)){throw 'Actual module observation log missing'}
$moduleRows=@(Get-Content -LiteralPath $moduleLog|ForEach-Object{$_|ConvertFrom-Json}|Where-Object kind -eq 'observed-module')
$typeboxRows=@($moduleRows|Where-Object{$_.path.Replace('\','/') -like "$taskRuntime/node_modules/typebox/*"})
if($typeboxRows.Count -lt 300){throw 'Actual full TypeBox module closure not observed'}
$taskLoadedVersions=@()
foreach($row in $moduleRows){
    if((Get-FileHash -LiteralPath $row.path).Hash -ceq $row.sha256.ToUpperInvariant()){continue}
    $physicalRoot=[IO.Path]::GetFullPath($taskOutput+'.physical-files').TrimEnd('\')+'\'
    if(![IO.Path]::GetFullPath($row.path).StartsWith($physicalRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'Observed immutable original module drift'}
    $versions=@($result.physical|Where-Object{[IO.Path]::GetFullPath($_.path) -ieq [IO.Path]::GetFullPath($row.path) -and $_.sha256 -ieq $row.sha256})
    if(!$versions.Count){throw 'Original observed physical version missing'}
    foreach($version in $versions){if([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($version.bytes))) -cne $row.sha256.ToUpperInvariant()){throw 'Retained original physical version digest drift'}}
    $taskLoadedVersions+=[ordered]@{path=$row.path;sha256=$row.sha256;original_write_versions=@($versions|ForEach-Object label)}
}
[ordered]@{status='genuine_source_capture_qualified';candidate=$taskCandidate;cases=39;attempt=$Attempt;source_pid=$terminal.pid;source_exit=0;full_posthash_drift=0;observed_typebox_modules=$typeboxRows.Count;observed_modules=$moduleRows.Count;retained_loaded_physical_versions=$taskLoadedVersions;module_log=$moduleLog;module_log_sha256=(Get-FileHash -LiteralPath $moduleLog).Hash;output_sha256=(Get-FileHash -LiteralPath $taskOutput).Hash;expected_still_absent=$true;native_qualified=$false;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-validation.json") -Encoding utf8NoBOM
Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName-validation.json") -Raw






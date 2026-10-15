param(
 [Parameter(Mandatory)][ValidateSet('compile','probe','allocations')][string]$Phase,
 [Parameter(Mandatory)][string]$ExpectedHead,
 [Parameter(Mandatory)][string]$SlotGrant,
 [Parameter(Mandatory)][ValidatePattern('^[a-z0-9-]+$')][string]$Pair,
 [ValidateSet('Debug','ReleaseSafe')][string]$Mode='Debug',
 [ValidateRange(0,4095)][int]$ShardIndex=0,
 [ValidateRange(1,4096)][int]$Shards=1,
 [string]$PairSealSha=''
)
$ErrorActionPreference='Stop'
$taskPrivate='C:/Users/adyba/pi-zig-sdk-resource-parser-native-20261015'
$taskEvidence='C:/Users/adyba/pi-zig-update-evidence-20261003'
$taskGit='C:/Program Files/Git/cmd/git.exe'
$taskZig='C:/Users/adyba/pi-zig-toolchain-20261003/zig-x86_64-windows-0.16.0/zig.exe'
$taskBase="sdk-resource-parsers-native-$Pair-20261015"
$taskName="$taskBase-$Phase"+$(if($Phase -ceq 'allocations'){"-$ShardIndex-of-$Shards"}else{''})
$taskSeal=Join-Path $taskEvidence "$taskBase-seal.json"
if(Test-Path -LiteralPath (Join-Path $taskEvidence "$taskName.json")){throw 'Unique native phase attempt required'}
if($ShardIndex -ge $Shards){throw 'Invalid exhaustive allocation shard'}
if((& $taskGit -C $taskPrivate rev-parse HEAD).Trim() -cne $ExpectedHead -or @(& $taskGit -C $taskPrivate status --porcelain=v1).Count){throw 'Exact sealed candidate must be clean'}
if((Get-FileHash -LiteralPath $taskZig).Hash -cne '086CE9D47BA42F33A514E1A6E04EB1D4A8FA1D75E0868E0213CAAD447C91E864'){throw 'Pinned compiler SHA changed'}
if((Get-FileHash -LiteralPath (Join-Path $taskPrivate 'src/extensions/fixtures/sdk-resource-parsers-5ab.input.txt')).Hash -cne '58A76B5A99CADACCB82100799AAB9B46DEAFC16B468E7A3FC3EFBFA2755ABF16'){throw 'Actual caller changed'}
if((Get-FileHash -LiteralPath (Join-Path $taskPrivate 'src/extensions/fixtures/sdk-resource-parsers-5ab.json')).Hash -cne '319A558BA194F216F49D7F39A72D43765A05528613A1C697D9F3865C5BB10A92'){throw 'Genuine Source expected bytes changed'}
function Rows($taskPaths){@($taskPaths|Sort-Object -Unique|ForEach-Object{@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})}
function Drift($taskRows){@($taskRows|Where-Object{!(Test-Path -LiteralPath $_.path -PathType Leaf) -or (Get-FileHash -LiteralPath $_.path).Hash -cne $_.sha256}|ForEach-Object path)}
function CandidatePaths{@(& $taskGit -C $taskPrivate ls-files --cached --others --exclude-standard|Sort-Object -Unique|ForEach-Object{Join-Path $taskPrivate $_})}
$taskSpecs=@(@{file='source5ab-full-manifest-20261015.json';count=1967},@{file='durable-19cb534-reference-20261012-all-built-runtime.json';count=31064},@{file='root-current8a-npm-tools-before.json';count=1774})
$taskReferences=@()
foreach($taskSpec in $taskSpecs){$taskRows=@(Get-Content -LiteralPath (Join-Path $taskEvidence $taskSpec.file) -Raw|ConvertFrom-Json);if($taskRows.Count -ne $taskSpec.count){throw 'Full reference inventory mismatch'};$taskReferences+=$taskRows}
$taskToolManifest=Join-Path $taskEvidence 'durable-latest89-full-inspect-53ae-tool-prehash-20261011.json'
$taskTools=@((Get-Content -LiteralPath $taskToolManifest -Raw|ConvertFrom-Json).inputs)
if($taskTools.Count -ne 19546){throw 'Full compiler inventory mismatch'}
$taskContractPath=Join-Path $taskEvidence 'source5ab-dependency-contract-audit-20261015.json'
$taskContract=Get-Content -LiteralPath $taskContractPath -Raw|ConvertFrom-Json
if($taskContract.latestHead -cne '5ab7fe74c400097b386662205cd93900695b8a71' -or $taskContract.installed_metadata_verified -ne 281 -or $taskContract.platform_optional_absent_records -ne 80 -or $taskContract.historical_missing_records_retained -ne 4){throw 'Dependency contract changed'}
$taskRuntime='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012'
$taskAbsent=@($taskContract.pins|Where-Object status -eq 'platform_optional_absent'|ForEach-Object{Join-Path $taskRuntime $_.path})+@($taskContract.mismatches|ForEach-Object{Join-Path $taskRuntime $_.path})
if($taskAbsent.Count -ne 84){throw 'Historical absence inventory mismatch'}
$taskSourcePost=Join-Path $taskEvidence 'sdk-resource-parsers-5ab-source-slot3-first-20261015-posthash.json'
$taskSourcePair=Join-Path $taskEvidence 'sdk-resource-parsers-5ab-source-slot3-first-20261015-full-pair.json'
$taskSourceQualification=Get-Content -LiteralPath $taskSourcePair -Raw|ConvertFrom-Json
$taskSourcePostQualification=Get-Content -LiteralPath $taskSourcePost -Raw|ConvertFrom-Json
if($taskSourceQualification.status -cne 'passed' -or $taskSourceQualification.tested_candidate_head -cne '15a2ed33498fb6337d34c406240dafde65685b91' -or @($taskSourcePostQualification.manifests|Where-Object drift -ne 0).Count -or $taskSourcePostQualification.control_drift.Count -or $taskSourcePostQualification.absent_drift.Count -or $taskSourcePostQualification.control_manifest_drift){throw 'Genuine Source33 authority is not complete'}
$taskControlsPaths=@($PSCommandPath,$taskZig,$taskGit,$taskToolManifest,$taskContractPath,$taskSourcePost,$taskSourcePair,(Join-Path $taskEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1'),(Join-Path $taskEvidence 'source5ab-observe-20261015.mjs'))+@($taskSpecs|ForEach-Object{Join-Path $taskEvidence $_.file})
# Actual parser discovery can walk .agents/skills through temporary-root ancestors.
# Freeze those common ancestors without touching unrelated trees or Git state.
$taskAmbientFiles=@();$taskAmbientTrees=@();$taskAmbientAbsent=@()
$taskAncestor=[IO.DirectoryInfo]::new((Join-Path $taskPrivate '.zig-cache/tmp'))
while($null -ne $taskAncestor){$taskRoot=Join-Path $taskAncestor.FullName '.agents/skills';if(Test-Path -LiteralPath $taskRoot -PathType Container){$taskFiles=@(Get-ChildItem -LiteralPath $taskRoot -File -Force -Recurse|ForEach-Object FullName|Sort-Object);$taskAmbientFiles+=$taskFiles;$taskAmbientTrees+=@{root=$taskRoot;files=$taskFiles}}else{$taskAmbientAbsent+=$taskRoot};$taskAncestor=$taskAncestor.Parent}
if($Phase -ceq 'compile'){
 if(Test-Path -LiteralPath $taskSeal){throw 'Unique native pair seal required'}
 $taskCandidate=Rows (CandidatePaths)
 $taskControls=Rows ($taskControlsPaths+$taskAmbientFiles)
 @{schema=1;candidate_head=$ExpectedHead;mode=$Mode;candidate=$taskCandidate;controls=$taskControls;ambient_trees=$taskAmbientTrees;ambient_absent=$taskAmbientAbsent;historical_absent=$taskAbsent;root_slot_grant=$SlotGrant;sealed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $taskSeal -Encoding utf8NoBOM
}else{
 if(!$PairSealSha -or (Get-FileHash -LiteralPath $taskSeal).Hash -cne $PairSealSha){throw 'Matching immutable compile-pair seal SHA required'}
 $taskPrior=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskBase-compile-posthash.json") -Raw|ConvertFrom-Json
 if($taskPrior.status -cne 'passed'){throw 'Matching compile terminal/full posthash must pass first'}
}
$taskSealHash=(Get-FileHash -LiteralPath $taskSeal).Hash
$taskFrozen=Get-Content -LiteralPath $taskSeal -Raw|ConvertFrom-Json
if($taskFrozen.candidate_head -cne $ExpectedHead -or $taskFrozen.mode -cne $Mode){throw 'Native pair candidate or optimization changed'}
$taskInventoryDrift=@(Compare-Object @($taskFrozen.candidate.path) (CandidatePaths))
if($taskInventoryDrift.Count -or @(Drift $taskFrozen.candidate).Count -or @(Drift $taskFrozen.controls).Count -or @(Drift $taskReferences).Count -or @(Drift $taskTools).Count -or @($taskFrozen.historical_absent+$taskFrozen.ambient_absent|Where-Object{Test-Path -LiteralPath $_}).Count){throw 'Complete native pair prehash mismatch'}
$taskFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
$taskNative=@(Get-CimInstance Win32_Process -Filter "Name = 'zig.exe'"|Where-Object{$_.CommandLine -match '\sbuild\s'}|Select-Object ProcessId,ParentProcessId,ExecutablePath,CommandLine,CreationDate)
$taskAdmission=@{status=if($taskFree -lt 16MB -or $taskNative.Count -ge 4){'admission_denied'}else{'admitted'};fresh_free_kib=$taskFree;required_kib=16MB;max_native_jobs=4;other_native=$taskNative;jobs=1;test_seconds=120;await_seconds=10;root_slot_grant=$SlotGrant;pair_seal_sha256=$taskSealHash;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}
$taskAdmission|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-admission.json") -Encoding utf8NoBOM
if($taskAdmission.status -cne 'admitted'){exit 2}
$taskTargets=if($Phase -ceq 'compile'){@('build-native-sdk-resource-parsers','build-native-sdk-resource-parsers-allocations')}elseif($Phase -ceq 'probe'){@('test-native-sdk-resource-parsers')}else{@('test-native-sdk-resource-parsers-allocations')}
$taskTimeout=if($Phase -ceq 'compile'){1320}else{300}
$taskEnvironment=@{PI_EXHAUSTIVE_ALLOCATION_SHARD='';PI_EXHAUSTIVE_ALLOCATION_SHARDS=''}
if($Phase -ceq 'allocations'){$taskEnvironment.PI_EXHAUSTIVE_ALLOCATION_SHARD=[string]$ShardIndex;$taskEnvironment.PI_EXHAUSTIVE_ALLOCATION_SHARDS=[string]$Shards}
$taskFailure=$null
try{& (Join-Path $taskEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1') -Name $taskName -Executable $taskZig -WorkingDirectory $taskPrivate -Arguments (@('build')+$taskTargets+@("-Doptimize=$Mode",'-Duse-llvm=true','-j1','--test-timeout','120s','--summary','all')) -TimeoutSeconds $taskTimeout -EnvironmentOverrides $taskEnvironment}catch{$taskFailure=$_.Exception.Message}
$taskCandidateDrift=@(Drift $taskFrozen.candidate);$taskControlDrift=@(Drift $taskFrozen.controls);$taskToolDrift=@(Drift $taskTools);$taskReferenceDrift=@(Drift $taskReferences)
$taskAbsentDrift=@($taskFrozen.historical_absent+$taskFrozen.ambient_absent|Where-Object{Test-Path -LiteralPath $_})
$taskInventoryDrift=@(Compare-Object @($taskFrozen.candidate.path) (CandidatePaths))
$taskTreeDrift=@()
foreach($taskTree in $taskFrozen.ambient_trees){$taskAfter=@(Get-ChildItem -LiteralPath $taskTree.root -File -Force -Recurse|ForEach-Object FullName|Sort-Object);$taskTreeDrift+=@(Compare-Object (@('TREE')+@($taskTree.files)) (@('TREE')+$taskAfter))}
$taskSealDrift=(Get-FileHash -LiteralPath $taskSeal).Hash -cne $taskSealHash
$taskHeadAfter=(& $taskGit -C $taskPrivate rev-parse HEAD).Trim()
$taskDirtyAfter=@(& $taskGit -C $taskPrivate status --porcelain=v1)
$taskOwner=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName.json") -Raw|ConvertFrom-Json
$taskStatus=if($taskFailure -or $taskOwner.status -cne 'passed' -or $taskCandidateDrift.Count -or $taskControlDrift.Count -or $taskToolDrift.Count -or $taskReferenceDrift.Count -or $taskAbsentDrift.Count -or $taskInventoryDrift.Count -or $taskTreeDrift.Count -or $taskSealDrift -or $taskHeadAfter -cne $ExpectedHead -or $taskDirtyAfter.Count){'failed'}else{'passed'}
@{status=$taskStatus;candidate_head=$ExpectedHead;head_after=$taskHeadAfter;dirty_after=$taskDirtyAfter;pair_seal_sha256=$taskSealHash;candidate_files=$taskFrozen.candidate.Count;candidate_drift=$taskCandidateDrift;candidate_inventory_drift=$taskInventoryDrift;controls=$taskFrozen.controls.Count;control_drift=$taskControlDrift;compiler_files=$taskTools.Count;compiler_drift=$taskToolDrift;reference_files=$taskReferences.Count;reference_drift=$taskReferenceDrift;historical_absences=84;ambient_absences=$taskFrozen.ambient_absent.Count;absence_drift=$taskAbsentDrift;ambient_tree_drift=$taskTreeDrift;pair_seal_drift=$taskSealDrift;owner_failure=$taskFailure;owner_pid=$taskOwner.pid;owner_status=$taskOwner.status;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-posthash.json") -Encoding utf8NoBOM
if($taskStatus -cne 'passed'){throw "Actual native parser phase failed: $($taskOwner.status) $taskFailure"}
Write-Output ("NATIVE_PARSER_PHASE_PASS=$Phase PAIR_SHA256=$taskSealHash")

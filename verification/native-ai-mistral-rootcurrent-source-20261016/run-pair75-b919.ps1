param([Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{40}$')][string]$ExpectedHead,[Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9-]+$')][string]$Attempt,[Parameter(Mandatory)][string]$RootGrant)
$ErrorActionPreference='Stop'
$taskPacket=$PSScriptRoot
$taskEvidence='C:/Users/adyba/pi-zig-update-evidence-20261003'
$taskPrivate=[IO.Path]::GetFullPath((Join-Path $taskPacket '../..'))
$taskExpectedHead=$ExpectedHead
$taskName='native-ai-mistral-root7cd-diagnostic75-'+$ExpectedHead.Substring(0,8)+'-'+$Attempt+'-20261016'
$taskZig='C:/Users/adyba/pi-zig-toolchain-20261003/zig-x86_64-windows-0.16.0/zig.exe'
$taskOwner=Join-Path $taskPacket 'run-owned-native.ps1'
$taskToolReference=Join-Path $taskEvidence 'durable-latest89-full-inspect-53ae-tool-prehash-20261011.json'
function Source-Rows { @(git -C $taskPrivate ls-files --cached --others --exclude-standard|Sort-Object -Unique|Where-Object{Test-Path -LiteralPath (Join-Path $taskPrivate $_) -PathType Leaf}|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath (Join-Path $taskPrivate $_)).Hash}}) }
function Drift($rows){$changed=[Collections.Generic.List[string]]::new();foreach($row in $rows){if(!(Test-Path -LiteralPath $row.path -PathType Leaf)){$changed.Add($row.path);continue};$stream=[IO.File]::OpenRead($row.path);try{$actual=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream))}finally{$stream.Dispose()};if($actual -ine $row.sha256){$changed.Add($row.path)}};return @($changed)}
function Source-Drift($before){@(Compare-Object ($before|ForEach-Object{"$($_.path):$($_.sha256)"}) (Source-Rows|ForEach-Object{"$($_.path):$($_.sha256)"}))}
function Admission($phase){[GC]::Collect();[GC]::WaitForPendingFinalizers();[GC]::Collect();$free=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory; $roots=@(Get-CimInstance Win32_Process|Where-Object{$_.ExecutablePath-and($_.ExecutablePath.EndsWith('\zig.exe')-or$_.ExecutablePath-like'C:\Users\adyba\pi-zig*\.zig-cache\*\build.exe'-or$_.ExecutablePath-like'C:\Users\adyba\pi-zig*\.zig-cache\*\test.exe')}|Select-Object ProcessId,ParentProcessId,ExecutablePath,CommandLine,@{n='created_utc';e={([DateTimeOffset]$_.CreationDate).UtcDateTime.ToString('o')}});$record=[ordered]@{status=if($free -lt 16MB -or $roots.Count -ne 0){'admission_failed'}else{'admitted'};candidate=$taskExpectedHead;grant=$RootGrant;slot=2;phase=$phase;free_kib=$free;threshold_kib=16MB;max_other_native_roots=0;other_native_roots=$roots;jobs=1;llvm=$true;compile_timeout_seconds=1320;runtime_timeout_seconds=300;test_timeout_seconds=120;host_await_timeout_seconds=10;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')};$record|ConvertTo-Json -Depth 7|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-$phase-admission.json") -Encoding utf8NoBOM;return $record.status -ceq 'admitted'}
if((Get-FileHash -LiteralPath $taskOwner).Hash -cne 'B91945EF77F91388BB8792959AB29C3A49505B5381BA0994723AC0FC6E0502AB'){throw 'Exact original proven B919 owner required'}
if((git -C $taskPrivate rev-parse HEAD) -cne $taskExpectedHead -or (git -C $taskPrivate status --porcelain)){throw 'Exact clean candidate required'}
if((git -C C:/Users/adyba/pi-upstream-source-5ab7fe7-20261015 rev-parse HEAD) -cne '5ab7fe74c400097b386662205cd93900695b8a71'){throw 'Pinned Source head drift'}
if((Get-FileHash -LiteralPath $taskZig).Hash -cne '086CE9D47BA42F33A514E1A6E04EB1D4A8FA1D75E0868E0213CAAD447C91E864'){throw 'Pinned Zig changed'}
$taskProtected=@((Get-Content -LiteralPath (Join-Path $taskPacket 'protected-root-inputs.json') -Raw|ConvertFrom-Json).protected_rows|ForEach-Object{@{path=(Join-Path $taskPrivate $_.path);sha256=$_.sha256}})
if($taskProtected.Count-ne9543-or@(Drift $taskProtected).Count){throw 'Root7cd protected Engine/AF/Body/HTTP/Models/SDK/node/C/goldens drift'}
$taskBefore=Source-Rows
$taskVendor=@($taskBefore|Where-Object path -like 'vendor/*')
if($taskVendor.Count -ne 1336){throw 'Full Root vendor1336 subset of frozen candidate required'}
$taskTools=(Get-Content -LiteralPath $taskToolReference -Raw|ConvertFrom-Json).inputs
if($taskTools.Count -ne 19546){throw 'Full compiler inventory required'}
$taskSpecs=@(@{name='source';file='source5ab-full-manifest-20261015.json';count=1967},@{name='dependencies';file='durable-19cb534-reference-20261012-all-built-runtime.json';count=31064},@{name='node_tools';file='root-current8a-npm-tools-before.json';count=1774})
$taskRefs=@();foreach($spec in $taskSpecs){$rows=@(Get-Content -LiteralPath (Join-Path $taskEvidence $spec.file) -Raw|ConvertFrom-Json);if($rows.Count -ne $spec.count -or @(Drift $rows).Count){throw "Reference inventory/drift $($spec.name)"};$taskRefs+=@{name=$spec.name;rows=$rows}}
$taskAuditPath=Join-Path $taskEvidence 'source5ab-dependency-contract-audit-20261015.json'
$taskAudit=Get-Content -LiteralPath $taskAuditPath -Raw|ConvertFrom-Json
$taskAbsent=@($taskAudit.pins|Where-Object status -eq 'platform_optional_absent'|ForEach-Object{Join-Path 'C:/Users/adyba/pi-upstream-runtime-19cb534-20261012' $_.path})+@($taskAudit.mismatches|ForEach-Object{Join-Path 'C:/Users/adyba/pi-upstream-runtime-19cb534-20261012' $_.path})
if($taskAbsent.Count -ne 84 -or @($taskAbsent|Where-Object{Test-Path -LiteralPath $_}).Count){throw 'Historical absence drift'}
$taskMetadataHelper=Join-Path $taskPrivate 'tools/ci/native_qualification_ci.ps1'
$taskControls=@($PSCommandPath,$taskOwner,(Join-Path $taskPacket 'metadata-discovery.ps1'),(Join-Path $taskPacket 'protected-root-inputs.json'),(Join-Path $taskPacket 'root-base-full-before.json'),$taskToolReference,$taskAuditPath,$taskMetadataHelper,(Join-Path $taskPacket 'planned75-tests.json'))+@($taskSpecs|ForEach-Object{Join-Path $taskEvidence $_.file})|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}}
$taskBefore|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-source-before.json") -Encoding utf8NoBOM
$taskControls|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-controls-before.json") -Encoding utf8NoBOM
if(@(Drift $taskTools).Count -or @(Drift $taskControls).Count){throw 'Compiler/control prehash drift'}
$taskBinariesBefore=@(if(Test-Path -LiteralPath (Join-Path $taskPrivate '.zig-cache/o') -PathType Container){Get-ChildItem -LiteralPath (Join-Path $taskPrivate '.zig-cache/o') -Filter test.exe -Recurse -File|ForEach-Object FullName})
$taskCompile=$null;$taskRuntime=$null;$taskMetadata=$null;$taskArtifacts=@();$taskFailure=$null
try{
 if(!(Admission 'compile')){throw 'Fresh compile admission denied'}
 & $taskOwner -ReceiptBase (Join-Path $taskEvidence "$taskName-compile") -Executable $taskZig -WorkingDirectory $taskPrivate -Arguments @('build','build-native-ai-http-checkpoint','-Doptimize=Debug','-Duse-llvm=true','-j1','--test-timeout','120s','--summary','all') -TimeoutSeconds 1320
 $taskCompile=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName-compile.process.json") -Raw|ConvertFrom-Json
 $taskBetweenSource=@(Source-Drift $taskBefore);$taskBetweenTools=@(Drift $taskTools);$taskBetweenControls=@(Drift $taskControls);$taskBetweenRefs=@($taskRefs|ForEach-Object{@{name=$_.name;count=$_.rows.Count;drift=@(Drift $_.rows).Count}});$taskBetweenAbsent=@($taskAbsent|Where-Object{Test-Path -LiteralPath $_})
 [ordered]@{candidate=$taskExpectedHead;source_drift=$taskBetweenSource.Count;vendor=1336;vendor_subset_of_candidate=$true;vendor_drift=@($taskBetweenSource|Where-Object InputObject -like 'vendor/*').Count;compiler_drift=$taskBetweenTools.Count;control_drift=$taskBetweenControls.Count;references=$taskBetweenRefs;absence_drift=$taskBetweenAbsent.Count;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 7|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-compile-posthash.json") -Encoding utf8NoBOM
 if($taskBetweenSource.Count -or $taskBetweenTools.Count -or $taskBetweenControls.Count -or @($taskBetweenRefs|Where-Object drift -ne 0).Count -or $taskBetweenAbsent.Count){throw 'Compile posthash drift; runtime prohibited'}
 if($taskCompile.status -cne 'passed'){throw 'Compilation did not pass; runtime prohibited'}
 if(!(Admission 'metadata')){throw 'Fresh metadata admission denied'}
 . $taskMetadataHelper
 . (Join-Path $taskPacket 'metadata-discovery.ps1')
 $taskNewArtifacts=@(Get-ChildItem -LiteralPath (Join-Path $taskPrivate '.zig-cache/o') -Filter test.exe -Recurse -File|Where-Object FullName -NotIn $taskBinariesBefore)
 if($taskNewArtifacts.Count -ne 1){throw 'Exactly one newly compiled Source30 and shared scheduling test artifact required'}
 $taskExpectedNames=@(Get-Content -LiteralPath (Join-Path $taskPacket 'planned75-tests.json') -Raw|ConvertFrom-Json)
 if($taskExpectedNames.Count -ne 75){throw 'Exact original74 names plus realpeer incremental-before-EOF regression required'}
 $taskMetadata=Read-RootCompositionMetadata $taskNewArtifacts[0].FullName $taskPrivate (Join-Path $taskEvidence "$taskName-metadata-probe") $taskExpectedNames
 $taskControls+=@{path=(Join-Path $taskEvidence "$taskName-metadata-probe-frozen-all-names.json");sha256=(Get-FileHash -LiteralPath (Join-Path $taskEvidence "$taskName-metadata-probe-frozen-all-names.json")).Hash}
 $taskMetadata|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-metadata-selected.json") -Encoding utf8NoBOM
 $taskArtifacts=@($taskNewArtifacts|ForEach-Object{[ordered]@{path=$_.FullName;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}})
 $taskArtifacts|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-artifacts-before.json") -Encoding utf8NoBOM
 $taskMetadataSource=@(Source-Drift $taskBefore);$taskMetadataTools=@(Drift $taskTools);$taskMetadataControls=@(Drift $taskControls);$taskMetadataRefs=@($taskRefs|ForEach-Object{@{name=$_.name;count=$_.rows.Count;drift=@(Drift $_.rows).Count}});$taskMetadataAbsent=@($taskAbsent|Where-Object{Test-Path -LiteralPath $_})
 [ordered]@{candidate=$taskExpectedHead;source_drift=$taskMetadataSource.Count;compiler_drift=$taskMetadataTools.Count;control_drift=$taskMetadataControls.Count;references=$taskMetadataRefs;absence_drift=$taskMetadataAbsent.Count;artifacts=$taskArtifacts;artifact_drift=@(Drift $taskArtifacts).Count;metadata=$taskMetadata;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 9|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-metadata-posthash.json") -Encoding utf8NoBOM
 if($taskMetadataSource.Count -or $taskMetadataTools.Count -or $taskMetadataControls.Count -or @($taskMetadataRefs|Where-Object drift -ne 0).Count -or $taskMetadataAbsent.Count -or @(Drift $taskArtifacts).Count){throw 'Metadata full posthash drift; runtime prohibited'}
 if(!(Admission 'runtime')){throw 'Fresh runtime admission denied'}
 & $taskOwner -ReceiptBase (Join-Path $taskEvidence "$taskName-runtime") -Executable $taskZig -WorkingDirectory $taskPrivate -Arguments @('build','test-native-ai-http-checkpoint','-Doptimize=Debug','-Duse-llvm=true','-j1','--test-timeout','120s','--summary','all') -TimeoutSeconds 300
 $taskRuntime=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName-runtime.process.json") -Raw|ConvertFrom-Json
} catch {$taskFailure=$_.Exception.Message} finally {
 if(!$taskCompile -and (Test-Path -LiteralPath (Join-Path $taskEvidence "$taskName-compile.process.json"))){$taskCompile=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName-compile.process.json") -Raw|ConvertFrom-Json}
 if(!$taskRuntime -and (Test-Path -LiteralPath (Join-Path $taskEvidence "$taskName-runtime.process.json"))){$taskRuntime=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName-runtime.process.json") -Raw|ConvertFrom-Json}
 $taskSourceDrift=@(Source-Drift $taskBefore);$taskToolDrift=@(Drift $taskTools);$taskControlDrift=@(Drift $taskControls);$taskRefPost=@($taskRefs|ForEach-Object{@{name=$_.name;count=$_.rows.Count;drift=@(Drift $_.rows).Count}});$taskAbsentPost=@($taskAbsent|Where-Object{Test-Path -LiteralPath $_})
 [ordered]@{candidate=$taskExpectedHead;scope='SOURCE-ONLY ROOT7cd composition pending actualdiagnostic75+allactualextraimports; original75 planned retained; historical74/75 negative is not Rootpass';source=$taskBefore.Count;source_drift=$taskSourceDrift.Count;vendor=1336;vendor_subset_of_candidate=$true;vendor_drift=@($taskSourceDrift|Where-Object InputObject -like 'vendor/*').Count;compiler=19546;compiler_drift=$taskToolDrift.Count;controls=$taskControls.Count;control_drift=$taskControlDrift.Count;references=$taskRefPost;absence_records=84;absence_drift=$taskAbsentPost.Count;artifact_drift=@(Drift $taskArtifacts).Count;metadata_count=if($taskMetadata){$taskMetadata.tests.Count}else{$null};compile=if($taskCompile){$taskCompile.status}else{'not_run'};runtime=if($taskRuntime){$taskRuntime.status}else{'not_run'};failure=$taskFailure;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 8|Tee-Object -FilePath (Join-Path $taskEvidence "$taskName-posthash.json")
}
if($taskFailure -or @(Drift $taskArtifacts).Count -or $taskSourceDrift.Count -or $taskToolDrift.Count -or $taskControlDrift.Count -or @($taskRefPost|Where-Object drift -ne 0).Count -or $taskAbsentPost.Count -or !$taskRuntime -or $taskRuntime.status -cne 'passed'){exit 1}

$ErrorActionPreference='Stop'
$taskEvidence=$PSScriptRoot
$taskPrivate='C:/Users/adyba/pi-zig-ai-google-mistral-20261015'
$taskExpectedHead='1c22a18117dcd1047e9c1fa8a6e8c94ef66362fb'
$taskName='native-ai-google-mistral-components-1c22a181-debug-first-20261015'
$taskZig='C:/Users/adyba/pi-zig-toolchain-20261003/zig-x86_64-windows-0.16.0/zig.exe'
$taskOwner=Join-Path $taskEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1'
$taskToolReference=Join-Path $taskEvidence 'durable-latest89-full-inspect-53ae-tool-prehash-20261011.json'
function Source-Rows { @(git -C $taskPrivate ls-files --cached --others --exclude-standard|Sort-Object -Unique|Where-Object{Test-Path -LiteralPath (Join-Path $taskPrivate $_) -PathType Leaf}|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath (Join-Path $taskPrivate $_)).Hash}}) }
function Drift($rows){$changed=[Collections.Generic.List[string]]::new();foreach($row in $rows){if(!(Test-Path -LiteralPath $row.path -PathType Leaf)){$changed.Add($row.path);continue};$stream=[IO.File]::OpenRead($row.path);try{$actual=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream))}finally{$stream.Dispose()};if($actual -ine $row.sha256){$changed.Add($row.path)}};return @($changed)}
function Source-Drift($before){@(Compare-Object ($before|ForEach-Object{"$($_.path):$($_.sha256)"}) (Source-Rows|ForEach-Object{"$($_.path):$($_.sha256)"}))}
function Admission($phase){[GC]::Collect();[GC]::WaitForPendingFinalizers();[GC]::Collect();$free=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory;$roots=@(Get-CimInstance Win32_Process -Filter "Name = 'zig.exe'"|Where-Object{$_.CommandLine -match '\sbuild\s'}|Select-Object ProcessId,ParentProcessId,ExecutablePath,CommandLine,@{n='created_utc';e={([DateTimeOffset]$_.CreationDate).UtcDateTime.ToString('o')}});$record=[ordered]@{status=if($free -lt 16MB -or $roots.Count -ge 4){'admission_failed'}else{'admitted'};candidate=$taskExpectedHead;slot=3;phase=$phase;free_kib=$free;threshold_kib=16MB;max_native_roots=4;other_native_roots=$roots;jobs=1;llvm=$true;compile_timeout_seconds=1320;runtime_timeout_seconds=300;test_timeout_seconds=120;host_await_timeout_seconds=10;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')};$record|ConvertTo-Json -Depth 7|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-$phase-admission.json") -Encoding utf8NoBOM;return $record.status -ceq 'admitted'}
if((git -C $taskPrivate rev-parse HEAD) -cne $taskExpectedHead -or (git -C $taskPrivate status --porcelain)){throw 'Exact clean candidate required'}
if((git -C C:/Users/adyba/pi-upstream-source-5ab7fe7-20261015 rev-parse HEAD) -cne '5ab7fe74c400097b386662205cd93900695b8a71'){throw 'Pinned Source head drift'}
if((Get-FileHash -LiteralPath $taskZig).Hash -cne '086CE9D47BA42F33A514E1A6E04EB1D4A8FA1D75E0868E0213CAAD447C91E864'){throw 'Pinned Zig changed'}
$taskBefore=Source-Rows
$taskTools=(Get-Content -LiteralPath $taskToolReference -Raw|ConvertFrom-Json).inputs
if($taskTools.Count -ne 19546){throw 'Full compiler inventory required'}
$taskSpecs=@(@{name='source';file='source5ab-full-manifest-20261015.json';count=1967},@{name='dependencies';file='durable-19cb534-reference-20261012-all-built-runtime.json';count=31064},@{name='node_tools';file='root-current8a-npm-tools-before.json';count=1774})
$taskRefs=@();foreach($spec in $taskSpecs){$rows=@(Get-Content -LiteralPath (Join-Path $taskEvidence $spec.file) -Raw|ConvertFrom-Json);if($rows.Count -ne $spec.count -or @(Drift $rows).Count){throw "Reference inventory/drift $($spec.name)"};$taskRefs+=@{name=$spec.name;rows=$rows}}
$taskAuditPath=Join-Path $taskEvidence 'source5ab-dependency-contract-audit-20261015.json'
$taskAudit=Get-Content -LiteralPath $taskAuditPath -Raw|ConvertFrom-Json
$taskAbsent=@($taskAudit.pins|Where-Object status -eq 'platform_optional_absent'|ForEach-Object{Join-Path 'C:/Users/adyba/pi-upstream-runtime-19cb534-20261012' $_.path})+@($taskAudit.mismatches|ForEach-Object{Join-Path 'C:/Users/adyba/pi-upstream-runtime-19cb534-20261012' $_.path})
if($taskAbsent.Count -ne 84 -or @($taskAbsent|Where-Object{Test-Path -LiteralPath $_}).Count){throw 'Historical absence drift'}
$taskControls=@($PSCommandPath,$taskOwner,$taskToolReference,$taskAuditPath)+@($taskSpecs|ForEach-Object{Join-Path $taskEvidence $_.file})|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}}
$taskBefore|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-source-before.json") -Encoding utf8NoBOM
$taskControls|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-controls-before.json") -Encoding utf8NoBOM
if(@(Drift $taskTools).Count -or @(Drift $taskControls).Count){throw 'Compiler/control prehash drift'}
$taskCompile=$null;$taskRuntime=$null;$taskFailure=$null
try{
 if(!(Admission 'compile')){throw 'Fresh compile admission denied'}
 & $taskOwner -Name "$taskName-compile" -Executable $taskZig -WorkingDirectory $taskPrivate -Arguments @('build','build-native-ai-google-mistral-components','-Doptimize=Debug','-Duse-llvm=true','-j1','--test-timeout','120s','--summary','all') -TimeoutSeconds 1320
 $taskCompile=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName-compile.json") -Raw|ConvertFrom-Json
 $taskBetweenSource=@(Source-Drift $taskBefore);$taskBetweenTools=@(Drift $taskTools);$taskBetweenControls=@(Drift $taskControls);$taskBetweenRefs=@($taskRefs|ForEach-Object{@{name=$_.name;count=$_.rows.Count;drift=@(Drift $_.rows).Count}});$taskBetweenAbsent=@($taskAbsent|Where-Object{Test-Path -LiteralPath $_})
 [ordered]@{candidate=$taskExpectedHead;source_drift=$taskBetweenSource.Count;compiler_drift=$taskBetweenTools.Count;control_drift=$taskBetweenControls.Count;references=$taskBetweenRefs;absence_drift=$taskBetweenAbsent.Count;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 7|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-compile-posthash.json") -Encoding utf8NoBOM
 if($taskBetweenSource.Count -or $taskBetweenTools.Count -or $taskBetweenControls.Count -or @($taskBetweenRefs|Where-Object drift -ne 0).Count -or $taskBetweenAbsent.Count){throw 'Compile posthash drift; runtime prohibited'}
 if($taskCompile.status -cne 'passed'){throw 'Compilation did not pass; runtime prohibited'}
 if(!(Admission 'runtime')){throw 'Fresh runtime admission denied'}
 & $taskOwner -Name "$taskName-runtime" -Executable $taskZig -WorkingDirectory $taskPrivate -Arguments @('build','test-native-ai-google-mistral-components','-Doptimize=Debug','-Duse-llvm=true','-j1','--test-timeout','120s','--summary','all') -TimeoutSeconds 300
 $taskRuntime=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName-runtime.json") -Raw|ConvertFrom-Json
} catch {$taskFailure=$_.Exception.Message} finally {
 $taskSourceDrift=@(Source-Drift $taskBefore);$taskToolDrift=@(Drift $taskTools);$taskControlDrift=@(Drift $taskControls);$taskRefPost=@($taskRefs|ForEach-Object{@{name=$_.name;count=$_.rows.Count;drift=@(Drift $_.rows).Count}});$taskAbsentPost=@($taskAbsent|Where-Object{Test-Path -LiteralPath $_})
 [ordered]@{candidate=$taskExpectedHead;scope='functional30/request27/retainedGC/fullhostOOM component; strict full-snapshot negative preserved separately';source=$taskBefore.Count;source_drift=$taskSourceDrift.Count;compiler=19546;compiler_drift=$taskToolDrift.Count;controls=$taskControls.Count;control_drift=$taskControlDrift.Count;references=$taskRefPost;absence_records=84;absence_drift=$taskAbsentPost.Count;compile=if($taskCompile){$taskCompile.status}else{'not_run'};runtime=if($taskRuntime){$taskRuntime.status}else{'not_run'};failure=$taskFailure;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 8|Tee-Object -FilePath (Join-Path $taskEvidence "$taskName-posthash.json")
}
if($taskFailure -or $taskSourceDrift.Count -or $taskToolDrift.Count -or $taskControlDrift.Count -or @($taskRefPost|Where-Object drift -ne 0).Count -or $taskAbsentPost.Count -or !$taskRuntime -or $taskRuntime.status -cne 'passed'){exit 1}

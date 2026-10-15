$ErrorActionPreference='Stop'
$taskEvidence=$PSScriptRoot
$taskPrivate='C:/Users/adyba/pi-zig-ai-google-mistral-20261015'
$taskExpectedHead='1c22a18117dcd1047e9c1fa8a6e8c94ef66362fb'
$taskName='native-ai-google-mistral-components-1c22a181-runtime-only-first-20261015'
$taskCompileName='native-ai-google-mistral-components-1c22a181-debug-first-20261015'
$taskExe=Join-Path $taskPrivate '.zig-cache/o/1635524a1e24730f35977181387a205b/test.exe'
$taskExeHash='0214E2F94BD706194F8D2B43546959AA2107992D0E5A0C9BB9183F508B73A85D'
$taskOwner=Join-Path $taskEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1'
function Rows{ @(git -C $taskPrivate ls-files --cached --others --exclude-standard|Sort-Object -Unique|Where-Object{Test-Path -LiteralPath (Join-Path $taskPrivate $_) -PathType Leaf}|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath (Join-Path $taskPrivate $_)).Hash}}) }
function Drift($rows){$changed=[Collections.Generic.List[string]]::new();foreach($row in $rows){if(!(Test-Path -LiteralPath $row.path -PathType Leaf)){$changed.Add($row.path);continue};$stream=[IO.File]::OpenRead($row.path);try{$actual=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream))}finally{$stream.Dispose()};if($actual -ine $row.sha256){$changed.Add($row.path)}};return @($changed)}
$taskCompilePath=Join-Path $taskEvidence "$taskCompileName-compile.json"
$taskPostPath=Join-Path $taskEvidence "$taskCompileName-posthash.json"
$taskCompile=Get-Content -LiteralPath $taskCompilePath -Raw|ConvertFrom-Json
$taskPost=Get-Content -LiteralPath $taskPostPath -Raw|ConvertFrom-Json
if($taskCompile.status -cne 'passed' -or $taskCompile.exit_code -ne 0 -or $taskPost.candidate -cne $taskExpectedHead -or $taskPost.source_drift -or $taskPost.compiler_drift -or $taskPost.control_drift -or $taskPost.absence_drift -or @($taskPost.references|Where-Object drift -ne 0).Count){throw 'Matching compile PASS/full terminal post0 required'}
if((git -C $taskPrivate rev-parse HEAD) -cne $taskExpectedHead -or (git -C $taskPrivate status --porcelain)){throw 'Exact clean candidate required'}
$taskBefore=@(Get-Content -LiteralPath (Join-Path $taskEvidence "$taskCompileName-source-before.json") -Raw|ConvertFrom-Json)
function CandidateDrift{ @(Compare-Object @($taskBefore|ForEach-Object{"$($_.path):$($_.sha256)"}) @(Rows|ForEach-Object{"$($_.path):$($_.sha256)"})) }
if(@(CandidateDrift).Count){throw 'Frozen compile source drift before runtime'}
$taskToolManifest=Join-Path $taskEvidence 'durable-latest89-full-inspect-53ae-tool-prehash-20261011.json'
$taskTools=(Get-Content -LiteralPath $taskToolManifest -Raw|ConvertFrom-Json).inputs
if($taskTools.Count -ne 19546 -or @(Drift $taskTools).Count){throw 'Full compiler drift'}
$taskSpecs=@(@{name='source';file='source5ab-full-manifest-20261015.json';count=1967},@{name='dependencies';file='durable-19cb534-reference-20261012-all-built-runtime.json';count=31064},@{name='node_tools';file='root-current8a-npm-tools-before.json';count=1774})
$taskRefs=@();foreach($spec in $taskSpecs){$rows=@(Get-Content -LiteralPath (Join-Path $taskEvidence $spec.file) -Raw|ConvertFrom-Json);if($rows.Count -ne $spec.count -or @(Drift $rows).Count){throw "Reference drift $($spec.name)"};$taskRefs+=@{name=$spec.name;rows=$rows}}
$taskAuditPath=Join-Path $taskEvidence 'source5ab-dependency-contract-audit-20261015.json'
$taskAudit=Get-Content -LiteralPath $taskAuditPath -Raw|ConvertFrom-Json
$taskAbsent=@($taskAudit.pins|Where-Object status -eq 'platform_optional_absent'|ForEach-Object{Join-Path 'C:/Users/adyba/pi-upstream-runtime-19cb534-20261012' $_.path})+@($taskAudit.mismatches|ForEach-Object{Join-Path 'C:/Users/adyba/pi-upstream-runtime-19cb534-20261012' $_.path})
if($taskAbsent.Count -ne 84 -or @($taskAbsent|Where-Object{Test-Path -LiteralPath $_}).Count){throw 'Absence drift'}
$taskCompileControls=@(Get-Content -LiteralPath (Join-Path $taskEvidence "$taskCompileName-controls-before.json") -Raw|ConvertFrom-Json)
if(@(Drift $taskCompileControls).Count){throw 'Compile controls drift'}
$taskControls=@($taskCompileControls)+@(@($PSCommandPath,$taskExe,$taskCompilePath,$taskPostPath,(Join-Path $taskEvidence "$taskCompileName-source-before.json"),(Join-Path $taskEvidence "$taskCompileName-controls-before.json"))|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})
$taskControls|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-controls-before.json") -Encoding utf8NoBOM
if((Get-FileHash -LiteralPath $taskExe).Hash -cne $taskExeHash){throw 'Compiled artifact digest drift'}
$taskArtifact=Get-Item -LiteralPath $taskExe
if($taskArtifact.LastWriteTimeUtc -lt ([datetime]$taskCompile.created_utc) -or $taskArtifact.LastWriteTimeUtc -gt ([datetime]$taskCompile.completed_utc)){throw 'Artifact timestamp is outside matching compile interval'}
$taskRuntime=$null;$taskFailure=$null
try{
 [GC]::Collect();[GC]::WaitForPendingFinalizers();[GC]::Collect()
 $free=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
 $roots=@(Get-CimInstance Win32_Process -Filter "Name = 'zig.exe'"|Where-Object{$_.CommandLine -match '\sbuild\s'}|Select-Object ProcessId,ExecutablePath,CommandLine)
 $admitted=$free -ge 16MB -and $roots.Count -lt 4
 [ordered]@{status=if($admitted){'admitted'}else{'admission_failed'};candidate=$taskExpectedHead;slot=3;free_kib=$free;required_kib=16MB;max_roots=4;other_roots=$roots;compile='not_invoked';artifact=$taskExe;artifact_sha256=$taskExeHash;runtime_upper_seconds=300;all_tests_deadline_seconds=120;test_deadline_seconds=120;host_await_seconds=10;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 7|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-admission.json") -Encoding utf8NoBOM
 if(!$admitted){throw 'Fresh runtime admission denied'}
 & $taskOwner -Name $taskName -Executable $taskExe -WorkingDirectory $taskPrivate -Arguments @('--seed=0') -TimeoutSeconds 120
 $taskRuntime=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName.json") -Raw|ConvertFrom-Json
} catch {$taskFailure=$_.Exception.Message} finally {
 $taskSourceDrift=@(CandidateDrift);$taskToolDrift=@(Drift $taskTools);$taskControlDrift=@(Drift $taskControls);$taskRefsPost=@($taskRefs|ForEach-Object{@{name=$_.name;count=$_.rows.Count;drift=@(Drift $_.rows).Count}});$taskAbsentDrift=@($taskAbsent|Where-Object{Test-Path -LiteralPath $_})
 [ordered]@{candidate=$taskExpectedHead;scope='functional30/request27/retainedGC/fullhostOOM component only; strict snapshot negative preserved';artifact=$taskExe;artifact_sha256=$taskExeHash;compile='matching prior PASS';runtime=if($taskRuntime){$taskRuntime.status}else{'not_run'};source=$taskBefore.Count;source_drift=$taskSourceDrift.Count;compiler=19546;compiler_drift=$taskToolDrift.Count;controls=$taskControls.Count;control_drift=$taskControlDrift.Count;references=$taskRefsPost;absence_records=84;absence_drift=$taskAbsentDrift.Count;failure=$taskFailure;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 8|Tee-Object -FilePath (Join-Path $taskEvidence "$taskName-posthash.json")
}
if($taskFailure -or $taskSourceDrift.Count -or $taskToolDrift.Count -or $taskControlDrift.Count -or @($taskRefsPost|Where-Object drift -ne 0).Count -or $taskAbsentDrift.Count -or !$taskRuntime -or $taskRuntime.status -cne 'passed'){exit 1}

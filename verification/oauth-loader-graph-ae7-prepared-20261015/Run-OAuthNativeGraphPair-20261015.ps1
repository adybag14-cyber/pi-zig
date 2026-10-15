param(
    [switch]$RootNativeGrant,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{40}$')][string]$ExpectedHead,
    [ValidateSet('loader','nine-flows')][string]$Scope='loader',
    [ValidatePattern('^[A-Za-z0-9_-]+$')][string]$Attempt='first'
)
$ErrorActionPreference='Stop'
if(!$RootNativeGrant){throw 'An explicit exact-head Root native grant is required'}
$taskReference='C:/Users/adyba/pi-zig-update-evidence-20261003'
$taskTree=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$taskZig='C:/Users/adyba/pi-zig-toolchain-20261003/zig-x86_64-windows-0.16.0/zig.exe'
$taskOwner=Join-Path $taskReference 'Invoke-OwnedEeSourceJob-20261012.ps1'
$taskUnique=[DateTimeOffset]::UtcNow.ToString('yyyyMMddTHHmmssfffffffZ')+'-'+[Guid]::NewGuid().ToString('N')
$taskName="native-oauth-$Scope-$($ExpectedHead.Substring(0,8))-$Attempt-$taskUnique"
$taskBase=Join-Path $taskReference $taskName
$taskTarget=if($Scope -ceq 'loader'){'native-ai-oauth-loader-graph'}else{'native-ai-oauth-nine-flow'}
if((git -C $taskTree rev-parse HEAD) -cne $ExpectedHead -or (git -C $taskTree status --porcelain)){throw 'Exact clean candidate required before native prehash'}
if((Get-FileHash -LiteralPath $taskZig).Hash -cne '086CE9D47BA42F33A514E1A6E04EB1D4A8FA1D75E0868E0213CAAD447C91E864'){throw 'Pinned Zig0.16 executable changed'}
function Candidate-Rows {
    @(git -C $taskTree ls-files|ForEach-Object {[ordered]@{path=(Join-Path $taskTree $_);sha256=(Get-FileHash -LiteralPath (Join-Path $taskTree $_)).Hash}})
}
function Row-Drift($taskRows){
    @($taskRows|Where-Object {!(Test-Path -LiteralPath $_.path -PathType Leaf) -or (Get-FileHash -LiteralPath $_.path).Hash -ine $_.sha256}|ForEach-Object path)
}
$taskCandidate=Candidate-Rows
$taskVendor=@(Get-ChildItem -LiteralPath (Join-Path $taskTree 'vendor') -File -Recurse -Force|ForEach-Object {[ordered]@{path=$_.FullName;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}})
$taskToolManifest=Join-Path $taskReference 'durable-latest89-full-inspect-53ae-tool-prehash-20261011.json'
$taskTools=@((Get-Content -LiteralPath $taskToolManifest -Raw|ConvertFrom-Json).inputs)
if($taskTools.Count -ne 19546){throw 'Complete pinned compiler/library inventory19546 required'}
$taskSpecs=@(
    @{name='source';file='sourceae7-full-manifest-20261015.json';count=1968},
    @{name='dependencies';file='sourceae7-runtime-manifest-20261015.json';count=31064},
    @{name='node_tools';file='sourceae7-node-tools-before-20261015.json';count=1774},
    @{name='preparation';file='sourceae7-preparation-controls-20261015.json';count=5}
)
$taskImmutable=@()
foreach($spec in $taskSpecs){
    $path=Join-Path $taskReference $spec.file
    $rows=@(Get-Content -LiteralPath $path -Raw|ConvertFrom-Json)
    if($rows.Count -ne $spec.count){throw "Immutable inventory mismatch $($spec.name)"}
    $taskImmutable+=@{name=$spec.name;rows=$rows;manifest=$path}
}
$taskAudit=Join-Path $taskReference 'sourceae7-dependency-contract-audit-20261015.json'
$taskContract=Get-Content -LiteralPath $taskAudit -Raw|ConvertFrom-Json
if($taskContract.latestHead -cne 'ae7b16d43b7c78c5b6fa3213fdd1215bb339729d' -or $taskContract.installed_metadata_verified -ne 281){throw 'Actual ae7 dependency audit scope changed'}
$taskRuntime='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012'
$taskAbsent=@($taskContract.pins|Where-Object status -eq 'platform_optional_absent'|ForEach-Object {Join-Path $taskRuntime $_.path})+@($taskContract.mismatches|ForEach-Object {Join-Path $taskRuntime $_.path})
if($taskAbsent.Count -ne 84){throw 'Full historical84 absence inventory required'}
$taskSourceProof=Join-Path $taskTree 'verification/oauth-loader-graph-ae7-source18-20261015/qualification-proof.json'
$taskSourceExpected=Join-Path $taskTree 'src/extensions/fixtures/ai-oauth-loader-graph-ae7-source18.json'
$taskSourceOutput=Join-Path $PSScriptRoot 'ai-oauth-loader-graph-ae7-source-first-20261015T2138301777753Z-6a2efbb58bd74f638536168cbc83e5a5-output.json'
$taskProof=Get-Content -LiteralPath $taskSourceProof -Raw|ConvertFrom-Json
if($taskProof.node_terminal -cne 'passed' -or $taskProof.node_exit_code -ne 0 -or !$taskProof.node_absent -or $taskProof.source_rows -ne 18 -or $taskProof.candidate_drift -ne 0 -or $taskProof.outer_control_drift -ne 0 -or $taskProof.immutable_manifests_drift -ne 0 -or !$taskProof.expected_written_after_both_posthashes){throw 'Genuine Source18 terminal/fullpost0 proof required'}
foreach($file in @($taskSourceExpected,$taskSourceOutput)){if((Get-FileHash -LiteralPath $file).Hash -cne 'BDFA8B2931054050287C00C0699D4E7E9903204944AE0BB5DF7253141A7782D7'){throw 'Original Source18 expected/output bytes changed'}}
$taskControls=@($PSCommandPath,$taskOwner,$taskToolManifest,$taskAudit,$taskSourceProof,$taskSourceExpected,$taskSourceOutput,(Join-Path $taskReference 'env-stream-span-prerequisite-3f0cce9a-20261015/borrowed-live-view-span-only.patch'))+@($taskImmutable|ForEach-Object manifest)
$taskControlRows=@($taskControls|ForEach-Object {[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})
$taskCandidate|ConvertTo-Json -Depth 4|Set-Content -LiteralPath "$taskBase-candidate-before.json" -Encoding utf8NoBOM
$taskVendor|ConvertTo-Json -Depth 4|Set-Content -LiteralPath "$taskBase-vendor-before.json" -Encoding utf8NoBOM
$taskControlRows|ConvertTo-Json -Depth 4|Set-Content -LiteralPath "$taskBase-controls-before.json" -Encoding utf8NoBOM
function Verify-Frozen {
    $result=@()
    foreach($group in @(@{name='candidate';rows=$taskCandidate},@{name='vendor';rows=$taskVendor},@{name='compiler';rows=$taskTools},@{name='controls';rows=$taskControlRows})+$taskImmutable){
        $drift=@(Row-Drift $group.rows)
        $result+=@{name=$group.name;files=$group.rows.Count;drift=$drift.Count;changed=$drift}
    }
    $absent=@($taskAbsent|Where-Object {Test-Path -LiteralPath $_})
    $current=Candidate-Rows
    $inventory=@(Compare-Object ($taskCandidate|ForEach-Object {"$($_.path):$($_.sha256)"}) ($current|ForEach-Object {"$($_.path):$($_.sha256)"}))
    $head=(git -C $taskTree rev-parse HEAD)
    $passed=!(@($result|Where-Object drift -ne 0).Count -or $absent.Count -or $inventory.Count -or $head -cne $ExpectedHead)
    return @{passed=$passed;checks=$result;absences=84;absence_drift=$absent.Count;candidate_inventory_drift=$inventory.Count;candidate_head=$head;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}
}
function Admit-Native([string]$phase){
    [GC]::Collect();[GC]::WaitForPendingFinalizers();[GC]::Collect()
    $free=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory*1024
    $processes=@(Get-CimInstance Win32_Process|Where-Object {$_.ExecutablePath -and ($_.ExecutablePath.EndsWith('\zig.exe') -or $_.ExecutablePath -like 'C:\Users\adyba\pi-zig*\.zig-cache\*\build.exe' -or $_.ExecutablePath -like 'C:\Users\adyba\pi-zig*\.zig-cache\*\test.exe')})
    $ids=@($processes|ForEach-Object ProcessId)
    $roots=@($processes|Where-Object {$_.ParentProcessId -notin $ids})
    @{phase=$phase;free_bytes=$free;required_bytes=16GB;existing_native_roots=$roots.Count;max_native_roots=4;jobs=1;compile_timeout_seconds=1320;runtime_timeout_seconds=300;test_timeout_seconds=120;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 4|Set-Content -LiteralPath "$taskBase-$phase-admission.json" -Encoding utf8NoBOM
    if($free -lt 16GB -or $roots.Count -ge 4){throw 'Normal16GiB/max4-root native admission denied'}
}
$taskBefore=Verify-Frozen
$taskBefore|ConvertTo-Json -Depth 8|Set-Content -LiteralPath "$taskBase-before.json" -Encoding utf8NoBOM
if(!$taskBefore.passed){throw 'Native OAuth prehash drift'}
$taskCompile=$null
$taskRuntimeReceipt=$null
$taskFailure=$null
try {
    Admit-Native 'compile'
    & $taskOwner -Name "$taskName-compile" -Executable $taskZig -WorkingDirectory $taskTree -Arguments @('build',"build-$taskTarget",'-Doptimize=Debug','-Duse-llvm=true','-j1','--test-timeout','120s','--summary','all') -TimeoutSeconds 1320
    $taskCompile=Get-Content -LiteralPath (Join-Path $taskReference "$taskName-compile.json") -Raw|ConvertFrom-Json
    $taskBetween=Verify-Frozen
    $taskBetween|ConvertTo-Json -Depth 8|Set-Content -LiteralPath "$taskBase-between.json" -Encoding utf8NoBOM
    if(!$taskBetween.passed){throw 'Native OAuth drift between compile and runtime'}
    if($taskCompile.status -ceq 'passed' -and $taskCompile.exit_code -eq 0){
        Admit-Native 'runtime'
        & $taskOwner -Name "$taskName-runtime" -Executable $taskZig -WorkingDirectory $taskTree -Arguments @('build',"test-$taskTarget",'-Doptimize=Debug','-Duse-llvm=true','-j1','--test-timeout','120s','--summary','all') -TimeoutSeconds 300
        $taskRuntimeReceipt=Get-Content -LiteralPath (Join-Path $taskReference "$taskName-runtime.json") -Raw|ConvertFrom-Json
    }
} catch {$taskFailure=$_}
finally {
    $taskPost=Verify-Frozen
    $taskPost|ConvertTo-Json -Depth 8|Set-Content -LiteralPath "$taskBase-posthash.json" -Encoding utf8NoBOM
    @{candidate=$ExpectedHead;scope=$Scope;compile=if($taskCompile){$taskCompile.status}else{'not_launched'};runtime=if($taskRuntimeReceipt){$taskRuntimeReceipt.status}else{'not_launched'};all_frozen_post_passed=$taskPost.passed;posthash="$taskBase-posthash.json";completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 4
}
if(!$taskPost.passed){throw 'Native OAuth terminal posthash drift'}
if($taskFailure){throw $taskFailure}
if(!$taskCompile -or $taskCompile.status -cne 'passed' -or $taskCompile.exit_code -ne 0 -or !$taskRuntimeReceipt -or $taskRuntimeReceipt.status -cne 'passed' -or $taskRuntimeReceipt.exit_code -ne 0){exit 1}

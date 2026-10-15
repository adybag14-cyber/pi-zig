param(
    [switch]$RootNativeGrant,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{40}$')][string]$ExpectedHead,
    [ValidatePattern('^[A-Za-z0-9_-]+$')][string]$Attempt='first',
    [ValidateSet('Debug','ReleaseSafe','ReleaseFast','ReleaseSmall')][string]$Mode='Debug'
)
$ErrorActionPreference='Stop'
if(!$RootNativeGrant){throw 'Auth helper native pair requires an explicit Root native slot grant'}
$taskReference='C:/Users/adyba/pi-zig-update-evidence-20261003'
$taskPrivate=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$taskUnique=[DateTimeOffset]::UtcNow.ToString('yyyyMMddTHHmmssfffffffZ')+'-'+[Guid]::NewGuid().ToString('N')
$taskName="native-auth-helpers-$($ExpectedHead.Substring(0,8))-$Mode-$Attempt-$taskUnique"
$taskZig='C:/Users/adyba/pi-zig-toolchain-20261003/zig-x86_64-windows-0.16.0/zig.exe'
$taskOwner=Join-Path $taskReference 'Invoke-OwnedEeSourceJob-20261012.ps1'
$taskToolReference=Join-Path $taskReference 'durable-latest89-full-inspect-53ae-tool-prehash-20261011.json'
function Source-Rows {
    @(git -C $taskPrivate ls-files --cached --others --exclude-standard|Sort-Object -Unique|Where-Object {Test-Path -LiteralPath (Join-Path $taskPrivate $_) -PathType Leaf}|ForEach-Object {[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath (Join-Path $taskPrivate $_)).Hash}})
}
function Tool-Drift($taskRows){
    $taskChanged=[Collections.Generic.List[string]]::new()
    foreach($taskRow in $taskRows){
        if(!(Test-Path -LiteralPath $taskRow.path -PathType Leaf)){$taskChanged.Add($taskRow.path);continue}
        $taskStream=[IO.File]::OpenRead($taskRow.path)
        try{$taskHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($taskStream))}finally{$taskStream.Dispose()}
        if($taskHash -cne $taskRow.sha256){$taskChanged.Add($taskRow.path)}
    }
    return @($taskChanged)
}
if((git -C $taskPrivate rev-parse HEAD) -cne $ExpectedHead -or (git -C $taskPrivate status --porcelain)){throw 'Exact clean candidate required before native freeze'}
$taskBefore=Source-Rows
$taskTools=@((Get-Content -LiteralPath $taskToolReference -Raw|ConvertFrom-Json).inputs)
if($taskTools.Count -ne 19546){throw 'Complete pinned compiler tool manifest required'}
$taskControls=@($PSCommandPath,$taskOwner,$taskToolReference)|ForEach-Object {[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}}
if((Get-FileHash -LiteralPath $taskZig).Hash -cne '086CE9D47BA42F33A514E1A6E04EB1D4A8FA1D75E0868E0213CAAD447C91E864'){throw 'Pinned Zig 0.16.0 changed'}
if(@(Tool-Drift $taskTools).Count -or @(Tool-Drift $taskControls).Count){throw 'Native prehash compiler/control drift'}
$taskBefore|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskReference "$taskName-source-before.json") -Encoding utf8NoBOM
$taskControls|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskReference "$taskName-controls-before.json") -Encoding utf8NoBOM
[GC]::Collect();[GC]::WaitForPendingFinalizers();[GC]::Collect()
$taskFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
$taskAdmission=[ordered]@{status=if($taskFree -lt 16MB){'admission_denied'}else{'admitted'};candidate=$ExpectedHead;free_kib=$taskFree;required_kib=16MB;root_grant=$true;source_files=$taskBefore.Count;compiler_files=$taskTools.Count;controls=$taskControls.Count;optimize=$Mode;jobs=1;llvm=$true;compile_timeout_seconds=1320;runtime_outer_timeout_seconds=300;test_timeout_seconds=10;host_await_timeout_seconds=10;native_launched=$false;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}
$taskAdmission|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskReference "$taskName-admission.json") -Encoding utf8NoBOM
if($taskAdmission.status -cne 'admitted'){$taskAdmission|ConvertTo-Json -Depth 5;exit 2}
$taskCompile=$null
$taskRuntime=$null
$taskFailure=$null
try {
    & $taskOwner -Name "$taskName-compile" -Executable $taskZig -WorkingDirectory $taskPrivate -Arguments @('build','build-native-ai-auth-helpers',"-Doptimize=$Mode",'-Duse-llvm=true','-j1','--test-timeout','10s','--summary','all') -TimeoutSeconds 1320
    $taskCompile=Get-Content -LiteralPath (Join-Path $taskReference "$taskName-compile.json") -Raw|ConvertFrom-Json
    if($taskCompile.status -ceq 'passed'){
        $taskBetween=Source-Rows
        if(@(Compare-Object ($taskBefore|ForEach-Object {"$($_.path):$($_.sha256)"}) ($taskBetween|ForEach-Object {"$($_.path):$($_.sha256)"})).Count -or @(Tool-Drift $taskTools).Count -or @(Tool-Drift $taskControls).Count){throw 'Native pair drift before runtime'}
        if((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory -lt 16MB){throw 'Fresh runtime admission below normal 16 GiB'}
        & $taskOwner -Name "$taskName-runtime" -Executable $taskZig -WorkingDirectory $taskPrivate -Arguments @('build','test-native-ai-auth-helpers',"-Doptimize=$Mode",'-Duse-llvm=true','-j1','--test-timeout','10s','--summary','all') -TimeoutSeconds 300
        $taskRuntime=Get-Content -LiteralPath (Join-Path $taskReference "$taskName-runtime.json") -Raw|ConvertFrom-Json
    }
} catch { $taskFailure=$_ }
finally {
    $taskAfter=Source-Rows
    $taskSourceDrift=@(Compare-Object ($taskBefore|ForEach-Object {"$($_.path):$($_.sha256)"}) ($taskAfter|ForEach-Object {"$($_.path):$($_.sha256)"}))
    $taskToolDrift=@(Tool-Drift $taskTools)
    $taskControlDrift=@(Tool-Drift $taskControls)
    [ordered]@{candidate=$ExpectedHead;candidate_after=(git -C $taskPrivate rev-parse HEAD);source_files=$taskBefore.Count;source_files_after=$taskAfter.Count;source_drift=$taskSourceDrift.Count;compiler_files=$taskTools.Count;compiler_drift=$taskToolDrift.Count;controls=$taskControls.Count;control_drift=$taskControlDrift.Count;compile=if($taskCompile){$taskCompile.status}else{'unknown'};runtime=if($taskRuntime){$taskRuntime.status}else{'not_run'};completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Tee-Object -FilePath (Join-Path $taskReference "$taskName-posthash.json")
}
if($taskSourceDrift.Count -or $taskToolDrift.Count -or $taskControlDrift.Count){throw 'Native pair terminal posthash drift'}
if($taskFailure){throw $taskFailure}
if(!$taskCompile -or $taskCompile.status -cne 'passed' -or !$taskRuntime -or $taskRuntime.status -cne 'passed'){exit 1}

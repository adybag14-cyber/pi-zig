param([ValidateSet('Debug','ReleaseSafe')][string]$Mode='Debug',[ValidateSet('Compile','Runtime')][string]$Phase='Compile',[string]$Attempt='first')
$ErrorActionPreference='Stop'
$taskEvidence=$PSScriptRoot
$taskPrivate='C:/Users/adyba/pi-zig-highlight-lazy-batch1-20261015'
$taskZig='C:/Users/adyba/pi-zig-toolchain-20261003/zig-x86_64-windows-0.16.0/zig.exe'
$taskName="highlight-lazy-batch1-$($Mode.ToLowerInvariant())-$($Phase.ToLowerInvariant())-$Attempt-20261015"
function Check-Rows($rows){
 @($rows|Where-Object{!(Test-Path -LiteralPath $_.path -PathType Leaf) -or (Get-FileHash -LiteralPath $_.path).Hash -ine $_.sha256})
}
function Source-Rows{
 @(git -C $taskPrivate ls-files --cached --others --exclude-standard|Sort-Object -Unique|Where-Object{Test-Path -LiteralPath (Join-Path $taskPrivate $_) -PathType Leaf}|ForEach-Object{@{path=(Join-Path $taskPrivate $_);relative=$_;sha256=(Get-FileHash -LiteralPath (Join-Path $taskPrivate $_)).Hash}})
}
$taskToolManifest=Join-Path $taskEvidence 'durable-latest89-full-inspect-53ae-tool-prehash-20261011.json'
$taskTools=@((Get-Content -LiteralPath $taskToolManifest -Raw|ConvertFrom-Json).inputs)
if($taskTools.Count -ne 19546 -or @(Check-Rows $taskTools).Count){throw 'Full pinned Zig manifest mismatch'}
if((Get-FileHash -LiteralPath $taskZig).Hash -cne '086CE9D47BA42F33A514E1A6E04EB1D4A8FA1D75E0868E0213CAAD447C91E864'){throw 'Zig0.16 pin mismatch'}
$taskExpected=Join-Path $taskPrivate 'src/extensions/fixtures/sdk-highlight-lazy-batch1-10_7_3.json'
if((Get-FileHash -LiteralPath $taskExpected).Hash -cne '17D9117F4F5F94DE6FD2A25C9C2CF162D5CAE40FD656FB35802021BA88B00CD3'){throw 'Genuine Source29 fixture mismatch'}
$taskBefore=Source-Rows
$taskBefore|ConvertTo-Json -Depth 4|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-source-before.json") -Encoding utf8NoBOM
$taskControls=@($PSCommandPath,(Join-Path $taskEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1'),$taskToolManifest,(Join-Path $taskEvidence 'highlight-lazy-batch1-source29-first-20261015.json'),(Join-Path $taskEvidence 'highlight-lazy-batch1-source29-first-20261015-posthash.json'))|ForEach-Object{@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}}
$taskControls|ConvertTo-Json -Depth 4|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-controls-before.json") -Encoding utf8NoBOM
$taskFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
@{status=if($taskFree -lt 16MB){'denied'}else{'admitted'};free_kib=$taskFree;required_kib=16MB;max_coordinated_jobs=4;jobs=1;test_timeout_seconds=120;host_await_timeout_seconds=10;cases=29;baseline='733800b8b872d86c5766dc4a30cf44ae8d373254';observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-admission.json") -Encoding utf8NoBOM
if($taskFree -lt 16MB){throw 'Normal native16GiB admission denied'}
$taskTarget=if($Phase -eq 'Compile'){'build-native-highlight-lazy-batch1'}else{'test-native-highlight-lazy-batch1'}
try{
 & (Join-Path $taskEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1') -Name $taskName -Executable $taskZig -WorkingDirectory $taskPrivate -Arguments @('build',$taskTarget,"-Doptimize=$Mode",'-Duse-llvm=true','-j1','--test-timeout','120s','--summary','all') -TimeoutSeconds $(if($Phase -eq 'Compile'){1320}else{300})
}finally{
 $taskAfter=Source-Rows
 $taskSourceDrift=@(Compare-Object @($taskBefore|ForEach-Object{"$($_.relative):$($_.sha256)"}) @($taskAfter|ForEach-Object{"$($_.relative):$($_.sha256)"}))
 $taskToolDrift=@(Check-Rows $taskTools)
 $taskControlDrift=@(Check-Rows $taskControls)
 @{source=$taskBefore.Count;source_after=$taskAfter.Count;source_drift=$taskSourceDrift.Count;zig_tools=$taskTools.Count;zig_tool_drift=$taskToolDrift.Count;control_drift=$taskControlDrift.Count;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-posthash.json") -Encoding utf8NoBOM
 if($taskSourceDrift.Count -or $taskToolDrift.Count -or $taskControlDrift.Count){throw 'Native29 immutable input drift'}
}
$taskOwner=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName.json") -Raw|ConvertFrom-Json
if($taskOwner.status -cne 'passed'){throw 'Native29 terminal failure'}
Write-Output "NATIVE_HIGHLIGHT_LAZY_BATCH1_PHASE_PASSED phase=$Phase mode=$Mode"

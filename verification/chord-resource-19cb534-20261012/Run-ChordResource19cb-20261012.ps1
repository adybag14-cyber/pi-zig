param([ValidateSet('Debug','ReleaseSafe')][string]$Mode='Debug',[string]$Attempt='first')
$ErrorActionPreference='Stop'
$taskEvidence=$PSScriptRoot
$taskPrivate='C:\Users\adyba\pi-zig-chord-runtime19cb-20261012'
$taskName="chord-resource19cb-$($Mode.ToLowerInvariant())-$Attempt-20261012"
$taskSourcePath=Join-Path $taskEvidence "$taskName-source-before.json"
function Source-Rows {
 @(git -C $taskPrivate ls-files --cached --others --exclude-standard|Sort-Object -Unique|Where-Object{Test-Path -LiteralPath (Join-Path $taskPrivate $_) -PathType Leaf}|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath (Join-Path $taskPrivate $_)).Hash}})
}
$taskBefore=Source-Rows
$taskBefore|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $taskSourcePath -Encoding utf8NoBOM
$taskTools=Get-Content -LiteralPath (Join-Path $taskEvidence 'durable-latest89-full-inspect-53ae-tool-prehash-20261011.json') -Raw|ConvertFrom-Json
$taskToolDrift=@($taskTools.inputs|Where-Object{!(Test-Path -LiteralPath $_.path) -or (Get-FileHash -LiteralPath $_.path).Hash -cne $_.sha256})
if($taskToolDrift.Count){throw 'Native tool prehash mismatch'}
$taskFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
if($taskFree -lt 16MB){throw 'Native job requires fresh16GiB physical RAM'}
& (Join-Path $taskEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1') -Name $taskName -Executable 'C:\Users\adyba\pi-zig-toolchain-20261003\zig-x86_64-windows-0.16.0\zig.exe' -WorkingDirectory $taskPrivate -Arguments @('build','test-native-chord-resource-source',"-Doptimize=$Mode",'-j1','--test-timeout','120s','--summary','all') -TimeoutSeconds 300
$taskAfter=Source-Rows
$taskSourceDrift=@(Compare-Object ($taskBefore|ForEach-Object{"$($_.path):$($_.sha256)"}) ($taskAfter|ForEach-Object{"$($_.path):$($_.sha256)"}))
$taskToolDrift=@($taskTools.inputs|Where-Object{!(Test-Path -LiteralPath $_.path) -or (Get-FileHash -LiteralPath $_.path).Hash -cne $_.sha256})
[ordered]@{source=$taskBefore.Count;source_after=$taskAfter.Count;source_drift=$taskSourceDrift.Count;tools=$taskTools.inputs.Count;tool_drift=$taskToolDrift.Count;admitted_free_kib=$taskFree;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 5|Tee-Object -FilePath (Join-Path $taskEvidence "$taskName-posthash.json")
if($taskSourceDrift.Count -or $taskToolDrift.Count){throw 'Native posthash mismatch'}
$taskResult=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName.json") -Raw|ConvertFrom-Json
if($taskResult.status -cne 'passed'){throw "Native diagnostic terminal $($taskResult.status)"}


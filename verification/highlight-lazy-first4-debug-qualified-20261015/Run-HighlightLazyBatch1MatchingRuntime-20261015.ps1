$ErrorActionPreference='Stop'
$taskEvidence=$PSScriptRoot
$taskPrivate='C:/Users/adyba/pi-zig-highlight-lazy-batch1-20261015'
$taskCompile='highlight-lazy-batch1-debug-compile-first-20261015'
$taskRuntime='highlight-lazy-batch1-debug-runtime-first-20261015'
$taskCompileOwner=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskCompile.json") -Raw|ConvertFrom-Json
$taskCompilePost=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskCompile-posthash.json") -Raw|ConvertFrom-Json
if($taskCompileOwner.status -cne 'passed' -or $taskCompilePost.source_drift -ne 0 -or $taskCompilePost.zig_tool_drift -ne 0 -or $taskCompilePost.control_drift -ne 0){throw 'Exact Debug compile terminal/post0 required'}
$taskSource=@(Get-Content -LiteralPath (Join-Path $taskEvidence "$taskCompile-source-before.json") -Raw|ConvertFrom-Json)
foreach($taskRow in $taskSource){if((Get-FileHash -LiteralPath $taskRow.path).Hash -ine $taskRow.sha256){throw 'Compile/runtime source identity drift'}}
$taskArtifacts=@(Get-ChildItem -LiteralPath (Join-Path $taskPrivate '.zig-cache/o') -File -Recurse -Filter 'test.exe'|ForEach-Object{@{path=$_.FullName;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash;bytes=$_.Length}})
if($taskArtifacts.Count -ne 1){throw 'One exact compiled test artifact required'}
$taskControls=@($PSCommandPath,(Join-Path $taskEvidence 'Run-HighlightLazyBatch1Native-20261015.ps1'),(Join-Path $taskEvidence "$taskCompile.json"),(Join-Path $taskEvidence "$taskCompile-posthash.json"),(Join-Path $taskEvidence "$taskCompile-source-before.json"))|ForEach-Object{@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}}
@{compile=$taskCompile;runtime=$taskRuntime;source_files=$taskSource.Count;artifacts=$taskArtifacts;controls=$taskControls;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskRuntime-pair-before.json") -Encoding utf8NoBOM
try {
 & (Join-Path $taskEvidence 'Run-HighlightLazyBatch1Native-20261015.ps1') -Mode Debug -Phase Runtime -Attempt first
} finally {
 $taskArtifactDrift=@($taskArtifacts|Where-Object{(Get-FileHash -LiteralPath $_.path).Hash -ine $_.sha256})
 $taskControlDrift=@($taskControls|Where-Object{(Get-FileHash -LiteralPath $_.path).Hash -ine $_.sha256})
 @{artifact_drift=$taskArtifactDrift.Count;control_drift=$taskControlDrift.Count;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskRuntime-pair-post.json") -Encoding utf8NoBOM
 if($taskArtifactDrift.Count -or $taskControlDrift.Count){throw 'Matching Debug runtime artifact/control drift'}
}

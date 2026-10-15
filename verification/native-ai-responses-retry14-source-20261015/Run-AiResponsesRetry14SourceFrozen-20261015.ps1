$ErrorActionPreference='Stop'
$taskEvidence=$PSScriptRoot
$taskName='ai-responses-retry14-5ab-source14-first-20261015'
$taskCandidate='C:/Users/adyba/pi-zig-native-responses-retry-20261015'
$taskQualified='C:/Users/adyba/pi-zig-native-responses-ws-20261015'
$taskInner=Join-Path $taskEvidence 'Run-AiResponsesRetry14Source-20261015.ps1'
$taskDriver=Join-Path $taskEvidence 'source5ab-responses-retry14-capture-20261015.mjs'
function Tree-Rows([string]$tree){
 @(git -C $tree ls-files --cached --others --exclude-standard|Sort-Object -Unique|ForEach-Object{[ordered]@{path=(Join-Path $tree $_);sha256=(Get-FileHash -LiteralPath (Join-Path $tree $_)).Hash}})
}
function Check-Rows($rows){@($rows|Where-Object{!(Test-Path -LiteralPath $_.path -PathType Leaf) -or (Get-FileHash -LiteralPath $_.path).Hash -cne $_.sha256})}
if((git -C $taskCandidate rev-parse HEAD) -cne 'c1f5a4e63c937b5b2b0ac9e67408cb36baa0fc84' -or (git -C $taskCandidate status --porcelain)){throw 'Exact clean retry candidate required'}
if((git -C $taskQualified rev-parse HEAD) -cne '7c0d6630615425da30db0a1b60b31cd60a72b3ec' -or (git -C $taskQualified status --porcelain)){throw 'Qualified candidate must stay unchanged'}
if((Get-FileHash -LiteralPath $taskInner).Hash -cne '9DEF7969FA9425B7A4EC177D3E22B8CF10B8B362465878FB30FA2981368CC97E' -or (Get-FileHash -LiteralPath $taskDriver).Hash -cne '15C1AB8F0A21A8B8FC3BB736077EE5E2EF160098E9C416871DC7DEE9F6364907'){throw 'Exact granted controls changed'}
if(Test-Path -LiteralPath (Join-Path $taskEvidence "$taskName.json")){throw 'Refuse replay of immutable Source attempt'}
$taskCandidateBefore=Tree-Rows $taskCandidate
$taskQualifiedBefore=Tree-Rows $taskQualified
$taskControls=@($PSCommandPath,$taskInner,$taskDriver)|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}}
[ordered]@{slot='LIGHT5';candidate=$taskCandidateBefore;qualified=$taskQualifiedBefore;controls=$taskControls}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-candidate-freeze.json") -Encoding utf8NoBOM
$taskFailure=$null
try{& $taskInner -Attempt first}catch{$taskFailure=$_}
$taskCandidateAfter=Tree-Rows $taskCandidate
$taskQualifiedAfter=Tree-Rows $taskQualified
$taskCandidateDrift=@(Check-Rows $taskCandidateBefore)
$taskQualifiedDrift=@(Check-Rows $taskQualifiedBefore)
$taskCandidatePaths=@(Compare-Object @($taskCandidateBefore.path) @($taskCandidateAfter.path))
$taskQualifiedPaths=@(Compare-Object @($taskQualifiedBefore.path) @($taskQualifiedAfter.path))
$taskControlDrift=@(Check-Rows $taskControls)
[ordered]@{slot='LIGHT5';candidate=$taskCandidateBefore.Count;candidate_after=$taskCandidateAfter.Count;candidate_drift=$taskCandidateDrift.Count;candidate_path_drift=$taskCandidatePaths.Count;qualified=$taskQualifiedBefore.Count;qualified_after=$taskQualifiedAfter.Count;qualified_drift=$taskQualifiedDrift.Count;qualified_path_drift=$taskQualifiedPaths.Count;controls=$taskControls.Count;control_drift=$taskControlDrift.Count;failure=if($taskFailure){$taskFailure.ToString()}else{$null};completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 5|Tee-Object -FilePath (Join-Path $taskEvidence "$taskName-candidate-posthash.json")
if($taskCandidateDrift.Count -or $taskQualifiedDrift.Count -or $taskCandidatePaths.Count -or $taskQualifiedPaths.Count -or $taskControlDrift.Count){throw 'Frozen candidate/control posthash drift'}
if($taskFailure){throw $taskFailure}

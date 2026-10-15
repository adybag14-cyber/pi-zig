param(
    [switch]$RootSourceGrant,
    [Parameter(Mandatory)][string]$ReleaseReceipt,
    [ValidatePattern('^[A-Za-z0-9_-]+$')][string]$Attempt='first'
)
$ErrorActionPreference='Stop'
if(!$RootSourceGrant){throw 'An explicit Root LIGHT6 Source18 grant is required'}
$taskReference='C:/Users/adyba/pi-zig-update-evidence-20261003'
$taskTree='C:/Users/adyba/pi-zig-ai-oauth-source-graph-20261015'
$taskExpectedHead='fe7e883d4b25c27b78d8336eacb58264217d5957'
$taskRunner=Join-Path $taskTree 'verification/oauth-loader-graph-ae7-prepared-20261015/Run-OAuthLoaderGraphSource18-20261015.ps1'
$taskExpectedOutput=Join-Path $taskTree 'src/extensions/fixtures/ai-oauth-loader-graph-ae7-source18.json'
$taskChatGPTProof='C:/Users/adyba/pi-zig-native-oauth-chatgpt-20261015/verification/native-ai-chatgpt-oauth-source43-20261015'
$taskUnique=[DateTimeOffset]::UtcNow.ToString('yyyyMMddTHHmmssfffffffZ')+'-'+[Guid]::NewGuid().ToString('N')
$taskPrefix=Join-Path $taskReference "oauth-nine-flow-source18-$Attempt-$taskUnique"
$taskRelease=Get-Content -LiteralPath $ReleaseReceipt -Raw|ConvertFrom-Json
if($taskRelease.slot -ne 6 -or !$taskRelease.released -or $taskRelease.lifecycle_terminal -cne 'passed' -or $taskRelease.lifecycle_post_drift -ne 0 -or $taskRelease.wire_terminal -cne 'passed' -or $taskRelease.wire_post_drift -ne 0){throw 'Explicit successful Bedrock LIGHT6 series release is required before prehash'}
if((git -C $taskTree rev-parse HEAD) -cne $taskExpectedHead -or (git -C $taskTree status --porcelain)){throw 'Exact clean granted fe7e883d candidate required'}
if(Test-Path -LiteralPath $taskExpectedOutput){throw 'Source18 expected must remain absent until genuine terminal/fullpost0'}
function Get-CandidateRows {
    @(git -C $taskTree ls-files|ForEach-Object {[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath (Join-Path $taskTree $_)).Hash}})
}
function Get-Drift($taskRows){
    @($taskRows|Where-Object {!(Test-Path -LiteralPath $_.path -PathType Leaf) -or (Get-FileHash -LiteralPath $_.path).Hash -cne $_.sha256}|ForEach-Object path)
}
$taskBefore=Get-CandidateRows
$taskProofPaths=@(Get-ChildItem -LiteralPath $taskChatGPTProof -File -Recurse|ForEach-Object FullName)
if($taskProofPaths.Count -ne 31){throw 'Complete actual ChatGPT Source43 proof packet inventory required'}
$taskControlPaths=@($PSCommandPath,$taskRunner,$ReleaseReceipt,$taskRelease.syntax_receipt)+$taskProofPaths
$taskControls=@($taskControlPaths|ForEach-Object {[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})
$taskFixturePaths=@('src/extensions/fixtures/ai-oauth-anthropic-openrouter-ae7.json','src/extensions/fixtures/ai-oauth-chatgpt-ae7.json','src/extensions/fixtures/oauth-codex-radius-ae7-source.json','src/extensions/fixtures/ai-oauth-meta-ae7.json','src/extensions/fixtures/ai-oauth-subscriptions-ae7.json')
$taskExpectedHashes=@('CBBC24227FA4719A581111EF6AA9B99AA7BD83BED6D39648738082E42CCA6301','61B2B03DADA222EF369EF20C901E64BFF7A17C5238E1E434FC7922FDF623DE24','085F6A4C5CC6AF456BC2FBBEB71365A527EE111CDE4794A837D3541B22E12495','3101B6FD96EA27EB28AB79B9D4EE55D34DB8DDA780C441979B0984974C11D720','7C15D350A44649E990B1F82401C9427B2B5FC9BDE307987609BF30123E2C6818')
for($i=0;$i -lt $taskFixturePaths.Count;$i++){if((Get-FileHash -LiteralPath (Join-Path $taskTree $taskFixturePaths[$i])).Hash -cne $taskExpectedHashes[$i]){throw 'Nine original flow Source fixture identity mismatch'}}
$taskBefore|ConvertTo-Json -Depth 4|Set-Content -LiteralPath "$taskPrefix-candidate-before.json" -Encoding utf8NoBOM
$taskControls|ConvertTo-Json -Depth 4|Set-Content -LiteralPath "$taskPrefix-controls-before.json" -Encoding utf8NoBOM
$taskFailure=$null
$taskExit=$null
try {
    & $taskRunner -RootSourceGrant -Attempt $Attempt
    $taskExit=$LASTEXITCODE
} catch {$taskFailure=$_}
finally {
    $taskAfter=Get-CandidateRows
    $taskCandidateDrift=@(Compare-Object ($taskBefore|ForEach-Object {"$($_.path):$($_.sha256)"}) ($taskAfter|ForEach-Object {"$($_.path):$($_.sha256)"}))
    $taskControlDrift=@(Get-Drift $taskControls)
    $taskHeadAfter=(git -C $taskTree rev-parse HEAD)
    $taskPost=[ordered]@{candidate_before=$taskExpectedHead;candidate_after=$taskHeadAfter;candidate_files=$taskBefore.Count;candidate_files_after=$taskAfter.Count;candidate_drift=$taskCandidateDrift.Count;vendor_files=@($taskBefore|Where-Object path -like 'vendor/*').Count;controls=$taskControls.Count;control_drift=$taskControlDrift.Count;original_flow_fixtures=5;actual_flows=9;expected18_absent=!(Test-Path -LiteralPath $taskExpectedOutput);runner_exit=$taskExit;runner_exception=if($taskFailure){[string]$taskFailure}else{$null};completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}
    $taskPost|ConvertTo-Json -Depth 5|Set-Content -LiteralPath "$taskPrefix-posthash.json" -Encoding utf8NoBOM
    $taskPost|ConvertTo-Json -Depth 5
}
if($taskCandidateDrift.Count -or $taskControlDrift.Count -or $taskHeadAfter -cne $taskExpectedHead -or !$taskPost.expected18_absent){throw 'Source18 outer freeze posthash drift'}
if($taskFailure){throw $taskFailure}
if($taskExit -ne 0){throw "Source18 runner exit $taskExit"}
Write-Output "SOURCE18_OUTER_FULLPOST0=$taskPrefix-posthash.json"

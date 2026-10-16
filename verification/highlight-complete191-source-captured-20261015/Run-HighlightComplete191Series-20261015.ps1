param([Parameter(Mandatory)][string]$CandidateHead)
$ErrorActionPreference='Stop'
$taskEvidence=$PSScriptRoot
$taskShell=@(Get-Command pwsh -CommandType Application)[0].Source
$taskOwner=Join-Path $taskEvidence 'Run-HighlightComplete191Source-20261015.ps1'
$taskControls=@($PSCommandPath,$taskOwner,$taskShell,(Join-Path $taskEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1'))|ForEach-Object{@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}}
$taskControls|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskEvidence 'highlight-complete191-series-operation-controls-20261015.json') -Encoding utf8NoBOM
foreach($taskMode in @('success','lookup_failure','safe_factory_failure')) {
 $taskName="highlight-complete191-source-$taskMode-first-20261015-operation"
 try {
  & (Join-Path $taskEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1') -Name $taskName -Executable $taskShell -WorkingDirectory $taskEvidence -Arguments @('-NoLogo','-NoProfile','-File',$taskOwner,'-Mode',$taskMode,'-CandidateHead',$CandidateHead) -TimeoutSeconds 600
 } finally {
  $taskDrift=@($taskControls|Where-Object{(Get-FileHash -LiteralPath $_.path).Hash -ine $_.sha256})
  @{mode=$taskMode;external_operation_timeout_seconds=600;inner_node_timeout_seconds=300;control_drift=$taskDrift.Count;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-controls-post.json") -Encoding utf8NoBOM
  if($taskDrift.Count){throw 'Outer series operation control drift'}
 }
 $taskOperation=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName.json") -Raw|ConvertFrom-Json
 $taskPost=Get-Content -LiteralPath (Join-Path $taskEvidence "highlight-complete191-source-$taskMode-first-20261015-posthash.json") -Raw|ConvertFrom-Json
 if($taskOperation.status -cne 'passed' -or @($taskPost.manifests|Where-Object drift -ne 0).Count -or $taskPost.control_drift -ne 0 -or $taskPost.native_drift -ne 0 -or $taskPost.absence_drift -ne 0 -or $taskPost.source_path_drift -ne 0){throw 'Whole191 actual Source series failfast terminal/post0 required'}
 Write-Output "GENUINE_COMPLETE191_MODE_TERMINAL_POST0_$taskMode"
}
Write-Output 'GENUINE_COMPLETE191_SOURCE_SERIES_TERMINAL_POST0'

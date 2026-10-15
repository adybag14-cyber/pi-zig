$ErrorActionPreference='Stop'
$taskEvidence=$PSScriptRoot
$taskOriginal=Join-Path $taskEvidence 'catalog5ab-official-first-20261015'
$taskReplay=Join-Path $taskEvidence 'catalog5ab-official-replay-20261015'
$taskManifest=Join-Path $taskEvidence 'catalog5ab-official-generator-first-20261015-artifacts.json'
if((Get-FileHash -LiteralPath $taskManifest).Hash -cne '6D3ABA79307114720123B6AEF930D08938D85766C53D16F319B6430F89887140'){throw 'Frozen original87 artifact manifest changed'}
$taskRows=@(Get-Content -LiteralPath $taskManifest -Raw|ConvertFrom-Json)
if($taskRows.Count -ne 87){throw 'Complete original87 artifact inventory required'}
$taskExpected=[Collections.Generic.List[string]]::new()
$taskDifferences=[Collections.Generic.List[string]]::new()
foreach($taskRow in $taskRows){
 $taskRelative=[IO.Path]::GetRelativePath($taskOriginal,$taskRow.path)
 if($taskRelative.StartsWith('..') -or [IO.Path]::IsPathRooted($taskRelative)){throw 'Original artifact escaped pinned root'}
 $taskExpected.Add($taskRelative)
 $taskRepeated=Join-Path $taskReplay $taskRelative
 if(!(Test-Path -LiteralPath $taskRow.path -PathType Leaf) -or (Get-FileHash -LiteralPath $taskRow.path).Hash -cne $taskRow.sha256){$taskDifferences.Add('original:'+ $taskRelative)}
 if(!(Test-Path -LiteralPath $taskRepeated -PathType Leaf) -or (Get-FileHash -LiteralPath $taskRepeated).Hash -cne $taskRow.sha256){$taskDifferences.Add('replay:'+ $taskRelative)}
}
$taskReplayPaths=@(Get-ChildItem -LiteralPath $taskReplay -File -Recurse|ForEach-Object{[IO.Path]::GetRelativePath($taskReplay,$_.FullName)}|Sort-Object)
$taskInventoryDrift=@(Compare-Object @($taskExpected|Sort-Object) $taskReplayPaths)
$taskPublication=Get-Content -LiteralPath (Join-Path $taskOriginal 'publication.json') -Raw|ConvertFrom-Json
if($taskPublication.minimumPiVersion -cne '1.2.1' -or $taskPublication.revision -cne 'sha256-4334227667568186df17628973e890a2582a44c4ef67f16621704387ae73c8c9' -or $taskPublication.sourceCommit -cne '5ab7fe74c400097b386662205cd93900695b8a71'){throw 'Official publication descriptor mismatch'}
$taskResult=[ordered]@{status=if($taskDifferences.Count -or $taskInventoryDrift.Count){'failed'}else{'passed'};original_generator_files=$taskRows.Count;replayed_generator_files=$taskReplayPaths.Count;byte_mismatches=$taskDifferences.Count;replay_inventory_drift=$taskInventoryDrift.Count;offline=$true;official_publication_descriptor_separate='publication.json';prior_wrapper_failure='Compared full current directory after publication dry-run added publication.json;87 generator artifacts were unchanged';original_artifact_manifest_sha256=(Get-FileHash -LiteralPath $taskManifest).Hash;validator_sha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash;validated_utc=[DateTimeOffset]::UtcNow.ToString('o')}
$taskResult|ConvertTo-Json -Depth 5|Tee-Object -FilePath (Join-Path $taskEvidence 'catalog5ab-source-replay-corrected-artifact-equivalence-20261015.json')
if($taskDifferences.Count -or $taskInventoryDrift.Count){throw 'Original87 replay mismatch'}

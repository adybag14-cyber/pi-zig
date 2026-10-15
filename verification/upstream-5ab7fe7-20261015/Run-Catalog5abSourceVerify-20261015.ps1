param([ValidateSet('PublishValidate','Replay')][string]$Phase='PublishValidate')
$ErrorActionPreference='Stop'
$taskEvidence=$PSScriptRoot
$taskSource='C:/Users/adyba/pi-upstream-source-5ab7fe7-20261015'
$taskNode='C:/Program Files/nodejs/node.exe'
$taskName="catalog5ab-source-$($Phase.ToLowerInvariant())-first-20261015"
$taskCatalog=Join-Path $taskEvidence 'catalog5ab-official-first-20261015'
$taskCapture=Join-Path $taskEvidence 'catalog5ab-network-first-20261015'
$taskReplay=Join-Path $taskEvidence 'catalog5ab-official-replay-20261015'
function Check-Rows($rows) {
 @($rows|Where-Object{!(Test-Path -LiteralPath $_.path -PathType Leaf) -or (Get-FileHash -LiteralPath $_.path).Hash -ine $_.sha256})
}
$taskSourceManifest=Join-Path $taskEvidence 'source5ab-full-manifest-20261015.json'
$taskToolsManifest=Join-Path $taskEvidence 'root-current8a-npm-tools-before.json'
$taskRows=@(Get-Content -LiteralPath $taskSourceManifest -Raw|ConvertFrom-Json)
$taskTools=@(Get-Content -LiteralPath $taskToolsManifest -Raw|ConvertFrom-Json)
if($taskRows.Count -ne 1967 -or $taskTools.Count -ne 1774 -or @(Check-Rows $taskRows).Count -or @(Check-Rows $taskTools).Count){throw 'Complete Source/tool prehash mismatch'}
$taskControls=@($PSCommandPath,(Join-Path $taskEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1'),(Join-Path $taskEvidence 'catalog5ab-replay-fetch-20261015.mjs'),$taskSourceManifest,$taskToolsManifest)+@(Get-ChildItem -LiteralPath $taskCatalog,$taskCapture -File -Recurse|ForEach-Object FullName)
$taskControls=@($taskControls|ForEach-Object{@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})
$taskControls|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-controls-before.json") -Encoding utf8NoBOM
$taskPathsBefore=@(Get-ChildItem -LiteralPath $taskSource -File -Recurse -Force|ForEach-Object{[IO.Path]::GetRelativePath($taskSource,$_.FullName)}|Sort-Object)
$taskFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
if($taskFree -lt 2MB){throw 'Source2GiB admission denied'}
@{status='admitted';free_kib=$taskFree;required_kib=2MB;heap_mb=128;max_coordinated_jobs=4;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-admission.json") -Encoding utf8NoBOM
try {
 if($Phase -eq 'PublishValidate'){
  & (Join-Path $taskEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1') -Name $taskName -Executable $taskNode -WorkingDirectory $taskSource -Arguments @('--max-old-space-size=128',(Join-Path $taskSource 'scripts/publish-model-catalog.mjs'),'--input',$taskCatalog,'--source-commit','5ab7fe74c400097b386662205cd93900695b8a71','--dry-run') -TimeoutSeconds 300 -EnvironmentOverrides @{NODE_OPTIONS='';NODE_PATH=''}
 }else{
  if(Test-Path -LiteralPath $taskReplay){throw 'Fresh replay output required'}
  & (Join-Path $taskEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1') -Name $taskName -Executable $taskNode -WorkingDirectory $taskSource -Arguments @('--max-old-space-size=128','--import',([Uri](Join-Path $taskEvidence 'catalog5ab-replay-fetch-20261015.mjs')).AbsoluteUri,(Join-Path $taskSource 'packages/ai/scripts/generate-models.ts'),'--strict','--json-only','--json-output',$taskReplay) -TimeoutSeconds 300 -EnvironmentOverrides @{NODE_OPTIONS='';NODE_PATH='';PI_CATALOG_REPLAY_DIR=$taskCapture}
 }
} finally {
 $taskSourceDrift=@(Check-Rows $taskRows)
 $taskToolsDrift=@(Check-Rows $taskTools)
 $taskControlsDrift=@(Check-Rows $taskControls)
 $taskPathsAfter=@(Get-ChildItem -LiteralPath $taskSource -File -Recurse -Force|ForEach-Object{[IO.Path]::GetRelativePath($taskSource,$_.FullName)}|Sort-Object)
 $taskPathDrift=@(Compare-Object $taskPathsBefore $taskPathsAfter)
 @{source=$taskRows.Count;source_drift=$taskSourceDrift.Count;node_tools=$taskTools.Count;node_tool_drift=$taskToolsDrift.Count;controls=$taskControls.Count;control_drift=$taskControlsDrift.Count;source_path_drift=$taskPathDrift.Count;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-posthash.json") -Encoding utf8NoBOM
 if($taskSourceDrift.Count -or $taskToolsDrift.Count -or $taskControlsDrift.Count -or $taskPathDrift.Count){throw 'Source verification immutable input drift'}
}
$taskOwner=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName.json") -Raw|ConvertFrom-Json
if($taskOwner.status -cne 'passed'){throw 'Source verification terminal failure'}
if($Phase -eq 'Replay'){
 $taskOriginal=@(Get-ChildItem -LiteralPath $taskCatalog -File -Recurse|ForEach-Object{@{relative=[IO.Path]::GetRelativePath($taskCatalog,$_.FullName);sha256=(Get-FileHash -LiteralPath $_).Hash}}|Sort-Object relative)
 $taskRepeated=@(Get-ChildItem -LiteralPath $taskReplay -File -Recurse|ForEach-Object{@{relative=[IO.Path]::GetRelativePath($taskReplay,$_.FullName);sha256=(Get-FileHash -LiteralPath $_).Hash}}|Sort-Object relative)
 $taskDifference=@(Compare-Object @($taskOriginal|ForEach-Object{"$($_.relative):$($_.sha256)"}) @($taskRepeated|ForEach-Object{"$($_.relative):$($_.sha256)"}))
 @{original_files=$taskOriginal.Count;replayed_files=$taskRepeated.Count;byte_mismatches=$taskDifference.Count;offline=$true;source_head='5ab7fe74c400097b386662205cd93900695b8a71'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-equivalence.json") -Encoding utf8NoBOM
 if($taskOriginal.Count -ne 87 -or $taskDifference.Count){throw 'Official generator replay mismatch'}
}
Write-Output "SOURCE_CATALOG5AB_VERIFY_PASSED phase=$Phase"

$ErrorActionPreference='Stop'
$taskEvidence=$PSScriptRoot
$taskSource='C:/Users/adyba/pi-upstream-source-5ab7fe7-20261015'
$taskNode='C:/Program Files/nodejs/node.exe'
$taskName='catalog5ab-official-generator-first-20261015'
$taskCapture=Join-Path $taskEvidence 'catalog5ab-network-first-20261015'
$taskOutput=Join-Path $taskEvidence 'catalog5ab-official-first-20261015'
if((git -C $taskSource rev-parse HEAD).Trim() -cne '5ab7fe74c400097b386662205cd93900695b8a71'){throw 'Source identity mismatch'}
if((Get-FileHash -LiteralPath $taskNode).Hash -cne '63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088'){throw 'Node pin mismatch'}
if((Test-Path -LiteralPath $taskCapture) -or (Test-Path -LiteralPath $taskOutput)){throw 'Fresh output paths required'}
function Check-Rows($rows) {
 @($rows|Where-Object{!(Test-Path -LiteralPath $_.path -PathType Leaf) -or (Get-FileHash -LiteralPath $_.path).Hash -cne $_.sha256})
}
$taskToolsManifest=Join-Path $taskEvidence 'root-current8a-npm-tools-before.json'
$taskTools=@(Get-Content -LiteralPath $taskToolsManifest -Raw|ConvertFrom-Json)
if($taskTools.Count -ne 1774 -or @(Check-Rows $taskTools).Count){throw 'Full pinned Node tools prehash mismatch'}
$taskControls=@($PSCommandPath,(Join-Path $taskEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1'),(Join-Path $taskEvidence 'catalog5ab-capture-fetch-20261015.mjs'),$taskToolsManifest,$taskNode)|ForEach-Object{@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}}
$taskControls|ConvertTo-Json -Depth 4|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-controls-before.json") -Encoding utf8NoBOM
$taskTracked=@(git -C $taskSource ls-files|Sort-Object|ForEach-Object{[ordered]@{relative=$_;path=(Join-Path $taskSource $_);sha256=(Get-FileHash -LiteralPath (Join-Path $taskSource $_)).Hash}})
$taskTracked|ConvertTo-Json -Depth 4|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-prehash.json") -Encoding utf8NoBOM
$taskPathsBefore=@(Get-ChildItem -LiteralPath $taskSource -Recurse -Force -File|ForEach-Object{[IO.Path]::GetRelativePath($taskSource,$_.FullName)}|Sort-Object)
$taskPathsBefore|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-paths-before.json") -Encoding utf8NoBOM
$taskFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
if($taskFree -lt 2MB){throw 'Source2GiB admission denied'}
@{status='admitted';free_kib=$taskFree;required_kib=2MB;heap_mb=128;max_coordinated_jobs=4;slot=1;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-admission.json") -Encoding utf8NoBOM
try {
 & (Join-Path $taskEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1') -Name $taskName -Executable $taskNode -WorkingDirectory $taskSource -Arguments @('--max-old-space-size=128','--import',([Uri](Join-Path $taskEvidence 'catalog5ab-capture-fetch-20261015.mjs')).AbsoluteUri,(Join-Path $taskSource 'packages/ai/scripts/generate-models.ts'),'--strict','--json-only','--json-output',$taskOutput) -TimeoutSeconds 300 -EnvironmentOverrides @{NODE_OPTIONS='';NODE_PATH='';PI_CATALOG_CAPTURE_DIR=$taskCapture}
} finally {
 $taskDrift=@(Check-Rows $taskTracked)
 $taskControlDrift=@(Check-Rows $taskControls)
 $taskToolDrift=@(Check-Rows $taskTools)
 $taskPathsAfter=@(Get-ChildItem -LiteralPath $taskSource -Recurse -Force -File|ForEach-Object{[IO.Path]::GetRelativePath($taskSource,$_.FullName)}|Sort-Object)
 $taskPathDrift=@(Compare-Object $taskPathsBefore $taskPathsAfter)
 @{tracked_source_files=$taskTracked.Count;tracked_drift=$taskDrift.Count;control_files=@($taskControls).Count;control_drift=$taskControlDrift.Count;node_tools=$taskTools.Count;node_tool_drift=$taskToolDrift.Count;source_paths=$taskPathsBefore.Count;source_path_drift=$taskPathDrift.Count;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-posthash.json") -Encoding utf8NoBOM
 if($taskDrift.Count -or $taskControlDrift.Count -or $taskToolDrift.Count -or $taskPathDrift.Count){throw 'Generator immutable input drift'}
}
$taskOwner=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName.json") -Raw|ConvertFrom-Json
if($taskOwner.status -cne 'passed'){throw 'Official generation failed'}
$taskArtifacts=@(Get-ChildItem -LiteralPath $taskOutput -Recurse -File|ForEach-Object{@{path=$_.FullName;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}})
$taskArtifacts|ConvertTo-Json -Depth 4|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-artifacts.json") -Encoding utf8NoBOM
Write-Output "LATEST5AB_OFFICIAL_CATALOG_GENERATED files=$($taskArtifacts.Count)"

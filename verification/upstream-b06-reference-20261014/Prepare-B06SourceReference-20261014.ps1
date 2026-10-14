$ErrorActionPreference='Stop'
$taskEvidence=$PSScriptRoot
$taskSource='C:/Users/adyba/pi-upstream-source-b06c1f2-20261014'
$taskNode='C:/Program Files/nodejs/node.exe'
$taskCatalog='C:/Users/adyba/pi-zig-sdk-events-hosted-20261013/verification/sdk-read-prompt-original-b45e0eb-20261014/models-all-pinned-439c5347.json'
$taskName='sdk-source-b06-official-hydration-20261014'
if((git -C $taskSource rev-parse HEAD).Trim() -cne 'b06c1f2cf1dea6af8748ddeee18c23587d2cb7c6'){throw 'Latest immutable Source identity mismatch'}
if((Get-FileHash -LiteralPath $taskNode).Hash -cne '63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088'){throw 'Node pin mismatch'}
if((Get-FileHash -LiteralPath $taskCatalog).Hash -cne '439C53478C84ED27A58F8B54E1C3BD45810E5A969515B4E3666A3898D51EE22F'){throw 'Historical official typed catalog pin mismatch'}
$taskTarget=[IO.Path]::GetFullPath((Join-Path $taskSource 'packages/ai/src/providers/data'))
if(!$taskTarget.StartsWith([IO.Path]::GetFullPath($taskSource)+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $taskTarget)){throw 'New hydration target must be contained and initially absent'}
if((Get-Item -LiteralPath $taskSource).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Reference Source root cannot be a reparse point'}
$taskTracked=@(git -C $taskSource ls-files|Sort-Object|ForEach-Object{[ordered]@{relative=$_;path=(Join-Path $taskSource $_);sha256=(Get-FileHash -LiteralPath (Join-Path $taskSource $_)).Hash}})
if($taskTracked.Count -ne 1922){throw 'Complete tracked latest Source inventory absent'}
$taskTracked|ConvertTo-Json -Depth 4|Set-Content -LiteralPath (Join-Path $taskEvidence 'sdk-source-b06-tracked-initial-20261014.json') -Encoding utf8NoBOM
$taskFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
if($taskFree -lt 2MB){throw 'Source hydration2GiB admission denied'}
$taskControls=@($PSCommandPath,$taskCatalog,$taskNode)|ForEach-Object{@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}}
$taskControls|ConvertTo-Json -Depth 4|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-controls-before.json") -Encoding utf8NoBOM
& (Join-Path $taskEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1') -Name $taskName -Executable $taskNode -WorkingDirectory $taskSource -Arguments @('--max-old-space-size=128',(Join-Path $taskSource 'packages/ai/scripts/hydrate-model-catalog.ts'),$taskCatalog) -TimeoutSeconds 300 -EnvironmentOverrides @{NODE_OPTIONS='';NODE_PATH=''}
$taskDrift=@($taskTracked|Where-Object{!(Test-Path -LiteralPath $_.path) -or (Get-FileHash -LiteralPath $_.path).Hash -cne $_.sha256})
$taskControlDrift=@($taskControls|Where-Object{(Get-FileHash -LiteralPath $_.path).Hash -cne $_.sha256})
@{tracked_source_files=$taskTracked.Count;tracked_drift=$taskDrift.Count;control_drift=$taskControlDrift.Count;historical_catalog_scope='Source fixture typed metadata only; current generated catalog remains a separate application gate';observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-posthash.json") -Encoding utf8NoBOM
if($taskDrift.Count -or $taskControlDrift.Count){throw 'Official reference hydration mutated frozen inputs'}
$taskOwner=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName.json") -Raw|ConvertFrom-Json
if($taskOwner.status -cne 'passed'){throw 'Official hydration did not pass'}
$taskGenerated=@(Get-ChildItem -LiteralPath $taskTarget -File -Force|ForEach-Object{@{path=$_.FullName;relative=[IO.Path]::GetRelativePath($taskSource,$_.FullName).Replace([IO.Path]::DirectorySeparatorChar,[char]'/');sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}})
if($taskGenerated.Count -ne 43){throw 'Official43 generated reference files required'}
@($taskTracked+$taskGenerated)|ConvertTo-Json -Depth 4|Set-Content -LiteralPath (Join-Path $taskEvidence 'sdk-source-b06-full-manifest-20261014.json') -Encoding utf8NoBOM
Write-Output 'LATEST_B06_SOURCE1965_PREPARED_WITH_OFFICIAL_FIXTURE_HYDRATION'

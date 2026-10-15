$ErrorActionPreference='Stop'
$taskEvidence=$PSScriptRoot
$taskSource='C:/Users/adyba/pi-upstream-source-5ab7fe7-20261015'
$taskPrevious='C:/Users/adyba/pi-upstream-source-b06c1f2-20261014'
$taskNode='C:/Program Files/nodejs/node.exe'
$taskCatalog=Join-Path $taskEvidence 'catalog5ab-official-first-20261015/models.all.json'
$taskName='source5ab-official-fresh-hydration-first-20261015'
function Check-Rows($rows) {
 @($rows|Where-Object{!(Test-Path -LiteralPath $_.path -PathType Leaf) -or (Get-FileHash -LiteralPath $_.path).Hash -ine $_.sha256})
}
if((git -C $taskSource rev-parse HEAD).Trim() -cne '5ab7fe74c400097b386662205cd93900695b8a71'){throw 'Latest Source identity mismatch'}
if((Get-FileHash -LiteralPath $taskCatalog).Hash -cne '4334227667568186DF17628973E890A2582A44C4EF67F16621704387AE73C8C9'){throw 'Fresh catalog mismatch'}
if((Get-FileHash -LiteralPath $taskNode).Hash -cne '63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088'){throw 'Node pin mismatch'}
if(Test-Path -LiteralPath (Join-Path $taskSource 'packages/ai/src/providers/data')){throw 'Fresh hydration target required'}
$taskAudit=Get-Content -LiteralPath (Join-Path $taskEvidence 'sdk-source-b06-dependency-contract-audit-20261014.json') -Raw|ConvertFrom-Json -AsHashtable
$taskNewLock=Get-Content -LiteralPath (Join-Path $taskSource 'package-lock.json') -Raw|ConvertFrom-Json -AsHashtable
$taskOldLock=Get-Content -LiteralPath (Join-Path $taskPrevious 'package-lock.json') -Raw|ConvertFrom-Json -AsHashtable
$taskNpm=0
foreach($taskEntry in $taskNewLock.packages.GetEnumerator()){
 if($taskEntry.Key -notlike '*node_modules/*' -or $taskEntry.Value.link){continue}
 $taskNpm++
 if(!$taskOldLock.packages.ContainsKey($taskEntry.Key) -or ($taskEntry.Value|ConvertTo-Json -Depth 90 -Compress) -cne ($taskOldLock.packages[$taskEntry.Key]|ConvertTo-Json -Depth 90 -Compress)){throw "Changed external npm record $($taskEntry.Key)"}
}
$taskSpecs=@(
 @{name='dependencies';file='durable-19cb534-reference-20261012-all-built-runtime.json';count=31064},
 @{name='node_tools';file='root-current8a-npm-tools-before.json';count=1774}
)
$taskFrozen=@()
foreach($taskSpec in $taskSpecs){
 $taskRows=@(Get-Content -LiteralPath (Join-Path $taskEvidence $taskSpec.file) -Raw|ConvertFrom-Json)
 if($taskRows.Count -ne $taskSpec.count -or @(Check-Rows $taskRows).Count){throw "Full frozen manifest prehash mismatch $($taskSpec.name)"}
 $taskFrozen+=@{name=$taskSpec.name;manifest=$taskSpec.file;rows=$taskRows}
}
$taskInstalled=0;$taskOptional=0
foreach($taskPin in $taskAudit.pins){
 if($taskPin.actualPath){
  if((Get-FileHash -LiteralPath $taskPin.actualPath).Hash -ine $taskPin.packageSha256){throw 'Installed dependency pin mismatch'}
  $taskInstalled++
 }elseif($taskPin.status -ceq 'platform_optional_absent' -and $taskPin.contract.optional){$taskOptional++}
 else{throw 'Unexplained missing dependency pin'}
}
$taskModules=Join-Path $taskSource 'node_modules'
if(Test-Path -LiteralPath $taskModules){throw 'New Source dependency link must initially be absent'}
New-Item -ItemType Junction -Path $taskModules -Target 'C:/Users/adyba/pi-upstream-runtime-19cb534-20261012/node_modules'|Out-Null
foreach($taskWorkspace in $taskAudit.workspaces){
 $taskPackage=Get-Content -LiteralPath (Join-Path $taskSource "$($taskWorkspace.path)/package.json") -Raw|ConvertFrom-Json -AsHashtable
 if($taskPackage.name -cne $taskWorkspace.specifier){throw 'Workspace authority changed'}
 $taskWorkspace.packageName=$taskPackage.name;$taskWorkspace.version=$taskPackage.version;$taskWorkspace.exports=$taskPackage.exports;$taskWorkspace.main=$taskPackage.main
}
$taskAudit.latestHead='5ab7fe74c400097b386662205cd93900695b8a71'
$taskAudit.lockSha256=(Get-FileHash -LiteralPath (Join-Path $taskSource 'package-lock.json')).Hash
$taskAudit.external_npm_identical_records=$taskNpm
$taskAudit.scope='Latest immutable official Source; every external npm lock record equal to b06; installed dependency pins and entire runtime manifest verified; latest workspace export metadata authoritative, old workspace classes rejected by observer'
$taskAudit|ConvertTo-Json -Depth 90|Set-Content -LiteralPath (Join-Path $taskEvidence 'source5ab-dependency-contract-audit-20261015.json') -Encoding utf8NoBOM
$taskTracked=@(git -C $taskSource ls-files|Sort-Object|ForEach-Object{@{path=(Join-Path $taskSource $_);relative=$_;sha256=(Get-FileHash -LiteralPath (Join-Path $taskSource $_)).Hash}})
if($taskTracked.Count -ne 1924){throw 'Source tracked inventory mismatch'}
$taskTracked|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-source-before.json") -Encoding utf8NoBOM
$taskControls=@($PSCommandPath,(Join-Path $taskEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1'),(Join-Path $taskEvidence 'source5ab-observe-20261015.mjs'),(Join-Path $taskEvidence 'source5ab-dependency-contract-audit-20261015.json'),$taskCatalog,$taskNode)+@($taskSpecs|ForEach-Object{Join-Path $taskEvidence $_.file})
$taskControls=@($taskControls|ForEach-Object{@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})
$taskControls|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-controls-before.json") -Encoding utf8NoBOM
$taskPathsBefore=@(Get-ChildItem -LiteralPath $taskSource -Recurse -Force -File|ForEach-Object{[IO.Path]::GetRelativePath($taskSource,$_.FullName).Replace('\','/')}|Sort-Object)
$taskPathsBefore|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-paths-before.json") -Encoding utf8NoBOM
$taskFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
if($taskFree -lt 2MB){throw 'Source2GiB admission denied'}
@{status='admitted';free_kib=$taskFree;required_kib=2MB;heap_mb=128;max_coordinated_jobs=4;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-admission.json") -Encoding utf8NoBOM
try {
 & (Join-Path $taskEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1') -Name $taskName -Executable $taskNode -WorkingDirectory $taskSource -Arguments @('--max-old-space-size=128',(Join-Path $taskSource 'packages/ai/scripts/hydrate-model-catalog.ts'),$taskCatalog) -TimeoutSeconds 300 -EnvironmentOverrides @{NODE_OPTIONS='';NODE_PATH=''}
} finally {
 $taskPost=@()
 foreach($taskItem in $taskFrozen){$taskDrift=@(Check-Rows $taskItem.rows);$taskPost+=@{name=$taskItem.name;files=$taskItem.rows.Count;drift=$taskDrift.Count}}
 $taskTrackedDrift=@(Check-Rows $taskTracked)
 $taskControlDrift=@(Check-Rows $taskControls)
 @{manifests=$taskPost;tracked_source=$taskTracked.Count;tracked_drift=$taskTrackedDrift.Count;control_drift=$taskControlDrift.Count;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-posthash.json") -Encoding utf8NoBOM
 if($taskTrackedDrift.Count -or $taskControlDrift.Count -or @($taskPost|Where-Object drift -ne 0).Count){throw 'Hydration immutable input drift'}
}
$taskOwner=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName.json") -Raw|ConvertFrom-Json
if($taskOwner.status -cne 'passed'){throw 'Hydration terminal failure'}
$taskHydrated=@(Get-ChildItem -LiteralPath (Join-Path $taskSource 'packages/ai/src/providers/data') -File -Force|ForEach-Object{@{path=$_.FullName;relative=[IO.Path]::GetRelativePath($taskSource,$_.FullName).Replace('\','/');sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}})
if($taskHydrated.Count -ne 43){throw 'Official hydration43 inventory mismatch'}
$taskPathsAfter=@(Get-ChildItem -LiteralPath $taskSource -Recurse -Force -File|ForEach-Object{[IO.Path]::GetRelativePath($taskSource,$_.FullName).Replace('\','/')}|Sort-Object)
$taskExpected=@($taskPathsBefore+@($taskHydrated|ForEach-Object relative)|Sort-Object)
if(@(Compare-Object $taskExpected $taskPathsAfter).Count){throw 'Unexpected post-hydration Source paths'}
@($taskTracked+$taskHydrated)|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskEvidence 'source5ab-full-manifest-20261015.json') -Encoding utf8NoBOM
@{head=$taskAudit.latestHead;tracked=1924;hydrated=43;full_source=1967;external_npm_identical=$taskNpm;installed_pins=$taskInstalled;platform_optional_absent=$taskOptional;unchanged_stale_absent=$taskAudit.mismatches.Count;source_path_drift=0;catalog_sha256=(Get-FileHash -LiteralPath $taskCatalog).Hash;full_pi_qualified=$false;public_activation=$false}|ConvertTo-Json|Tee-Object -FilePath (Join-Path $taskEvidence 'source5ab-preparation-20261015.json')

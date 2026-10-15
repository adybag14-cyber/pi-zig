param([Parameter(Mandatory)][string]$SlotGrant,[string]$Attempt='first')
$ErrorActionPreference='Stop'
$taskEvidence='C:/Users/adyba/pi-zig-update-evidence-20261003'
$taskPrivate='C:/Users/adyba/pi-zig-sdk-fs-metadata-20261016'
$taskName="node-fs-metadata-24-source-$Attempt-20261016"
$taskNode='C:/Program Files/nodejs/node.exe'
$taskInput=Join-Path $taskPrivate 'src/extensions/fixtures/node-fs-metadata-24.input.txt'
$taskSetup=Join-Path $taskPrivate 'src/extensions/fixtures/node-fs-metadata-24.files.json'
$taskDriver=Join-Path $PSScriptRoot 'node-fs-metadata-source-24.mjs'
$taskObserver=Join-Path $taskEvidence 'source5ab-observe-20261015.mjs'
$taskAsset=Join-Path $taskPrivate 'src/extensions/fixtures/sdk-resource-paths-dark-5ab.json'
if(Test-Path -LiteralPath (Join-Path $taskEvidence "$taskName.json")){throw 'Unique Source attempt name required'}
function Rows($taskPaths){@($taskPaths|Sort-Object -Unique|ForEach-Object{@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})}
function Drift($taskRows){@($taskRows|Where-Object{!(Test-Path -LiteralPath $_.path -PathType Leaf) -or (Get-FileHash -LiteralPath $_.path).Hash -cne $_.sha256}|ForEach-Object path)}
$taskRoot=Join-Path $taskEvidence ('node-fs-metadata-assets-'+$Attempt+'-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $taskRoot|Out-Null
New-Item -ItemType Directory -Path (Join-Path $taskRoot 'home')|Out-Null
$taskRootFull=[IO.Path]::GetFullPath($taskRoot)
$taskFiles=Get-Content -LiteralPath $taskSetup -Raw|ConvertFrom-Json
if($taskFiles.inherits -cne 'sdk-resource-class-5ab.files.json'){throw 'Unexpected inherited genuine fixture setup'}
$taskBaseSetup=Join-Path $taskPrivate 'src/extensions/fixtures/sdk-resource-class-5ab.files.json'
$taskBaseFiles=Get-Content -LiteralPath $taskBaseSetup -Raw|ConvertFrom-Json
$taskFiles.files=@($taskBaseFiles.files)+@($taskFiles.files)
$taskFiles.themes=@($taskBaseFiles.themes)+@($taskFiles.themes)
$taskFixturePaths=@()
foreach($taskFile in @($taskFiles.files)+@($taskFiles.themes)){
 $taskPath=[IO.Path]::GetFullPath((Join-Path $taskRoot $taskFile.path))
 if(!$taskPath.StartsWith($taskRootFull+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Fixture escaped owned root'}
 New-Item -ItemType Directory -Path (Split-Path -Parent $taskPath) -Force|Out-Null
 if($taskFile.PSObject.Properties.Name -contains 'content'){$taskContent=$taskFile.content}else{
  if($taskFile.asset -cne 'sdk-resource-paths-dark-5ab.json'){throw 'Unknown real Theme fixture asset'}
  $taskTheme=Get-Content -LiteralPath $taskAsset -Raw|ConvertFrom-Json
  $taskTheme.name=$taskFile.name
  $taskContent=$taskTheme|ConvertTo-Json -Depth 32
 }
 [IO.File]::WriteAllText($taskPath,$taskContent,[Text.UTF8Encoding]::new($false))
 $taskFixturePaths+=$taskPath
}
# Context and .agents discovery walks real ancestors. Freeze their existing
# readable inputs and absence state rather than filtering ambient results.
$taskAmbientPaths=@()
$taskAmbientAbsent=@()
$taskAmbientTrees=@()
$taskAncestor=[IO.DirectoryInfo]::new((Join-Path $taskRoot 'project'))
while($null -ne $taskAncestor){
 foreach($taskLeaf in @('AGENTS.override.md','AGENTS.md','AGENTS.MD','CLAUDE.md','CLAUDE.MD','.git')){
  $taskPath=Join-Path $taskAncestor.FullName $taskLeaf
  if($taskLeaf -ceq '.git' -and (Test-Path -LiteralPath $taskPath)){throw 'Ambient Git checkout requires a separately frozen linked-worktree context closure before this Source caller can run'}
  if(Test-Path -LiteralPath $taskPath -PathType Leaf){$taskAmbientPaths+=$taskPath}elseif(!(Test-Path -LiteralPath $taskPath)){$taskAmbientAbsent+=$taskPath}
 }
 $taskAgents=Join-Path $taskAncestor.FullName '.agents/skills'
 if(Test-Path -LiteralPath $taskAgents -PathType Container){$taskTreeFiles=@(Get-ChildItem -LiteralPath $taskAgents -File -Recurse -Force|ForEach-Object FullName|Sort-Object);$taskAmbientTrees+=@{root=$taskAgents;files=$taskTreeFiles};$taskAmbientPaths+=$taskTreeFiles}else{$taskAmbientAbsent+=$taskAgents}
 $taskAncestor=$taskAncestor.Parent
}
$taskSpecs=@(@{name='source';file='source5ab-full-manifest-20261015.json';count=1967},@{name='dependencies';file='durable-19cb534-reference-20261012-all-built-runtime.json';count=31064},@{name='node_tools';file='root-current8a-npm-tools-before.json';count=1774})
$taskFrozen=@()
foreach($taskSpec in $taskSpecs){
 $taskRows=@(Get-Content -LiteralPath (Join-Path $taskEvidence $taskSpec.file) -Raw|ConvertFrom-Json)
 if($taskRows.Count -ne $taskSpec.count -or @(Drift $taskRows).Count){throw "Full reference prehash invalid $($taskSpec.name)"}
 $taskFrozen+=@{name=$taskSpec.name;rows=$taskRows}
}
if((Get-FileHash -LiteralPath $taskNode).Hash -cne '63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088'){throw 'Pinned Node changed'}
$taskRuntime='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012'
$taskContract=Get-Content -LiteralPath (Join-Path $taskEvidence 'source5ab-dependency-contract-audit-20261015.json') -Raw|ConvertFrom-Json
if($taskContract.latestHead -cne '5ab7fe74c400097b386662205cd93900695b8a71' -or $taskContract.installed_metadata_verified -ne 281 -or $taskContract.platform_optional_absent_records -ne 80 -or $taskContract.historical_missing_records_retained -ne 4){throw 'Dependency contract scope changed'}
$taskAbsent=@($taskContract.pins|Where-Object status -eq 'platform_optional_absent'|ForEach-Object{Join-Path $taskRuntime $_.path})+@($taskContract.mismatches|ForEach-Object{Join-Path $taskRuntime $_.path})
if($taskAbsent.Count -ne 84 -or @($taskAbsent|Where-Object{Test-Path -LiteralPath $_}).Count){throw 'Historical absence state changed'}
$taskExtra=Rows (@($taskInput,$taskSetup,$taskBaseSetup,$taskDriver,$taskObserver,$taskAsset,$PSCommandPath,(Join-Path $taskEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1'),(Join-Path $taskEvidence 'source5ab-dependency-contract-audit-20261015.json'))+@($taskSpecs|ForEach-Object{Join-Path $taskEvidence $_.file})+$taskFixturePaths+$taskAmbientPaths)
$taskControlManifest=Join-Path $taskEvidence "$taskName-controls-before.json"
$taskExtra|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $taskControlManifest -Encoding utf8NoBOM
$taskControlManifestHash=(Get-FileHash -LiteralPath $taskControlManifest).Hash
$taskFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
@{status=if($taskFree -lt 2MB){'admission_denied'}else{'admitted'};free_kib=$taskFree;required_kib=2MB;heap_mb=256;outer_seconds=300;root_slot_grant=$SlotGrant;fixture_files=$taskFixturePaths.Count;ambient_files=$taskAmbientPaths.Count;ambient_absences=$taskAmbientAbsent.Count;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-admission.json")
if($taskFree -lt 2MB){exit 2}
$taskOutput=Join-Path $taskEvidence "$taskName-output.json"
& (Join-Path $taskEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1') -Name $taskName -Executable $taskNode -WorkingDirectory 'C:/Users/adyba/pi-upstream-source-5ab7fe7-20261015' -Arguments @('--max-old-space-size=256','--conditions=source','--experimental-transform-types','--import',([Uri]$taskObserver).AbsoluteUri,$taskDriver,$taskOutput,$taskInput,$taskRoot) -TimeoutSeconds 300 -EnvironmentOverrides @{NODE_OPTIONS='';NODE_PATH='';HOME=(Join-Path $taskRoot 'home');PI_SOURCE_ORACLE_CONTROL_MANIFEST=$taskControlManifest;PI_PACKAGE_DIR='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012/packages/coding-agent'}
$taskPost=@($taskFrozen|ForEach-Object{$taskChanged=@(Drift $_.rows);@{name=$_.name;files=$_.rows.Count;drift=$taskChanged.Count;changed=$taskChanged}})
$taskExtraChanged=@(Drift $taskExtra)
$taskAbsentChanged=@($taskAbsent+$taskAmbientAbsent|Where-Object{Test-Path -LiteralPath $_})
$taskManifestChanged=(Get-FileHash -LiteralPath $taskControlManifest).Hash -cne $taskControlManifestHash
$taskAmbientTreeDrift=@()
foreach($taskTree in $taskAmbientTrees){$taskAfterTreeFiles=@(Get-ChildItem -LiteralPath $taskTree.root -File -Recurse -Force|ForEach-Object FullName|Sort-Object);$taskAmbientTreeDrift+=@(Compare-Object (@('TREE')+@($taskTree.files)) (@('TREE')+$taskAfterTreeFiles))}
@{manifests=$taskPost;control_files=$taskExtra.Count;control_drift=$taskExtraChanged;control_manifest_drift=$taskManifestChanged;historical_absences=84;ambient_absences=$taskAmbientAbsent.Count;ambient_tree_drift=$taskAmbientTreeDrift;absent_drift=$taskAbsentChanged;fixture_root=$taskRoot;fixture_files=$taskFixturePaths.Count;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-posthash.json") -Encoding utf8NoBOM
if(@($taskPost|Where-Object drift -ne 0).Count -or $taskExtraChanged.Count -or $taskManifestChanged -or $taskAbsentChanged.Count -or $taskAmbientTreeDrift.Count){throw 'Source reference/control/fixture/absence posthash drift'}
$taskOwner=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName.json") -Raw|ConvertFrom-Json
if($taskOwner.status -cne 'passed'){throw "Actual Source oracle terminal $($taskOwner.status)"}
$taskResult=Get-Content -LiteralPath $taskOutput -Raw|ConvertFrom-Json
if($taskResult.sourceHead -cne '5ab7fe74c400097b386662205cd93900695b8a71' -or @($taskResult.rows).Count -ne $taskResult.cases -or $taskResult.cases -ne 22){throw 'Actual Node metadata caller corpus incomplete'}
Write-Output ('ACTUAL_NODE_METADATA_CASES='+$taskResult.cases)

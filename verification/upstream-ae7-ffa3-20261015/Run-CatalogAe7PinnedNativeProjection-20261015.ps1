$ErrorActionPreference='Stop'
$taskEvidence=$PSScriptRoot
$taskPrivate='C:/Users/adyba/pi-zig-upstream-catalog-ae7-20261015'
$taskReference='C:/Users/adyba/pi-zig-upstream-catalog-20261015'
$taskBinary=Join-Path $taskReference '.zig-cache/o/52406646a4a1987391f327026a7fd80a/pi-maintenance.exe'
$taskRaw=Join-Path $taskEvidence 'catalog-ae7-preparation-20261015/official-pinned-models.all.json'
$taskArchive=Join-Path $taskEvidence 'pi-upstream-ae7b16d-immutable-20261015.tar'
$taskManifest=Join-Path $taskPrivate 'src/ai/catalog_builtin_manifest.json'
$taskSourceManifest=Join-Path $taskEvidence 'catalog-ae7-preparation-20261015/source-full-after-hydration.json'
$taskToolManifest=Join-Path $taskEvidence 'durable-latest89-full-inspect-53ae-tool-prehash-20261011.json'
$taskName='catalog-ae7-ffa3-native-projection-first-20261015'
function Check-Rows($rows){@($rows|Where-Object{!(Test-Path -LiteralPath $_.path -PathType Leaf) -or (Get-FileHash -LiteralPath $_.path).Hash -ine $_.sha256})}
function Native-Rows {@(git -C $taskPrivate ls-files --cached --others --exclude-standard|Sort-Object -Unique|Where-Object{Test-Path -LiteralPath (Join-Path $taskPrivate $_) -PathType Leaf}|ForEach-Object{@{path=(Join-Path $taskPrivate $_);relative=$_;sha256=(Get-FileHash -LiteralPath (Join-Path $taskPrivate $_)).Hash}})}
if((git -C $taskPrivate rev-parse HEAD) -cne 'ee3e06e74d2136c0669209d3acff806956fb40ea'){throw 'Exact canonical successor base required'}
foreach($taskPin in @(
 @{path=$taskBinary;sha256='68C8C4E6D623D4B18D745D7A4FAEE61B2542529913222CF8D4403008650738AE'},
 @{path=$taskRaw;sha256='FFA3E98626230F378F80200DEBB736C4A2238B5F2BA246A92CFC7D8E19604678'},
 @{path=$taskArchive;sha256='CC12DEECB13CC85CC52CE19806BD45BD6264911E3BB2BF7ADD5775E09A18EF37'},
 @{path=$taskManifest;sha256='05A7F9B7D8FC9A28018F38C6EBB4B0321E3C3685FD6BED191730D5B32D9E60AF'},
 @{path=$taskSourceManifest;sha256='11D8B47D45731FA91BD179D841AE8CB4D3AD34EA540D8349CB17F963937F88E2'}
)){if((Get-FileHash -LiteralPath $taskPin.path).Hash -ine $taskPin.sha256){throw 'Pinned canonical catalog input mismatch'}}
# The proven executable implements these exact unchanged native source modules.
$taskToolNames=@('maintenance.zig','catalog.zig','projections.zig','config_schemas.zig','artifacts.zig','release.zig','upstream_contract.zig','native_composed_coverage.zig','native_composed_scope.zig','agent_allocation_coverage.zig','exhaustive_allocation_coverage.zig')
$taskToolSource=@()
foreach($taskFile in $taskToolNames){$taskOld=Join-Path $taskReference "tools/$taskFile";$taskNew=Join-Path $taskPrivate "tools/$taskFile";if((Get-FileHash -LiteralPath $taskOld).Hash -cne (Get-FileHash -LiteralPath $taskNew).Hash){throw 'Proven maintenance source closure drift'};$taskToolSource+=@{path=$taskOld;sha256=(Get-FileHash -LiteralPath $taskOld).Hash};$taskToolSource+=@{path=$taskNew;sha256=(Get-FileHash -LiteralPath $taskNew).Hash}}
$taskZig=@((Get-Content -LiteralPath $taskToolManifest -Raw|ConvertFrom-Json).inputs)
$taskSource=@(Get-Content -LiteralPath $taskSourceManifest -Raw|ConvertFrom-Json)
if($taskZig.Count -ne 19546 -or @(Check-Rows $taskZig).Count){throw 'Full pinned Zig input identity mismatch'}
if($taskSource.Count -ne 1968 -or @(Check-Rows $taskSource).Count){throw 'Full actual ae7 Source identity mismatch'}
$taskBefore=Native-Rows
$taskBefore|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-native-before.json") -Encoding utf8NoBOM
$taskControls=@($PSCommandPath,(Join-Path $taskEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1'),$taskBinary,$taskRaw,$taskArchive,$taskManifest,$taskSourceManifest,$taskToolManifest,(Join-Path $taskEvidence 'catalog-ae7-preparation-20261015/independent-audit.json'))|ForEach-Object{@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}}
$taskControls+= $taskToolSource
$taskControls|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-controls-before.json") -Encoding utf8NoBOM
$taskFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
@{status=if($taskFree -lt 2MB){'denied'}else{'admitted'};free_kib=$taskFree;required_kib=2MB;new_zig_compile=$false;timeout_seconds_per_phase=300;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-admission.json") -Encoding utf8NoBOM
if($taskFree -lt 2MB){throw 'Normal direct native tool2GiB admission denied'}
$taskSourceRoot='C:/Users/adyba/pi-upstream-catalog-source-ae7b16d-20261015'
$taskPaths=@(Get-ChildItem -LiteralPath $taskSourceRoot -File -Force -Recurse|ForEach-Object{[IO.Path]::GetRelativePath($taskSourceRoot,$_.FullName)}|Sort-Object)
try {
 & (Join-Path $taskEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1') -Name "$taskName-import" -Executable $taskBinary -WorkingDirectory $taskPrivate -Arguments @('import-catalog',$taskRaw,'1.3.0','ae7b16d43b7c78c5b6fa3213fdd1215bb339729d',$taskArchive,'sha256-ffa3e98626230f378f80200debb736c4a2238b5f2ba246a92cfc7d8e19604678','src/ai/catalog_source.json') -TimeoutSeconds 300
 if((Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName-import.json") -Raw|ConvertFrom-Json).status -cne 'passed'){throw 'Canonical native import terminal failure'}
 & (Join-Path $taskEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1') -Name "$taskName-generate" -Executable $taskBinary -WorkingDirectory $taskPrivate -Arguments @('catalog') -TimeoutSeconds 300
 if((Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName-generate.json") -Raw|ConvertFrom-Json).status -cne 'passed'){throw 'Canonical native generation terminal failure'}
 $taskDerived=@('src/ai/catalog_source.json','src/ai/catalog_generated.zig')|ForEach-Object{@{path=(Join-Path $taskPrivate $_);sha256=(Get-FileHash -LiteralPath (Join-Path $taskPrivate $_)).Hash}}
 $taskDerived|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-derived-before-check.json") -Encoding utf8NoBOM
 & (Join-Path $taskEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1') -Name "$taskName-check" -Executable $taskBinary -WorkingDirectory $taskPrivate -Arguments @('catalog','--check') -TimeoutSeconds 300
 if((Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName-check.json") -Raw|ConvertFrom-Json).status -cne 'passed' -or @(Check-Rows $taskDerived).Count){throw 'Canonical native generated checker failure/drift'}
} finally {
 $taskAfter=Native-Rows
 $taskAllowed=@('src/ai/catalog_source.json','src/ai/catalog_generated.zig')
 $taskBeforeRows=@($taskBefore|Where-Object{$_.relative -notin $taskAllowed}|ForEach-Object{"$($_.relative):$($_.sha256)"})
 $taskAfterRows=@($taskAfter|Where-Object{$_.relative -notin $taskAllowed}|ForEach-Object{"$($_.relative):$($_.sha256)"})
 $taskNativeDrift=@(Compare-Object $taskBeforeRows $taskAfterRows)
 $taskSourceDrift=@(Check-Rows $taskSource);$taskZigDrift=@(Check-Rows $taskZig);$taskControlsDrift=@(Check-Rows $taskControls)
 $taskPathsAfter=@(Get-ChildItem -LiteralPath $taskSourceRoot -File -Force -Recurse|ForEach-Object{[IO.Path]::GetRelativePath($taskSourceRoot,$_.FullName)}|Sort-Object)
 $taskPathDrift=@(Compare-Object $taskPaths $taskPathsAfter)
 @{native_before=$taskBefore.Count;native_after=$taskAfter.Count;allowed_mutations=$taskAllowed;native_drift_outside_allowed=$taskNativeDrift.Count;source_files=$taskSource.Count;source_drift=$taskSourceDrift.Count;source_path_drift=$taskPathDrift.Count;zig_files=$taskZig.Count;zig_drift=$taskZigDrift.Count;control_drift=$taskControlsDrift.Count;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-posthash.json") -Encoding utf8NoBOM
 if($taskNativeDrift.Count -or $taskSourceDrift.Count -or $taskPathDrift.Count -or $taskZigDrift.Count -or $taskControlsDrift.Count){throw 'Canonical native projection immutable input drift'}
}
Write-Output 'CANONICAL_AE7_FFA3_NATIVE_PROJECTION_GENERATED_AND_CHECKED'

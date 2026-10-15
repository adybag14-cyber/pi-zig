param([ValidateSet('Import','DebugCompile','DebugRuntime','ReleaseSafeCompile','ReleaseSafeRuntime')][string]$Phase='Import',[string]$Attempt='first')
$ErrorActionPreference='Stop'
$taskEvidence=$PSScriptRoot
$taskPrivate='C:/Users/adyba/pi-zig-upstream-catalog-20261015'
$taskZig='C:/Users/adyba/pi-zig-toolchain-20261003/zig-x86_64-windows-0.16.0/zig.exe'
$taskName="catalog5ab-native-$($Phase.ToLowerInvariant())-$Attempt-20261015"
$taskArchive=Join-Path $taskEvidence 'pi-upstream-5ab7fe7-immutable-20261015.tar'
$taskCatalog=Join-Path $taskEvidence 'catalog5ab-official-first-20261015/models.all.json'
$taskToolsManifest=Join-Path $taskEvidence 'durable-latest89-full-inspect-53ae-tool-prehash-20261011.json'
function Check-Rows($rows) {
 @($rows|Where-Object{!(Test-Path -LiteralPath $_.path -PathType Leaf) -or (Get-FileHash -LiteralPath $_.path).Hash -ine $_.sha256})
}
function Source-Rows {
 @(git -C $taskPrivate ls-files --cached --others --exclude-standard|Sort-Object -Unique|Where-Object{Test-Path -LiteralPath (Join-Path $taskPrivate $_) -PathType Leaf}|ForEach-Object{@{path=(Join-Path $taskPrivate $_);relative=$_;sha256=(Get-FileHash -LiteralPath (Join-Path $taskPrivate $_)).Hash}})
}
if((Get-FileHash -LiteralPath $taskZig).Hash -cne '086CE9D47BA42F33A514E1A6E04EB1D4A8FA1D75E0868E0213CAAD447C91E864'){throw 'Zig pin mismatch'}
if((Get-FileHash -LiteralPath $taskArchive).Hash -cne 'BB1B83D360C004472059628EA7594FEE16232EB3931A58A1F07E2ABA67C3DF72'){throw 'Archive mismatch'}
if((Get-FileHash -LiteralPath $taskCatalog).Hash -cne '4334227667568186DF17628973E890A2582A44C4EF67F16621704387AE73C8C9'){throw 'Official typed catalog mismatch'}
$taskTools=@((Get-Content -LiteralPath $taskToolsManifest -Raw|ConvertFrom-Json).inputs)
if($taskTools.Count -ne 19546 -or @(Check-Rows $taskTools).Count){throw 'Full pinned Zig toolchain mismatch'}
$taskControls=@($PSCommandPath,(Join-Path $taskEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1'),$taskArchive,$taskCatalog,$taskToolsManifest)|ForEach-Object{@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}}
$taskControls|ConvertTo-Json -Depth 4|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-controls-before.json") -Encoding utf8NoBOM
$taskBefore=Source-Rows
$taskBefore|ConvertTo-Json -Depth 4|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-source-before.json") -Encoding utf8NoBOM
$taskFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
@{status=if($taskFree -lt 16MB){'denied'}else{'admitted'};free_kib=$taskFree;required_kib=16MB;max_coordinated_jobs=4;jobs=1;test_timeout_seconds=120;phase=$Phase;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-admission.json") -Encoding utf8NoBOM
if($taskFree -lt 16MB){throw 'Normal native16GiB admission denied'}
try {
 if($Phase -eq 'Import'){
  & (Join-Path $taskEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1') -Name "$taskName-import" -Executable $taskZig -WorkingDirectory $taskPrivate -Arguments @('build','maintenance','-j1','--','import-catalog',$taskCatalog,'1.2.0','5ab7fe74c400097b386662205cd93900695b8a71',$taskArchive,'sha256-4334227667568186df17628973e890a2582a44c4ef67f16621704387ae73c8c9','src/ai/catalog_source.json') -TimeoutSeconds 1320
  $taskImport=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName-import.json") -Raw|ConvertFrom-Json
  if($taskImport.status -cne 'passed'){throw 'Native import failed'}
  & (Join-Path $taskEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1') -Name "$taskName-generate" -Executable $taskZig -WorkingDirectory $taskPrivate -Arguments @('build','maintenance','-j1','--','catalog') -TimeoutSeconds 300
  $taskGenerate=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName-generate.json") -Raw|ConvertFrom-Json
  if($taskGenerate.status -cne 'passed'){throw 'Native generation failed'}
  & (Join-Path $taskEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1') -Name "$taskName-check" -Executable $taskZig -WorkingDirectory $taskPrivate -Arguments @('build','maintenance','-j1','--','catalog','--check') -TimeoutSeconds 300
  $taskCheck=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName-check.json") -Raw|ConvertFrom-Json
  if($taskCheck.status -cne 'passed'){throw 'Native generated catalog stale'}
 }else{
  $taskMode=if($Phase.StartsWith('ReleaseSafe')){'ReleaseSafe'}else{'Debug'}
  $taskCompile=$Phase.EndsWith('Compile')
  $taskTarget=if($taskCompile){'build-latest-catalog-data'}else{'test-latest-catalog-data'}
  & (Join-Path $taskEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1') -Name $taskName -Executable $taskZig -WorkingDirectory $taskPrivate -Arguments @('build',$taskTarget,"-Doptimize=$taskMode",'-Duse-llvm=true','-j1','--test-timeout','120s','--summary','all') -TimeoutSeconds $(if($taskCompile){1320}else{300})
  $taskCheck=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName.json") -Raw|ConvertFrom-Json
  if($taskCheck.status -cne 'passed'){throw 'Native focused catalog phase failed'}
 }
}finally{
 $taskAfter=Source-Rows
 $taskAllowed=if($Phase -eq 'Import'){@('src/ai/catalog_source.json','src/ai/catalog_generated.zig')}else{@()}
 $taskUnchangedBefore=@($taskBefore|Where-Object{$_.relative -notin $taskAllowed}|ForEach-Object{"$($_.relative):$($_.sha256)"})
 $taskUnchangedAfter=@($taskAfter|Where-Object{$_.relative -notin $taskAllowed}|ForEach-Object{"$($_.relative):$($_.sha256)"})
 $taskSourceDrift=@(Compare-Object $taskUnchangedBefore $taskUnchangedAfter)
 $taskToolsDrift=@(Check-Rows $taskTools)
 $taskControlsDrift=@(Check-Rows $taskControls)
 @{source_before=$taskBefore.Count;source_after=$taskAfter.Count;source_drift_outside_allowed=$taskSourceDrift.Count;allowed_mutations=$taskAllowed;zig_tools=$taskTools.Count;zig_tool_drift=$taskToolsDrift.Count;control_drift=$taskControlsDrift.Count;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-posthash.json") -Encoding utf8NoBOM
 if($taskSourceDrift.Count -or $taskToolsDrift.Count -or $taskControlsDrift.Count){throw 'Native immutable input drift'}
}
Write-Output "NATIVE_CATALOG5AB_PHASE_PASSED phase=$Phase"

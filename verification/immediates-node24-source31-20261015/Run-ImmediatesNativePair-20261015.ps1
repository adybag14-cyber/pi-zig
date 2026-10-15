param([ValidateSet('Debug','ReleaseSafe')][string]$Mode='Debug',[string]$Attempt='first',[int]$Slot=3,[Parameter(Mandatory)][string]$ExpectedHead)
$ErrorActionPreference='Stop'
$taskEvidence=$PSScriptRoot
$taskTree='C:/Users/adyba/pi-zig-native-immediates-20261015'
$taskZig='C:/Users/adyba/pi-zig-toolchain-20261003/zig-x86_64-windows-0.16.0/zig.exe'
$taskName="immediates-native-$($Mode.ToLowerInvariant())-$Attempt-20261015"
$taskOwner=Join-Path $taskEvidence 'Invoke-WebCryptoOwnedSource-20261015.ps1'
$taskToolManifest=Join-Path $taskEvidence 'durable-latest89-full-inspect-53ae-tool-prehash-20261011.json'
$taskNodeManifest=Join-Path $taskEvidence 'sourceae7-node-tools-before-20261015.json'
function Check-Rows($rows){
 $changed=[Collections.Generic.List[string]]::new()
 foreach($row in $rows){
  if(!(Test-Path -LiteralPath $row.path -PathType Leaf)){$changed.Add($row.path);continue}
  $stream=[IO.File]::OpenRead($row.path)
  try{$actual=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream))}finally{$stream.Dispose()}
  if($actual -cne $row.sha256){$changed.Add($row.path)}
 }
 return @($changed)
}
function Candidate-Rows {
 @(& git -c gc.auto=0 -c maintenance.auto=false -C $taskTree ls-files --cached --others --exclude-standard|Sort-Object -Unique|ForEach-Object {$path=Join-Path $taskTree $_;@{path=$path;relative=$_;sha256=(Get-FileHash -LiteralPath $path).Hash}})
}
function Compiler-Paths {@(Get-ChildItem -LiteralPath (Split-Path $taskZig -Parent) -Recurse -File -Force|ForEach-Object FullName|Sort-Object)}
function Node-Paths {@(@('C:\Program Files\nodejs\node.exe')+@(Get-ChildItem -LiteralPath 'C:/Program Files/nodejs/node_modules/npm' -Recurse -File -Force|ForEach-Object FullName)|Sort-Object)}
if((& git -c gc.auto=0 -c maintenance.auto=false -C $taskTree rev-parse HEAD) -cne $ExpectedHead -or (& git -c gc.auto=0 -c maintenance.auto=false -C $taskTree status --porcelain)){throw 'Exact clean native candidate required'}
if((Get-FileHash -LiteralPath $taskZig).Hash -cne '086CE9D47BA42F33A514E1A6E04EB1D4A8FA1D75E0868E0213CAAD447C91E864'){throw 'Pinned Zig0.16 compiler changed'}
if((Get-FileHash -LiteralPath (Join-Path $taskTree 'src/extensions/fixtures/immediates-node24.json')).Hash -cne '998FA2F426746FB3CC2406AC4A375C4777EDE4A3F6485A2C6E4C5CEA09FF5F27'){throw 'Genuine Source31 fixture changed'}
$taskTools=@((Get-Content -Raw $taskToolManifest|ConvertFrom-Json).inputs)
$taskNode=@(Get-Content -Raw $taskNodeManifest|ConvertFrom-Json)
if($taskTools.Count -ne 19546 -or $taskNode.Count -ne 1774 -or @(Check-Rows $taskTools).Count -or @(Check-Rows $taskNode).Count){throw 'Full compiler/Node immutable input prehash drift'}
$taskCompilerPaths=Compiler-Paths;$taskNodePaths=Node-Paths
if(@(Compare-Object @($taskTools.path|Sort-Object) $taskCompilerPaths).Count -or @(Compare-Object @($taskNode.path|Sort-Object) $taskNodePaths).Count){throw 'Compiler/Node full scoped path inventory prehash drift'}
$taskBefore=Candidate-Rows
$taskControls=@($PSCommandPath,$taskOwner,$taskToolManifest,$taskNodeManifest,(Join-Path $taskEvidence 'web-body-node24-source-first-20261015-node-builtin-authorities.json'),(Join-Path $taskEvidence 'Run-ImmediatesNode24Source-20261015.ps1'),(Join-Path $taskEvidence 'immediates-node24-source-first-20261015.json'),(Join-Path $taskEvidence 'immediates-node24-source-first-20261015-posthash.json'),(Join-Path $taskEvidence 'immediates-node24-source-first-20261015-validation.json'))|ForEach-Object {@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}}
$taskBefore|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-before.json") -Encoding utf8NoBOM
$taskControls|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-controls.json") -Encoding utf8NoBOM
function Post-Check([string]$phase){
 $after=Candidate-Rows
 $drift=@(Compare-Object @($taskBefore|ForEach-Object {"$($_.relative):$($_.sha256)"}) @($after|ForEach-Object {"$($_.relative):$($_.sha256)"}))
 $toolDrift=@(Check-Rows $taskTools);$nodeDrift=@(Check-Rows $taskNode);$controlDrift=@(Check-Rows $taskControls)
 $compilerInventoryDrift=@(Compare-Object $taskCompilerPaths @(Compiler-Paths));$nodeInventoryDrift=@(Compare-Object $taskNodePaths @(Node-Paths))
 @{candidate=$ExpectedHead;source_files=$taskBefore.Count;source_after=$after.Count;source_drift=$drift;compiler_files=$taskTools.Count;compiler_drift=$toolDrift;compiler_inventory_drift=$compilerInventoryDrift;node_files=$taskNode.Count;node_drift=$nodeDrift;node_inventory_drift=$nodeInventoryDrift;node_scope='node.exe plus complete npm directory1774; unrelated launchers/corepack excluded';builtin_source_count=368;non_source_configs_excluded=$true;control_files=@($taskControls).Count;control_drift=$controlDrift;phase=$phase;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-$phase-posthash.json") -Encoding utf8NoBOM
 if($drift.Count -or $toolDrift.Count -or $nodeDrift.Count -or $controlDrift.Count -or $compilerInventoryDrift.Count -or $nodeInventoryDrift.Count){throw 'Frozen native pair input drift'}
}
function Admission([string]$phase){
 $free=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
 $roots=@(Get-CimInstance Win32_Process -Filter "Name = 'zig.exe'"|Where-Object {$_.CommandLine -match '\sbuild\s'}|Select-Object ProcessId,CommandLine)
 @{status=if($free -lt 16MB -or $roots.Count -ge 4){'denied'}else{'admitted'};free_kib=$free;required_kib=16MB;slot=$Slot;jobs=1;maximum_native_roots=4;other_native_roots=$roots;compile_outer_seconds=1320;runtime_outer_seconds=300;test_timeout_seconds=120;host_await_seconds=10;candidate=$ExpectedHead;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-$phase-admission.json") -Encoding utf8NoBOM
 if($free -lt 16MB -or $roots.Count -ge 4){throw 'Fresh native16GiB/max4 admission denied'}
}
Admission 'compile'
try{& $taskOwner -Name "$taskName-compile" -Executable $taskZig -WorkingDirectory $taskTree -Arguments @('build','build-native-immediates',"-Doptimize=$Mode",'-Duse-llvm=true','-j1','--test-timeout','120s','--summary','all') -TimeoutSeconds 1320}finally{Post-Check 'compile'}
$taskCompile=Get-Content -Raw (Join-Path $taskEvidence "$taskName-compile.json")|ConvertFrom-Json
if($taskCompile.status -cne 'passed'){throw 'Native Immediates compile terminal failed'}
$taskArtifacts=@(Get-ChildItem -LiteralPath (Join-Path $taskTree '.zig-cache') -Recurse -File|Where-Object Extension -in @('.exe','.pdb')|ForEach-Object {@{path=$_.FullName;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}})
if(!$taskArtifacts.Count){throw 'Compiled native artifact missing'}
$taskArtifacts|ConvertTo-Json -Depth 4|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-artifacts.json") -Encoding utf8NoBOM
Admission 'runtime'
try{& $taskOwner -Name "$taskName-runtime" -Executable $taskZig -WorkingDirectory $taskTree -Arguments @('build','test-native-immediates',"-Doptimize=$Mode",'-Duse-llvm=true','-j1','--test-timeout','120s','--summary','all') -TimeoutSeconds 300}finally{Post-Check 'runtime'}
$taskRuntime=Get-Content -Raw (Join-Path $taskEvidence "$taskName-runtime.json")|ConvertFrom-Json
if($taskRuntime.status -cne 'passed' -or @(Check-Rows $taskArtifacts).Count){throw 'Native Immediates runtime failure/artifact drift'}
@{candidate=$ExpectedHead;source_cases=31;mode=$Mode;compile_pid=$taskCompile.pid;runtime_pid=$taskRuntime.pid;artifact_count=$taskArtifacts.Count;terminal='passed';full_pi_qualified=$false}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-validation.json") -Encoding utf8NoBOM
Write-Output 'NATIVE_IMMEDIATES_FROZEN_PAIR_PASSED'

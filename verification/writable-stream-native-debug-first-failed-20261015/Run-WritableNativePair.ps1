$ErrorActionPreference='Stop'
$taskEvidence=$PSScriptRoot
$taskTree='C:/Users/adyba/pi-zig-native-writable-stream-20261015'
$taskHead='ae17eba02d74beec606606e850f0ed5e1a05d6f7'
$taskZig='C:/Users/adyba/pi-zig-toolchain-20261003/zig-x86_64-windows-0.16.0/zig.exe'
$taskGit=(Get-Command git.exe -CommandType Application|Select-Object -First 1).Source
$taskRootEvidence='C:/Users/adyba/pi-zig-update-evidence-20261003'
$taskOwner=Join-Path $taskEvidence 'Invoke-OwnedNativeJob.ps1'
$taskToolManifest=Join-Path $taskRootEvidence 'durable-latest89-full-inspect-53ae-tool-prehash-20261011.json'
$taskNodeManifest=Join-Path $taskRootEvidence 'root-current8a-npm-tools-before.json'
$taskAuthority=Join-Path $taskRootEvidence 'web-body-node24-source-first-20261015-node-builtin-authorities.json'
$taskSourcePacket=Join-Path $taskTree 'verification/writable-stream-node24-source56-captured-20261015'
function CandidateGit([string[]]$Arguments){& $taskGit -c gc.auto=0 -c maintenance.auto=false -c pack.threads=2 -c pack.windowMemory=64m -C $taskTree @Arguments}
function FileHash([string]$Path){$input=[IO.File]::OpenRead($Path);try{return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($input))}finally{$input.Dispose()}}
function ChangedRows($Rows){$changed=[Collections.Generic.List[string]]::new();foreach($row in $Rows){if(!(Test-Path -LiteralPath $row.path -PathType Leaf) -or (FileHash $row.path) -ine $row.sha256){$changed.Add($row.path)}};return @($changed)}
function FreezePaths($Paths,[string]$Manifest){$rows=@($Paths|ForEach-Object{@{path=$_;sha256=(FileHash $_)}});$rows|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $Manifest -Encoding utf8NoBOM;return ,$rows}
function CandidatePaths{@(CandidateGit @('ls-files','--cached','--others','--exclude-standard')|Sort-Object -Unique|ForEach-Object{Join-Path $taskTree $_})}
function CompilerPaths{@(Get-ChildItem -LiteralPath (Split-Path $taskZig -Parent) -File -Force -Recurse|ForEach-Object FullName|Sort-Object)}
function NodePaths{@(@('C:/Program Files/nodejs/node.exe')+@(Get-ChildItem -LiteralPath 'C:/Program Files/nodejs/node_modules/npm' -File -Force -Recurse|ForEach-Object FullName)|ForEach-Object{[IO.Path]::GetFullPath($_)}|Sort-Object)}
function VendorPaths{@(Get-ChildItem -LiteralPath (Join-Path $taskTree 'vendor') -File -Force -Recurse|ForEach-Object FullName|Sort-Object)}
function State([string]$Status){@{status=$Status;head=$taskHead;utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence 'caller-state.json') -Encoding utf8NoBOM}
try {
 State 'preparing'
 if((CandidateGit @('rev-parse','HEAD')) -cne $taskHead -or @(CandidateGit @('status','--porcelain')).Count){throw 'Exact clean published native candidate required'}
 if((FileHash $taskZig) -cne '086CE9D47BA42F33A514E1A6E04EB1D4A8FA1D75E0868E0213CAAD447C91E864'){throw 'Pinned Zig0.16 compiler changed'}
 if((FileHash (Join-Path $taskTree 'src/extensions/fixtures/writable-stream-node24.json')) -cne '1325C1A9B672A3F206E7711C2A3AAC4A43DDC8E4B2B169F7461AA3F8CBEA8EE5'){throw 'Genuine Source56 expected fixture changed'}
 if((FileHash $taskAuthority) -cne '0CD86676BB2A46A4E772D1FD8BB3D00FCA658383BC388846DCC796547DC79263'){throw 'Original368 builtin body artifact changed'}
 $sourceValidation=Get-Content -Raw (Join-Path $taskSourcePacket 'validation.json')|ConvertFrom-Json
 $sourceBuiltin=Get-Content -Raw (Join-Path $taskSourcePacket 'actual-builtin-authority.json')|ConvertFrom-Json
 if(!$sourceValidation.accepted_after_terminal_and_fullpost0 -or $sourceValidation.source_cases -ne 56 -or $sourceBuiltin.keys -ne 369 -or $sourceBuiltin.stringBodies -ne 368 -or !$sourceBuiltin.configsOwn -or !$sourceBuiltin.configsUndefined){throw 'Source56 genuine builtin/reference qualification absent'}
 State 'full-prehash'
 $taskTools=@((Get-Content -Raw $taskToolManifest|ConvertFrom-Json).inputs)
 $taskNode=@(Get-Content -Raw $taskNodeManifest|ConvertFrom-Json)
 if($taskTools.Count -ne 19546 -or $taskNode.Count -ne 1774 -or @(ChangedRows $taskTools).Count -or @(ChangedRows $taskNode).Count){throw 'Strict19546 compiler/1774 Node prehash mismatch'}
 $taskCompilerPaths=CompilerPaths;$taskNodePaths=NodePaths;$taskVendorPaths=VendorPaths;$taskCandidatePaths=CandidatePaths
 if(@(Compare-Object @($taskTools.path|ForEach-Object{[IO.Path]::GetFullPath($_)}|Sort-Object) $taskCompilerPaths).Count -or @(Compare-Object @($taskNode.path|ForEach-Object{[IO.Path]::GetFullPath($_)}|Sort-Object) $taskNodePaths).Count){throw 'Strict compiler/Node scoped path inventory mismatch'}
 $taskBefore=FreezePaths $taskCandidatePaths (Join-Path $taskEvidence 'whole-candidate-before.json')
 $taskVendor=FreezePaths $taskVendorPaths (Join-Path $taskEvidence 'whole-vendor-before.json')
 $taskControls=FreezePaths @($PSCommandPath,$taskOwner,$taskToolManifest,$taskNodeManifest,$taskAuthority,$taskGit,$taskZig,(Join-Path $taskSourcePacket 'validation.json'),(Join-Path $taskSourcePacket 'full-posthash.json'),(Join-Path $taskSourcePacket 'actual-builtin-authority.json'),(Join-Path $taskSourcePacket 'Run-WritableStreamNode24Source.ps1'),(Join-Path $taskSourcePacket 'Invoke-OwnedEeSourceJob-20261012.ps1'),(Join-Path $taskSourcePacket 'controls-before.json'),(Join-Path $taskEvidence 'whole-candidate-before.json'),(Join-Path $taskEvidence 'whole-vendor-before.json')) (Join-Path $taskEvidence 'controls-before.json')
 function PostCheck([string]$Phase){
  $candidateChanged=@(ChangedRows $taskBefore);$vendorChanged=@(ChangedRows $taskVendor);$compilerChanged=@(ChangedRows $taskTools);$nodeChanged=@(ChangedRows $taskNode);$controlChanged=@(ChangedRows $taskControls)
  $candidatePathsChanged=@(Compare-Object $taskCandidatePaths @(CandidatePaths));$vendorPathsChanged=@(Compare-Object $taskVendorPaths @(VendorPaths));$compilerPathsChanged=@(Compare-Object $taskCompilerPaths @(CompilerPaths));$nodePathsChanged=@(Compare-Object $taskNodePaths @(NodePaths))
  $headChanged=(CandidateGit @('rev-parse','HEAD')) -cne $taskHead;$dirty=@(CandidateGit @('status','--porcelain'))
  @{phase=$Phase;candidate=$taskHead;candidate_files=$taskBefore.Count;candidate_drift=$candidateChanged;candidate_path_drift=$candidatePathsChanged;vendor_files=$taskVendor.Count;vendor_drift=$vendorChanged;vendor_path_drift=$vendorPathsChanged;compiler_files=19546;compiler_drift=$compilerChanged;compiler_path_drift=$compilerPathsChanged;node_files=1774;node_drift=$nodeChanged;node_path_drift=$nodePathsChanged;control_files=$taskControls.Count;control_drift=$controlChanged;head_drift=$headChanged;candidate_dirty=$dirty;source_cases=56;builtin_bodies=368;builtin_keys=369;configs_own_undefined=$true;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 7|Set-Content -LiteralPath (Join-Path $taskEvidence "$Phase-posthash.json") -Encoding utf8NoBOM
  if($candidateChanged.Count -or $vendorChanged.Count -or $compilerChanged.Count -or $nodeChanged.Count -or $controlChanged.Count -or $candidatePathsChanged.Count -or $vendorPathsChanged.Count -or $compilerPathsChanged.Count -or $nodePathsChanged.Count -or $headChanged -or $dirty.Count){throw 'Frozen native pair immutable input drift'}
 }
 function Admission([string]$Phase){
  $free=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
  $roots=@(Get-CimInstance Win32_Process -Filter "Name = 'zig.exe'"|Where-Object{$_.CommandLine -match '\sbuild\s'}|Select-Object ProcessId,CommandLine)
  @{phase=$Phase;status=if($free -lt 16MB -or $roots.Count -ge 4){'denied'}else{'admitted'};free_kib=$free;required_kib=16MB;slot=3;jobs=1;maximum_native_roots=4;other_native_roots=$roots;compile_outer_seconds=1320;runtime_outer_seconds=300;test_timeout_seconds=120;host_await_seconds=10;candidate=$taskHead;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskEvidence "$Phase-admission.json") -Encoding utf8NoBOM
  if($free -lt 16MB -or $roots.Count -ge 4){throw 'Fresh native16GiB/max4 admission denied'}
 }
 Admission 'compile';State 'compile-running'
 try {& $taskOwner -Executable $taskZig -WorkingDirectory $taskTree -Arguments @('build','build-native-writable-stream','-Doptimize=Debug','-Duse-llvm=true','-j1','--test-timeout','120s','--summary','all') -ReceiptBase (Join-Path $taskEvidence 'compile') -TimeoutSeconds 1320} finally {State 'compile-posthash';PostCheck 'compile'}
 $taskCompile=Get-Content -Raw (Join-Path $taskEvidence 'compile.process.json')|ConvertFrom-Json
 if($taskCompile.status -cne 'passed' -or $taskCompile.exit_code -ne 0 -or !$taskCompile.owned_root_absent){throw 'Writable native compile terminal failed'}
 $taskArtifacts=@(Get-ChildItem -LiteralPath (Join-Path $taskTree '.zig-cache') -File -Recurse|Where-Object Extension -in @('.exe','.pdb')|ForEach-Object{@{path=$_.FullName;sha256=(FileHash $_.FullName)}})
 if(!$taskArtifacts.Count){throw 'Compiled native artifacts absent'}
 $taskArtifacts|ConvertTo-Json -Depth 4|Set-Content -LiteralPath (Join-Path $taskEvidence 'artifacts-before-runtime.json') -Encoding utf8NoBOM
 Admission 'runtime';State 'runtime-running'
 try {& $taskOwner -Executable $taskZig -WorkingDirectory $taskTree -Arguments @('build','test-native-writable-stream','-Doptimize=Debug','-Duse-llvm=true','-j1','--test-timeout','120s','--summary','all') -ReceiptBase (Join-Path $taskEvidence 'runtime') -TimeoutSeconds 300} finally {State 'runtime-posthash';PostCheck 'runtime'}
 $taskRuntime=Get-Content -Raw (Join-Path $taskEvidence 'runtime.process.json')|ConvertFrom-Json
 if($taskRuntime.status -cne 'passed' -or $taskRuntime.exit_code -ne 0 -or !$taskRuntime.owned_root_absent -or @(ChangedRows $taskArtifacts).Count){throw 'Writable native runtime terminal failed/artifact changed'}
 @{candidate=$taskHead;source_cases=56;mode='Debug';compile_pid=$taskCompile.pid;runtime_pid=$taskRuntime.pid;terminal='passed';artifact_count=$taskArtifacts.Count;compile_and_runtime_fullpost0=$true;public_activation=$false;full_pi_qualified=$false}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence 'validation.json') -Encoding utf8NoBOM
 State 'passed';Write-Output 'NATIVE_WRITABLE_SOURCE56_FROZEN_PAIR_PASSED'
} catch {
 State 'failed';@{message=$_.Exception.Message;stack=$_.ScriptStackTrace;utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence 'caller-error.json') -Encoding utf8NoBOM;throw
}

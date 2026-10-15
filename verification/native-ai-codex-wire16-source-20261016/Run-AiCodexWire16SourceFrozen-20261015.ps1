param([ValidateRange(1,6)][int]$Slot,[string]$Attempt='first')
$ErrorActionPreference='Stop'
$taskEvidence=$PSScriptRoot
$taskName="ai-codex-wire16-5ab-source16-$Attempt-20261015"
$taskCandidate='C:/Users/adyba/pi-zig-native-responses-ws-provider-20261015'
$taskQualified='C:/Users/adyba/pi-zig-native-responses-retry-20261015'
$taskSource='C:/Users/adyba/pi-upstream-source-5ab7fe7-20261015'
$taskCompiler='C:/Users/adyba/pi-zig-toolchain-20261003/zig-x86_64-windows-0.16.0'
$taskInner=Join-Path $taskEvidence 'Run-AiCodexWire16Source-20261015.ps1'
$taskDriver=Join-Path $taskEvidence 'source5ab-codex-wire16-capture-20261015.mjs'
function Tree-Rows([string]$tree){
 @(git -c gc.auto=0 -c maintenance.auto=false -C $tree ls-files --cached --others --exclude-standard|Sort-Object -Unique|ForEach-Object{[ordered]@{path=(Join-Path $tree $_);sha256=(Get-FileHash -LiteralPath (Join-Path $tree $_)).Hash}})
}
function Check-Rows($rows){@($rows|Where-Object{!(Test-Path -LiteralPath $_.path -PathType Leaf) -or (Get-FileHash -LiteralPath $_.path).Hash -cne $_.sha256})}
function Source-Paths{@(git -c gc.auto=0 -c maintenance.auto=false -C $taskSource ls-files --cached --others --exclude-standard|Sort-Object -Unique)}
function Compiler-Paths{@(Get-ChildItem -LiteralPath $taskCompiler -Recurse -Force -File|ForEach-Object FullName|Sort-Object -Unique)}
if(!$PSBoundParameters.ContainsKey('Slot')){throw 'Root-granted LIGHT slot must be explicit'}
if((git -C $taskCandidate rev-parse HEAD) -cne '7506f22d06fc2adbdb98a41d0dc8b3a42fb8b7dc' -or (git -C $taskCandidate status --porcelain)){throw 'Exact clean WS provider candidate required'}
if((git -C $taskQualified rev-parse HEAD) -cne 'cdceb00262999deca1e02b531266227b5ad61588' -or (git -C $taskQualified status --porcelain)){throw 'Qualified retry checkout must remain unchanged'}
if((Get-FileHash -LiteralPath $taskInner).Hash -cne '3DBC755AD437B686D318E24D74536F57886BF7EBC8FC8488F6695B5D5357E070'){throw 'Granted strict inner owner changed'}
if((Get-FileHash -LiteralPath $taskDriver).Hash -cne 'A8DA38B97F19B7438BDC4580BBB947C1F644EA0F1366D5E0C9B55B37DB877FF5'){throw 'Granted Source16 caller changed'}
if(Test-Path -LiteralPath (Join-Path $taskEvidence "$taskName.json")){throw 'Refuse replay of immutable Source attempt'}
if(Test-Path -LiteralPath (Join-Path $taskCandidate 'src/extensions/fixtures/ai-codex-wire16-5ab.json')){throw 'Expected must remain absent before terminal genuine capture'}
& 'C:/Program Files/nodejs/node.exe' --check $taskDriver
if($LASTEXITCODE -ne 0){throw 'Source16 caller syntax failed'}
$taskCandidateBefore=Tree-Rows $taskCandidate
$taskQualifiedBefore=Tree-Rows $taskQualified
$taskSourcePathsBefore=Source-Paths
$taskCompilerPathsBefore=Compiler-Paths
$taskControls=@($PSCommandPath,$taskInner,$taskDriver)|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}}
[ordered]@{slot="LIGHT$Slot";candidate=$taskCandidateBefore;qualified=$taskQualifiedBefore;source_paths=$taskSourcePathsBefore;compiler_paths=$taskCompilerPathsBefore;controls=$taskControls}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-candidate-freeze.json") -Encoding utf8NoBOM
$taskFailure=$null
try{& $taskInner -Attempt $Attempt}catch{$taskFailure=$_}
$taskCandidateAfter=Tree-Rows $taskCandidate
$taskQualifiedAfter=Tree-Rows $taskQualified
$taskCandidateDrift=@(Check-Rows $taskCandidateBefore)
$taskQualifiedDrift=@(Check-Rows $taskQualifiedBefore)
$taskCandidatePaths=@(Compare-Object @($taskCandidateBefore.path) @($taskCandidateAfter.path))
$taskQualifiedPaths=@(Compare-Object @($taskQualifiedBefore.path) @($taskQualifiedAfter.path))
$taskSourcePaths=@(Compare-Object $taskSourcePathsBefore (Source-Paths))
$taskCompilerPaths=@(Compare-Object $taskCompilerPathsBefore (Compiler-Paths))
$taskControlDrift=@(Check-Rows $taskControls)
$taskHeadChanged=(git -C $taskCandidate rev-parse HEAD) -cne '7506f22d06fc2adbdb98a41d0dc8b3a42fb8b7dc'
$taskQualifiedHeadChanged=(git -C $taskQualified rev-parse HEAD) -cne 'cdceb00262999deca1e02b531266227b5ad61588'
[ordered]@{slot="LIGHT$Slot";candidate=$taskCandidateBefore.Count;candidate_after=$taskCandidateAfter.Count;candidate_drift=$taskCandidateDrift.Count;candidate_path_drift=$taskCandidatePaths.Count;candidate_head_drift=$taskHeadChanged;qualified=$taskQualifiedBefore.Count;qualified_after=$taskQualifiedAfter.Count;qualified_drift=$taskQualifiedDrift.Count;qualified_path_drift=$taskQualifiedPaths.Count;qualified_head_drift=$taskQualifiedHeadChanged;source_paths=$taskSourcePathsBefore.Count;source_path_drift=$taskSourcePaths.Count;compiler_paths=$taskCompilerPathsBefore.Count;compiler_path_drift=$taskCompilerPaths.Count;controls=$taskControls.Count;control_drift=$taskControlDrift.Count;failure=if($taskFailure){$taskFailure.ToString()}else{$null};completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 5|Tee-Object -FilePath (Join-Path $taskEvidence "$taskName-candidate-posthash.json")
if($taskCandidateDrift.Count -or $taskQualifiedDrift.Count -or $taskCandidatePaths.Count -or $taskQualifiedPaths.Count -or $taskSourcePaths.Count -or $taskCompilerPaths.Count -or $taskControlDrift.Count -or $taskHeadChanged -or $taskQualifiedHeadChanged){throw 'Frozen candidate/reference/control posthash drift'}
if($taskFailure){throw $taskFailure}



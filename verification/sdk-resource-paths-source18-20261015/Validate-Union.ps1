$ErrorActionPreference='Stop'
$taskEvidence=$PSScriptRoot
$taskPrivate='C:/Users/adyba/pi-zig-sdk-bindings-20261015'
$taskCommit='1847a4d140c7f0e7ecf98e3d255856a724fcf608'
$taskFirst='sdk-resource-paths-runtime-sharded-debug-first-20261015'
$taskResume='sdk-resource-paths-runtime-shardedresume-debug-second-20261015'
$taskValidatorHash=(Get-FileHash -LiteralPath $PSCommandPath).Hash
if((git -C $taskPrivate rev-parse HEAD).Trim() -cne $taskCommit -or @(git -C $taskPrivate status --porcelain).Count){throw 'Exact sealed loader candidate required'}
$taskSnapshots=@()
foreach($taskPrefix in @($taskFirst,$taskResume)){
 $taskBefore=@(Get-Content -LiteralPath (Join-Path $taskEvidence "$taskPrefix-source-before.json") -Raw|ConvertFrom-Json)
 if($taskBefore.Count -ne 5604){throw 'Complete candidate inventory mismatch'}
 $taskSnapshots+=,@($taskBefore|ForEach-Object{"$($_.path):$($_.sha256)"})
 $taskPost=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskPrefix-posthash.json") -Raw|ConvertFrom-Json
 $taskPair=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskPrefix-reference-controls-posthash.json") -Raw|ConvertFrom-Json
 if($taskPost.source_drift -ne 0 -or $taskPost.tool_drift -ne 0 -or $taskPost.tools -ne 19546 -or $taskPair.references -ne 34805 -or $taskPair.controls -ne 9 -or $taskPair.reference_drift.Count -or $taskPair.control_drift.Count){throw 'Frozen pair drift or incomplete inventories'}
}
if(@(Compare-Object $taskSnapshots[0] $taskSnapshots[1]).Count){throw 'Candidate bytes differed between shard batches'}
$taskOwners=@();$taskRanges=@()
for($taskShard=0;$taskShard -lt 8;$taskShard++){
 $taskPrefix=if($taskShard -lt 3){$taskFirst}else{$taskResume}
 $taskName="$taskPrefix-shard-$taskShard-of-8"
 $taskOwner=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName.json") -Raw|ConvertFrom-Json
 if($taskOwner.status -cne 'passed' -or $taskOwner.exit_code -ne 0 -or !$taskOwner.identity_captured -or $taskOwner.executable_sha256 -cne '086CE9D47BA42F33A514E1A6E04EB1D4A8FA1D75E0868E0213CAAD447C91E864'){throw "Nonpassing or unauthenticated shard $taskShard"}
 $taskLog=[IO.File]::ReadAllText((Join-Path $taskEvidence "$taskName.stderr.log"))+[IO.File]::ReadAllText((Join-Path $taskEvidence "$taskName.stdout.log"))
 foreach($taskProbe in @(@{label='sdk-resourcepaths5ab';total=6246},@{label='sdk-bindings5ab';total=267})){
  $taskStart=[int][Math]::Floor($taskProbe.total*$taskShard/8)
  $taskEnd=[int][Math]::Floor($taskProbe.total*($taskShard+1)/8)
  if(!$taskLog.Contains("EXHAUSTIVE_ALLOCATION_BASELINE $($taskProbe.label) total=$($taskProbe.total)") -or !$taskLog.Contains("EXHAUSTIVE_ALLOCATION_COMPLETE $($taskProbe.label) $taskShard/8 range=[$taskStart,$taskEnd) total=$($taskProbe.total)")){throw "Incomplete exact allocation range $($taskProbe.label) shard $taskShard"}
  $taskIndices=[Regex]::Matches($taskLog,"EXHAUSTIVE_ALLOCATION_INDEX_COMPLETE $($taskProbe.label) (\d+)")
  if($taskIndices.Count -ne ($taskEnd-$taskStart)){throw 'Allocation index completion count mismatch'}
  for($taskIndex=0;$taskIndex -lt $taskIndices.Count;$taskIndex++){if([int]$taskIndices[$taskIndex].Groups[1].Value -ne $taskStart+$taskIndex){throw 'Allocation union has a gap duplicate or reordered completion'}}
  $taskRanges+=@{label=$taskProbe.label;shard=$taskShard;shards=8;start=$taskStart;end=$taskEnd;total=$taskProbe.total;complete=$true}
 }
 $taskOwners+=@{name=$taskName;owner=$taskOwner;sha256=(Get-FileHash -LiteralPath (Join-Path $taskEvidence "$taskName.json")).Hash}
}
$taskSummary=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskResume.json") -Raw|ConvertFrom-Json
if($taskSummary.status -cne 'passed' -or $taskSummary.completed_shards -ne 5){throw 'Remaining shard batch not complete'}
$taskSource=Get-Content -LiteralPath (Join-Path $taskPrivate 'src/extensions/fixtures/sdk-resource-paths-5ab.json') -Raw|ConvertFrom-Json
$taskSourcePost=Get-Content -LiteralPath (Join-Path $taskEvidence 'sdk-resource-paths-5ab-source18-third-20261015-posthash.json') -Raw|ConvertFrom-Json
if($taskSource.cases -ne 18 -or $taskSource.resourceFiles.Count -ne 8 -or $taskSource.resourceFileDrift -ne 0 -or @($taskSourcePost.manifests|Where-Object drift -ne 0).Count -or $taskSourcePost.caller_input_drift.Count){throw 'Genuine Source or resource asset closure failed'}
$taskProof=[ordered]@{status='component_qualified_windows_debug';commit=$taskCommit;tree=(git -C $taskPrivate rev-parse 'HEAD^{tree}').Trim();worktree=$taskPrivate;source_head=$taskSource.sourceHead;source_cases=18;bindings_source_cases=39;input_sha256=$taskSource.inputSha256;golden_sha256=(Get-FileHash -LiteralPath (Join-Path $taskPrivate 'src/extensions/fixtures/sdk-resource-paths-5ab.json')).Hash;allocation_universes=@(@{label='sdk-resourcepaths5ab';indices=6246;range='[0,6246)';complete=$true},@{label='sdk-bindings5ab';indices=267;range='[0,267)';complete=$true});candidate_files=5604;compiler_vendor_inputs=19546;reference_files=34805;controls_per_batch=9;all_posthash_drift=0;shards=8;owners=$taskOwners;ranges=$taskRanges;validator_sha256=$taskValidatorHash;full_resource_loader_qualified=$false;full_factory_qualified=$false;public_activation=$false;scope='Actual native explicit discovered resource pipeline, real skill/prompt/Theme files and rendering, live override/metadata/cache/failure behavior and actual ExtensionRunner to ordinary AgentSession.bindExtensions to actual loader composition. This does not qualify complete loader class reflection, automatic package/default discovery, all parser cases, full factory or provider transport.';completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}
if((Get-FileHash -LiteralPath $PSCommandPath).Hash -cne $taskValidatorHash){throw 'Union validator drift'}
$taskPath=Join-Path $taskEvidence 'sdk-resource-paths-source18-qualified-debug-20261015.json'
$taskProof|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $taskPath -Encoding utf8NoBOM
Get-FileHash -LiteralPath $taskPath
Write-Output 'QUALIFIED_COMPLETE_ALLOCATION_UNIONS loader=6246 bindings=267 shards=8'
param([Parameter(Mandatory)][string]$Archive)
$ErrorActionPreference='Stop'
if((Get-FileHash -LiteralPath $Archive).Hash -cne '6A1843275D629B5A30934FD170F3DF74CA2051795549D6A1E40AD04F23D46D57'){throw 'Frozen Immediate proof archive digest mismatch'}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$taskZip=[IO.Compression.ZipFile]::OpenRead([IO.Path]::GetFullPath($Archive))
try{
 function Read-Entry([string]$name){$entry=$taskZip.GetEntry($name);if(!$entry){throw "Missing archive entry $name"};$reader=[IO.StreamReader]::new($entry.Open());try{$reader.ReadToEnd()}finally{$reader.Dispose()}}
 $taskRows=@((Read-Entry 'archive-manifest.json')|ConvertFrom-Json)
 if($taskRows.Count -ne 70 -or @($taskZip.Entries).Count -ne 71 -or @($taskZip.Entries.FullName|Sort-Object -Unique).Count -ne 71){throw 'Exact71-entry archive inventory required'}
 foreach($row in $taskRows){
  $entry=$taskZip.GetEntry($row.path)
  if(!$entry -or $entry.Length -ne $row.bytes){throw "Archive payload size mismatch $($row.path)"}
  $stream=$entry.Open();try{$digest=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream))}finally{$stream.Dispose()}
  if($digest -cne $row.sha256){throw "Archive raw bytes changed $($row.path)"}
 }
 $taskHead='919ef1d81b71e8dc7774d90e5b5bfe636957779b'
 $taskPrefix='immediates-native-debug-second-poll-boundary-20261015'
 $taskValidation=(Read-Entry "$taskPrefix-validation.json")|ConvertFrom-Json
 if($taskValidation.candidate -cne $taskHead -or $taskValidation.source_cases -ne 31 -or $taskValidation.additional_source_cases -ne 1 -or $taskValidation.real_tcp_poll_callbacks -ne 4 -or $taskValidation.terminal -cne 'passed' -or $taskValidation.compile_pid -ne 70808 -or $taskValidation.runtime_pid -ne 29808 -or $taskValidation.artifact_count -ne 6){throw 'Qualified retry identity mismatch'}
 foreach($phase in @('compile','runtime')){
  $owner=(Read-Entry "$taskPrefix-$phase.json")|ConvertFrom-Json
  $post=(Read-Entry "$taskPrefix-$phase-posthash.json")|ConvertFrom-Json
  if($owner.status -cne 'passed' -or $owner.exit_code -ne 0 -or !$owner.identity_captured -or $owner.executable_sha256 -cne '086CE9D47BA42F33A514E1A6E04EB1D4A8FA1D75E0868E0213CAAD447C91E864' -or $post.candidate -cne $taskHead -or $post.source_files -ne 6965 -or $post.source_after -ne 6965 -or $post.compiler_files -ne 19546 -or $post.node_files -ne 1774 -or $post.control_files -ne 13 -or $post.builtin_source_count -ne 368 -or !$post.non_source_configs_excluded){throw 'Frozen retry proof scope mismatch'}
  foreach($property in @('compiler_drift','compiler_inventory_drift','source_drift','node_drift','node_inventory_drift','control_drift')){
   if($property -notin $post.PSObject.Properties.Name -or @($post.$property).Count){throw "Native input drift $phase $property"}
  }
 }
 if((Read-Entry "$taskPrefix-compile.stderr.log") -notmatch '155/155 steps succeeded' -or (Read-Entry "$taskPrefix-runtime.stderr.log") -notmatch '156/156 steps succeeded; 21/21 tests passed'){throw 'Actual retry terminal summaries missing'}
 $first=(Read-Entry 'immediates-native-debug-first-20261015-validation.json')|ConvertFrom-Json
 if($first.candidate -cne 'abaab4bdc58eb4d17886c023fef46bfd71a2d435' -or $first.terminal -cne 'passed' -or (Read-Entry 'immediates-native-debug-first-20261015-runtime.stderr.log') -notmatch '156/156 steps succeeded; 20/20 tests passed'){throw 'Original20-test passing cohort not retained'}
 foreach($spec in @(@{file='tested-source/immediates-node24.json';count=31;polls=3;pid=70908;prefix='immediates-node24-source-first-20261015'},@{file='tested-source/immediates-poll-stall-node24.json';count=1;polls=1;pid=51740;prefix='immediates-poll-stall-node24-source-first-20261015'})){
  $source=(Read-Entry $spec.file)|ConvertFrom-Json
  $owner=(Read-Entry "$($spec.prefix).json")|ConvertFrom-Json
  $post=(Read-Entry "$($spec.prefix)-posthash.json")|ConvertFrom-Json
  if($source.nodeVersion -cne 'v24.14.0' -or $source.count -ne $spec.count -or @($source.rows).Count -ne $spec.count -or $source.realLoopbackPolls -ne $spec.polls -or $source.builtinSourceCount -ne 368 -or $source.actualNativeEntries -ne 369 -or $source.excludedNonSourceKeys[0] -cne 'configs' -or $owner.pid -ne $spec.pid -or $owner.status -cne 'passed' -or !$post.expected_still_absent){throw 'Actual Source scope or terminal identity mismatch'}
  foreach($property in @('candidate_drift','candidate_inventory_drift','node_drift','node_inventory_drift','control_drift')){if($property -notin $post.PSObject.Properties.Name -or @($post.$property).Count){throw 'Actual Source posthash drift'}}
 }
 $sourceBefore=@((Read-Entry "$taskPrefix-before.json")|ConvertFrom-Json)
 if($sourceBefore.Count -ne 6965){throw 'Complete tested source manifest missing'}
 foreach($relative in @('src/extensions/native_immediates.zig','src/extensions/engine.zig','src/extensions/timers.zig','src/extensions/native_stdio_frontend.zig','src/native_immediates_test.zig','build.zig','src/extensions/fixtures/immediates-node24.input.txt','src/extensions/fixtures/immediates-node24.json','src/extensions/fixtures/immediates-poll-stall-node24.input.txt','src/extensions/fixtures/immediates-poll-stall-node24.json','tools/capture-immediates-node24.mjs','tools/capture-immediate-poll-stall-node24.mjs')){
  $row=@($sourceBefore|Where-Object relative -ceq $relative)
  $payload=@($taskRows|Where-Object path -ceq ('tested-source/'+[IO.Path]::GetFileName($relative)))
  if($row.Count -ne 1 -or $payload.Count -ne 1 -or $row[0].sha256 -cne $payload[0].sha256){throw "Archived product/control bytes do not match tested source $relative"}
 }
 $artifacts=@((Read-Entry "$taskPrefix-artifacts.json")|ConvertFrom-Json)
 if(@($artifacts|Where-Object sha256 -ceq '6C06D246B5A53D05A6617D35A2CBC4DD9A929B23A843649735F3BB167AAF3E57').Count -ne 1 -or @($artifacts|Where-Object sha256 -ceq '8D5FF7A4DE14E4DDE356D3FDE59E875FD519E583DF7ED26F41D434294F3A0261').Count -ne 1){throw 'Retry test executable/PDB identities missing'}
 Write-Output 'NATIVE_IMMEDIATES_70_RAW_PAYLOADS_SOURCE31_PLUS1_AND21_TESTS_VERIFIED'
}finally{$taskZip.Dispose()}

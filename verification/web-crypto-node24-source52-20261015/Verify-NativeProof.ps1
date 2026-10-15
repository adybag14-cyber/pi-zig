param([Parameter(Mandatory)][string]$Archive)
$ErrorActionPreference='Stop'
if((Get-FileHash -LiteralPath $Archive).Hash -cne '7DB3EDE2288559F84AC5F7184553C86BD76CB608DDBA151805AC9F44B720B223'){throw 'Frozen native proof archive digest mismatch'}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$taskZip=[IO.Compression.ZipFile]::OpenRead([IO.Path]::GetFullPath($Archive))
try{
 function Read-Entry([string]$name){$entry=$taskZip.GetEntry($name);if(!$entry){throw "Missing archive entry $name"};$reader=[IO.StreamReader]::new($entry.Open());try{$reader.ReadToEnd()}finally{$reader.Dispose()}}
 $taskRows=@((Read-Entry 'archive-manifest.json')|ConvertFrom-Json)
 if($taskRows.Count -ne 30 -or @($taskZip.Entries).Count -ne 31 -or @($taskZip.Entries.FullName|Sort-Object -Unique).Count -ne 31){throw 'Exact archive inventory required'}
 foreach($row in $taskRows){
  $entry=$taskZip.GetEntry($row.path)
  if(!$entry -or $entry.Length -ne $row.bytes){throw "Archive entry size mismatch $($row.path)"}
  $stream=$entry.Open();try{$digest=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream))}finally{$stream.Dispose()}
  if($digest -cne $row.sha256){throw "Archive raw byte digest mismatch $($row.path)"}
 }
 $taskExpectedHead='6894882c29cd21011b414e7fc23571329c528e99'
 $taskValidation=(Read-Entry 'webcrypto-native-debug-first-20261015-validation.json')|ConvertFrom-Json
 if($taskValidation.candidate -cne $taskExpectedHead -or $taskValidation.source_cases -ne 52 -or $taskValidation.terminal -cne 'passed' -or $taskValidation.mode -cne 'Debug' -or $taskValidation.compile_pid -ne 73508 -or $taskValidation.runtime_pid -ne 912 -or $taskValidation.artifact_count -ne 4){throw 'Native proof identity mismatch'}
 foreach($phase in @('compile','runtime')){
  $owner=(Read-Entry "webcrypto-native-debug-first-20261015-$phase.json")|ConvertFrom-Json
  $post=(Read-Entry "webcrypto-native-debug-first-20261015-$phase-posthash.json")|ConvertFrom-Json
  if($owner.status -cne 'passed' -or $owner.exit_code -ne 0 -or !$owner.identity_captured -or $post.candidate -cne $taskExpectedHead -or $post.source_files -ne 6573 -or $post.source_after -ne 6573 -or $post.compiler_files -ne 19546 -or $post.node_files -ne 1774 -or $post.control_files -ne 9 -or $post.builtin_source_count -ne 368 -or !$post.non_source_configs_excluded){throw 'Frozen native proof scope mismatch'}
  foreach($property in @('compiler_drift','compiler_inventory_drift','source_drift','node_drift','node_inventory_drift','control_drift')){if(@($post.$property).Count){throw "Native drift $phase $property"}}
 }
 if((Read-Entry 'webcrypto-native-debug-first-20261015-compile.stderr.log') -notmatch '155/155 steps succeeded' -or (Read-Entry 'webcrypto-native-debug-first-20261015-runtime.stderr.log') -notmatch '156/156 steps succeeded; 3/3 tests passed'){throw 'Actual native log terminal summary missing'}
 $source=(Read-Entry 'tested-source/web-crypto-node24.json')|ConvertFrom-Json
 if($source.nodeVersion -cne 'v24.14.0' -or $source.count -ne 52 -or @($source.rows).Count -ne 52 -or $source.builtinAuthorityCount -ne 368 -or $source.actualBuiltinEntries -ne 369 -or @($source.excludedNonSourceKeys).Count -ne 1 -or $source.excludedNonSourceKeys[0] -cne 'configs'){throw 'Genuine Source52 authority mismatch'}
 Write-Output 'NATIVE_WEBCRYPTO_DEBUG_PROOF_30_RAW_PAYLOADS_AND_SOURCE52_VERIFIED'
}finally{$taskZip.Dispose()}

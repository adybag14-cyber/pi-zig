function Invoke-NativeTestProtocol {
 param([Parameter(Mandatory)][string]$Binary,[Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$Receipt,[Parameter(Mandatory)][int]$ExpectedCount)
 if($ExpectedCount -le 0 -or $ExpectedCount -gt 64){throw 'Unsupported exact native test count'}
 # At most 776 bytes, below the pinned test runner's 4096-byte input buffer.
 # Zig 0.16 Client.run_test=5 with one u32 index, followed by Client.exit=0.
 # --listen waits for these bytes until the owner has checked its live identity.
 $taskRequest=[IO.MemoryStream]::new()
 try {
  for($taskIndex=0;$taskIndex -lt $ExpectedCount;$taskIndex++){
   foreach($taskWord in @([uint32]5,[uint32]4,[uint32]$taskIndex)){
    $taskBytes=[BitConverter]::GetBytes($taskWord);$taskRequest.Write($taskBytes,0,4)
   }
  }
  $taskRequest.Write([byte[]]::new(8),0,8)
  $taskOwned=Invoke-CiOwnedProcess $Binary @('--listen=-') $Root $Receipt 120 $taskRequest.ToArray()
 }finally{$taskRequest.Dispose()}
 $taskOutput=[IO.File]::ReadAllBytes("$Receipt.stdout.bin")
 $taskOffset=0;$taskVersion=$null;$taskStarted=0;$taskResults=@()
 while($taskOffset -lt $taskOutput.Length){
  if($taskOutput.Length-$taskOffset -lt 8){throw 'Truncated test protocol header'}
  $taskTag=[BitConverter]::ToUInt32($taskOutput,$taskOffset)
  $taskLength=[BitConverter]::ToUInt32($taskOutput,$taskOffset+4);$taskOffset+=8
  if($taskLength -gt 1MB -or $taskLength -gt $taskOutput.Length-$taskOffset){throw 'Invalid test protocol body length'}
  switch($taskTag){
   0 {
    if($null -ne $taskVersion -or $taskStarted -ne 0 -or $taskResults.Count){throw 'Unexpected duplicate/late Zig version'}
    $taskVersion=[Text.Encoding]::UTF8.GetString($taskOutput,$taskOffset,$taskLength)
   }
   5 {
    if($taskVersion -cne '0.16.0' -or $taskLength -ne 0 -or $taskStarted -ne $taskResults.Count -or $taskStarted -ge $ExpectedCount){throw 'Unexpected native test start'}
    $taskStarted++
   }
   4 {
    # Server.TestResults = u32 index + align(4) packed u64 flags, 12 bytes.
    if($taskLength -ne 12 -or $taskStarted -ne $taskResults.Count+1){throw 'Unexpected native test result'}
    $taskIndex=[BitConverter]::ToUInt32($taskOutput,$taskOffset)
    $taskFlags=[BitConverter]::ToUInt64($taskOutput,$taskOffset+4)
    if($taskIndex -ne $taskResults.Count){throw 'Missing, duplicate or out-of-order test result'}
    $taskResults+=,[pscustomobject]@{index=$taskIndex;flags=$taskFlags;passed=($taskFlags -eq 0)}
   }
   default {throw "Unexpected native test protocol tag $taskTag"}
  }
  $taskOffset+=$taskLength
 }
 $taskFailed=@($taskResults|Where-Object{!$_.passed})
 $taskSummary=[ordered]@{binary=$Binary;binary_sha256=$taskOwned.executable_sha256;version=$taskVersion;expected=$ExpectedCount;started=$taskStarted;completed=$taskResults.Count;results=$taskResults;failed_or_skipped_or_logged_or_leaked=$taskFailed.Count;owner_receipt="$Receipt.json";status='passed'}
 if($taskVersion -cne '0.16.0' -or $taskStarted -ne $ExpectedCount -or $taskResults.Count -ne $ExpectedCount -or $taskFailed.Count){$taskSummary.status='failed'}
 $taskSummary|ConvertTo-Json -Depth 6|Set-Content -LiteralPath "$Receipt.results.json" -Encoding utf8NoBOM
 if($taskSummary.status -cne 'passed'){throw 'Native test protocol did not report every selected test passing without logs/leaks'}
 [pscustomobject]$taskSummary
}

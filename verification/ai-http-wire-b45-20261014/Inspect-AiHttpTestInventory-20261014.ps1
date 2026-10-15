param([string]$Binary='C:/Users/adyba/pi-zig-ai-compat-b45-20261014/.zig-cache/o/3a71ecb73e7e7458d867fbf0ade8ab3c/test.exe')
$ErrorActionPreference='Stop'
$taskExpected=@(
 'native_ai_http_test.test.native AI HTTP raw transport replays12 genuine Source wire payloads and exact SSE data without provider substitution',
 'native_ai_http_test.test.native AI HTTP preserves CR LF BOM multiline event fields and non-success response body',
 'native_ai_http_test.test.native AI HTTP real abort signal cancels owned body work and retires reader roots',
 'native_ai_http_test.test.native AI HTTP full-queue timeout and VM teardown cancel join and release owned responses',
 'native_ai_http_test.test.native AI HTTP every host allocation unwinds pre-aborted preparation without starting a worker',
 'extensions.native_durable_storage.test_0'
)
$taskBytes=[IO.File]::ReadAllBytes($Binary)
$taskText=[Text.Encoding]::Latin1.GetString($taskBytes)
$taskPe=[BitConverter]::ToInt32($taskBytes,0x3c)
if([BitConverter]::ToUInt32($taskBytes,$taskPe) -ne 0x4550){throw 'Not a PE image'}
$taskOptional=$taskPe+24
if([BitConverter]::ToUInt16($taskBytes,$taskOptional) -ne 0x20b){throw 'Not a PE32+ image'}
$taskBase=[BitConverter]::ToUInt64($taskBytes,$taskOptional+24)
$taskSections=@()
$taskSectionTable=$taskOptional+[BitConverter]::ToUInt16($taskBytes,$taskPe+20)
for($taskIndex=0;$taskIndex -lt [BitConverter]::ToUInt16($taskBytes,$taskPe+6);$taskIndex++){
 $taskOffset=$taskSectionTable+$taskIndex*40
 $taskSections+=@{virtual=[BitConverter]::ToUInt32($taskBytes,$taskOffset+12);raw=[BitConverter]::ToUInt32($taskBytes,$taskOffset+20);size=[BitConverter]::ToUInt32($taskBytes,$taskOffset+16);virtual_size=[BitConverter]::ToUInt32($taskBytes,$taskOffset+8);execute=([BitConverter]::ToUInt32($taskBytes,$taskOffset+36) -band 0x20000000) -ne 0}
}
$taskNames=@{}
foreach($taskName in $taskExpected){
 $taskOffset=0
 while(($taskOffset=$taskText.IndexOf($taskName,$taskOffset,[StringComparison]::Ordinal)) -ge 0){
  foreach($taskSection in $taskSections){if($taskOffset -ge $taskSection.raw -and $taskOffset -lt $taskSection.raw+$taskSection.size){$taskNames[[string]($taskBase+$taskSection.virtual+$taskOffset-$taskSection.raw)]=$taskName;break}}
  $taskOffset++
 }
}
$taskFound=@{}
$taskPermutations=@(@(0,1,2),@(0,2,1),@(1,0,2),@(1,2,0),@(2,0,1),@(2,1,0))
foreach($taskAddress in @($taskNames.Keys)){
 if($taskNames[$taskAddress] -cne $taskExpected[0]){continue}
 $taskNeedle=[Text.Encoding]::Latin1.GetString([BitConverter]::GetBytes([UInt64]::Parse($taskAddress)))
 $taskReference=0
 while(($taskReference=$taskText.IndexOf($taskNeedle,$taskReference,[StringComparison]::Ordinal)) -ge 0){
  foreach($taskPermutation in $taskPermutations){
   for($taskFirst=0;$taskFirst -lt 6;$taskFirst++){
    $taskStart=$taskReference-$taskPermutation[0]*8-$taskFirst*24
    if($taskStart -lt 0 -or $taskStart+144 -gt $taskBytes.Length){continue}
    $taskRows=@()
    for($taskRow=0;$taskRow -lt 6;$taskRow++){
     $taskAt=$taskStart+$taskRow*24
     $taskPointer=[BitConverter]::ToUInt64($taskBytes,$taskAt+$taskPermutation[0]*8)
     $taskLength=[BitConverter]::ToUInt64($taskBytes,$taskAt+$taskPermutation[1]*8)
     $taskFunction=[BitConverter]::ToUInt64($taskBytes,$taskAt+$taskPermutation[2]*8)
     $taskName=$taskNames[[string]$taskPointer]
     if(!$taskName -or $taskLength -ne [Text.Encoding]::UTF8.GetByteCount($taskName)){break}
     $taskExecutable=@($taskSections|Where-Object {$_.execute -and $taskFunction -ge $taskBase+$_.virtual -and $taskFunction -lt $taskBase+$_.virtual+$_.virtual_size}).Count -ne 0
     if(!$taskExecutable){break}
     $taskRows+=@{name=$taskName;bytes=$taskLength;function_virtual_address=$taskFunction;name_virtual_address=$taskPointer}
    }
    if($taskRows.Count -eq 6 -and @($taskRows.name|Sort-Object -Unique).Count -eq 6 -and !(Compare-Object ($taskRows.name|Sort-Object) ($taskExpected|Sort-Object))){$taskFound[[string]$taskStart]=@{file_offset=$taskStart;word_permutation=$taskPermutation;tests=$taskRows}}
   }
  }
  $taskReference++
 }
}
if($taskFound.Count -ne 1){throw "Expected exactly one six-entry compiled TestFn array, found $($taskFound.Count)"}
$taskResult=@{method='Read-only PE32+ TestFn metadata: six contiguous24-byte entries, exact UTF8 names/lengths, every function pointer within executable section; no binary execution';binary=(Resolve-Path -LiteralPath $Binary).Path;binary_sha256=(Get-FileHash -LiteralPath $Binary).Hash;bytes=$taskBytes.Length;inventory=@($taskFound.Values)[0];authored_tests=5;imported_unnamed_tests=1;runtime_count=6;recorded_utc=[DateTimeOffset]::UtcNow.ToString('o')}
$taskResult|ConvertTo-Json -Depth 7|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'native-ai-http-debug-compiled-test-inventory-20261014.json') -Encoding utf8NoBOM
$taskResult|ConvertTo-Json -Depth 7

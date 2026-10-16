# Metadata-only discovery: retain every selected entry, require every planned
# original entry, then requery with the frozen actual count/name set. This does
# not send run_test, filter assertions, or remove additional Root imports.
function Read-RootCompositionMetadata {
 param([string]$Binary,[string]$Root,[string]$Receipt,[string[]]$PlannedNames)
 $taskRequest=[byte[]](4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
 $taskOwned=Invoke-CiOwnedProcess $Binary @('--listen=-') $Root ($Receipt+'-discovery') 30 $taskRequest
 $taskBytes=[IO.File]::ReadAllBytes($Receipt+'-discovery.stdout.bin')
 $taskOffset=0;$taskNames=$null;$taskVersion=$null
 while($taskOffset-lt$taskBytes.Length){
  if($taskOffset+8-gt$taskBytes.Length){throw 'Truncated actual metadata header'}
  $taskTag=[BitConverter]::ToUInt32($taskBytes,$taskOffset)
  $taskLength=[BitConverter]::ToUInt32($taskBytes,$taskOffset+4);$taskOffset+=8
  if($taskLength-gt1MB-or$taskOffset+$taskLength-gt$taskBytes.Length){throw 'Invalid actual metadata length'}
  if($taskTag-eq0){$taskVersion=[Text.Encoding]::UTF8.GetString($taskBytes,$taskOffset,$taskLength)}
  elseif($taskTag-eq3){
   if($null-ne$taskNames){throw 'Duplicate actual metadata array'}
   $taskStrings=[BitConverter]::ToUInt32($taskBytes,$taskOffset)
   $taskCount=[BitConverter]::ToUInt32($taskBytes,$taskOffset+4)
   if($taskCount-lt$PlannedNames.Count-or$taskCount-gt4096-or$taskLength-ne8+8*$taskCount+$taskStrings){throw 'Actual metadata shape/count does not retain planned cohort'}
   $taskStringStart=$taskOffset+8+8*$taskCount;$taskNames=@()
   for($taskIndex=0;$taskIndex-lt$taskCount;$taskIndex++){
    $taskNameOffset=[BitConverter]::ToUInt32($taskBytes,$taskOffset+8+4*$taskIndex)
    $taskPanic=[BitConverter]::ToUInt32($taskBytes,$taskOffset+8+4*$taskCount+4*$taskIndex)
    if($taskPanic-ne0-or$taskNameOffset-ge$taskStrings){throw 'Unexpected actual panic/name offset'}
    $taskEnd=$taskNameOffset
    while($taskEnd-lt$taskStrings-and$taskBytes[$taskStringStart+$taskEnd]-ne0){$taskEnd++}
    if($taskEnd-eq$taskStrings){throw 'Unterminated actual test name'}
    $taskNames+=[Text.Encoding]::UTF8.GetString($taskBytes,$taskStringStart+$taskNameOffset,$taskEnd-$taskNameOffset)
   }
  }else{throw "Unexpected metadata-only tag $taskTag"}
  $taskOffset+=$taskLength
 }
 if($taskVersion-cne'0.16.0'-or$null-eq$taskNames){throw 'Actual metadata/version missing'}
 $taskUnique=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
 foreach($taskName in $taskNames){if(!$taskUnique.Add($taskName)){throw 'Duplicate actual selected test name'}}
 foreach($taskName in $PlannedNames){if(!$taskUnique.Contains($taskName)){throw "Original planned test missing: $taskName"}}
 $taskNames|ConvertTo-Json|Set-Content -LiteralPath ($Receipt+'-frozen-all-names.json') -Encoding utf8NoBOM
 $taskFrozenHash=(Get-FileHash -LiteralPath ($Receipt+'-frozen-all-names.json')).Hash
 if(!(Admission 'metadata-requery')){throw 'Fresh metadata-requery admission denied'}
 $taskMetadata=Read-CiTestMetadata $Binary $Root ($Receipt+'-exact-requery') $taskNames.Count
 if(@(Compare-Object ($taskNames|Sort-Object -CaseSensitive) ($taskMetadata.tests|Sort-Object -CaseSensitive) -CaseSensitive).Count-or$taskMetadata.binary_sha256-cne$taskOwned.executable_sha256-or(Get-FileHash -LiteralPath ($Receipt+'-frozen-all-names.json')).Hash-cne$taskFrozenHash){throw 'Frozen actual metadata requery mismatch'}
 return $taskMetadata
}

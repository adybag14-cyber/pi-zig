$ErrorActionPreference='Stop'
function Invoke-AiOwnedProcess {
 param([string]$Executable,[string[]]$Arguments,[string]$WorkingDirectory,[string]$Receipt,[int]$TimeoutSeconds,[byte[]]$InputBytes=$null)
 $taskExe=(Resolve-Path -LiteralPath $Executable).Path
 if([IO.Path]::GetFileName($taskExe) -notin @('zig','zig.exe','node','node.exe','test','test.exe')){throw 'Unexpected owned executable'}
 $taskStart=[Diagnostics.ProcessStartInfo]::new($taskExe)
 $taskStart.WorkingDirectory=$WorkingDirectory;$taskStart.UseShellExecute=$false;$taskStart.CreateNoWindow=$true
 $taskStart.RedirectStandardOutput=$true;$taskStart.RedirectStandardError=$true;$taskStart.RedirectStandardInput=$true
 foreach($taskArg in $Arguments){$taskStart.ArgumentList.Add($taskArg)}
 $taskStart.Environment['NODE_OPTIONS']='';$taskStart.Environment['NODE_PATH']='';$taskStart.Environment['NODE_COMPILE_CACHE']=''
 $taskProcess=[Diagnostics.Process]::new();$taskProcess.StartInfo=$taskStart
 $taskOutput=[IO.MemoryStream]::new()
 $taskRecord=$null;$taskCreated=$null;$taskCopy=$null;$taskError=$null
 try {
  if(!$taskProcess.Start()){throw 'Owned process did not start'}
  $taskCreated=$taskProcess.StartTime.ToUniversalTime()
  $taskRecord=[ordered]@{executable=$taskExe;executable_sha256=(Get-FileHash -LiteralPath $taskExe).Hash;arguments=$Arguments;working_directory=$WorkingDirectory;pid=$taskProcess.Id;created_utc=$taskCreated.ToString('o');identity='Retained native Process handle and exact ProcessStartInfo argv';timeout_seconds=$TimeoutSeconds;status='running'}
  $taskRecord|ConvertTo-Json -Depth 5|Set-Content -LiteralPath "$Receipt.json" -Encoding utf8NoBOM
  $taskCopy=$taskProcess.StandardOutput.BaseStream.CopyToAsync($taskOutput)
  $taskError=$taskProcess.StandardError.ReadToEndAsync()
  if($null -ne $InputBytes){$taskProcess.StandardInput.BaseStream.Write($InputBytes,0,$InputBytes.Length);$taskProcess.StandardInput.BaseStream.Flush()}
  $taskProcess.StandardInput.Close()
  if(!$taskProcess.WaitForExit($TimeoutSeconds*1000)){
   $taskImage=$taskProcess.MainModule.FileName
   $taskSameImage=if($IsWindows){[StringComparer]::OrdinalIgnoreCase.Equals($taskImage,$taskExe)}else{[StringComparer]::Ordinal.Equals($taskImage,$taskExe)}
   if($taskProcess.Id -ne $taskRecord.pid -or $taskProcess.StartTime.ToUniversalTime() -ne $taskCreated -or !$taskSameImage){throw 'Owned timeout identity mismatch; refusing termination'}
   $taskProcess.Kill($true);$taskProcess.WaitForExit();$taskRecord.status='timeout'
  }else{$taskRecord.status=if($taskProcess.ExitCode -eq 0){'passed'}else{'failed'}}
  $taskCopy.GetAwaiter().GetResult();$taskErrors=$taskError.GetAwaiter().GetResult()
  [IO.File]::WriteAllBytes("$Receipt.stdout.bin",$taskOutput.ToArray())
  [IO.File]::WriteAllText("$Receipt.stderr.log",$taskErrors,[Text.UTF8Encoding]::new($false))
  $taskRecord.exit_code=$taskProcess.ExitCode;$taskRecord.completed_utc=[DateTimeOffset]::UtcNow.ToString('o')
  $taskRecord|ConvertTo-Json -Depth 5|Set-Content -LiteralPath "$Receipt.json" -Encoding utf8NoBOM
  if($taskRecord.status -cne 'passed'){throw "Owned terminal $($taskRecord.status): $taskExe"}
  return $taskRecord
 }catch{
  $taskFailure=$_
  if($null -ne $taskRecord -and $taskRecord.status -ceq 'running'){
   if(!$taskProcess.HasExited){
    $taskImage=$taskProcess.MainModule.FileName
    $taskSameImage=if($IsWindows){[StringComparer]::OrdinalIgnoreCase.Equals($taskImage,$taskExe)}else{[StringComparer]::Ordinal.Equals($taskImage,$taskExe)}
    if($taskProcess.Id -ne $taskRecord.pid -or $taskProcess.StartTime.ToUniversalTime() -ne $taskCreated -or !$taskSameImage){$taskRecord.status='identity_mismatch';$taskRecord|ConvertTo-Json -Depth 5|Set-Content -LiteralPath "$Receipt.json" -Encoding utf8NoBOM;throw 'Owned cleanup identity mismatch; refusing termination'}
    $taskProcess.Kill($true);$taskProcess.WaitForExit()
   }
   if($null -ne $taskCopy){$taskCopy.GetAwaiter().GetResult();[IO.File]::WriteAllBytes("$Receipt.stdout.bin",$taskOutput.ToArray())}
   if($null -ne $taskError){[IO.File]::WriteAllText("$Receipt.stderr.log",$taskError.GetAwaiter().GetResult(),[Text.UTF8Encoding]::new($false))}
   $taskRecord.status='owner_failed';$taskRecord.error=$taskFailure.Exception.Message;$taskRecord.exit_code=$taskProcess.ExitCode;$taskRecord.completed_utc=[DateTimeOffset]::UtcNow.ToString('o')
   $taskRecord|ConvertTo-Json -Depth 5|Set-Content -LiteralPath "$Receipt.json" -Encoding utf8NoBOM
  }
  throw
 }finally{$taskOutput.Dispose();$taskProcess.Dispose()}
}
function Get-AiRows {
 param([string]$Root,[string[]]$Paths)
 @(foreach($taskPath in $Paths){$taskFile=Join-Path $Root $taskPath;[ordered]@{relative=$taskPath;path=$taskFile;sha256=(Get-FileHash -LiteralPath $taskFile).Hash}})
}
function Assert-AiRows {
 param($Rows,[string]$Output)
 $taskDrift=@($Rows|Where-Object {!(Test-Path -LiteralPath $_.path -PathType Leaf) -or (Get-FileHash -LiteralPath $_.path).Hash -cne $_.sha256}|ForEach-Object path)
 @{count=@($Rows).Count;drift=$taskDrift;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $Output -Encoding utf8NoBOM
 if($taskDrift.Count){throw 'Frozen input drift'}
}
function Read-AiTestMetadata {
 param([string]$Binary,[string]$Root,[string]$Receipt)
 # Zig0.16 Client tags: query_test_metadata=4, exit=0. No run_test is sent.
 $taskRequest=[byte[]](4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
 $taskOwned=Invoke-AiOwnedProcess $Binary @('--listen=-') $Root $Receipt 30 $taskRequest
 $taskBytes=[IO.File]::ReadAllBytes("$Receipt.stdout.bin");$taskOffset=0;$taskVersion=$null;$taskNames=$null
 while($taskOffset -lt $taskBytes.Length){
  if($taskOffset+8 -gt $taskBytes.Length){throw 'Truncated native metadata header'}
  $taskTag=[BitConverter]::ToUInt32($taskBytes,$taskOffset);$taskLength=[BitConverter]::ToUInt32($taskBytes,$taskOffset+4);$taskOffset+=8
  if($taskLength -gt 1MB -or $taskOffset+$taskLength -gt $taskBytes.Length){throw 'Native metadata length mismatch'}
  if($taskTag -eq 0){$taskVersion=[Text.Encoding]::UTF8.GetString($taskBytes,$taskOffset,$taskLength)}
  elseif($taskTag -eq 3){
   if($null -ne $taskNames){throw 'Duplicate native metadata array'}
   $taskCount=[BitConverter]::ToUInt32($taskBytes,$taskOffset);$taskStrings=[BitConverter]::ToUInt32($taskBytes,$taskOffset+4)
   if($taskCount -ne 6 -or $taskLength -ne 8+8*$taskCount+$taskStrings){throw 'Exactly six native tests required'}
   $taskStringStart=$taskOffset+8+8*$taskCount;$taskNames=@()
   for($taskIndex=0;$taskIndex -lt $taskCount;$taskIndex++){
    $taskNameOffset=[BitConverter]::ToUInt32($taskBytes,$taskOffset+8+4*$taskIndex)
    $taskPanic=[BitConverter]::ToUInt32($taskBytes,$taskOffset+8+4*$taskCount+4*$taskIndex)
    if($taskPanic -ne 0 -or $taskNameOffset -ge $taskStrings){throw 'Unexpected panic/offset metadata'}
    $taskEnd=$taskNameOffset;while($taskEnd -lt $taskStrings -and $taskBytes[$taskStringStart+$taskEnd] -ne 0){$taskEnd++}
    if($taskEnd -eq $taskStrings){throw 'Unterminated native test name'}
    $taskNames+=[Text.Encoding]::UTF8.GetString($taskBytes,$taskStringStart+$taskNameOffset,$taskEnd-$taskNameOffset)
   }
  }else{throw "Unexpected metadata-only protocol tag $taskTag"}
  $taskOffset+=$taskLength
 }
 if($taskVersion -cne '0.16.0' -or $taskNames.Count -ne 6){throw 'Native metadata/version missing'}
 return @{binary=$Binary;binary_sha256=$taskOwned.executable_sha256;version=$taskVersion;tests=$taskNames;method='Actual metadata-only Zig0.16 protocol; query and clean exit, no unit run command'}
}

$ErrorActionPreference='Stop'
function Get-AiLiveIdentity {
 param([Diagnostics.Process]$Process)
 $taskLive=Get-Process -Id $Process.Id -ErrorAction Stop
 try {
  if($IsWindows){
   $taskCim=Get-CimInstance Win32_Process -Filter "ProcessId = $($Process.Id)"
   if(!$taskCim -or [string]::IsNullOrEmpty($taskCim.CommandLine)){throw 'Owned live Windows command line unavailable'}
   $taskCommand=$taskCim.CommandLine;$taskMethod='Win32_Process.CommandLine'
  }elseif($IsLinux){
   $taskCommand=[Convert]::ToBase64String([IO.File]::ReadAllBytes("/proc/$($Process.Id)/cmdline"));$taskMethod='/proc cmdline exact bytes (base64)'
   if(!$taskCommand){throw 'Owned live Linux command line unavailable'}
  }elseif($IsMacOS){
   $taskCommand=[string]::Join("`n",@(& /bin/ps -p $Process.Id -o command=));$taskMethod='ps command= exact output'
   if($LASTEXITCODE -ne 0 -or !$taskCommand){throw 'Owned live macOS command line unavailable'}
  }else{throw 'Unsupported owned identity platform'}
  return @{pid=$taskLive.Id;executable=$taskLive.MainModule.FileName;created_utc=$taskLive.StartTime.ToUniversalTime().ToString('o');command_line=$taskCommand;command_line_method=$taskMethod}
 }finally{$taskLive.Dispose()}
}
function Stop-AiOwnedProcess {
 param([Diagnostics.Process]$Process,$Record)
 if($Process.HasExited){return}
 $taskLive=Get-AiLiveIdentity $Process
 $Record.cleanup_identity=$taskLive
 $taskComparer=if($IsWindows){[StringComparer]::OrdinalIgnoreCase}else{[StringComparer]::Ordinal}
 if($Process.Handle.ToInt64() -ne $Record.retained_handle -or $Process.Id -ne $Record.pid -or $Process.StartTime.ToUniversalTime().ToString('o') -cne $Record.created_utc -or $taskLive.pid -ne $Record.pid -or $taskLive.created_utc -cne $Record.created_utc -or !$taskComparer.Equals($taskLive.executable,$Record.executable) -or $taskLive.command_line_method -cne $Record.live_identity.command_line_method -or $taskLive.command_line -cne $Record.live_identity.command_line -or (Get-FileHash -LiteralPath $Record.executable).Hash -cne $Record.executable_sha256){throw 'Owned cleanup identity mismatch; refusing termination'}
 $Process.Kill($true)
 if(!$Process.WaitForExit(10000)){throw 'Owned termination did not settle within ten seconds'}
 $Record.termination_verified=$Process.HasExited
}
function Save-AiOwnedOutput {
 param($Copy,$ErrorTask,[IO.MemoryStream]$Output,[string]$Receipt)
 if($null -eq $Copy -or $null -eq $ErrorTask){return}
 $taskPipes=[Threading.Tasks.Task]::WhenAll([Threading.Tasks.Task[]]@($Copy,$ErrorTask))
 if(!$taskPipes.Wait(10000)){throw 'Owned redirected pipes did not settle within ten seconds'}
 $Copy.GetAwaiter().GetResult()
 [IO.File]::WriteAllBytes("$Receipt.stdout.bin",$Output.ToArray())
 [IO.File]::WriteAllText("$Receipt.stderr.log",$ErrorTask.GetAwaiter().GetResult(),[Text.UTF8Encoding]::new($false))
}
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
  $taskRecord=[ordered]@{executable=$taskExe;executable_sha256=(Get-FileHash -LiteralPath $taskExe).Hash;arguments=$Arguments;working_directory=$WorkingDirectory;pid=$taskProcess.Id;retained_handle=$taskProcess.Handle.ToInt64();created_utc=$taskCreated.ToString('o');identity='Retained native Process handle plus fresh executable/UTC start and exact live command line';timeout_seconds=$TimeoutSeconds;status='running';live_identity=$null}
  $taskCopy=$taskProcess.StandardOutput.BaseStream.CopyToAsync($taskOutput)
  $taskError=$taskProcess.StandardError.ReadToEndAsync()
  $taskRecord.live_identity=Get-AiLiveIdentity $taskProcess
  $taskComparer=if($IsWindows){[StringComparer]::OrdinalIgnoreCase}else{[StringComparer]::Ordinal}
  if($taskRecord.live_identity.created_utc -cne $taskRecord.created_utc -or !$taskComparer.Equals($taskRecord.live_identity.executable,$taskExe)){throw 'Owned launch identity mismatch'}
  $taskRecord|ConvertTo-Json -Depth 6|Set-Content -LiteralPath "$Receipt.json" -Encoding utf8NoBOM
  if($null -ne $InputBytes){$taskProcess.StandardInput.BaseStream.Write($InputBytes,0,$InputBytes.Length);$taskProcess.StandardInput.BaseStream.Flush()}
  $taskProcess.StandardInput.Close()
  if(!$taskProcess.WaitForExit($TimeoutSeconds*1000)){
   Stop-AiOwnedProcess $taskProcess $taskRecord;$taskRecord.status='timeout'
  }else{$taskRecord.status=if($taskProcess.ExitCode -eq 0){'passed'}else{'failed'}}
  Save-AiOwnedOutput $taskCopy $taskError $taskOutput $Receipt
  $taskRecord.exit_code=$taskProcess.ExitCode;$taskRecord.completed_utc=[DateTimeOffset]::UtcNow.ToString('o')
  $taskRecord|ConvertTo-Json -Depth 5|Set-Content -LiteralPath "$Receipt.json" -Encoding utf8NoBOM
  if($taskRecord.status -cne 'passed'){throw "Owned terminal $($taskRecord.status): $taskExe"}
  return $taskRecord
 }catch{
  $taskFailure=$_
  if($null -ne $taskRecord -and $taskRecord.status -in @('running','passed','failed','timeout')){
   try {
   if(!$taskProcess.HasExited){
    if($null -eq $taskRecord.live_identity){throw 'Owned initial live identity unavailable; refusing termination'}
    Stop-AiOwnedProcess $taskProcess $taskRecord
   }
   Save-AiOwnedOutput $taskCopy $taskError $taskOutput $Receipt
   if($taskRecord.status -ceq 'running'){$taskRecord.status='owner_failed'}
   }catch{$taskRecord.status='cleanup_failed';$taskRecord.cleanup_error=$_.Exception.Message}
   $taskRecord.error=$taskFailure.Exception.Message;if($taskProcess.HasExited){$taskRecord.exit_code=$taskProcess.ExitCode};$taskRecord.completed_utc=[DateTimeOffset]::UtcNow.ToString('o')
   $taskRecord|ConvertTo-Json -Depth 6|Set-Content -LiteralPath "$Receipt.json" -Encoding utf8NoBOM
  }
  throw
 }finally{$taskOutput.Dispose();$taskProcess.Dispose()}
}
function Get-AiRows {
 param([string]$Root,[string[]]$Paths)
 @(foreach($taskPath in $Paths){$taskFile=Join-Path $Root $taskPath;[ordered]@{relative=$taskPath;path=$taskFile;sha256=(Get-FileHash -LiteralPath $taskFile).Hash}})
}
function Get-AiInventory {
 param([string]$Root,[ValidateSet('tree','tracked')][string]$Kind='tree',[string[]]$Excluded=@())
 $taskPaths=if($Kind -ceq 'tracked'){
  @(git -C $Root ls-files)
  if($LASTEXITCODE -ne 0){throw 'Tracked inventory failed'}
 }else{
  # Prune declared output roots before descending; include hidden input files.
  $taskPending=[Collections.Generic.Stack[string]]::new();$taskPending.Push($Root)
  while($taskPending.Count){
   foreach($taskItem in Get-ChildItem -LiteralPath $taskPending.Pop() -Force){
    $taskRelative=[IO.Path]::GetRelativePath($Root,$taskItem.FullName).Replace('\','/')
    if(@($Excluded|Where-Object {$taskRelative -ceq $_ -or $taskRelative.StartsWith($_+'/',[StringComparison]::Ordinal)}).Count){continue}
    if($taskItem.PSIsContainer){
     if($taskItem.Attributes -band [IO.FileAttributes]::ReparsePoint){throw "Uninventoried linked directory: $taskRelative"}
     $taskPending.Push($taskItem.FullName)
    }else{$taskRelative}
   }
  }
 }
 $taskRows=Get-AiRows $Root @($taskPaths|Sort-Object -CaseSensitive)
 return @{root=$Root;kind=$Kind;excluded=$Excluded;rows=@($taskRows)}
}
function Assert-AiInventory {
 param($Inventory,[string]$Output)
 $taskCurrent=Get-AiInventory $Inventory.root $Inventory.kind $Inventory.excluded
 $taskBefore=@($Inventory.rows|ForEach-Object relative)
 $taskAfter=@($taskCurrent.rows|ForEach-Object relative)
 $taskPathDrift=@(Compare-Object $taskBefore $taskAfter -CaseSensitive)
 $taskHashes=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal);foreach($taskRow in $taskCurrent.rows){$taskHashes.Add($taskRow.relative,$taskRow.sha256)}
 $taskDrift=@($Inventory.rows|Where-Object {!$taskHashes.ContainsKey($_.relative) -or $taskHashes[$_.relative] -cne $_.sha256}|ForEach-Object relative)
 @{root=$Inventory.root;kind=$Inventory.kind;excluded=$Inventory.excluded;before_count=$taskBefore.Count;after_count=$taskAfter.Count;path_drift=$taskPathDrift;hash_drift=$taskDrift;rows=$taskCurrent.rows;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 7|Set-Content -LiteralPath $Output -Encoding utf8NoBOM
 if($taskPathDrift.Count -or $taskDrift.Count){throw 'Frozen input path inventory or hash drift'}
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
   # Zig0.16 Server.OutMessage.TestMetadata puts string_bytes_len before tests_len.
   $taskStrings=[BitConverter]::ToUInt32($taskBytes,$taskOffset);$taskCount=[BitConverter]::ToUInt32($taskBytes,$taskOffset+4)
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

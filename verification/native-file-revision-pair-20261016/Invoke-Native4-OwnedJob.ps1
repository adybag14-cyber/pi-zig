param(
 [Parameter(Mandatory)][string]$Executable,
 [Parameter(Mandatory)][string]$WorkingDirectory,
 [Parameter(Mandatory)][string[]]$Arguments,
 [Parameter(Mandatory)][string]$ReceiptBase,
 [ValidateSet(300,1320)][int]$TimeoutSeconds=300,
 [hashtable]$EnvironmentOverrides=@{}
)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath "$ReceiptBase.process.json"){throw 'Immutable owner receipt already exists'}
$taskExecutable=[IO.Path]::GetFullPath($Executable)
if($taskExecutable -match '(?i)codex'){throw 'Refuse host process launch/control'}
$taskSemaphore=[Threading.Semaphore]::new(4,4,'Local\PiZigOwnedValidationRoots20261015')
if(!$taskSemaphore.WaitOne(0)){throw 'Four coordinated native/source roots are already admitted'}
function Write-Receipt($value){
 $taskTemporary="$ReceiptBase.process.json.tmp"
 [IO.File]::WriteAllText($taskTemporary,($value|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
 Move-Item -LiteralPath $taskTemporary -Destination "$ReceiptBase.process.json" -Force
}
try{
 $taskStart=[Diagnostics.ProcessStartInfo]::new()
 $taskStart.FileName=$taskExecutable;$taskStart.WorkingDirectory=$WorkingDirectory
 $taskStart.UseShellExecute=$false;$taskStart.CreateNoWindow=$true
 $taskStart.RedirectStandardOutput=$true;$taskStart.RedirectStandardError=$true
 foreach($taskArgument in $Arguments){$taskStart.ArgumentList.Add($taskArgument)}
 foreach($taskKey in $EnvironmentOverrides.Keys){$taskStart.Environment[$taskKey]=[string]$EnvironmentOverrides[$taskKey]}
 $taskProcess=[Diagnostics.Process]::new();$taskProcess.StartInfo=$taskStart
 $taskExecutableHash=(Get-FileHash -LiteralPath $taskExecutable).Hash
 $taskLaunched=[DateTimeOffset]::UtcNow.ToString('o')
 if(!$taskProcess.Start()){throw 'Owned root launch failed'}
 $taskCreated=$taskProcess.StartTime.ToUniversalTime()
 $taskLive=Get-CimInstance Win32_Process -Filter "ProcessId = $($taskProcess.Id)"
 $taskCommand=if($taskLive){$taskLive.CommandLine}else{$null}
 $taskRecord=[ordered]@{pid=$taskProcess.Id;executable=$taskExecutable;executable_sha256=$taskExecutableHash;argv=@($Arguments);live_command_line=$taskCommand;created_utc=$taskCreated.ToString('o');launched_utc=$taskLaunched;working_directory=$WorkingDirectory;outer_seconds=$TimeoutSeconds;settle_seconds=10;slot=4;maximum_coordinated_roots=4;identity_source='retained kernel Process handle plus exact ProcessStartInfo argv and live CIM when available';status='running'}
 Write-Receipt $taskRecord
 Write-Output ($taskRecord|ConvertTo-Json -Depth 6 -Compress)
 $taskOut=$taskProcess.StandardOutput.ReadToEndAsync();$taskErr=$taskProcess.StandardError.ReadToEndAsync()
 $taskFinished=$taskProcess.WaitForExit($TimeoutSeconds*1000)
 $taskDescendants=@()
 if(!$taskFinished){
  $taskCurrent=Get-CimInstance Win32_Process -Filter "ProcessId = $($taskProcess.Id)"
  if(!$taskCurrent -or $taskCurrent.ExecutablePath -ine $taskExecutable -or !$taskCommand -or $taskCurrent.CommandLine -cne $taskCommand -or [Math]::Abs((([DateTimeOffset]$taskCurrent.CreationDate).UtcDateTime-$taskCreated).Ticks) -gt 10){throw 'Timeout root identity mismatch; refusing termination'}
  $taskCensus=@(Get-CimInstance Win32_Process)
  $taskParentIds=@([uint32]$taskProcess.Id)
  do{
   $taskChildren=@($taskCensus|Where-Object{$_.ParentProcessId -in $taskParentIds})
   if($taskChildren.Count){$taskDescendants+=@($taskChildren|ForEach-Object{[ordered]@{pid=$_.ProcessId;parent_pid=$_.ParentProcessId;executable=$_.ExecutablePath;command_line=$_.CommandLine;created_utc=([DateTimeOffset]$_.CreationDate).UtcDateTime.ToString('o')}})}
   $taskParentIds=@($taskChildren|ForEach-Object ProcessId)
  }while($taskParentIds.Count)
  if(@($taskDescendants|Where-Object{$_.executable -match '(?i)codex'}).Count){throw 'Host descendant detected; refusing termination'}
  $taskProcess.Kill($true)
  if(!$taskProcess.WaitForExit(10000)){throw 'Owned root did not settle within ten seconds'}
 }
 [IO.File]::WriteAllText("$ReceiptBase.stdout.log",$taskOut.GetAwaiter().GetResult())
 [IO.File]::WriteAllText("$ReceiptBase.stderr.log",$taskErr.GetAwaiter().GetResult())
 $taskAfter=Get-CimInstance Win32_Process -Filter "ProcessId = $($taskProcess.Id)"
 $taskStillOwned=$taskAfter -and [Math]::Abs((([DateTimeOffset]$taskAfter.CreationDate).UtcDateTime-$taskCreated).Ticks) -le 10
 $taskRemaining=@($taskDescendants|Where-Object{$taskDescendant=$_;$taskFound=Get-CimInstance Win32_Process -Filter "ProcessId = $($taskDescendant.pid)";$taskFound -and ([DateTimeOffset]$taskFound.CreationDate).UtcDateTime.ToString('o') -ceq $taskDescendant.created_utc})
 $taskRecord.status=if(!$taskFinished){'timed_out'}elseif($taskProcess.ExitCode -eq 0){'passed'}else{'failed'}
 $taskRecord.exit_code=$taskProcess.ExitCode;$taskRecord.completed_utc=[DateTimeOffset]::UtcNow.ToString('o')
 $taskRecord.owned_root_absent=!$taskStillOwned;$taskRecord.pid_reused=[bool]($taskAfter -and !$taskStillOwned)
 $taskRecord.timeout_descendants=$taskDescendants;$taskRecord.owned_timeout_descendants_remaining=$taskRemaining.Count
 Write-Receipt $taskRecord
 Write-Output ($taskRecord|ConvertTo-Json -Depth 10 -Compress)
 if($taskStillOwned -or $taskRemaining.Count){throw 'Owned process absence verification failed'}
 if($taskRecord.status -cne 'passed'){throw "Owned terminal $($taskRecord.status)"}
}finally{$null=$taskSemaphore.Release();$taskSemaphore.Dispose()}

param([Parameter(Mandatory)][string]$Name,[Parameter(Mandatory)][string]$Executable,[Parameter(Mandatory)][string]$WorkingDirectory,[Parameter(Mandatory)][string[]]$Arguments,[int]$TimeoutSeconds=300,[int]$SettleSeconds=10,[hashtable]$EnvironmentOverrides=@{})
$ErrorActionPreference='Stop'
$taskState=Join-Path $PSScriptRoot "$Name.json"
if(Test-Path -LiteralPath $taskState){throw 'Refuse owned Source record replay'}
$taskStart=[Diagnostics.ProcessStartInfo]::new()
$taskStart.FileName=[IO.Path]::GetFullPath($Executable)
$taskStart.WorkingDirectory=$WorkingDirectory
foreach($taskKey in $EnvironmentOverrides.Keys){$taskStart.Environment[$taskKey]=[string]$EnvironmentOverrides[$taskKey]}
$taskStart.UseShellExecute=$false
$taskStart.CreateNoWindow=$true
$taskStart.RedirectStandardOutput=$true
$taskStart.RedirectStandardError=$true
foreach($taskArgument in $Arguments){$taskStart.ArgumentList.Add($taskArgument)}
$taskProcess=[Diagnostics.Process]::new()
$taskProcess.StartInfo=$taskStart
$taskExecutableHash=(Get-FileHash -LiteralPath $taskStart.FileName).Hash
$taskLaunched=[DateTimeOffset]::UtcNow.ToString('o')
if(!$taskProcess.Start()){throw 'Owned OAuth Source failed to launch'}
$taskCreated=$taskProcess.StartTime.ToUniversalTime()
$taskIdentity=Get-CimInstance Win32_Process -Filter "ProcessId = $($taskProcess.Id)" -ErrorAction SilentlyContinue
if($taskIdentity -and (-not $taskIdentity.ExecutablePath -or -not $taskIdentity.CommandLine -or -not $taskIdentity.CreationDate)){$taskIdentity=$null}
$taskRecord=[ordered]@{name=$Name;pid=$taskProcess.Id;executable=$taskStart.FileName;executable_sha256=$taskExecutableHash
 command_line=if($taskIdentity){$taskIdentity.CommandLine}else{$taskStart.FileName+' '+($Arguments -join ' ')}
 command_line_source=if($taskIdentity){'live Win32_Process'}else{'retained ProcessStartInfo argv; child already exited'}
 created_utc=$taskCreated.ToString('o');launched_utc=$taskLaunched;identity_captured=$true;working_directory=$WorkingDirectory;timeout_seconds=$TimeoutSeconds;settle_seconds=$SettleSeconds;status='running'}
$taskRecord|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $taskState -Encoding utf8NoBOM
$taskOut=$taskProcess.StandardOutput.ReadToEndAsync()
$taskErr=$taskProcess.StandardError.ReadToEndAsync()
$taskFinished=$taskProcess.WaitForExit($TimeoutSeconds*1000)
if(!$taskFinished){
 $taskLive=Get-CimInstance Win32_Process -Filter "ProcessId = $($taskProcess.Id)"
 if(!$taskLive -or $taskLive.ExecutablePath -cne $taskStart.FileName -or $taskLive.ExecutablePath -match 'codex' -or
  [Math]::Abs((([DateTimeOffset]$taskLive.CreationDate).UtcDateTime-$taskCreated).TotalMilliseconds) -gt 1){throw 'OAuth Source timeout identity mismatch; preserve process'}
 if($taskIdentity -and $taskLive.CommandLine -cne $taskIdentity.CommandLine){throw 'OAuth Source timeout command changed; preserve process'}
 $taskProcess.Kill($false)
 if(!$taskProcess.WaitForExit($SettleSeconds*1000)){throw 'OAuth Source owned process did not settle within bound'}
}
[IO.File]::WriteAllText((Join-Path $PSScriptRoot "$Name.stdout.log"),$taskOut.GetAwaiter().GetResult())
[IO.File]::WriteAllText((Join-Path $PSScriptRoot "$Name.stderr.log"),$taskErr.GetAwaiter().GetResult())
$taskRecord.exit_code=$taskProcess.ExitCode
$taskRecord.status=if(!$taskFinished){'timed_out'}elseif($taskProcess.ExitCode -eq 0){'passed'}else{'failed'}
$taskRecord.completed_utc=[DateTimeOffset]::UtcNow.ToString('o')
$taskAfter=Get-CimInstance Win32_Process -Filter "ProcessId = $($taskProcess.Id)" -ErrorAction SilentlyContinue
$taskRecord.independent_pid_absent=($null -eq $taskAfter)
$taskRecord.terminal_kernel_handle=$taskProcess.HasExited
$taskRecord|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $taskState -Encoding utf8NoBOM
$taskRecord|ConvertTo-Json -Depth 6
$taskProcess.Dispose()

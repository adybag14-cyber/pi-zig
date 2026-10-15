param([Parameter(Mandatory)][string]$Name,[Parameter(Mandatory)][string[]]$Arguments,[hashtable]$EnvironmentOverrides=@{})
$ErrorActionPreference='Stop'
$taskExe='C:\Program Files\nodejs\node.exe'
$taskRoot='C:\Users\adyba\pi-upstream-source-4954d76-20261015'
$taskState=Join-Path $PSScriptRoot "$Name-owner.json"
if(Test-Path -LiteralPath $taskState){throw 'Fresh unique owned process record required'}
if((Get-FileHash -LiteralPath $taskExe).Hash -cne '63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088'){throw 'Node executable pin mismatch'}
$taskStart=[Diagnostics.ProcessStartInfo]::new()
$taskStart.FileName=$taskExe;$taskStart.WorkingDirectory=$taskRoot;$taskStart.UseShellExecute=$false;$taskStart.CreateNoWindow=$true
$taskStart.RedirectStandardOutput=$true;$taskStart.RedirectStandardError=$true
$taskStart.Environment['NODE_OPTIONS']='';$taskStart.Environment['NODE_PATH']=''
foreach($taskKey in $EnvironmentOverrides.Keys){$taskStart.Environment[$taskKey]=[string]$EnvironmentOverrides[$taskKey]}
foreach($taskArgument in $Arguments){$taskStart.ArgumentList.Add($taskArgument)}
$taskProcess=[Diagnostics.Process]::new();$taskProcess.StartInfo=$taskStart
$taskLaunch=[DateTimeOffset]::UtcNow.ToString('o')
if(!$taskProcess.Start()){throw 'Node launch failed'}
$taskHandle=$taskProcess.Handle;$taskCreated=$taskProcess.StartTime.ToUniversalTime()
$taskOut=$taskProcess.StandardOutput.ReadToEndAsync();$taskErr=$taskProcess.StandardError.ReadToEndAsync()
$taskInitial=Get-CimInstance Win32_Process -Filter "ProcessId = $($taskProcess.Id)"
$taskRecord=[ordered]@{name=$Name;pid=$taskProcess.Id;executable=$taskExe;created_utc=$taskCreated.ToString('o');launched_utc=$taskLaunch;launch_argv=$Arguments;raw_initial_command_line=if($taskInitial){$taskInitial.CommandLine}else{$null};identity_source=if($taskInitial){'live Win32_Process raw CommandLine plus retained handle/executable/UTC start'}else{'retained handle and exact launch argv; no live CIM snapshot captured'};retained_handle=$true;status='running';timeout_seconds=300;settle_seconds=10}
$taskRecord|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $taskState -Encoding utf8NoBOM
$taskFinished=$taskProcess.WaitForExit(300000)
$taskSettleClock=[Diagnostics.Stopwatch]::StartNew()
if(!$taskFinished){
 $taskLive=Get-CimInstance Win32_Process -Filter "ProcessId = $($taskProcess.Id)"
 if(!$taskInitial -or !$taskInitial.CommandLine -or !$taskLive -or $taskLive.CommandLine -cne $taskInitial.CommandLine -or $taskLive.ExecutablePath -ine $taskExe -or $taskInitial.ExecutablePath -ine $taskExe -or ([DateTimeOffset]$taskLive.CreationDate).UtcDateTime -ne ([DateTimeOffset]$taskInitial.CreationDate).UtcDateTime -or [Math]::Abs((([DateTimeOffset]$taskLive.CreationDate).UtcDateTime-$taskCreated).Ticks) -gt 10 -or $taskProcess.Handle -ne $taskHandle -or $taskProcess.StartTime.ToUniversalTime() -ne $taskCreated){throw 'Exact owned timeout identity unavailable/mismatched; refusing control'}
 $taskRecord.raw_before_control_command_line=$taskLive.CommandLine
 $taskProcess.Kill()
 $taskFinishedAfterKill=$taskProcess.WaitForExit(10000)
 if(!$taskFinishedAfterKill){throw 'Owned process did not settle within10s'}
 if(Get-CimInstance Win32_Process -Filter "ProcessId = $($taskProcess.Id)"){throw 'Post-control owned PID absence not verified'}
}
$taskSettleRemaining=[Math]::Max(0,10000-[int]$taskSettleClock.ElapsedMilliseconds)
$taskPipeSettled=[Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($taskOut,$taskErr),$taskSettleRemaining)
if(!$taskPipeSettled){throw 'Owned stdout/stderr did not settle within10s'}
[IO.File]::WriteAllText((Join-Path $PSScriptRoot "$Name.stdout.log"),$taskOut.Result)
[IO.File]::WriteAllText((Join-Path $PSScriptRoot "$Name.stderr.log"),$taskErr.Result)
$taskRecord.exit_code=$taskProcess.ExitCode;$taskRecord.completed_utc=[DateTimeOffset]::UtcNow.ToString('o')
$taskRecord.status=if(!$taskFinished){'timed_out'}elseif($taskProcess.ExitCode -eq 0){'passed'}else{'failed'}
$taskRecord|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $taskState -Encoding utf8NoBOM
if($taskRecord.status -cne 'passed'){throw "Owned Node terminal $($taskRecord.status)"}

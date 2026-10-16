param([Parameter(Mandatory)][string]$Name,[Parameter(Mandatory)][string]$Executable,[Parameter(Mandatory)][string]$WorkingDirectory,[Parameter(Mandatory)][string[]]$Arguments,[int]$TimeoutSeconds=30,[hashtable]$EnvironmentOverrides=@{})
$ErrorActionPreference='Stop'
$taskStart=[Diagnostics.ProcessStartInfo]::new()
$taskStart.FileName=[IO.Path]::GetFullPath($Executable)
$taskStart.WorkingDirectory=$WorkingDirectory
foreach($taskKey in $EnvironmentOverrides.Keys){$taskStart.Environment[$taskKey]=[string]$EnvironmentOverrides[$taskKey]}
$taskStart.UseShellExecute=$false
$taskStart.CreateNoWindow=$true
$taskStart.RedirectStandardOutput=$true
$taskStart.RedirectStandardError=$true
foreach($argument in $Arguments){$taskStart.ArgumentList.Add($argument)}
$taskProcess=[Diagnostics.Process]::new()
$taskProcess.StartInfo=$taskStart
$taskExecutableHash=(Get-FileHash -LiteralPath $taskStart.FileName).Hash
$taskLaunched=[DateTimeOffset]::UtcNow.ToString('o')
if(!$taskProcess.Start()){throw 'Fast Source owner failed to launch'}
# Capture from the retained kernel Process handle before a very short Source
# oracle can exit while a comparatively slow Win32_Process query is running.
$taskCreated=$taskProcess.StartTime.ToUniversalTime()
$taskIdentity=Get-CimInstance Win32_Process -Filter "ProcessId = $($taskProcess.Id)"
if($taskIdentity -and (-not $taskIdentity.ExecutablePath -or -not $taskIdentity.CommandLine -or -not $taskIdentity.CreationDate)){$taskIdentity=$null}
$taskRecord=[ordered]@{name=$Name;pid=$taskProcess.Id;executable=$taskStart.FileName;executable_sha256=$taskExecutableHash
    command_line=if($taskIdentity){$taskIdentity.CommandLine}else{$taskStart.FileName+' '+($Arguments -join ' ')}
    command_line_source=if($taskIdentity){'live Win32_Process'}else{'exact native ProcessStartInfo argv; child already exited'}
    created_utc=$taskCreated.ToString('o');launched_utc=$taskLaunched;identity_captured=$true;identity_source='retained kernel Process handle PID/starttime and exact native launch; live CIM when available'
    working_directory=$WorkingDirectory;status='running'}
$taskState=Join-Path $PSScriptRoot "$Name.json"
if(Test-Path -LiteralPath $taskState){throw 'Refuse owned Source record replay'}
$taskRecord|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $taskState -Encoding utf8NoBOM
$taskOut=$taskProcess.StandardOutput.ReadToEndAsync()
$taskErr=$taskProcess.StandardError.ReadToEndAsync()
$taskFinished=$taskProcess.WaitForExit($TimeoutSeconds*1000)
if(!$taskFinished){
    $taskLive=Get-CimInstance Win32_Process -Filter "ProcessId = $($taskProcess.Id)"
    if(!$taskLive -or $taskLive.ExecutablePath -cne $taskStart.FileName -or
        [Math]::Abs((([DateTimeOffset]$taskLive.CreationDate).UtcDateTime-$taskCreated).Ticks) -gt 10 -or
        $taskLive.ExecutablePath -match 'codex'){throw 'Fast Source timeout ownership mismatch; refusing termination'}
    if($taskIdentity -and $taskLive.CommandLine -cne $taskIdentity.CommandLine){throw 'Fast Source command identity changed; refusing termination'}
    $taskProcess.Kill($true)
    if(!$taskProcess.WaitForExit(10000)){throw 'Owned Source child did not settle within10s after verified termination'}
}
[IO.File]::WriteAllText((Join-Path $PSScriptRoot "$Name.stdout.log"),$taskOut.GetAwaiter().GetResult())
[IO.File]::WriteAllText((Join-Path $PSScriptRoot "$Name.stderr.log"),$taskErr.GetAwaiter().GetResult())
$taskRecord.exit_code=$taskProcess.ExitCode
$taskRecord.status=if(!$taskFinished){'timed_out'}elseif($taskProcess.ExitCode -eq 0){'passed'}else{'failed'}
$taskRecord.completed_utc=[DateTimeOffset]::UtcNow.ToString('o')
$taskRecord|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $taskState -Encoding utf8NoBOM
$taskRecord|ConvertTo-Json -Depth 5
if(!$taskFinished -or $taskProcess.ExitCode -ne 0){exit 1}

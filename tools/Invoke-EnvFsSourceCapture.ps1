param([Parameter(Mandatory)][string]$ExpectedHead,[Parameter(Mandatory)][string]$SourceRoot,[Parameter(Mandatory)][string]$ToolReceipt,[Parameter(Mandatory)][string]$Receipt)
$ErrorActionPreference='Stop'
$taskRoot=(Get-Location).ProviderPath
if((git rev-parse HEAD).Trim() -cne $ExpectedHead){throw 'Candidate head mismatch'}
$taskReceipt=[IO.Path]::GetFullPath((Join-Path $taskRoot $Receipt))
if(!$taskReceipt.StartsWith($taskRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::Ordinal)){throw 'Source receipt must stay in owned checkout'}
New-Item -ItemType Directory -Path $taskReceipt -Force|Out-Null
$taskTool=Get-Content -LiteralPath $ToolReceipt -Raw|ConvertFrom-Json
if((Get-FileHash -LiteralPath $taskTool.node).Hash -cne $taskTool.node_sha256){throw 'Pinned reference tool drift'}
$taskBefore=@(git ls-files|Sort-Object|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath (Join-Path $taskRoot $_)).Hash}})
$taskBefore|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskReceipt 'candidate-before.json') -Encoding utf8NoBOM
if($IsWindows){$taskFree=[uint64](Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory*1024}
elseif($IsLinux){
    $taskLine=Get-Content /proc/meminfo|Where-Object{$_ -match '^MemAvailable:'}
    $taskFree=[uint64]([regex]::Match($taskLine,'\d+').Value)*1024
    if((Test-Path /sys/fs/cgroup/memory.max) -and (Test-Path /sys/fs/cgroup/memory.current)){
        $taskLimit=(Get-Content /sys/fs/cgroup/memory.max -Raw).Trim()
        if($taskLimit -match '^\d+$'){$taskFree=[Math]::Min($taskFree,[Math]::Max(0,[int64]$taskLimit-[int64](Get-Content /sys/fs/cgroup/memory.current -Raw)))}
    }
}else{
    $taskPageSize=[uint64](& sysctl -n hw.pagesize)
    $taskStats=(& vm_stat)-join "`n"
    $taskPages=[uint64]0
    foreach($taskKind in @('free','inactive','speculative')){$taskPages+=[uint64]([regex]::Match($taskStats,"Pages ${taskKind}:\s+(\d+)").Groups[1].Value)}
    $taskFree=$taskPages*$taskPageSize
}
[ordered]@{free_bytes=$taskFree;minimum_bytes=2147483648;heap_mib=256;deadline_seconds=30;checked_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content (Join-Path $taskReceipt 'admission.json')
if($taskFree -lt 2147483648){throw 'Fresh Source-only2GiB admission refused'}
$taskStart=[Diagnostics.ProcessStartInfo]::new()
$taskStart.FileName=[IO.Path]::GetFullPath($taskTool.node)
$taskStart.WorkingDirectory=$taskRoot
$taskStart.UseShellExecute=$false
$taskStart.CreateNoWindow=$true
$taskStart.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
$taskStart.RedirectStandardOutput=$true
$taskStart.RedirectStandardError=$true
$taskOracleInput=Join-Path $taskRoot 'src/extensions/fixtures/env-node-fs-original-source-capture.input.txt'
$taskOracleHash=(Get-FileHash -LiteralPath $taskOracleInput).Hash
$taskTempRoot=if($env:RUNNER_TEMP){$env:RUNNER_TEMP}else{[IO.Path]::GetTempPath()}
$taskOracleTemp=[IO.Path]::GetFullPath((Join-Path $taskTempRoot ('env-node-fs-source-'+[guid]::NewGuid().ToString('N')+'.mjs')))
if($taskOracleTemp.StartsWith($taskRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::Ordinal)){throw 'Reference oracle temp must stay outside candidate checkout'}
if(Test-Path -LiteralPath $taskOracleTemp){throw 'Refuse reference oracle temp replay'}
[IO.File]::WriteAllBytes($taskOracleTemp,[IO.File]::ReadAllBytes($taskOracleInput))
if((Get-FileHash -LiteralPath $taskOracleTemp).Hash -cne $taskOracleHash){throw 'Reference oracle materialization changed bytes'}
[ordered]@{input=$taskOracleInput;input_sha256=$taskOracleHash;temp=$taskOracleTemp;temp_sha256=(Get-FileHash -LiteralPath $taskOracleTemp).Hash;body_rewritten=$false}|ConvertTo-Json|Set-Content (Join-Path $taskReceipt 'oracle-materialization.json')
foreach($taskArgument in @('--max-old-space-size=256','--conditions=source',$taskOracleTemp,[IO.Path]::GetFullPath((Join-Path $taskRoot $SourceRoot)),$taskRoot,$taskReceipt)){$taskStart.ArgumentList.Add($taskArgument)}
$taskProcess=[Diagnostics.Process]::new()
$taskProcess.StartInfo=$taskStart
if(!$taskProcess.Start()){throw 'Owned Source oracle did not start'}
$taskCreated=$taskProcess.StartTime.ToUniversalTime()
$taskCommand=if($IsWindows){(Get-CimInstance Win32_Process -Filter "ProcessId = $($taskProcess.Id)").CommandLine}else{((& ps -p $taskProcess.Id -o command=) -join "`n").Trim()}
$taskRecord=[ordered]@{pid=$taskProcess.Id;created_utc=$taskCreated.ToString('o');executable=$taskStart.FileName;executable_sha256=$taskTool.node_sha256;argv=@($taskStart.ArgumentList);command_line=$taskCommand;identity_source='retained native Process handle and exact ProcessStartInfo argv';status='running';native_qualified=$false}
$taskRecord|ConvertTo-Json -Depth 5|Set-Content (Join-Path $taskReceipt 'owned-process.json')
$taskOut=$taskProcess.StandardOutput.ReadToEndAsync()
$taskErr=$taskProcess.StandardError.ReadToEndAsync()
$taskFinished=$taskProcess.WaitForExit(30000)
if(!$taskFinished){
    $taskProcess.Refresh()
    if($taskProcess.StartTime.ToUniversalTime() -ne $taskCreated -or $taskProcess.MainModule.FileName -cne $taskStart.FileName -or $taskStart.FileName -match 'codex'){throw 'Owned Source timeout identity mismatch; refusing process control'}
    if($IsWindows){
        $taskLive=Get-CimInstance Win32_Process -Filter "ProcessId = $($taskProcess.Id)"
        if(!$taskLive -or $taskLive.ExecutablePath -cne $taskStart.FileName -or [Math]::Abs((([DateTimeOffset]$taskLive.CreationDate).UtcDateTime-$taskCreated).Ticks) -gt 10){throw 'Fresh Source timeout identity mismatch'}
        if($taskCommand -and $taskLive.CommandLine -cne $taskCommand){throw 'Owned Source timeout argv mismatch'}
    }else{
        $taskFreshCommand=((& ps -p $taskProcess.Id -o command=) -join "`n").Trim()
        if(!$taskCommand -or $taskFreshCommand -cne $taskCommand){throw 'Owned Source timeout argv mismatch'}
    }
    $taskProcess.Kill($true)
    if(!$taskProcess.WaitForExit(10000)){throw 'Owned Source timeout process did not terminate'}
}
[IO.File]::WriteAllText((Join-Path $taskReceipt 'stdout.log'),$taskOut.GetAwaiter().GetResult())
[IO.File]::WriteAllText((Join-Path $taskReceipt 'stderr.log'),$taskErr.GetAwaiter().GetResult())
$taskRecord.status=if(!$taskFinished){'timed_out'}elseif($taskProcess.ExitCode -eq 0){'passed'}else{'failed'}
$taskRecord.exit_code=$taskProcess.ExitCode
$taskRecord.completed_utc=[DateTimeOffset]::UtcNow.ToString('o')
$taskRecord|ConvertTo-Json -Depth 5|Set-Content (Join-Path $taskReceipt 'owned-process.json')
$taskAfter=@(git ls-files|Sort-Object|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath (Join-Path $taskRoot $_)).Hash}})
$taskDrift=@(Compare-Object ($taskBefore|ForEach-Object{"$($_.path):$($_.sha256)"}) ($taskAfter|ForEach-Object{"$($_.path):$($_.sha256)"}))
$taskToolDrift=(Get-FileHash -LiteralPath $taskTool.node).Hash -cne $taskTool.node_sha256
$taskOracleDrift=(Get-FileHash -LiteralPath $taskOracleInput).Hash -cne $taskOracleHash -or (Get-FileHash -LiteralPath $taskOracleTemp).Hash -cne $taskOracleHash
[ordered]@{candidate_head=(git rev-parse HEAD).Trim();source_count=$taskBefore.Count;source_after=$taskAfter.Count;source_drift=$taskDrift.Count;tool_drift=$taskToolDrift;oracle_input_sha256=$taskOracleHash;oracle_temp_drift=$taskOracleDrift;native_qualified=$false;full_env_qualified=$false;public_activation=$false}|ConvertTo-Json|Set-Content (Join-Path $taskReceipt 'candidate-posthash.json')
if($taskDrift.Count -or $taskToolDrift -or $taskOracleDrift -or (git rev-parse HEAD).Trim() -cne $ExpectedHead){throw 'Candidate/tool source-only post drift'}
if(!$taskFinished -or $taskProcess.ExitCode -ne 0){throw "Owned Source terminal $($taskRecord.status)"}

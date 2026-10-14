param([Parameter(Mandatory)][string]$ExpectedHead,[Parameter(Mandatory)][string]$ExpectedManifestHash,[Parameter(Mandatory)][string]$SourceRoot,[Parameter(Mandatory)][string]$ToolReceipt,[Parameter(Mandatory)][string]$Receipt)
$ErrorActionPreference='Stop'
$taskRoot=(Get-Location).ProviderPath
if((git rev-parse HEAD).Trim() -cne $ExpectedHead){throw 'Candidate head mismatch'}
$taskReceipt=[IO.Path]::GetFullPath((Join-Path $taskRoot $Receipt))
if(!$taskReceipt.StartsWith($taskRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::Ordinal)){throw 'Source receipt must stay in owned checkout'}
New-Item -ItemType Directory -Path $taskReceipt -Force|Out-Null
function Control-Rows {
    @(Get-ChildItem Env:|Where-Object{$_.Name -match '^(PI_|ZIG_)'}|Sort-Object Name|ForEach-Object{[ordered]@{name=$_.Name;value_sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($_.Value)))}})
}
$taskControls=Control-Rows
$taskControls|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskReceipt 'controls-before.json') -Encoding utf8NoBOM
$taskManifestPath=Join-Path $taskRoot 'src/extensions/fixtures/env-node-arraybufferview4-source-manifest-e6220e1.json'
if((Get-FileHash -LiteralPath $taskManifestPath).Hash -cne $ExpectedManifestHash){throw 'Pinned Source manifest drift'}
$taskManifest=Get-Content -LiteralPath $taskManifestPath -Raw|ConvertFrom-Json
if($taskManifest.fixtures.Count -ne 7 -or $taskManifest.source_corpora -ne 3 -or $taskManifest.expected_tests -ne 4 -or $taskManifest.public_guest_activation -or $taskManifest.posix_native_qualified){throw 'Source manifest scope mismatch'}
foreach($taskFixture in $taskManifest.fixtures){if((Get-FileHash -LiteralPath (Join-Path $taskRoot $taskFixture.path)).Hash -cne $taskFixture.sha256){throw 'Pinned Source observer drift'}}
$taskTool=Get-Content -LiteralPath $ToolReceipt -Raw|ConvertFrom-Json
if((Get-FileHash -LiteralPath $taskTool.node).Hash -cne $taskTool.node_sha256){throw 'Pinned reference tool drift'}
$taskReferenceRoot=[IO.Path]::GetFullPath((Join-Path $taskRoot $SourceRoot))
if((git -C $taskReferenceRoot rev-parse HEAD).Trim() -cne 'e6220e1316f86af818a0ccbfe1c09d7e918b41cf'){throw 'Original Source head mismatch'}
function Original-Rows {
    @(git -C $taskReferenceRoot ls-files|Sort-Object|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath (Join-Path $taskReferenceRoot $_)).Hash}})
}
$taskOriginalBefore=Original-Rows
if($taskOriginalBefore.Count -ne 1902){throw 'Original Source inventory mismatch'}
$taskOriginalBefore|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskReceipt 'original-before.json') -Encoding utf8NoBOM
$taskBodies=@()
foreach($taskName in @('env-node-view-span','env-node-view-kernel','env-node-view-public-getters')){
    $taskInput=Join-Path $taskRoot ('src/extensions/fixtures/'+$taskName+'-source-24.input.txt')
    $taskBody=Join-Path $taskReceipt ($taskName+'-source-body-24-20261014.txt')
    [IO.File]::WriteAllBytes($taskBody,[IO.File]::ReadAllBytes($taskInput))
    $taskHash=(Get-FileHash -LiteralPath $taskInput).Hash
    if((Get-FileHash -LiteralPath $taskBody).Hash -cne $taskHash){throw 'Source observer materialization changed bytes'}
    $taskBodies+=[ordered]@{name=$taskName;input=$taskInput;body=$taskBody;sha256=$taskHash}
}
$taskBodies|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskReceipt 'observer-materialization.json') -Encoding utf8NoBOM
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
$taskOracleInput=Join-Path $taskRoot 'src/extensions/fixtures/env-node-view-original-source-capture.input.txt'
$taskOracleHash=(Get-FileHash -LiteralPath $taskOracleInput).Hash
$taskTempRoot=if($env:RUNNER_TEMP){$env:RUNNER_TEMP}else{[IO.Path]::GetTempPath()}
$taskOracleTemp=[IO.Path]::GetFullPath((Join-Path $taskTempRoot ('env-node-view-source-'+[guid]::NewGuid().ToString('N')+'.mjs')))
if($taskOracleTemp.StartsWith($taskRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::Ordinal)){throw 'Reference oracle temp must stay outside candidate checkout'}
if(Test-Path -LiteralPath $taskOracleTemp){throw 'Refuse reference oracle temp replay'}
[IO.File]::WriteAllBytes($taskOracleTemp,[IO.File]::ReadAllBytes($taskOracleInput))
if((Get-FileHash -LiteralPath $taskOracleTemp).Hash -cne $taskOracleHash){throw 'Reference oracle materialization changed bytes'}
[ordered]@{input=$taskOracleInput;input_sha256=$taskOracleHash;temp=$taskOracleTemp;temp_sha256=(Get-FileHash -LiteralPath $taskOracleTemp).Hash;body_rewritten=$false}|ConvertTo-Json|Set-Content (Join-Path $taskReceipt 'oracle-materialization.json')
foreach($taskArgument in @('--max-old-space-size=256','--expose-internals','--expose-gc',$taskOracleTemp,$taskReceipt)){$taskStart.ArgumentList.Add($taskArgument)}
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

$taskOriginalAfter=Original-Rows
$taskOriginalDrift=@(Compare-Object @($taskOriginalBefore|ForEach-Object{"$($_.path):$($_.sha256)"}) @($taskOriginalAfter|ForEach-Object{"$($_.path):$($_.sha256)"}))
$taskBodyDrift=@($taskBodies|Where-Object{(Get-FileHash -LiteralPath $_.input).Hash -cne $_.sha256 -or (Get-FileHash -LiteralPath $_.body).Hash -cne $_.sha256})
$taskControlsAfter=Control-Rows
$taskControlDrift=@(Compare-Object @($taskControls|ForEach-Object{"$($_.name):$($_.value_sha256)"}) @($taskControlsAfter|ForEach-Object{"$($_.name):$($_.value_sha256)"}))
[ordered]@{source_files=$taskOriginalBefore.Count;source_after=$taskOriginalAfter.Count;source_drift=$taskOriginalDrift.Count;observer_files=$taskBodies.Count;observer_drift=$taskBodyDrift.Count;controls=$taskControls.Count;control_drift=$taskControlDrift.Count;tool_drift=$taskToolDrift;oracle_temp_drift=$taskOracleDrift;native_qualified=$false;posix_native=$false;public_frontend_qualified=$false;public_activation=$false}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskReceipt 'original-posthash.json') -Encoding utf8NoBOM
if($taskOriginalDrift.Count -or $taskBodyDrift.Count -or $taskControlDrift.Count){throw 'Original Source observer or control drift'}
if($taskDrift.Count -or $taskToolDrift -or $taskOracleDrift -or (git rev-parse HEAD).Trim() -cne $ExpectedHead){throw 'Candidate/tool source-only post drift'}
if(!$taskFinished -or $taskProcess.ExitCode -ne 0){throw "Owned Source terminal $($taskRecord.status)"}
$taskPackets=Get-Content -LiteralPath (Join-Path $taskReceipt 'env-node-view-source-capture-24-20261014-packets.json') -Raw|ConvertFrom-Json
if($taskPackets.records.Count -ne 3 -or $taskPackets.node -cne '24.14.0' -or $taskPackets.native_qualified -or $taskPackets.public_frontend_qualified){throw 'Actual Source packet scope mismatch'}
foreach($taskRecord in $taskPackets.records){
    $taskCount=switch($taskRecord.name){'env-node-view-span'{15};'env-node-view-kernel'{4};'env-node-view-public-getters'{7};default{throw 'Unexpected Source packet'}}
    if($taskRecord.cases -ne $taskCount){throw 'Actual Source packet count mismatch'}
    $taskActualPath=Join-Path $taskReceipt ($taskRecord.name+'-source-data-24-20261014.json')
    $taskExpectedPath=Join-Path $taskRoot ('src/extensions/fixtures/'+$taskRecord.name+'-source-24.json')
    $taskActual=Get-Content -LiteralPath $taskActualPath -Raw|ConvertFrom-Json -AsHashtable|ConvertTo-Json -Depth 40 -Compress
    $taskExpected=Get-Content -LiteralPath $taskExpectedPath -Raw|ConvertFrom-Json -AsHashtable|ConvertTo-Json -Depth 40 -Compress
    if($taskActual -cne $taskExpected){throw "Actual same-platform Source packet mismatch: $($taskRecord.name)"}
}
[ordered]@{head=$ExpectedHead;node=$taskPackets.node;platform=$taskPackets.platform;source_files=$taskOriginalBefore.Count;source_drift=$taskOriginalDrift.Count;observer_drift=$taskBodyDrift.Count;tool_drift=$taskToolDrift;oracle_temp_drift=$taskOracleDrift;records=$taskPackets.records;native_qualified=$false;posix_native=$false;public_frontend_qualified=$false;full_env_qualified=$false;public_activation=$false}|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $taskReceipt 'source-only.json') -Encoding utf8NoBOM

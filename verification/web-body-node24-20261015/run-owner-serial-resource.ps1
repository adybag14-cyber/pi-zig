param(
    [Parameter(Mandatory)][string]$Executable,
    [Parameter(Mandatory)][string]$WorkingDirectory,
    [Parameter(Mandatory)][string[]]$Arguments,
    [Parameter(Mandatory)][string]$ReceiptBase,
    [ValidateSet(300,1320)][int]$TimeoutSeconds=300
)
$ErrorActionPreference='Stop'
if(!$IsWindows){throw 'The serial resource owner requires Windows identity and memory surfaces'}
if(Test-Path -LiteralPath "$ReceiptBase.process.json"){throw 'Refuse serial owner overwrite'}
$taskExe=[IO.Path]::GetFullPath($Executable)
$taskWorkspace=[IO.Path]::GetFullPath($WorkingDirectory)
if($taskExe-match'(?i)codex|node_modules'){throw 'Refuse a host executable as an owned native root'}
function Write-AtomicJson($Value,[string]$Path){
    $taskTemporary="$Path.tmp-$PID"
    $Value|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $taskTemporary -Encoding utf8NoBOM
    Move-Item -LiteralPath $taskTemporary -Destination $Path -Force
}
function Process-Identity($Value){
    [ordered]@{pid=[int]$Value.ProcessId;parent_pid=[int]$Value.ParentProcessId;executable=[string]$Value.ExecutablePath;command_line=[string]$Value.CommandLine;created_utc=$Value.CreationDate.ToUniversalTime().ToString('o')}
}
function Identity-Key($Value){"$($Value.pid)|$($Value.created_utc)"}
function Same-Identity($Recorded,$Current){
    if(!$Current){return $false}
    $taskIdentity=Process-Identity $Current
    return $taskIdentity.pid-eq$Recorded.pid-and$taskIdentity.parent_pid-eq$Recorded.parent_pid-and$taskIdentity.executable-ceq$Recorded.executable-and$taskIdentity.command_line-ceq$Recorded.command_line-and$taskIdentity.created_utc-ceq$Recorded.created_utc
}
$taskNative=@(Get-CimInstance Win32_Process|Where-Object{$_.ExecutablePath-and($_.ExecutablePath.EndsWith('\zig.exe')-or$_.ExecutablePath-like'C:\Users\adyba\pi-zig*\.zig-cache\*\build.exe'-or$_.ExecutablePath-like'C:\Users\adyba\pi-zig*\.zig-cache\*\test.exe')})
$taskAvailable=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory*1024
$taskAdmission=[ordered]@{policy='Root revised serial single-native admission; previous16GiB negatives retained';minimum_available_bytes=12GB;cancel_below_available_bytes=4GB;available_bytes=$taskAvailable;other_native_processes=$taskNative.Count;sample_interval_ms=1000;checked_utc=[DateTimeOffset]::UtcNow.ToString('o')}
Write-AtomicJson $taskAdmission "$ReceiptBase-resource-admission.json"
if($taskAvailable-lt12GB-or$taskNative.Count-ne0){throw 'Serial12GiB/zero-other-native admission rejected before launch'}
$taskStart=[Diagnostics.ProcessStartInfo]::new()
$taskStart.FileName=$taskExe
$taskStart.WorkingDirectory=$taskWorkspace
$taskStart.UseShellExecute=$false
$taskStart.CreateNoWindow=$true
$taskStart.RedirectStandardOutput=$true
$taskStart.RedirectStandardError=$true
foreach($taskArgument in $Arguments){$taskStart.ArgumentList.Add($taskArgument)}
$taskProcess=[Diagnostics.Process]::new()
$taskProcess.StartInfo=$taskStart
$taskLaunched=[DateTimeOffset]::UtcNow.ToString('o')
if(!$taskProcess.Start()){throw 'Serial owned native process failed to start'}
$taskOut=$taskProcess.StandardOutput.ReadToEndAsync()
$taskErr=$taskProcess.StandardError.ReadToEndAsync()
$taskRootLive=Get-CimInstance Win32_Process -Filter "ProcessId=$($taskProcess.Id)"
if(!$taskRootLive){throw 'Native root exited before launch identity capture'}
$taskRoot=Process-Identity $taskRootLive
if($taskRoot.executable-cne$taskExe-or!$taskRoot.command_line){throw 'Native root launch identity mismatch'}
$taskRoot.parent_key=$null
$taskRoot.depth=0
$taskRoot.peak_rss_bytes=0L
$taskOwned=[ordered]@{}
$taskOwned[(Identity-Key $taskRoot)]=$taskRoot
$taskRecord=[ordered]@{pid=$taskRoot.pid;executable=$taskExe;executable_sha256=(Get-FileHash -LiteralPath $taskExe).Hash;argv=@($Arguments);live_command_line=$taskRoot.command_line;created_utc=$taskRoot.created_utc;parent_pid=$taskRoot.parent_pid;launched_utc=$taskLaunched;working_directory=$taskWorkspace;outer_seconds=$TimeoutSeconds;settle_seconds=10;status='running';resource_policy=$taskAdmission;owner_pid=$PID;owner_script_sha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash}
Write-AtomicJson $taskRecord "$ReceiptBase.process.json"
$taskClock=[Diagnostics.Stopwatch]::StartNew()
$taskPeakAggregate=0L
$taskMinimumAvailable=$taskAvailable
$taskSampleCount=0
function Capture-Owned {
    $taskAll=@(Get-CimInstance Win32_Process)
    $taskLiveByPid=@{}
    foreach($taskCurrent in $taskAll){$taskLiveByPid[[int]$taskCurrent.ProcessId]=$taskCurrent}
    do{
        $taskAdded=$false
        foreach($taskCurrent in $taskAll){
            $taskParent=@($taskOwned.Values|Where-Object{$_.pid-eq$taskCurrent.ParentProcessId-and(Same-Identity $_ $taskLiveByPid[[int]$_.pid])})
            if($taskParent.Count-ne1){continue}
            $taskIdentity=Process-Identity $taskCurrent
            $taskKey=Identity-Key $taskIdentity
            if($taskOwned.Contains($taskKey)){continue}
            if(!$taskIdentity.executable-or!$taskIdentity.command_line-or$taskIdentity.executable-match'(?i)codex|@openai|node_modules'){
                throw 'Unverifiable or host descendant; refusing ownership/control'
            }
            if([DateTimeOffset]::Parse($taskIdentity.created_utc).UtcDateTime-lt[DateTimeOffset]::Parse($taskParent[0].created_utc).UtcDateTime){throw 'Descendant predates its owned parent'}
            $taskIdentity.parent_key=Identity-Key $taskParent[0]
            $taskIdentity.depth=$taskParent[0].depth+1
            $taskIdentity.peak_rss_bytes=0L
            $taskOwned[$taskKey]=$taskIdentity
            $taskAdded=$true
        }
    }while($taskAdded)
    $taskAggregate=0L
    $taskLiveCount=0
    foreach($taskIdentity in $taskOwned.Values){
        if(!(Same-Identity $taskIdentity $taskLiveByPid[[int]$taskIdentity.pid])){continue}
        $taskLiveCount++
        $taskRss=[long]$taskLiveByPid[[int]$taskIdentity.pid].WorkingSetSize
        # Windows reports the lifetime peak for each still-live exact identity;
        # aggregate RSS is sampled, rather than represented as an OS peak.
        $taskPeakRss=$taskRss
        $taskMetrics=Get-Process -Id $taskIdentity.pid -ErrorAction SilentlyContinue
        if($taskMetrics-and(Same-Identity $taskIdentity (Get-CimInstance Win32_Process -Filter "ProcessId=$($taskIdentity.pid)"))){
            $taskPeakRss=[Math]::Max($taskPeakRss,$taskMetrics.PeakWorkingSet64)
        }
        $taskIdentity.peak_rss_bytes=[Math]::Max($taskIdentity.peak_rss_bytes,$taskPeakRss)
        $taskAggregate+=$taskRss
    }
    [pscustomobject]@{aggregate_rss_bytes=$taskAggregate;live_count=$taskLiveCount}
}
function Retained-Ancestry($Identity){
    $taskCursor=$Identity
    $taskDepth=0
    while($taskCursor.parent_key){
        if(!$taskOwned.Contains($taskCursor.parent_key)){return $false}
        $taskParent=$taskOwned[$taskCursor.parent_key]
        if($taskParent.pid-ne$taskCursor.parent_pid-or$taskParent.depth-ne$taskCursor.depth-1){return $false}
        $taskCursor=$taskParent
        $taskDepth++
        if($taskDepth-gt100){return $false}
    }
    return (Identity-Key $taskCursor)-ceq(Identity-Key $taskRoot)
}
function Stop-VerifiedOwned {
    for($taskRound=0;$taskRound-lt5;$taskRound++){
        $null=Capture-Owned
        foreach($taskIdentity in @($taskOwned.Values|Sort-Object depth -Descending)){
            $taskCurrent=Get-CimInstance Win32_Process -Filter "ProcessId=$($taskIdentity.pid)"
            if(!$taskCurrent){continue}
            if(!(Same-Identity $taskIdentity $taskCurrent)){continue} # Reused PID is unrelated.
            if(!(Retained-Ancestry $taskIdentity)-or$taskIdentity.executable-match'(?i)codex|@openai|node_modules'){throw 'Owned cancellation ancestry/host safety rejection'}
            Stop-Process -Id $taskIdentity.pid -Force -ErrorAction Stop
        }
        $null=$taskProcess.WaitForExit(250)
        if((Capture-Owned).live_count-eq0){break}
    }
    $taskSettle=[Diagnostics.Stopwatch]::StartNew()
    do{
        $taskRemaining=@($taskOwned.Values|Where-Object{Same-Identity $_ (Get-CimInstance Win32_Process -Filter "ProcessId=$($_.pid)")})
        if(!$taskRemaining.Count){break}
        Start-Sleep -Milliseconds 100
    }while($taskSettle.Elapsed.TotalSeconds-lt10)
    if($taskRemaining.Count){throw 'Exact owned identities remained after bounded cancellation'}
}
$taskReason=$null
$taskMonitorError=$null
try{
    while($true){
        $taskSample=Capture-Owned
        $taskAvailable=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory*1024
        $taskPeakAggregate=[Math]::Max($taskPeakAggregate,$taskSample.aggregate_rss_bytes)
        $taskMinimumAvailable=[Math]::Min($taskMinimumAvailable,$taskAvailable)
        $taskSampleCount++
        [ordered]@{utc=[DateTimeOffset]::UtcNow.ToString('o');elapsed_seconds=$taskClock.Elapsed.TotalSeconds;available_bytes=$taskAvailable;aggregate_owned_rss_bytes=$taskSample.aggregate_rss_bytes;live_owned_processes=$taskSample.live_count;retained_owned_identities=$taskOwned.Count}|ConvertTo-Json -Compress|Add-Content -LiteralPath "$ReceiptBase-resource-samples.jsonl" -Encoding utf8NoBOM
        Write-AtomicJson @($taskOwned.Values) "$ReceiptBase-owned-identities.json"
        if($taskProcess.HasExited){break}
        if($taskAvailable-lt4GB){$taskReason='resource_failure_available_below4GiB';break}
        if($taskClock.Elapsed.TotalSeconds-ge$TimeoutSeconds){$taskReason='timed_out';break}
        $null=$taskProcess.WaitForExit(1000)
    }
}catch{$taskMonitorError=$_;$taskReason='resource_monitor_failure'}
if($taskReason){
    $taskRecord.status='cancelling'
    $taskRecord.cancellation_reason=$taskReason
    Write-AtomicJson $taskRecord "$ReceiptBase.process.json"
    try{Stop-VerifiedOwned}catch{$taskMonitorError=$_;$taskRecord.status='cancelled_unsettled'}
}
$taskTerminalSettle=[Diagnostics.Stopwatch]::StartNew()
do{
    $taskTerminalSample=Capture-Owned
    if($taskTerminalSample.live_count-eq0){break}
    Start-Sleep -Milliseconds 100
}while($taskTerminalSettle.Elapsed.TotalSeconds-lt10)
$taskAbsence=@($taskOwned.Values|ForEach-Object{
    $taskCurrent=Get-CimInstance Win32_Process -Filter "ProcessId=$($_.pid)"
    [ordered]@{identity=$_;same_owned_identity_present=(Same-Identity $_ $taskCurrent);pid_absent=($null-eq$taskCurrent);reused_pid_present=($null-ne$taskCurrent-and!(Same-Identity $_ $taskCurrent))}
})
Write-AtomicJson $taskAbsence "$ReceiptBase-owned-absence.json"
Write-AtomicJson ([ordered]@{sample_count=$taskSampleCount;root_peak_rss_bytes=$taskRoot.peak_rss_bytes;aggregate_owned_sampled_peak_rss_bytes=$taskPeakAggregate;minimum_available_bytes=$taskMinimumAvailable;owned_identities=@($taskOwned.Values);cancellation_reason=$taskReason;monitor_error=$(if($taskMonitorError){[string]$taskMonitorError}else{$null})}) "$ReceiptBase-resource-summary.json"
if(!$taskProcess.HasExited-or@($taskAbsence|Where-Object same_owned_identity_present).Count){
    $taskRecord.status='cancelled_unsettled'
}else{
    [IO.File]::WriteAllText("$ReceiptBase.stdout.log",$taskOut.GetAwaiter().GetResult())
    [IO.File]::WriteAllText("$ReceiptBase.stderr.log",$taskErr.GetAwaiter().GetResult())
    $taskRecord.exit_code=$taskProcess.ExitCode
    $taskRecord.status=if($taskReason){$taskReason}elseif($taskProcess.ExitCode-eq0){'passed'}else{'failed'}
}
$taskRecord.completed_utc=[DateTimeOffset]::UtcNow.ToString('o')
Write-AtomicJson $taskRecord "$ReceiptBase.process.json"
Write-Output ($taskRecord|ConvertTo-Json -Depth 8)
if($taskRecord.status-cne'passed'){throw "Serial native terminal $($taskRecord.status)"}

param(
    [Parameter(Mandatory)][string]$Executable,
    [Parameter(Mandatory)][string]$WorkingDirectory,
    [Parameter(Mandatory)][string[]]$Arguments,
    [Parameter(Mandatory)][string]$ReceiptBase,
    [ValidateSet(300,1320)][int]$TimeoutSeconds=300
)
$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath "$ReceiptBase.process.json") { throw 'Refuse native owner overwrite' }
$taskStart = [Diagnostics.ProcessStartInfo]::new()
$taskStart.FileName = [IO.Path]::GetFullPath($Executable)
$taskStart.WorkingDirectory = $WorkingDirectory
$taskStart.UseShellExecute = $false
$taskStart.CreateNoWindow = $true
$taskStart.RedirectStandardOutput = $true
$taskStart.RedirectStandardError = $true
foreach ($taskArgument in $Arguments) { $taskStart.ArgumentList.Add($taskArgument) }
$taskHash = (Get-FileHash -LiteralPath $taskStart.FileName).Hash
$taskProcess = [Diagnostics.Process]::new()
$taskProcess.StartInfo = $taskStart
$taskLaunched = [DateTimeOffset]::UtcNow.ToString('o')
if (!$taskProcess.Start()) { throw 'Owned native process failed to start' }
$taskCreated = $taskProcess.StartTime.ToUniversalTime()
$taskLiveArgv = if ($IsWindows) { (Get-CimInstance Win32_Process -Filter "ProcessId = $($taskProcess.Id)").CommandLine } else { ((& /bin/ps -p $taskProcess.Id -o command=) -join "`n").Trim() }
$taskRecord = [ordered]@{pid=$taskProcess.Id;executable=$taskStart.FileName;executable_sha256=$taskHash;argv=@($Arguments);live_command_line=$taskLiveArgv;created_utc=$taskCreated.ToString('o');launched_utc=$taskLaunched;working_directory=$WorkingDirectory;outer_seconds=$TimeoutSeconds;settle_seconds=10;status='running'}
$taskRecord | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath "$ReceiptBase.process.json"
$taskOut = $taskProcess.StandardOutput.ReadToEndAsync()
$taskErr = $taskProcess.StandardError.ReadToEndAsync()
$taskFinished = $taskProcess.WaitForExit($TimeoutSeconds*1000)
if (!$taskFinished) {
    $taskLive = Get-Process -Id $taskProcess.Id -ErrorAction SilentlyContinue
    if (!$taskLive -or $taskLive.Path -cne $taskStart.FileName -or $taskLive.StartTime.ToUniversalTime().Ticks -ne $taskCreated.Ticks) { throw 'Native timeout identity mismatch; refusing termination' }
    $taskCurrentArgv = if ($IsWindows) { (Get-CimInstance Win32_Process -Filter "ProcessId = $($taskProcess.Id)").CommandLine } else { ((& /bin/ps -p $taskProcess.Id -o command=) -join "`n").Trim() }
    if (!$taskLiveArgv -or $taskCurrentArgv -cne $taskLiveArgv -or $taskStart.FileName -match 'codex') { throw 'Native command identity mismatch; refusing termination' }
    $taskProcess.Kill($true)
    if (!$taskProcess.WaitForExit(10000)) {
        $taskRecord.status='timed_out_unsettled';$taskRecord.completed_utc=[DateTimeOffset]::UtcNow.ToString('o')
        $taskRecord | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath "$ReceiptBase.process.json"
        throw 'Owned native process failed to settle within10seconds'
    }
}
[IO.File]::WriteAllText("$ReceiptBase.stdout.log",$taskOut.GetAwaiter().GetResult())
[IO.File]::WriteAllText("$ReceiptBase.stderr.log",$taskErr.GetAwaiter().GetResult())
$taskRecord.status = if (!$taskFinished) { 'timed_out' } elseif ($taskProcess.ExitCode -eq 0) { 'passed' } else { 'failed' }
$taskRecord.exit_code=$taskProcess.ExitCode;$taskRecord.completed_utc=[DateTimeOffset]::UtcNow.ToString('o')
$taskRemaining=Get-CimInstance Win32_Process -Filter "ProcessId = $($taskProcess.Id)" -ErrorAction SilentlyContinue
$taskRecord.owned_identity_absent=(!$taskRemaining -or $taskRemaining.ExecutablePath-cne$taskStart.FileName -or ([DateTimeOffset]$taskRemaining.CreationDate).UtcDateTime.Ticks-ne$taskCreated.Ticks)
if(!$taskRecord.owned_identity_absent){$taskRecord.status='owned_identity_remaining'}
$taskRecord | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath "$ReceiptBase.process.json"
Write-Output ($taskRecord | ConvertTo-Json -Depth 5)
if ($taskRecord.status -cne 'passed') { throw "Native terminal $($taskRecord.status)" }

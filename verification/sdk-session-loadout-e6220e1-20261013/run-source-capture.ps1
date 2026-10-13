param(
    [Parameter(Mandatory)][string]$Executable,
    [Parameter(Mandatory)][string]$WorkingDirectory,
    [Parameter(Mandatory)][string[]]$Arguments,
    [Parameter(Mandatory)][string]$ReceiptBase
)
$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath "$ReceiptBase.process.json") { throw 'Refuse capture owner overwrite' }
$taskStart = [Diagnostics.ProcessStartInfo]::new()
$taskStart.FileName = [IO.Path]::GetFullPath($Executable)
$taskStart.WorkingDirectory = $WorkingDirectory
$taskStart.UseShellExecute = $false
$taskStart.CreateNoWindow = $true
$taskStart.RedirectStandardOutput = $true
$taskStart.RedirectStandardError = $true
foreach ($taskArgument in $Arguments) { $taskStart.ArgumentList.Add($taskArgument) }
$taskProcess = [Diagnostics.Process]::new()
$taskProcess.StartInfo = $taskStart
$taskHash = (Get-FileHash -LiteralPath $taskStart.FileName).Hash
$taskLaunched = [DateTimeOffset]::UtcNow.ToString('o')
if (!$taskProcess.Start()) { throw 'Owned Source process failed to start' }
$taskCreated = $taskProcess.StartTime.ToUniversalTime()
$taskLiveArgv = ((& ps -p $taskProcess.Id -o command=) -join "`n").Trim()
$taskRecord = [ordered]@{
    pid=$taskProcess.Id; executable=$taskStart.FileName; executable_sha256=$taskHash
    argv=@($Arguments); live_command_line=$taskLiveArgv; command_line_source='Exact ProcessStartInfo argv and live ps command'
    created_utc=$taskCreated.ToString('o'); launched_utc=$taskLaunched
    working_directory=$WorkingDirectory; outer_seconds=300; settle_seconds=10; status='running'
}
$taskRecord | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath "$ReceiptBase.process.json"
$taskOut = $taskProcess.StandardOutput.ReadToEndAsync()
$taskErr = $taskProcess.StandardError.ReadToEndAsync()
$taskFinished = $taskProcess.WaitForExit(300000)
if (!$taskFinished) {
    $taskLive = Get-Process -Id $taskProcess.Id -ErrorAction SilentlyContinue
    if (!$taskLive -or $taskLive.Path -cne $taskStart.FileName -or $taskLive.StartTime.ToUniversalTime().Ticks -ne $taskCreated.Ticks) { throw 'Owned Source timeout PID/executable/starttime mismatch; refusing termination' }
    $taskCurrentArgv = ((& ps -p $taskProcess.Id -o command=) -join "`n").Trim()
    if (!$taskLiveArgv -or $taskCurrentArgv -cne $taskLiveArgv -or $taskStart.FileName -match 'codex') { throw 'Owned Source command identity mismatch; refusing termination' }
    $taskProcess.Kill($true)
    if (!$taskProcess.WaitForExit(10000)) {
        $taskRecord.status = 'timed_out_unsettled'
        $taskRecord.completed_utc = [DateTimeOffset]::UtcNow.ToString('o')
        $taskRecord | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath "$ReceiptBase.process.json"
        throw 'Owned Source process did not settle within10seconds'
    }
}
[IO.File]::WriteAllText("$ReceiptBase.stdout.log", $taskOut.GetAwaiter().GetResult())
[IO.File]::WriteAllText("$ReceiptBase.stderr.log", $taskErr.GetAwaiter().GetResult())
$taskRecord.status = if (!$taskFinished) { 'timed_out' } elseif ($taskProcess.ExitCode -eq 0) { 'passed' } else { 'failed' }
$taskRecord.exit_code = $taskProcess.ExitCode
$taskRecord.completed_utc = [DateTimeOffset]::UtcNow.ToString('o')
$taskRecord | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath "$ReceiptBase.process.json"
Write-Output ($taskRecord | ConvertTo-Json -Depth 5)
if ($taskRecord.status -cne 'passed') { throw "Original Source capture terminal $($taskRecord.status)" }

$ErrorActionPreference='Stop'
$taskRoot='C:/Users/adyba/pi-zig-chord-full-composition-e6220e1-20261013'
$taskManifest=Join-Path $PSScriptRoot 'chord-composition-apply-releasesafe-first-20261013-source-before.json'
$taskRows=@(Get-Content -LiteralPath $taskManifest -Raw|ConvertFrom-Json)
$taskHead=(git -C $taskRoot rev-parse HEAD).Trim()
$taskGit=(Get-Command git).Source
$taskStart=[Diagnostics.ProcessStartInfo]::new()
$taskStart.FileName=$taskGit
$taskStart.WorkingDirectory=$taskRoot
$taskStart.UseShellExecute=$false
$taskStart.CreateNoWindow=$true
$taskStart.RedirectStandardInput=$true
$taskStart.RedirectStandardOutput=$true
$taskStart.RedirectStandardError=$true
$taskStart.ArgumentList.Add('cat-file')
$taskStart.ArgumentList.Add('--batch')
$taskProcess=[Diagnostics.Process]::Start($taskStart)
$taskCreated=$taskProcess.StartTime.ToUniversalTime().ToString('o')
$taskError=$taskProcess.StandardError.ReadToEndAsync()
$taskOutput=$taskProcess.StandardOutput.BaseStream
$taskBuffer=[byte[]]::new(65536)
$taskDrift=[Collections.Generic.List[string]]::new()
$taskCount=0
try {
 foreach($row in $taskRows){
  $taskProcess.StandardInput.WriteLine("${taskHead}:$($row.path)")
  $taskProcess.StandardInput.Flush()
  $taskHeader=[Collections.Generic.List[byte]]::new()
  while(($taskByte=$taskOutput.ReadByte()) -ne 10){if($taskByte -lt 0){throw 'Unexpected git batch EOF'};$taskHeader.Add([byte]$taskByte)}
  $taskHeaderText=[Text.Encoding]::UTF8.GetString($taskHeader.ToArray())
  if($taskHeaderText -notmatch '^[0-9a-f]{40} blob ([0-9]+)$'){throw "Missing committed Source blob: $($row.path)"}
  $taskRemaining=[long]$Matches[1]
  $taskHash=[Security.Cryptography.IncrementalHash]::CreateHash([Security.Cryptography.HashAlgorithmName]::SHA256)
  try {
   while($taskRemaining -gt 0){
    $taskRead=$taskOutput.Read($taskBuffer,0,[int][Math]::Min($taskBuffer.Length,$taskRemaining))
    if($taskRead -le 0){throw 'Incomplete committed Source blob'}
    $taskHash.AppendData($taskBuffer,0,$taskRead)
    $taskRemaining-=$taskRead
   }
   $taskActual=[Convert]::ToHexString($taskHash.GetHashAndReset())
  } finally {$taskHash.Dispose()}
  if($taskOutput.ReadByte() -ne 10){throw 'Malformed git batch boundary'}
  if($taskActual -cne $row.sha256){$taskDrift.Add($row.path)}
  $taskCount++
 }
} finally {
 $taskProcess.StandardInput.Close()
 if(!$taskProcess.WaitForExit(10000)){throw 'Owned git batch did not settle within10s after EOF'}
}
$taskErrorText=$taskError.GetAwaiter().GetResult()
if($taskProcess.ExitCode -ne 0 -or $taskErrorText){throw 'Committed byte reader failed'}
$taskResult=[ordered]@{status=if($taskDrift.Count){'failed'}else{'passed'};head=$taskHead;tree=(git -C $taskRoot rev-parse 'HEAD^{tree}').Trim();release_safe_source_manifest=$taskManifest;manifest_sha256=(Get-FileHash -LiteralPath $taskManifest).Hash;committed_blobs_checked=$taskCount;committed_byte_drift=$taskDrift.Count;drift=@($taskDrift);reader_pid=$taskProcess.Id;reader_created_utc=$taskCreated;reader_executable=$taskGit;reader_executable_sha256=(Get-FileHash -LiteralPath $taskGit).Hash;reader_command='git cat-file --batch';reader_exit_code=$taskProcess.ExitCode;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}
$taskResult|ConvertTo-Json -Depth 5|Tee-Object -FilePath (Join-Path $PSScriptRoot 'chord-apply-committed-rs-bytes-20261013.json')
$taskProcess.Dispose()
if($taskDrift.Count){throw 'Committed source differs from successful ReleaseSafe bytes'}




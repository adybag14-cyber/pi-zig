param([Parameter(Mandatory)][string]$Attempt,[Parameter(Mandatory)][string]$RootGrant)
$ErrorActionPreference='Stop'
$chordRoot='C:/Users/adyba/pi-zig-chord-v4-full-graph-b45-20261014'
$chordEvidence=$PSScriptRoot
$chordName="chord-v4-shared-debug-compile-$Attempt-20261014"
$chordZig='C:/Users/adyba/pi-zig-toolchain-20261003/zig-x86_64-windows-0.16.0/zig.exe'
if(Test-Path -LiteralPath (Join-Path $chordEvidence "$chordName.json")){throw 'Refuse owned native receipt replay'}
if((git -C $chordRoot rev-parse HEAD).Trim() -cne '73b4b80f04823036480de4639e78415b22449bde'){throw 'Exact reviewed complete partition source head changed'}
function Source-Rows {
 @(git -C $chordRoot ls-files --cached --others --exclude-standard|Sort-Object -Unique|Where-Object{Test-Path -LiteralPath (Join-Path $chordRoot $_) -PathType Leaf}|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath (Join-Path $chordRoot $_)).Hash}})
}
function Check-Rows($rows,[string]$root) {
 $drift=[Collections.Generic.List[string]]::new()
 foreach($row in $rows){
  $path=if([IO.Path]::IsPathRooted($row.path)){$row.path}else{Join-Path $root $row.path}
  if(!(Test-Path -LiteralPath $path -PathType Leaf)){$drift.Add($path);continue}
  $stream=[IO.File]::OpenRead($path)
  try{$hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream))}finally{$stream.Dispose()}
  if($hash -cne $row.sha256){$drift.Add($path)}
 }
 @($drift)
}
$chordBefore=Source-Rows
$chordBefore|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $chordEvidence "$chordName-source-before.json") -Encoding utf8NoBOM
$chordToolManifest=Join-Path $chordEvidence 'durable-latest89-full-inspect-53ae-tool-prehash-20261011.json'
$chordTools=(Get-Content -LiteralPath $chordToolManifest -Raw|ConvertFrom-Json).inputs
$chordToolBefore=@(Check-Rows $chordTools '')
if($chordToolBefore.Count){throw 'Full pinned compiler prehash drift'}
$chordToolInventory=@(Get-ChildItem -LiteralPath (Split-Path -Parent $chordZig) -File -Recurse|ForEach-Object FullName|Sort-Object)
if(Compare-Object @($chordTools.path|Sort-Object) $chordToolInventory){throw 'Full compiler file inventory drift'}
$chordSourceManifest=Join-Path $chordEvidence 'sdk-source-b45-full-manifest-20261014.json'
$chordSourceData=Get-Content -LiteralPath $chordSourceManifest -Raw|ConvertFrom-Json
$chordSourceInputs=if($chordSourceData -is [array]){@($chordSourceData)}elseif($chordSourceData.inputs){@($chordSourceData.inputs)}elseif($chordSourceData.files -is [array]){@($chordSourceData.files)}else{@($chordSourceData)}
$chordOriginalBefore=@(Check-Rows $chordSourceInputs 'C:/Users/adyba/pi-upstream-source-b45e0eb-20261014')
if($chordSourceInputs.Count -ne 1965 -or $chordOriginalBefore.Count){throw 'Actual original Source authority drift'}
$chordControlPaths=@($PSCommandPath,$chordToolManifest,$chordSourceManifest)
$chordControls=@($chordControlPaths|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})
if((Get-FileHash -LiteralPath $chordZig).Hash -cne '086CE9D47BA42F33A514E1A6E04EB1D4A8FA1D75E0868E0213CAAD447C91E864'){throw 'Pinned Zig executable changed'}
[GC]::Collect();[GC]::WaitForPendingFinalizers();[GC]::Collect()
$chordOtherNative=@(Get-CimInstance Win32_Process -Filter "Name = 'zig.exe'"|Select-Object ProcessId,ParentProcessId,ExecutablePath,CommandLine,@{n='created_utc';e={([DateTimeOffset]$_.CreationDate).UtcDateTime.ToString('o')}})
$chordOtherRoots=@($chordOtherNative|Where-Object{$_.CommandLine -match 'zig(?:\.exe)?"?\s+build\s'})
$chordFree=[long](Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory*1024
$chordAdmission=[ordered]@{observed_utc=[DateTimeOffset]::UtcNow.ToString('o');free_bytes=$chordFree;required_bytes=16GB;other_native=$chordOtherNative;source_inputs=$chordBefore.Count;original_source_inputs=$chordSourceInputs.Count;compiler_inputs=$chordTools.Count;normal_floor=$true;sole8_exception_used=$false;root_authority=$RootGrant;compile_seconds=1320;runtime_authorized=$false;jobs=1;llvm='default';compiler_peak_calibrated=$false;public_activation=$false}
$chordAdmission|ConvertTo-Json -Depth 7|Set-Content -LiteralPath (Join-Path $chordEvidence "$chordName-admission.json") -Encoding utf8NoBOM
if($chordFree -lt 16GB -or $chordOtherRoots.Count -gt 1){throw 'Fresh normal16GiB or max2 native admission rejected; no Zig launched'}
$chordArguments=@('build','build-native-chord-contracts-v4-source','build-native-chord-cells-v4-source','build-native-chord-shared-v4-source','-Doptimize=Debug','-j1','--summary','all')
$chordStart=[Diagnostics.ProcessStartInfo]::new()
$chordStart.FileName=$chordZig;$chordStart.WorkingDirectory=$chordRoot;$chordStart.UseShellExecute=$false;$chordStart.CreateNoWindow=$true;$chordStart.RedirectStandardOutput=$true;$chordStart.RedirectStandardError=$true
foreach($argument in $chordArguments){$chordStart.ArgumentList.Add($argument)}
$chordProcess=[Diagnostics.Process]::Start($chordStart)
$chordCreated=$chordProcess.StartTime.ToUniversalTime()
$chordIdentity=Get-CimInstance Win32_Process -Filter "ProcessId = $($chordProcess.Id)"
$chordOwner=[ordered]@{head=(git -C $chordRoot rev-parse HEAD).Trim();name=$chordName;pid=$chordProcess.Id;created_utc=$chordCreated.ToString('o');executable=$chordZig;executable_sha256=(Get-FileHash -LiteralPath $chordZig).Hash;command_line=$chordIdentity.CommandLine;argv=$chordArguments;working_directory=$chordRoot;status='running';deadline_seconds=1320;jobs=1;phase='compile_only';runtime_authorized=$false;compiler_peak_calibrated=$false}
$chordOwner|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $chordEvidence "$chordName.json") -Encoding utf8NoBOM
$chordOut=$chordProcess.StandardOutput.ReadToEndAsync();$chordErr=$chordProcess.StandardError.ReadToEndAsync()
$chordWatch=[Diagnostics.Stopwatch]::StartNew();$chordFinished=$false;$chordObserved=[Collections.Generic.HashSet[uint32]]::new();[void]$chordObserved.Add([uint32]$chordProcess.Id)
$chordPeak=[Collections.Generic.Dictionary[uint32,long]]::new();$chordSamples=Join-Path $chordEvidence "$chordName-rss-samples.jsonl"
while($chordWatch.Elapsed.TotalSeconds -lt 1320){
 if($chordProcess.WaitForExit(1000)){$chordFinished=$true;break}
 $sampleProcesses=@(Get-CimInstance Win32_Process -Filter "Name = 'zig.exe' OR Name = 'build.exe'")
 foreach($sample in $sampleProcesses){if($chordObserved.Contains([uint32]$sample.ParentProcessId)){[void]$chordObserved.Add([uint32]$sample.ProcessId)}}
 foreach($sample in $sampleProcesses){if($chordObserved.Contains([uint32]$sample.ProcessId)){
  $bytes=[long]$sample.WorkingSetSize
  if(!$chordPeak.ContainsKey([uint32]$sample.ProcessId) -or $bytes -gt $chordPeak[[uint32]$sample.ProcessId]){$chordPeak[[uint32]$sample.ProcessId]=$bytes}
  [ordered]@{utc=[DateTimeOffset]::UtcNow.ToString('o');pid=$sample.ProcessId;parent=$sample.ParentProcessId;exe=$sample.ExecutablePath;created_utc=([DateTimeOffset]$sample.CreationDate).UtcDateTime.ToString('o');command_line=$sample.CommandLine;working_set_bytes=$bytes;private_page_bytes=[long]$sample.PrivatePageCount}|ConvertTo-Json -Compress|Add-Content -LiteralPath $chordSamples -Encoding utf8NoBOM
 }}
}
if(!$chordFinished -and !$chordProcess.HasExited){
 $live=Get-CimInstance Win32_Process -Filter "ProcessId = $($chordProcess.Id)"
 if(!$live -or ![StringComparer]::OrdinalIgnoreCase.Equals([IO.Path]::GetFullPath($live.ExecutablePath),[IO.Path]::GetFullPath($chordZig)) -or $live.CommandLine -cne $chordIdentity.CommandLine -or [Math]::Abs((([DateTimeOffset]$live.CreationDate).UtcDateTime-$chordCreated).Ticks) -gt 10 -or $live.ExecutablePath -match 'codex'){throw 'Owned compile deadline identity changed; refusing termination'}
 $chordProcess.Kill($true);if(!$chordProcess.WaitForExit(10000)){throw 'Owned compile did not terminate'}
}
[IO.File]::WriteAllText((Join-Path $chordEvidence "$chordName.stdout.log"),$chordOut.GetAwaiter().GetResult());[IO.File]::WriteAllText((Join-Path $chordEvidence "$chordName.stderr.log"),$chordErr.GetAwaiter().GetResult())
$chordOwner.status=if(!$chordFinished){'timed_out'}elseif($chordProcess.ExitCode -eq 0){'passed'}else{'failed'};$chordOwner.exit_code=$chordProcess.ExitCode;$chordOwner.elapsed_seconds=$chordWatch.Elapsed.TotalSeconds;$chordOwner.root_peak_working_set_bytes=$chordProcess.PeakWorkingSet64;$chordOwner.sampled_process_peak_bytes=@($chordPeak.GetEnumerator()|ForEach-Object{[ordered]@{pid=$_.Key;observed_peak_bytes=$_.Value}});$chordOwner.peak_scope='One-second sampled exact descendant ancestry RSS is a lower bound; root kernel peak separate; compiler not calibrated';$chordOwner.completed_utc=[DateTimeOffset]::UtcNow.ToString('o')
$chordOwner|ConvertTo-Json -Depth 7|Set-Content -LiteralPath (Join-Path $chordEvidence "$chordName.json") -Encoding utf8NoBOM
$chordProcess.Dispose()
$chordAfter=Source-Rows
$chordDrift=@(Compare-Object @($chordBefore|ForEach-Object{"$($_.path):$($_.sha256)"}) @($chordAfter|ForEach-Object{"$($_.path):$($_.sha256)"}))
$chordToolAfter=@(Check-Rows $chordTools '');$chordOriginalAfter=@(Check-Rows $chordSourceInputs 'C:/Users/adyba/pi-upstream-source-b45e0eb-20261014');$chordControlAfter=@(Check-Rows $chordControls '')
$chordToolNamesAfter=@(Get-ChildItem -LiteralPath (Split-Path -Parent $chordZig) -File -Recurse|ForEach-Object FullName|Sort-Object)
$chordToolNamesDrift=@(Compare-Object $chordToolInventory $chordToolNamesAfter)
$chordPost=[ordered]@{head=$chordOwner.head;status=$chordOwner.status;exit_code=$chordOwner.exit_code;source_before=$chordBefore.Count;source_after=$chordAfter.Count;source_drift=$chordDrift.Count;compiler_count=$chordTools.Count;compiler_drift=$chordToolAfter.Count;compiler_inventory_drift=$chordToolNamesDrift.Count;original_source_count=$chordSourceInputs.Count;original_source_drift=$chordOriginalAfter.Count;control_drift=$chordControlAfter.Count;root_pid_absent=!(Get-CimInstance Win32_Process -Filter "ProcessId = $($chordOwner.pid)");runtime_executed=$false;public_activation=$false;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}
$chordPost|ConvertTo-Json -Depth 7|Set-Content -LiteralPath (Join-Path $chordEvidence "$chordName-posthash.json") -Encoding utf8NoBOM
$chordPost|ConvertTo-Json -Depth 5
if($chordDrift.Count -or $chordToolAfter.Count -or $chordToolNamesDrift.Count -or $chordOriginalAfter.Count -or $chordControlAfter.Count){throw 'Full compile freeze changed'}
if($chordOwner.status -cne 'passed'){throw 'Compile-only terminal failed; runtime remains prohibited'}

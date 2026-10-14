param([ValidateSet('Freeze','Compile','Run','Post')][string]$Phase,[Parameter(Mandatory)][string]$ExpectedHead)
$Mode='Debug';$Platform='macos-latest'
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Assert-ChordComposedPartitions.ps1')
$candidateReceipt='verification/native-chord-resource-mac-partition-candidate'
function Hash-Rows($paths) { @($paths|Sort-Object|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash}}) }
function Check-Rows($rows) { @($rows|Where-Object{!(Test-Path -LiteralPath $_.path -PathType Leaf) -or (Get-FileHash -LiteralPath $_.path -Algorithm SHA256).Hash -cne $_.sha256}) }
function Owned-Process([string]$Name,[string[]]$Arguments,[int]$Deadline) {
 $candidateSource=Get-Content "$candidateReceipt/source.json" -Raw|ConvertFrom-Json
 $candidateStart=[Diagnostics.ProcessStartInfo]::new()
 $candidateStart.FileName=$candidateSource.zig
 $candidateStart.WorkingDirectory=(Get-Location).Path
 $candidateStart.UseShellExecute=$false
 $candidateStart.CreateNoWindow=$true
 $candidateStart.RedirectStandardOutput=$true
 $candidateStart.RedirectStandardError=$true
 foreach($candidateArgument in $Arguments){$candidateStart.ArgumentList.Add($candidateArgument)}
 $candidateProcess=[Diagnostics.Process]::Start($candidateStart)
 $candidateCreated=$candidateProcess.StartTime.ToUniversalTime()
 $candidateCim=if($IsWindows){Get-CimInstance Win32_Process -Filter "ProcessId = $($candidateProcess.Id)"}else{$null}
 $candidateOwner=[ordered]@{name=$Name;status='running';head=$ExpectedHead;pid=$candidateProcess.Id;created_utc=$candidateCreated.ToString('o');executable=$candidateStart.FileName;executable_sha256=$candidateSource.zig_sha256;argv=$Arguments;command_line=if($candidateCim){$candidateCim.CommandLine}else{$candidateStart.FileName+' '+($Arguments -join ' ')};identity='Retained kernel Process handle and exact ProcessStartInfo argv, plus live Windows CIM when available';deadline_seconds=$Deadline;test_timeout_seconds=120;host_await_seconds=10;jobs=1;llvm='default';compiler_peak_calibrated=$false}
 $candidateOwner|ConvertTo-Json -Depth 6|Set-Content "$candidateReceipt/$Name-owner.json" -Encoding utf8NoBOM
 $candidateStdout=$candidateProcess.StandardOutput.ReadToEndAsync()
 $candidateStderr=$candidateProcess.StandardError.ReadToEndAsync()
 $candidateFinished=$candidateProcess.WaitForExit($Deadline*1000)
 if(!$candidateFinished -and !$candidateProcess.HasExited){
  if($candidateStart.FileName -match 'codex' -or $candidateProcess.StartTime.ToUniversalTime() -ne $candidateCreated -or ![StringComparer]::OrdinalIgnoreCase.Equals([IO.Path]::GetFullPath($candidateProcess.MainModule.FileName),[IO.Path]::GetFullPath($candidateStart.FileName))){throw 'Owned deadline identity changed, refusing termination'}
  if($IsWindows){
   $candidateCurrent=Get-CimInstance Win32_Process -Filter "ProcessId = $($candidateProcess.Id)"
   if(!$candidateCurrent -or ![StringComparer]::OrdinalIgnoreCase.Equals([IO.Path]::GetFullPath($candidateCurrent.ExecutablePath),[IO.Path]::GetFullPath($candidateStart.FileName)) -or [Math]::Abs((([DateTimeOffset]$candidateCurrent.CreationDate).UtcDateTime-$candidateCreated).Ticks) -gt 10 -or ($candidateCim -and $candidateCurrent.CommandLine -cne $candidateCim.CommandLine)){throw 'Owned Windows deadline identity changed, refusing termination'}
  }
  $candidateProcess.Kill($true)
  if(!$candidateProcess.WaitForExit(10000)){throw 'Owned job did not settle after exact termination'}
 }
 $candidateOut=$candidateStdout.GetAwaiter().GetResult()
 $candidateErr=$candidateStderr.GetAwaiter().GetResult()
 [IO.File]::WriteAllText((Join-Path (Get-Location) "$candidateReceipt/$Name.stdout.log"),$candidateOut)
 [IO.File]::WriteAllText((Join-Path (Get-Location) "$candidateReceipt/$Name.stderr.log"),$candidateErr)
 $candidateOwner.status=if(!$candidateFinished){'timed_out'}elseif($candidateProcess.ExitCode -eq 0){'passed'}else{'failed'}
 $candidateOwner.exit_code=$candidateProcess.ExitCode
 try{$candidateOwner.root_peak_working_set_bytes=$candidateProcess.PeakWorkingSet64}catch{$candidateOwner.root_peak_working_set_bytes=$null}
 $candidateOwner.completed_utc=[DateTimeOffset]::UtcNow.ToString('o')
 $candidateOwner|ConvertTo-Json -Depth 6|Set-Content "$candidateReceipt/$Name-owner.json" -Encoding utf8NoBOM
 $candidateOwner.root_pid_absent=!(Get-Process -Id $candidateProcess.Id -ErrorAction SilentlyContinue)
 $candidateOwner|ConvertTo-Json -Depth 6|Set-Content "$candidateReceipt/$Name-owner.json" -Encoding utf8NoBOM
 $candidateProcess.Dispose()
 Write-Output $candidateOut
 Write-Output $candidateErr
 if($candidateOwner.status -cne 'passed'){throw "Owned $Name terminal $($candidateOwner.status)"}
}
if($ExpectedHead -cnotmatch '^[0-9a-f]{40}$' -or (git rev-parse HEAD).Trim() -cne $ExpectedHead){throw 'Exact reviewed historical successor head required'}
if($Phase -eq 'Freeze'){
 & (Join-Path $PSScriptRoot 'Invoke-ChordSource54Candidate.ps1') -Phase Freeze -Mode $Mode -ExpectedHead $ExpectedHead -Platform $Platform -ReceiptPath $candidateReceipt
 $auditPath=Join-Path $PSScriptRoot 'chord-promise-resource-da46-independent-artifact-audit-20261014.json'
 if((Get-FileHash -LiteralPath $auditPath).Hash -cne 'E004DBCA6BEE8E864DB6B81B90BCD60FCC762CE74B1564D1E0A21B3FA219B279'){throw 'Independent prior artifact audit changed'}
 $audit=Get-Content -LiteralPath $auditPath -Raw|ConvertFrom-Json
 if($audit.head -cne 'da46b70fafae4a14a70e0a4d66618d82cf5a5d05' -or $audit.run -ne 38610788981 -or $audit.positive_profiles -ne 5 -or $audit.negative_profiles -ne 1 -or $audit.full_six_qualified){throw 'Historical positive/negative inventory changed'}
 foreach($row in $audit.production_probe_golden){
  if($row.path -ceq 'src/native_chord_resource_await_source_test.zig'){continue}
  if((Get-FileHash -LiteralPath $row.path).Hash -cne $row.sha256){throw 'Production VM/resource code or original Source golden changed'}
 }
 # Only appended tests and build metadata differ: the entire original source-test prefix, including Probe, remains exact.
 $original=(git show 'da46b70fafae4a14a70e0a4d66618d82cf5a5d05:src/native_chord_resource_await_source_test.zig') -join "`n"
 $current=[IO.File]::ReadAllText('src/native_chord_resource_await_source_test.zig').Replace("`r`n","`n")
 if(!$current.StartsWith($original.TrimEnd(),[StringComparison]::Ordinal)){throw 'Original full Resource probe or tests changed'}
 foreach($profile in $audit.profiles){
  if(!$profile.production_probe_golden_identical -or $profile.allpost_drift -or $profile.module_vm514.completed -ne 514 -or $profile.module_vm514.owner_leaks -ne 0){throw 'Prior profile provenance failed'}
 }
 [ordered]@{head=$ExpectedHead;source='1692bba6347a287ab0f3cb554a4430fafffc474b';prior_run=38610788981;prior_head=$audit.head;preserved_positive_profiles=5;preserved_negative='macos-latest/Debug Resource120 timeout';platform=$Platform;mode=$Mode;source_cases=4;guarded_source_cases=4;compiled_expected=6;host_gpa_baseline=858;production_probe_changed=$false;broader_source50_regression='not_run';public_activation=$false;full_pi_qualified=$false}|ConvertTo-Json|Set-Content "$candidateReceipt/successor-source.json" -Encoding utf8NoBOM
 return
}
if($Phase -eq 'Compile'){
 & (Join-Path $PSScriptRoot 'Test-ChordResourceMacPartitionCollector.ps1')
 & zig fmt --check src/native_chord_resource_await_source_test.zig build.zig
 if($LASTEXITCODE -ne 0){throw 'Resource successor formatting failed'}
 Owned-Process 'compile' @('build','build-native-chord-resource-mac-partitions','-Doptimize=Debug','-j1','--summary','all') 1320
 return
}
if($Phase -eq 'Run'){
 . (Join-Path $PSScriptRoot 'Assert-ChordResourceMacPartitions.ps1')
 Owned-Process 'runtime' @('build','test-native-chord-resource-mac-partitions','-Doptimize=Debug','-j1','--test-timeout','120s','--summary','all') 300
 $log=[IO.File]::ReadAllText("$candidateReceipt/runtime.stdout.log")+[Environment]::NewLine+[IO.File]::ReadAllText("$candidateReceipt/runtime.stderr.log")
 $markers=[regex]::Matches($log,'CHORD_RESOURCE_MAC_COMPILED_INVENTORY=(\[[^\r\n]*\])')
 if($markers.Count -ne 1){throw 'Missing or duplicated Resource successor inventory'}
 $names=@($markers[0].Groups[1].Value|ConvertFrom-Json)
 $wanted=@('native Chord Resource MacDebug partition compiled inventory','native latest Chord1692 ResourceAwait actual Source4 intrinsic species own then abort cleanup and rejection identity with GC','native latest Chord1692 ResourceAwait original caller caught allocation diagnostic preserves replacement and first failure stack','native Chord Resource MacDebug whole guarded4 GPA partition 0','native Chord Resource MacDebug whole guarded4 GPA partition 1')
 if($names.Count -ne 6 -or @($names|Sort-Object -Unique).Count -ne 6){throw 'Resource successor compiled count changed'}
 foreach($name in $wanted){if(@($names|Where-Object{$_.EndsWith('.test.'+$name,[StringComparison]::Ordinal)}).Count -ne 1){throw 'Missing original Resource or complete partition gate'}}
 if(@($names|Where-Object{$_ -ceq 'extensions.native_durable_storage.test_0'}).Count -ne 1 -or $log.IndexOf('run test 6 pass (6 total)',[StringComparison]::Ordinal) -lt 0){throw 'Every original Resource and partition test must pass'}
 $negative=[regex]::Matches($log,'CHORD_RESOURCE_ORIGINAL_CALLER_FAILURE_INDEX=(\d+) baseline=(\d+)')
 if($negative.Count -ne 1 -or $negative[0].Groups[1].Value -cne '856' -or $negative[0].Groups[2].Value -cne '858'){throw 'Original caller negative changed'}
 $coverage=Assert-ChordResourceMacPartitions -Log $log
 foreach($phaseName in @('compile','runtime')){
  $owner=Get-Content "$candidateReceipt/$phaseName-owner.json" -Raw|ConvertFrom-Json
  if($owner.head -cne $ExpectedHead -or $owner.status -cne 'passed' -or $owner.exit_code -ne 0 -or !$owner.root_pid_absent -or $owner.jobs -ne 1 -or $owner.test_timeout_seconds -ne 120 -or $owner.host_await_seconds -ne 10 -or $owner.deadline_seconds -ne $(if($phaseName -ceq 'compile'){1320}else{300})){throw 'Original Resource successor owned guards failed'}
 }
 [ordered]@{head=$ExpectedHead;mode=$Mode;platform=$Platform;status='passed';source='1692bba6347a287ab0f3cb554a4430fafffc474b';source_cases=4;guarded_source_cases=4;compiled_tests=6;compiled_names=$names;host_gpa_coverage=$coverage;production_probe_changed=$false;preserved_prior_positive_profiles=5;c_malloc_exhaustive=$false;public_activation=$false;full_pi_qualified=$false}|ConvertTo-Json -Depth 8|Set-Content "$candidateReceipt/result.json" -Encoding utf8NoBOM
 return
}
if($Phase -eq 'Post'){
 & (Join-Path $PSScriptRoot 'Invoke-ChordSource54Candidate.ps1') -Phase Post -Mode $Mode -ExpectedHead $ExpectedHead -Platform $Platform -ReceiptPath $candidateReceipt
}

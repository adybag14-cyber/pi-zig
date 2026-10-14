param([ValidateSet('Freeze','Compile','Run','Post','Validate')][string]$Phase,[ValidateSet('Debug','ReleaseSafe')][string]$Mode,[Parameter(Mandatory)][string]$ExpectedHead,[string]$Platform=$env:ImageOS,[string]$Receipt)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Assert-ChordComposedPartitions.ps1')
$candidateReceipt='verification/native-chord-promise-resource-candidate'
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
function Assert-Focused([string]$Directory) {
 $source=Get-Content "$Directory/source.json" -Raw|ConvertFrom-Json
 $focused=Get-Content "$Directory/focused-source.json" -Raw|ConvertFrom-Json
 if($source.source -cne '1692bba6347a287ab0f3cb554a4430fafffc474b' -or $source.zig_version -cne '0.16.0' -or $source.mode -cne $Mode -or $source.platform -cne $Platform -or $source.total_source_cases -ne 54 -or $source.public_activation -or $source.full_pi_qualified){throw 'Full original authority/compiler freeze changed'}
 if($source.head -cne $ExpectedHead -or $focused.head -cne $ExpectedHead -or $focused.mode -cne $Mode -or $focused.platform -cne $Platform -or $focused.native_targets -ne 2 -or $focused.compiled_tests -ne 12 -or $focused.source_cases -ne 4 -or $focused.guarded_source_cases -ne 4 -or $focused.public_activation -or $focused.full_pi_qualified){throw 'Focused exact-head scope changed'}
 $components=@(
  @{name='module';marker='CHORD_MODULE_PROMISE_COMPILED_INVENTORY';count=7;names=@('native Chord intrinsic module compiled inventory','native Chord intrinsic module pure guest TLA ignores species and own then while public then retains species','native Chord intrinsic module pure guest rejected TLA preserves exact ordinary rejection identity','native Chord intrinsic module pure guest dynamic import fulfillment rejection and own then ignore species','native Chord intrinsic module complete pure guest TLA dynamic import identities and native GC allocation sweep','native Chord intrinsic module direct VM heap limit sweep settles TLA and dynamic import failures and releases memory owners')},
  @{name='resource';marker='CHORD_RESOURCE_AWAIT_COMPILED_INVENTORY';count=5;names=@('native latest Chord1692 ResourceAwait compiled inventory','native latest Chord1692 ResourceAwait actual Source4 intrinsic species own then abort cleanup and rejection identity with GC','native latest Chord1692 ResourceAwait original caller caught allocation diagnostic preserves replacement and first failure stack','native latest Chord1692 ResourceAwait complete actual Source4 factory and native GC teardown allocation sweep')}
 )
 $results=@()
 foreach($component in $components){
  $owner=Get-Content "$Directory/runtime-$($component.name)-owner.json" -Raw|ConvertFrom-Json
  if($owner.head -cne $ExpectedHead -or $owner.status -cne 'passed' -or $owner.exit_code -ne 0 -or !$owner.root_pid_absent -or $owner.deadline_seconds -ne 300 -or $owner.test_timeout_seconds -ne 120 -or $owner.host_await_seconds -ne 10 -or $owner.jobs -ne 1){throw 'Focused owned runtime did not pass original guards'}
  $log=[IO.File]::ReadAllText("$Directory/runtime-$($component.name).stdout.log")+[Environment]::NewLine+[IO.File]::ReadAllText("$Directory/runtime-$($component.name).stderr.log")
  $matches=[regex]::Matches($log,$component.marker+'=(\[[^\r\n]*\])')
  if($matches.Count -ne 1){throw 'Missing or duplicated focused compiled inventory'}
  $names=@($matches[0].Groups[1].Value|ConvertFrom-Json)
  if($names.Count -ne $component.count -or @($names|Sort-Object -Unique).Count -ne $component.count){throw 'Focused compiled count changed'}
  foreach($wanted in $component.names){if(@($names|Where-Object{$_.EndsWith('.test.'+$wanted,[StringComparison]::Ordinal)}).Count -ne 1){throw "Missing focused gate $wanted"}}
  if(@($names|Where-Object{$_ -ceq 'extensions.native_durable_storage.test_0'}).Count -ne 1 -or $log.IndexOf(('run test '+$component.count+' pass ('+$component.count+' total)'),[StringComparison]::Ordinal) -lt 0){throw 'Every focused gate must pass without skips'}
  $baselineMarker=if($component.name -ceq 'module'){'CHORD_MODULE_PROMISE_GPA_BASELINE_ALLOCATIONS'}else{'CHORD_RESOURCE_AWAIT_GPA_BASELINE_ALLOCATIONS'}
  $baselines=[regex]::Matches($log,$baselineMarker+'=(\d+)')
  if($baselines.Count -ne 1 -or [long]$baselines[0].Groups[1].Value -le 0){throw 'Missing full host allocator baseline'}
  $baseline=[long]$baselines[0].Groups[1].Value
  $vm=$null
  if($component.name -ceq 'module'){
   $coverage=[regex]::Matches($log,'CHORD_MODULE_VM_HEAP_LIMIT_COVERAGE=(\{[^\r\n]*\})')
   if($coverage.Count -ne 1){throw 'Missing or duplicated actual VM budget coverage'}
   $vm=$coverage[0].Groups[1].Value|ConvertFrom-Json
   if($vm.programs -ne 2 -or $vm.minimum_budget -ne 0 -or $vm.maximum_budget -ne 8192 -or $vm.step -ne 32 -or $vm.completed -ne 514 -or $vm.failures -le 0 -or $vm.successes -le 0 -or ($vm.failures+$vm.successes) -ne 514 -or $vm.owner_leaks -ne 0 -or @($vm.failures_by_program).Count -ne 2 -or @($vm.successes_by_program).Count -ne 2){throw 'Targeted VM budget matrix incomplete'}
   foreach($index in 0..1){if($vm.failures_by_program[$index] -le 0 -or $vm.successes_by_program[$index] -le 0 -or ($vm.failures_by_program[$index]+$vm.successes_by_program[$index]) -ne 257){throw 'Targeted VM program omitted budgets or expected failures'}}
   if(($vm.failures_by_program|Measure-Object -Sum).Sum -ne $vm.failures -or ($vm.successes_by_program|Measure-Object -Sum).Sum -ne $vm.successes){throw 'Targeted VM program totals disagree'}
  }else{
   $negative=[regex]::Matches($log,'CHORD_RESOURCE_ORIGINAL_CALLER_FAILURE_INDEX=(\d+) baseline=(\d+)')
   if($negative.Count -ne 1 -or [long]$negative[0].Groups[2].Value -ne $baseline -or [long]$negative[0].Groups[1].Value -ne ($baseline-2)){throw 'Original caller allocation negative changed'}
  }
  $results+=@([ordered]@{component=$component.name;compiled_tests=$component.count;compiled_names=$names;host_gpa_baseline=$baseline;all_host_allocation_indices='passed';native_gc='passed';targeted_vm_budget_coverage=$vm;c_malloc_exhaustive=$false;status='passed'})
 }
 $compile=Get-Content "$Directory/compile-owner.json" -Raw|ConvertFrom-Json
 if($compile.head -cne $ExpectedHead -or $compile.status -cne 'passed' -or $compile.exit_code -ne 0 -or !$compile.root_pid_absent -or $compile.deadline_seconds -ne 1320 -or $compile.jobs -ne 1){throw 'Focused compile terminal proof changed'}
 [ordered]@{head=$ExpectedHead;mode=$Mode;platform=$Platform;status='passed';source_cases=4;guarded_source_cases=4;compiled_tests=12;components=$results;full_source50_regression='not_run_by_this_focused_workflow';c_malloc_exhaustive=$false;public_activation=$false;full_pi_qualified=$false}
}
if($ExpectedHead -cnotmatch '^[0-9a-f]{40}$' -or (git rev-parse HEAD).Trim() -cne $ExpectedHead){throw 'Exact reviewed candidate head required'}
if($Phase -eq 'Validate'){
 if(!$Receipt){throw 'Downloaded exact-profile receipt required'}
 $result=Assert-Focused $Receipt
 $frozenSource=Get-Content "$Receipt/source.json" -Raw|ConvertFrom-Json
 foreach($kind in @('inputs','tools')){$post=Get-Content "$Receipt/$kind-posthash.json" -Raw|ConvertFrom-Json;$expectedCount=if($kind -ceq 'inputs'){$frozenSource.source_count}else{$frozenSource.tool_count};if(!$post.count -or $post.count -ne $expectedCount -or $post.drift_count -or @($post.drift).Count){throw 'Focused source/compiler posthash failed'}}
 $inventory=Get-Content "$Receipt/inventory-posthash.json" -Raw|ConvertFrom-Json
 if($inventory.tracked_inventory_changes -or $inventory.tool_inventory_changes -or @($inventory.unexpected_untracked).Count){throw 'Focused source/compiler inventory changed'}
 $result|ConvertTo-Json -Depth 8
 return
}
if($Phase -eq 'Freeze'){
 & (Join-Path $PSScriptRoot 'Invoke-ChordSource54Candidate.ps1') -Phase Freeze -Mode $Mode -ExpectedHead $ExpectedHead -Platform $Platform -ReceiptPath $candidateReceipt
 # Reuse the complete genuine Source54/vendor/compiler freeze, then add the separately captured guarded observer.
 $guarded=Get-Content (Join-Path $PSScriptRoot 'resource-await-guarded-source-inventory.json') -Raw|ConvertFrom-Json
 $ordinary=Get-Content (Join-Path $PSScriptRoot 'resource-await-source-inventory.json') -Raw|ConvertFrom-Json
 if($guarded.source -cne '1692bba6347a287ab0f3cb554a4430fafffc474b' -or $guarded.cases -ne 4 -or $guarded.full_source_inputs -ne 34793 -or !$guarded.original_body_unchanged -or !$guarded.actual_factory_calls -or $guarded.source_body_replaced -or $guarded.public_activation -or $guarded.oracle_sha256 -cne $ordinary.oracle_sha256 -or $guarded.original_oracle_sha256 -cne $ordinary.oracle_sha256){throw 'Guarded actual Source4 contract changed'}
 foreach($file in @(@{path=$guarded.caller;hash=$guarded.caller_sha256},@{path=$guarded.oracle;hash=$guarded.oracle_sha256})){if((Get-FileHash -LiteralPath ('src/extensions/fixtures/'+$file.path)).Hash -cne $file.hash){throw 'Guarded caller/oracle bytes changed'}}
 if(@($guarded.capture_attempts).Count -ne 2){throw 'Guarded original double capture missing'}
 foreach($attempt in $guarded.capture_attempts){
  $proof=Get-Content (Join-Path $PSScriptRoot "$attempt-qualified.json") -Raw|ConvertFrom-Json
  if($proof.source -cne $guarded.source -or !$proof.actual_factory_calls -or $proof.source_body_replaced -or $proof.driver_drift -or $proof.job.status -cne 'passed' -or $proof.job.exit_code -ne 0 -or $proof.output_sha256 -cne $ordinary.oracle_sha256){throw 'Guarded actual Node capture changed'}
  foreach($side in @($proof.pre,$proof.post)){if((@($side.files)|Measure-Object -Sum).Sum -ne 34793 -or @($side|Where-Object{$_.drift -ne 0}).Count){throw 'Guarded full original closure drift'}}
 }
 $guardedFreeze=Get-Content (Join-Path $PSScriptRoot 'chord-resource-await-guarded-1692-candidate-post-20261014.json') -Raw|ConvertFrom-Json
 if($guardedFreeze.candidate_drift -or $guardedFreeze.candidate_inventory_drift -or $guardedFreeze.owned_pids_remaining -or !$guardedFreeze.original_and_guarded_byte_equal -or $guardedFreeze.oracle_sha256 -cne $ordinary.oracle_sha256 -or $guardedFreeze.full_source_inputs -ne 34793){throw 'Guarded actual Node candidate freeze changed'}
 [ordered]@{head=$ExpectedHead;mode=$Mode;platform=$Platform;native_targets=2;compiled_tests=12;source_cases=4;guarded_source_cases=4;source_body_replaced=$false;targeted_c_vm_budgets=514;c_malloc_exhaustive=$false;full_source50_regression='not_run_by_this_focused_workflow';public_activation=$false;full_pi_qualified=$false}|ConvertTo-Json|Set-Content "$candidateReceipt/focused-source.json" -Encoding utf8NoBOM
 return
}
if($Phase -eq 'Compile'){
 & (Join-Path $PSScriptRoot 'Test-ChordPromiseResourceCollector.ps1')
 & zig fmt --check src/native_chord_module_promise_test.zig src/native_chord_resource_await_source_test.zig src/extensions/native_chord_latest_resources.zig
 if($LASTEXITCODE -ne 0){throw 'Focused formatting failed'}
 Owned-Process 'compile' @('build','build-native-chord-module-promise','build-native-chord-resource-await-source',"-Doptimize=$Mode",'-j1','--summary','all') 1320
 return
}
if($Phase -eq 'Run'){
 foreach($component in @(@{name='module';target='test-native-chord-module-promise'},@{name='resource';target='test-native-chord-resource-await-source'})){
  Owned-Process ('runtime-'+$component.name) @('build',$component.target,"-Doptimize=$Mode",'-j1','--test-timeout','120s','--summary','all') 300
 }
 Assert-Focused $candidateReceipt|ConvertTo-Json -Depth 8|Set-Content "$candidateReceipt/focused-result.json" -Encoding utf8NoBOM
 return
}
if($Phase -eq 'Post'){
 & (Join-Path $PSScriptRoot 'Invoke-ChordSource54Candidate.ps1') -Phase Post -Mode $Mode -ExpectedHead $ExpectedHead -Platform $Platform -ReceiptPath $candidateReceipt
}

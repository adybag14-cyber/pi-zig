param([ValidateSet('Freeze','Compile','Run','Post')][string]$Phase,[ValidateSet('Debug','ReleaseSafe')][string]$Mode,[Parameter(Mandatory)][string]$ExpectedHead,[string]$Platform=$env:ImageOS)
$ErrorActionPreference='Stop'
$candidateReceipt='verification/native-chord-latest-candidate'
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
  if($candidateStart.FileName -match 'codex' -or $candidateProcess.StartTime.ToUniversalTime() -ne $candidateCreated -or $candidateProcess.MainModule.FileName -cne $candidateStart.FileName){throw 'Owned deadline identity changed, refusing termination'}
  if($IsWindows){
   $candidateCurrent=Get-CimInstance Win32_Process -Filter "ProcessId = $($candidateProcess.Id)"
   if(!$candidateCurrent -or $candidateCurrent.ExecutablePath -cne $candidateStart.FileName -or [Math]::Abs((([DateTimeOffset]$candidateCurrent.CreationDate).UtcDateTime-$candidateCreated).Ticks) -gt 10 -or ($candidateCim -and $candidateCurrent.CommandLine -cne $candidateCim.CommandLine)){throw 'Owned Windows deadline identity changed, refusing termination'}
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
 $candidateProcess.Dispose()
 Write-Output $candidateOut
 Write-Output $candidateErr
 if($candidateOwner.status -cne 'passed'){throw "Owned $Name terminal $($candidateOwner.status)"}
}
if($ExpectedHead -cnotmatch '^[0-9a-f]{40}$' -or (git rev-parse HEAD).Trim() -cne $ExpectedHead){throw 'Exact reviewed candidate head required'}
if($Phase -eq 'Freeze'){
 if((git status --porcelain).Count){throw 'Candidate checkout must be clean before evidence writes'}
 New-Item -ItemType Directory -Path $candidateReceipt -Force|Out-Null
 $candidateZigInfo=[IO.FileInfo]::new((Get-Command zig).Source)
 $candidateZigTarget=$candidateZigInfo.ResolveLinkTarget($true)
 $candidateZig=if($candidateZigTarget){$candidateZigTarget.FullName}else{$candidateZigInfo.FullName}
 if((& $candidateZig version).Trim() -cne '0.16.0'){throw 'Pinned Zig baseline changed'}
 $candidateToolRoot=Split-Path -Parent $candidateZig
 $candidateInputs=Hash-Rows @(git ls-files)
 $candidateTools=Hash-Rows @(Get-ChildItem -LiteralPath $candidateToolRoot -File -Recurse|ForEach-Object FullName)
 $candidateInputs|ConvertTo-Json -Depth 4|Set-Content "$candidateReceipt/inputs.json" -Encoding utf8NoBOM
 $candidateTools|ConvertTo-Json -Depth 4|Set-Content "$candidateReceipt/tools.json" -Encoding utf8NoBOM
 $candidateInventory=Get-Content verification/chord-latest-1692-source-20261014/fixture-inventory.json -Raw|ConvertFrom-Json
 if($candidateInventory.source -cne '1692bba6347a287ab0f3cb554a4430fafffc474b' -or $candidateInventory.total_cases -ne 27 -or $candidateInventory.full_source_inputs -ne 34793 -or $candidateInventory.source_body_replaced -or $candidateInventory.public_activation){throw 'Current Source inventory changed'}
 $candidateCount=0
 foreach($candidateFixture in $candidateInventory.fixtures){
  if((Get-FileHash -LiteralPath $candidateFixture.oracle).Hash -cne $candidateFixture.oracle_sha256 -or (Get-FileHash -LiteralPath $candidateFixture.input).Hash -cne $candidateFixture.input_sha256){throw 'Frozen Source caller or oracle changed'}
  $candidateOriginal=Get-Content -LiteralPath $candidateFixture.oracle -Raw|ConvertFrom-Json
  if($candidateOriginal.source -cne $candidateInventory.source -or @($candidateOriginal.cases).Count -ne $candidateFixture.cases -or (Compare-Object @($candidateOriginal.cases.name) @($candidateFixture.case_names))){throw 'Original case inventory changed'}
  $candidateCount += $candidateFixture.cases
 }
 if($candidateCount -ne 27){throw 'Missing original Source cases'}
 foreach($candidateCapture in @('chord-object-reload-original-1692-third-20261014','chord-full-links-original-1692-second-20261014','chord-full-host-closed-original-1692-second-20261014','chord-v2-original-1692-second-20261014')){
  $candidateProof=Get-Content "verification/chord-latest-1692-source-20261014/$candidateCapture-qualified.json" -Raw|ConvertFrom-Json
  if($candidateProof.source -cne $candidateInventory.source -or !$candidateProof.actual_factory_calls -or $candidateProof.source_body_replaced -or $candidateProof.driver_drift -or $candidateProof.job.status -cne 'passed' -or $candidateProof.job.exit_code -ne 0){throw 'Source oracle was not qualified'}
  foreach($candidateSide in @($candidateProof.pre,$candidateProof.post)){if((@($candidateSide.files)|Measure-Object -Sum).Sum -ne 34793 -or @($candidateSide|Where-Object{$_.drift -ne 0}).Count){throw 'Source closure freeze changed'}}
 }
 $candidateVendor=Get-Content vendor/chord-zlib-node-24.14.0/SOURCE.json -Raw|ConvertFrom-Json
 if($candidateVendor.node_commit -cne 'f657bb8ed86365ff3fdbe32e27563e778b41486a' -or !$candidateVendor.c_only -or @($candidateVendor.source_changes).Count){throw 'Pinned direct C dependency changed'}
 foreach($candidateVendorFile in $candidateVendor.selected_files){if((Get-FileHash -LiteralPath ('vendor/chord-zlib-node-24.14.0/'+$candidateVendorFile.path)).Hash -cne $candidateVendorFile.sha256){throw 'Original C dependency bytes changed'}}
 [ordered]@{head=$ExpectedHead;tree=(git rev-parse 'HEAD^{tree}').Trim();source='1692bba6347a287ab0f3cb554a4430fafffc474b';mode=$Mode;platform=$Platform;zig=$candidateZig;zig_version='0.16.0';zig_sha256=(Get-FileHash -LiteralPath $candidateZig).Hash;compiler_distribution=$candidateToolRoot;source_count=$candidateInputs.Count;tool_count=$candidateTools.Count;source_cases=27;public_activation=$false;node_loader_qualified=$false;manager_qualified=$false;full_pi_qualified=$false;scope='Private actual latest Host Object Ref Ctx reload cluster protocol-v2 graph Source27 GC and full GPA'}|ConvertTo-Json -Depth 6|Set-Content "$candidateReceipt/source.json" -Encoding utf8NoBOM
 return
}
if($Phase -eq 'Compile'){
 $candidateFormat=@(git ls-files 'src/extensions/native_chord*.zig')+@('src/native_chord_latest_source_test.zig','build.zig')
 & zig fmt --check @candidateFormat
 if($LASTEXITCODE -ne 0){throw 'Native formatting failed'}
 Owned-Process 'compile' @('build','build-native-chord-latest-source',"-Doptimize=$Mode",'-j1','--summary','all') 1320
 return
}
if($Phase -eq 'Run'){
 Owned-Process 'runtime' @('build','test-native-chord-latest-source',"-Doptimize=$Mode",'-j1','--test-timeout','120s','--summary','all') 300
 $candidateLog=(Get-Content "$candidateReceipt/runtime.stdout.log" -Raw)+[Environment]::NewLine+(Get-Content "$candidateReceipt/runtime.stderr.log" -Raw)
 $candidateMarker=[regex]::Matches($candidateLog,'CHORD_LATEST_COMPILED_INVENTORY=(\[[^\r\n]*\])')
 if($candidateMarker.Count -ne 1){throw 'Missing or duplicated compiled inventory'}
 $candidateNames=@($candidateMarker[0].Groups[1].Value|ConvertFrom-Json)
 $candidateWanted=@('native latest Chord1692 compiled selected inventory','native latest Chord1692 actual Source8 object factories reload cells resource adoption signals tasks','native latest Chord1692 actual Source8 full Host Connection RemoteRef RelayRef links calls state and invalidation','native latest Chord1692 actual Source2 already closed full Host construction accept connect','native latest Chord1692 actual Source9 protocol2 packed bytes window acknowledgement maxCalls negatives','native latest Chord1692 actual object refs root signals and declarations survive GC then teardown','native latest Chord1692 complete actual object factory root call and teardown GPA sweep')
 if($candidateNames.Count -ne 7 -or @($candidateNames|Sort-Object -Unique).Count -ne 7){throw 'Selected compiled inventory changed'}
 foreach($candidateName in $candidateWanted){if(@($candidateNames|Where-Object{$_.EndsWith('.test.'+$candidateName,[StringComparison]::Ordinal)}).Count -ne 1){throw "Missing selected gate $candidateName"}}
 if($candidateLog.IndexOf('run test 7 pass (7 total)',[StringComparison]::Ordinal) -lt 0){throw 'All selected native gates did not execute'}
 [ordered]@{head=$ExpectedHead;mode=$Mode;platform=$Platform;status='passed';source_cases=27;compiled_tests=7;compiled_names=$candidateNames;gc='passed';all_gpa_failures='passed';host_await_seconds=10;test_timeout_seconds=120;outer_timeout_seconds=300;public_activation=$false;node_loader_qualified=$false;manager_qualified=$false;full_pi_qualified=$false}|ConvertTo-Json -Depth 6|Set-Content "$candidateReceipt/result.json" -Encoding utf8NoBOM
 return
}
if($Phase -eq 'Post'){
 foreach($candidateKind in @('inputs','tools')){
  $candidateRows=@(Get-Content "$candidateReceipt/$candidateKind.json" -Raw|ConvertFrom-Json)
  $candidateDrift=Check-Rows $candidateRows
  [ordered]@{count=$candidateRows.Count;drift_count=$candidateDrift.Count;drift=$candidateDrift;checked_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 5|Set-Content "$candidateReceipt/$candidateKind-posthash.json" -Encoding utf8NoBOM
  if($candidateDrift.Count){throw "Frozen $candidateKind bytes changed"}
 }
 $candidateSource=Get-Content "$candidateReceipt/source.json" -Raw|ConvertFrom-Json
 $candidateInputRows=Get-Content "$candidateReceipt/inputs.json" -Raw|ConvertFrom-Json
 $candidateToolRows=Get-Content "$candidateReceipt/tools.json" -Raw|ConvertFrom-Json
 $candidateTrackedChanges=@(Compare-Object @($candidateInputRows.path|Sort-Object) @(git ls-files|Sort-Object))
 $candidateToolChanges=@(Compare-Object @($candidateToolRows.path|Sort-Object) @(Get-ChildItem -LiteralPath $candidateSource.compiler_distribution -File -Recurse|ForEach-Object FullName|Sort-Object))
 $candidateUnexpected=@(git ls-files --others --exclude-standard|Where-Object{!$_.StartsWith($candidateReceipt+'/',[StringComparison]::Ordinal)})
 [ordered]@{tracked_inventory_changes=$candidateTrackedChanges.Count;tool_inventory_changes=$candidateToolChanges.Count;unexpected_untracked=$candidateUnexpected}|ConvertTo-Json -Depth 5|Set-Content "$candidateReceipt/inventory-posthash.json" -Encoding utf8NoBOM
 if($candidateTrackedChanges.Count -or $candidateToolChanges.Count -or $candidateUnexpected.Count){throw 'Frozen input names changed'}
 git diff --exit-code
 if($LASTEXITCODE -ne 0){throw 'Tracked source bytes changed'}
}

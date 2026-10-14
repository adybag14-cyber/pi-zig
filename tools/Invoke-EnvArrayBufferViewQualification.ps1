param(
    [ValidateSet('Debug','ReleaseSafe')][string]$Mode='Debug',
    [Parameter(Mandatory)][string]$ExpectedHead,
    [Parameter(Mandatory)][string]$ExpectedManifestHash,
    [ValidateSet('Compile','Run')][string]$Phase='Run',
    [string]$Receipt='verification/env-arraybufferview',
    [ValidateSet(8,16)][int]$AdmissionGiB=16,
    [switch]$HostedSoleJob,
    [ValidateSet(300,1320)][int]$OuterSeconds=300
)
$ErrorActionPreference='Stop'
$taskRoot=(Get-Location).ProviderPath
$taskReceipt=[IO.Path]::GetFullPath((Join-Path $taskRoot $Receipt))
if(!$taskReceipt.StartsWith($taskRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Receipt must remain in owned checkout'}
New-Item -ItemType Directory -Path $taskReceipt -Force|Out-Null
$taskHead=(git rev-parse HEAD).Trim()
if($taskHead -cne $ExpectedHead){throw 'Checkout head drift'}
if(($Phase -ceq 'Compile' -and $OuterSeconds -ne 1320) -or ($Phase -ceq 'Run' -and $OuterSeconds -ne 300)){throw 'Separate original compile/runtime deadline required'}
function Control-Rows {
    @(Get-ChildItem Env:|Where-Object{$_.Name -match '^(PI_|ZIG_)'}|Sort-Object Name|ForEach-Object{[ordered]@{name=$_.Name;value_sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($_.Value)))}})
}
$taskControls=Control-Rows
$taskControls|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskReceipt 'controls-before.json') -Encoding utf8NoBOM
$taskZig=(Get-Command zig -CommandType Application|Select-Object -First 1).Source
if((& $taskZig version).Trim() -cne '0.16.0' -or (Get-FileHash -LiteralPath $taskZig).Hash -cne '086CE9D47BA42F33A514E1A6E04EB1D4A8FA1D75E0868E0213CAAD447C91E864'){throw 'Pinned official Windows Zig executable drift'}
$taskManifestPath='src/extensions/fixtures/env-node-arraybufferview4-source-manifest-e6220e1.json'
if((Get-FileHash -LiteralPath $taskManifestPath).Hash -cne $ExpectedManifestHash){throw 'ArrayBufferView Source manifest drift'}
$taskManifest=Get-Content -LiteralPath $taskManifestPath -Raw|ConvertFrom-Json
if($taskManifest.upstream -cne 'e6220e1316f86af818a0ccbfe1c09d7e918b41cf' -or $taskManifest.source_snapshot_tracked_files -ne 1902 -or $taskManifest.source_corpora -ne 3 -or $taskManifest.expected_tests -ne 4 -or $taskManifest.required_tests.Count -ne 3 -or $taskManifest.fixtures.Count -ne 7 -or $taskManifest.lifecycle_module_imported -or $taskManifest.full_filehandle_graph_qualified -or $taskManifest.full_env_package_qualified -or $taskManifest.posix_native_qualified -or $taskManifest.public_guest_activation){throw 'ArrayBufferView Source identity inventory or scope drift'}
foreach($taskFixture in $taskManifest.fixtures){if((Get-FileHash -LiteralPath $taskFixture.path).Hash -cne $taskFixture.sha256){throw "Original FileHandle capture drift: $($taskFixture.path)"}}
if($taskManifest.native_inputs.Count -ne 2){throw 'Additive C API source inventory mismatch'}
foreach($taskFile in $taskManifest.native_inputs){if((Get-FileHash -LiteralPath $taskFile.path).Hash -cne $taskFile.sha256){throw 'Additive C API source hash mismatch'}}
if((Get-FileHash -LiteralPath 'vendor/libuv/PI-UPSTREAM-PROVENANCE.json').Hash -cne $taskManifest.libuv_provenance_sha256){throw 'Pinned linked C provenance drift'}
$taskUv=Get-Content -LiteralPath vendor/libuv/PI-UPSTREAM-PROVENANCE.json -Raw|ConvertFrom-Json
if($taskUv.commit -cne 'f657bb8ed86365ff3fdbe32e27563e778b41486a' -or $taskUv.version -cne '1.51.0' -or $taskUv.files.Count -ne 416){throw 'Pinned linked C identity drift'}
foreach($taskFile in $taskUv.files){if((Get-FileHash -LiteralPath (Join-Path vendor/libuv $taskFile.path)).Hash -cne $taskFile.sha256){throw "Pinned libuv source drift: $($taskFile.path)"}}
$taskInputs=@(git ls-files|Sort-Object|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})
$taskTools=@(Get-ChildItem -LiteralPath (Split-Path -Parent $taskZig) -Recurse -File -Force|Sort-Object FullName|ForEach-Object{[ordered]@{path=$_.FullName;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}})
if($taskTools.Count -ne 19546){throw 'Pinned complete compiler inventory drift'}
$taskPinnedPath='verification/env-node-filehandle-primitives7-20261014/pinned-compiler-manifest.json'
if((Get-FileHash -LiteralPath $taskPinnedPath).Hash -cne $taskManifest.compiler_manifest_sha256){throw 'Pinned full compiler proof drift'}
$taskPinned=Get-Content -LiteralPath $taskPinnedPath -Raw|ConvertFrom-Json
$taskExpectedTools=@{}
foreach($taskFile in $taskPinned.inputs){$taskExpectedTools[$taskFile.path.Substring($taskPinned.root.Length+1).Replace('\','/')]=$taskFile.sha256}
if($taskExpectedTools.Count -ne 19546){throw 'Pinned compiler proof inventory mismatch'}
foreach($taskFile in $taskTools){$taskRelative=[IO.Path]::GetRelativePath((Split-Path -Parent $taskZig),$taskFile.path).Replace('\','/');if(!$taskExpectedTools.ContainsKey($taskRelative) -or $taskExpectedTools[$taskRelative] -cne $taskFile.sha256){throw "Pinned compiler input drift: $taskRelative"}}
$taskInputs|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskReceipt 'inputs-before.json') -Encoding utf8NoBOM
$taskTools|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskReceipt 'tools-before.json') -Encoding utf8NoBOM
if($Phase -ceq 'Run'){
    $taskCompileRoot=Join-Path (Split-Path -Parent $taskReceipt) 'compile'
    $taskCompileInputs=Get-Content -LiteralPath (Join-Path $taskCompileRoot 'inputs-before.json') -Raw|ConvertFrom-Json
    $taskCompileSource=Get-Content -LiteralPath (Join-Path $taskCompileRoot 'source.json') -Raw|ConvertFrom-Json
    $taskCompileOwner=Get-Content -LiteralPath (Join-Path $taskCompileRoot 'owned-process.json') -Raw|ConvertFrom-Json
    $taskPairDrift=@(Compare-Object @($taskInputs|ForEach-Object{"$($_.path):$($_.sha256)"}) @($taskCompileInputs|ForEach-Object{"$($_.path):$($_.sha256)"}))
    if($taskPairDrift.Count -or $taskCompileSource.head -cne $ExpectedHead -or $taskCompileSource.mode -cne $Mode -or $taskCompileSource.phase -cne 'Compile' -or $taskCompileOwner.status -cne 'passed'){throw 'Runtime requires the same fully frozen successful compile source'}
    [ordered]@{source_files=$taskInputs.Count;compile_runtime_source_drift=$taskPairDrift.Count;compile_head=$taskCompileSource.head;mode=$Mode}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskReceipt 'compile-runtime-identity.json') -Encoding utf8NoBOM
}
if($AdmissionGiB -eq 8 -and (!$HostedSoleJob -or $env:GITHUB_ACTIONS -cne 'true')){throw 'Calibrated8GiB requires the explicitly authorized sole hosted runner'}
$taskFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
[ordered]@{free_kib=$taskFree;minimum_gib=$AdmissionGiB;hosted_sole=[bool]$HostedSoleJob;checked_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content (Join-Path $taskReceipt 'admission.json')
if($taskFree -lt $AdmissionGiB*1MB){throw 'Fresh native admission refused after full prehash'}
[ordered]@{head=$taskHead;tree=(git rev-parse 'HEAD^{tree}').Trim();upstream=$taskManifest.upstream;mode=$Mode;phase=$Phase;source_count=$taskInputs.Count;tool_count=$taskTools.Count;manifest_sha256=$ExpectedManifestHash;outer_seconds=$OuterSeconds;test_timeout_seconds=120;host_timeout_seconds=10;scope=$taskManifest.scope;lifecycle_module_imported=$false;public_guest_activation=$false;full_filehandle_graph_qualified=$false;full_env_package_qualified=$false;posix_native_qualified=$false}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskReceipt 'source.json') -Encoding utf8NoBOM
$taskStart=[Diagnostics.ProcessStartInfo]::new()
$taskStart.FileName=$taskZig
$taskStart.WorkingDirectory=$taskRoot
$taskStart.UseShellExecute=$false
$taskStart.CreateNoWindow=$true
$taskStart.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
$taskStart.RedirectStandardOutput=$true
$taskStart.RedirectStandardError=$true
$taskStep=if($Phase -ceq 'Compile'){'build-hosted-native-env-arraybufferview'}else{'test-native-env-arraybufferview'}
$taskArguments=@('build',$taskStep,"-Doptimize=$Mode",'-Duse-llvm=true','-Ddiagnostic-tests=true','-j1','--test-timeout','120s','--summary','all')
foreach($taskArgument in $taskArguments){$taskStart.ArgumentList.Add($taskArgument)}
$taskProcess=[Diagnostics.Process]::new()
$taskProcess.StartInfo=$taskStart
if(!$taskProcess.Start()){throw 'Owned native qualification failed to launch'}
$taskCreated=$taskProcess.StartTime.ToUniversalTime()
$taskLive=Get-CimInstance Win32_Process -Filter "ProcessId = $($taskProcess.Id)"
$taskRecord=[ordered]@{pid=$taskProcess.Id;created_utc=$taskCreated.ToString('o');executable=$taskZig;argv=$taskArguments;command_line=if($taskLive){$taskLive.CommandLine}else{$null};identity_source='retained native Process handle and exact ProcessStartInfo argv';status='running'}
$taskRecord|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskReceipt 'owned-process.json') -Encoding utf8NoBOM
$taskStdout=$taskProcess.StandardOutput.ReadToEndAsync()
$taskStderr=$taskProcess.StandardError.ReadToEndAsync()
$taskFinished=$taskProcess.WaitForExit($OuterSeconds*1000)
if(!$taskFinished){
    $taskFresh=Get-CimInstance Win32_Process -Filter "ProcessId = $($taskProcess.Id)"
    if(!$taskFresh -or $taskFresh.ExecutablePath -cne $taskZig -or [Math]::Abs((([DateTimeOffset]$taskFresh.CreationDate).UtcDateTime-$taskCreated).Ticks) -gt 10 -or $taskFresh.ExecutablePath -match 'codex'){throw 'Owned timeout identity mismatch; refusing process control'}
    if($taskLive -and $taskFresh.CommandLine -cne $taskLive.CommandLine){throw 'Owned timeout argv changed'}
    $taskProcess.Kill($true)
    if(!$taskProcess.WaitForExit(10000)){throw 'Verified owned timeout process did not terminate'}
}
$taskOut=$taskStdout.GetAwaiter().GetResult()
$taskErr=$taskStderr.GetAwaiter().GetResult()
[IO.File]::WriteAllText((Join-Path $taskReceipt 'stdout.log'),$taskOut)
[IO.File]::WriteAllText((Join-Path $taskReceipt 'stderr.log'),$taskErr)
$taskLog=$taskOut+"`n"+$taskErr
[IO.File]::WriteAllText((Join-Path $taskReceipt 'tests.log'),$taskLog)
$taskRecord.exit_code=$taskProcess.ExitCode
$taskRecord.status=if(!$taskFinished){'timed_out'}elseif($taskProcess.ExitCode -eq 0){'passed'}else{'failed'}
$taskRecord.completed_utc=[DateTimeOffset]::UtcNow.ToString('o')
$taskRecord|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskReceipt 'owned-process.json') -Encoding utf8NoBOM
$taskAfter=@(git ls-files|Sort-Object|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})
$taskSourceDrift=@(Compare-Object ($taskInputs|ForEach-Object{"$($_.path):$($_.sha256)"}) ($taskAfter|ForEach-Object{"$($_.path):$($_.sha256)"}))
$taskToolDrift=@($taskTools|Where-Object{!(Test-Path -LiteralPath $_.path) -or (Get-FileHash -LiteralPath $_.path).Hash -cne $_.sha256})
$taskVendorDrift=@($taskUv.files|Where-Object{(Get-FileHash -LiteralPath (Join-Path vendor/libuv $_.path)).Hash -cne $_.sha256})
$taskControlsAfter=Control-Rows
$taskControlDrift=@(Compare-Object @($taskControls|ForEach-Object{"$($_.name):$($_.value_sha256)"}) @($taskControlsAfter|ForEach-Object{"$($_.name):$($_.value_sha256)"}))
[ordered]@{source_count=$taskInputs.Count;source_after=$taskAfter.Count;source_drift=$taskSourceDrift.Count;tool_count=$taskTools.Count;tool_drift=$taskToolDrift.Count;vendor_count=$taskUv.files.Count;vendor_drift=$taskVendorDrift.Count;controls=$taskControls.Count;control_drift=$taskControlDrift.Count;head_after=(git rev-parse HEAD).Trim();completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskReceipt 'posthash.json') -Encoding utf8NoBOM
if($taskSourceDrift.Count -or $taskToolDrift.Count -or $taskVendorDrift.Count -or $taskControlDrift.Count -or (git rev-parse HEAD).Trim() -cne $ExpectedHead){throw 'Frozen native source/tool/vendor/control identity drift'}
if(!$taskFinished -or $taskProcess.ExitCode -ne 0){Write-Output $taskLog;throw "Native qualification terminal $($taskRecord.status)"}
if($Phase -ceq 'Compile'){
    if($taskLog -match '(?m)^\d+/\d+ .*\.\.\.' -or $taskLog.Contains('ENV_ARRAYBUFFERVIEW_TEST_INVENTORY=',[StringComparison]::Ordinal)){throw 'Compile-only phase unexpectedly executed tests'}
    [ordered]@{phase=$Phase;native_compilation='passed';runtime_tests_executed=$false;head=$taskHead;full_filehandle_graph_qualified=$false;public_guest_activation=$false}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskReceipt 'compile-only.json') -Encoding utf8NoBOM
    Write-Output $taskLog
    return
}
$taskMarkers=[regex]::Matches($taskLog,'(?m)^ENV_ARRAYBUFFERVIEW_TEST_INVENTORY=(.+)\r?$')
if($taskMarkers.Count -ne 1){throw 'Missing or duplicate actual compiled inventory'}
$taskInventory=@($taskMarkers[0].Groups[1].Value|ConvertFrom-Json)
if($taskInventory.Count -ne 4 -or @($taskInventory|Sort-Object -Unique).Count -ne 4){throw 'Actual ArrayBufferView4 compiled inventory mismatch'}
$taskWanted=@([regex]::Matches([IO.File]::ReadAllText((Join-Path $taskRoot 'src/native_env_arraybufferview_test.zig')),'(?m)^test "([^"\r\n]+)"')|ForEach-Object{$_.Groups[1].Value})
if($taskWanted.Count -ne 3 -or @(Compare-Object $taskWanted $taskManifest.required_tests).Count){throw 'Source test body inventory drift'}
foreach($taskName in $taskWanted){if(@($taskInventory|Where-Object{$_.EndsWith('.test.'+$taskName,[StringComparison]::Ordinal)}).Count -ne 1){throw "Required intrinsic comparator absent or duplicated: $taskName"}}
if(@($taskInventory|Where-Object{$_ -ceq 'extensions.native_durable_storage.test_0'}).Count -ne 1){throw 'Required VM storage ownership body absent'}
foreach($taskName in $taskInventory){
    if($taskName.EndsWith('.test.native Env ArrayBufferView actual compiled intrinsic inventory',[StringComparison]::Ordinal)){continue}
    if([regex]::Matches($taskLog,'(?m)^\d+/4 '+[regex]::Escape($taskName)+'\.\.\.OK\r?$').Count -ne 1){throw "Missing terminal or skipped mandatory intrinsic body: $taskName"}
}
if(!$taskLog.Contains('All 4 tests passed.',[StringComparison]::Ordinal)){throw 'Incomplete ArrayBufferView4 execution'}
[ordered]@{actual_compiled_tests=4;named_source_tests=3;inventory=$taskInventory;passed=4;failed=0;skipped=0;source_corpora=3;manifest_sha256=$ExpectedManifestHash;lifecycle_module_imported=$false;full_filehandle_graph_qualified=$false;full_env_package_qualified=$false;posix_native_qualified=$false;public_guest_activation=$false;scope=$taskManifest.scope}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskReceipt 'coverage.json') -Encoding utf8NoBOM
Write-Output $taskLog

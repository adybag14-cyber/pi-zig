param(
    [ValidateSet('Debug','ReleaseSafe')][string]$Mode='Debug',
    [Parameter(Mandatory)][string]$ExpectedHead,
    [Parameter(Mandatory)][string]$ExpectedSourceManifestHash,
    [Parameter(Mandatory)][string]$ExpectedGuestManifestHash,
    [string]$ExpectedNodeReaderManifestHash,
    [string]$ExpectedNodeFsManifestHash,
    [string]$ExpectedCompilerManifestHash,
    [ValidateSet('Compile','Run')][string]$Phase='Run',
    [string]$Receipt='verification/env-guest',
    [int]$OuterSeconds=300
)
$ErrorActionPreference='Stop'
$taskRoot=(Get-Location).ProviderPath
$taskReceipt=[IO.Path]::GetFullPath((Join-Path $taskRoot $Receipt))
if(!$taskReceipt.StartsWith($taskRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Receipt must remain in owned checkout'}
New-Item -ItemType Directory -Path $taskReceipt -Force|Out-Null
$taskHead=(git rev-parse HEAD).Trim()
if($taskHead -cne $ExpectedHead){throw 'Checkout head drift'}
$taskZig=(Get-Command zig -CommandType Application|Select-Object -First 1).Source
if((& $taskZig version).Trim() -cne '0.16.0'){throw 'Zig version drift'}
if((Get-FileHash -LiteralPath $taskZig).Hash -cne '086CE9D47BA42F33A514E1A6E04EB1D4A8FA1D75E0868E0213CAAD447C91E864'){throw 'Pinned official Windows Zig executable drift'}
$taskSourceManifest='src/env/fixtures/list-files-source-manifest-e6220e1.json'
if((Get-FileHash -LiteralPath $taskSourceManifest).Hash -cne $ExpectedSourceManifestHash){throw 'Original Source manifest drift'}
$taskOriginal=Get-Content -LiteralPath $taskSourceManifest -Raw|ConvertFrom-Json
if($taskOriginal.upstream -cne 'e6220e1316f86af818a0ccbfe1c09d7e918b41cf'){throw 'Original Source head drift'}
foreach($taskFixture in $taskOriginal.fixtures){if((Get-FileHash -LiteralPath $taskFixture.path).Hash -cne $taskFixture.sha256){throw "Original capture drift: $($taskFixture.path)"}}
if($taskOriginal.source_walk_cases -ne 20 -or $taskOriginal.source_ignore_cases -ne 89 -or $taskOriginal.source_error_cases -ne 6 -or $taskOriginal.source_windows_edge_cases -ne 6){throw 'Required original Source case inventory drift'}
$taskGuestManifest='src/extensions/fixtures/env-guest-source-manifest-e6220e1.json'
if((Get-FileHash -LiteralPath $taskGuestManifest).Hash -cne $ExpectedGuestManifestHash){throw 'Original guest Source manifest drift'}
$taskGuestOriginal=Get-Content -LiteralPath $taskGuestManifest -Raw|ConvertFrom-Json
if($taskGuestOriginal.upstream -cne 'e6220e1316f86af818a0ccbfe1c09d7e918b41cf' -or $taskGuestOriginal.public_guest_activation -or $taskGuestOriginal.full_env_package_qualified){throw 'Guest Source identity or activation boundary drift'}
foreach($taskFixture in $taskGuestOriginal.fixtures){if((Get-FileHash -LiteralPath $taskFixture.path).Hash -cne $taskFixture.sha256){throw "Original guest capture drift: $($taskFixture.path)"}}
if($ExpectedNodeReaderManifestHash){
    $taskNodeManifest='src/extensions/fixtures/env-node-readers-source-manifest-e6220e1.json'
    if((Get-FileHash -LiteralPath $taskNodeManifest).Hash -cne $ExpectedNodeReaderManifestHash){throw 'Original Node reader Source manifest drift'}
    $taskNodeOriginal=Get-Content -LiteralPath $taskNodeManifest -Raw|ConvertFrom-Json
    if($taskNodeOriginal.upstream -cne $taskOriginal.upstream -or $taskNodeOriginal.source_snapshot_tracked_files -ne 1902 -or $taskNodeOriginal.public_guest_activation -or $taskNodeOriginal.full_env_package_qualified -or $taskNodeOriginal.fixtures.Count -ne 8){throw 'Node reader Source identity, inventory or activation boundary drift'}
    foreach($taskFixture in $taskNodeOriginal.fixtures){if((Get-FileHash -LiteralPath $taskFixture.path).Hash -cne $taskFixture.sha256){throw "Original Node reader capture drift: $($taskFixture.path)"}}
}
if($ExpectedNodeFsManifestHash){
    $taskFsManifest='src/extensions/fixtures/env-node-fs-source-manifest-e6220e1.json'
    if((Get-FileHash -LiteralPath $taskFsManifest).Hash -cne $ExpectedNodeFsManifestHash){throw 'Original Node filesystem manifest drift'}
    $taskFsOriginal=Get-Content -LiteralPath $taskFsManifest -Raw|ConvertFrom-Json
    if($taskFsOriginal.upstream -cne $taskOriginal.upstream -or $taskFsOriginal.source_snapshot_tracked_files -ne 1902 -or $taskFsOriginal.source_corpora -ne 8 -or $taskFsOriginal.expected_guest_tests -ne 20 -or $taskFsOriginal.fixtures.Count -ne 18 -or $taskFsOriginal.public_guest_activation -or $taskFsOriginal.full_env_package_qualified -or $taskFsOriginal.posix_native_qualified){throw 'Node filesystem source identity inventory or scope drift'}
    foreach($taskFixture in $taskFsOriginal.fixtures){if((Get-FileHash -LiteralPath $taskFixture.path).Hash -cne $taskFixture.sha256){throw "Original filesystem capture drift: $($taskFixture.path)"}}
    $taskUvPath='vendor/libuv/PI-UPSTREAM-PROVENANCE.json'
    if((Get-FileHash -LiteralPath $taskUvPath).Hash -cne $taskFsOriginal.libuv_provenance_sha256){throw 'Pinned libuv provenance drift'}
    $taskUv=Get-Content -LiteralPath $taskUvPath -Raw|ConvertFrom-Json
    if($taskUv.commit -cne 'f657bb8ed86365ff3fdbe32e27563e778b41486a' -or $taskUv.version -cne '1.51.0' -or $taskUv.files.Count -ne 416){throw 'Pinned linked C source identity drift'}
    foreach($taskFile in $taskUv.files){if((Get-FileHash -LiteralPath (Join-Path 'vendor/libuv' $taskFile.path)).Hash -cne $taskFile.sha256){throw "Pinned libuv source drift: $($taskFile.path)"}}
    [ordered]@{source_fs_manifest_sha256=$ExpectedNodeFsManifestHash;upstream=$taskFsOriginal.upstream;source_corpora=$taskFsOriginal.source_corpora;expected_guest_tests=$taskFsOriginal.expected_guest_tests;libuv_provenance_sha256=$taskFsOriginal.libuv_provenance_sha256;scope=$taskFsOriginal.scope;full_env_package_qualified=$false;public_guest_activation=$false;posix_native_qualified=$false}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskReceipt 'filesystem-scope.json') -Encoding utf8NoBOM
}
$taskInputs=@(git ls-files|Sort-Object|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})
$taskToolRoot=Split-Path -Parent $taskZig
$taskTools=@(Get-ChildItem -LiteralPath $taskToolRoot -Recurse -File -Force|Sort-Object FullName|ForEach-Object{[ordered]@{path=$_.FullName;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}})
if($ExpectedCompilerManifestHash){
    $taskPinnedPath='verification/env-node-filehandle-primitives7-20261014/pinned-compiler-manifest.json'
    if((Get-FileHash -LiteralPath $taskPinnedPath).Hash -cne $ExpectedCompilerManifestHash){throw 'Pinned complete compiler proof drift'}
    $taskPinned=Get-Content -LiteralPath $taskPinnedPath -Raw|ConvertFrom-Json
    $taskExpectedTools=@{}
    foreach($taskFile in $taskPinned.inputs){$taskExpectedTools[$taskFile.path.Substring($taskPinned.root.Length+1).Replace('\','/')]=$taskFile.sha256}
    if($taskExpectedTools.Count -ne 19546 -or $taskTools.Count -ne 19546){throw 'Pinned complete compiler inventory mismatch'}
    foreach($taskFile in $taskTools){$taskRelative=[IO.Path]::GetRelativePath($taskToolRoot,$taskFile.path).Replace('\','/');if(!$taskExpectedTools.ContainsKey($taskRelative) -or $taskExpectedTools[$taskRelative] -cne $taskFile.sha256){throw "Pinned compiler input drift: $taskRelative"}}
}
$taskInputs|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskReceipt 'inputs-before.json') -Encoding utf8NoBOM
$taskTools|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskReceipt 'tools-before.json') -Encoding utf8NoBOM
$taskMinimumGiB=if($env:GITHUB_ACTIONS -ceq 'true'){8}else{16}
$taskFreeKiB=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
[ordered]@{free_kib=$taskFreeKiB;minimum_gib=$taskMinimumGiB;policy=if($taskMinimumGiB -eq 8){'Explicitly authorized sole hosted runner'}else{'Normal local16GiB'};checked_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content (Join-Path $taskReceipt 'admission.json')
if($taskFreeKiB -lt $taskMinimumGiB*1MB){throw 'Fresh native admission refused after full prehash'}
[ordered]@{head=$taskHead;tree=(git rev-parse 'HEAD^{tree}').Trim();upstream=$taskOriginal.upstream;mode=$Mode;phase=$Phase;source_count=$taskInputs.Count;tool_count=$taskTools.Count;source_manifest_sha256=$ExpectedSourceManifestHash;guest_manifest_sha256=$ExpectedGuestManifestHash;node_reader_manifest_sha256=$ExpectedNodeReaderManifestHash;zig=$taskZig;outer_seconds=$OuterSeconds;test_timeout_seconds=120;host_timeout_seconds=10;public_guest_activation=$false;full_env_package_qualified=$false;scope='Private Connection and RemoteExecutionEnv guest candidate plus original typed Env gates; Node/Local and full public package remain unqualified.'}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskReceipt 'source.json') -Encoding utf8NoBOM
$taskStart=[Diagnostics.ProcessStartInfo]::new()
$taskStart.FileName=$taskZig
$taskStart.WorkingDirectory=$taskRoot
$taskStart.UseShellExecute=$false
$taskStart.CreateNoWindow=$true
$taskStart.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
$taskStart.RedirectStandardOutput=$true
$taskStart.RedirectStandardError=$true
$taskSteps=if($Phase -ceq 'Compile'){@('build-hosted-native-env-guest')}else{@('test-native-env-guest','test-env-list-files','test-env')}
$taskArguments=@('build')+$taskSteps+@("-Doptimize=$Mode",'-Duse-llvm=true','-Ddiagnostic-tests=true','-j1','--test-timeout','120s','--summary','all')
foreach($taskArgument in $taskArguments){$taskStart.ArgumentList.Add($taskArgument)}
$taskProcess=[Diagnostics.Process]::new()
$taskProcess.StartInfo=$taskStart
if(!$taskProcess.Start()){throw 'Owned native qualification failed to launch'}
$taskCreated=$taskProcess.StartTime.ToUniversalTime()
$taskLive=Get-CimInstance Win32_Process -Filter "ProcessId = $($taskProcess.Id)"
$taskRecord=[ordered]@{pid=$taskProcess.Id;created_utc=$taskCreated.ToString('o');executable=$taskZig;argv=$taskArguments;command_line=if($taskLive){$taskLive.CommandLine}else{$null};status='running'}
$taskRecord|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskReceipt 'owned-process.json') -Encoding utf8NoBOM
$taskStdout=$taskProcess.StandardOutput.ReadToEndAsync()
$taskStderr=$taskProcess.StandardError.ReadToEndAsync()
$taskFinished=$taskProcess.WaitForExit($OuterSeconds*1000)
if(!$taskFinished){
    $taskFresh=Get-CimInstance Win32_Process -Filter "ProcessId = $($taskProcess.Id)"
    if(!$taskFresh -or $taskFresh.ExecutablePath -cne $taskZig -or [Math]::Abs((([DateTimeOffset]$taskFresh.CreationDate).UtcDateTime-$taskCreated).Ticks) -gt 10 -or $taskFresh.ExecutablePath -match 'codex'){throw 'Owned timeout identity mismatch; refusing process control'}
    if($taskLive -and $taskFresh.CommandLine -cne $taskLive.CommandLine){throw 'Owned timeout command identity changed'}
    $taskProcess.Kill($true)
    if(!$taskProcess.WaitForExit(10000)){throw 'Verified owned timeout process did not settle within 10 seconds after termination'}
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
$taskSourceDrift=@($taskInputs|Where-Object{!(Test-Path -LiteralPath $_.path) -or (Get-FileHash -LiteralPath $_.path).Hash -cne $_.sha256})
$taskToolDrift=@($taskTools|Where-Object{!(Test-Path -LiteralPath $_.path) -or (Get-FileHash -LiteralPath $_.path).Hash -cne $_.sha256})
[ordered]@{source_count=$taskInputs.Count;source_drift=$taskSourceDrift.Count;tool_count=$taskTools.Count;tool_drift=$taskToolDrift.Count;head_after=(git rev-parse HEAD).Trim();completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskReceipt 'posthash.json') -Encoding utf8NoBOM
if($taskSourceDrift.Count -or $taskToolDrift.Count -or (git rev-parse HEAD).Trim() -cne $ExpectedHead){throw 'Frozen native source/tool identity drift'}
if(!$taskFinished -or $taskProcess.ExitCode -ne 0){Write-Output $taskLog;throw "Native qualification terminal $($taskRecord.status)"}
if($Phase -ceq 'Compile'){
    if($taskLog -match '(?m)^\d+/\d+ .*\.\.\.' -or $taskLog.Contains('ENV_GUEST_TEST_INVENTORY=',[StringComparison]::Ordinal) -or $taskLog.Contains('ENV_LIST_FILES_TEST_INVENTORY=',[StringComparison]::Ordinal)){throw 'Compile-only phase unexpectedly executed tests'}
    [ordered]@{phase=$Phase;native_compilation='passed';runtime_tests_executed=$false;public_guest_activation=$false;full_env_package_qualified=$false;head=$taskHead}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskReceipt 'compile-only.json') -Encoding utf8NoBOM
    Write-Output $taskLog
    return
}
$taskMarkers=[regex]::Matches($taskLog,'(?m)^ENV_LIST_FILES_TEST_INVENTORY=(.+)\r?$')
if($taskMarkers.Count -ne 1){throw 'Missing or duplicate actual compiled inventory'}
$taskInventory=@($taskMarkers[0].Groups[1].Value|ConvertFrom-Json)
if(!$taskInventory.Count -or @($taskInventory|Sort-Object -Unique).Count -ne $taskInventory.Count){throw 'Empty or duplicate compiled test names'}
$taskWanted=@(foreach($taskFile in @('src/env_list_files_test.zig','src/env/list_files_test.zig','src/durable/list_ignore.zig')){foreach($taskMatch in [regex]::Matches([IO.File]::ReadAllText((Join-Path $taskRoot $taskFile)),'(?m)^test "([^"\r\n]+)"')){$taskMatch.Groups[1].Value}})
foreach($taskName in $taskWanted){if(@($taskInventory|Where-Object{$_.EndsWith('.test.'+$taskName,[StringComparison]::Ordinal)}).Count -ne 1){throw "Selected Source body absent or duplicated: $taskName"}}
if($taskWanted.Count -ne $taskInventory.Count){throw 'Actual compiled inventory has unmapped tests'}
$taskSkipped=@()
foreach($taskName in $taskInventory){
    if($taskName.EndsWith('.test.listFiles actual compiled inventory',[StringComparison]::Ordinal)){continue}
    $taskPattern='(?m)^\d+/'+$taskInventory.Count+' '+[regex]::Escape($taskName)+'\.\.\.(OK|SKIP)\r?$'
    $taskResult=[regex]::Matches($taskLog,$taskPattern)
    if($taskResult.Count -ne 1){throw "No unique completed selected test: $taskName"}
    if($taskResult[0].Groups[1].Value -ceq 'SKIP'){
        if(!$taskName.EndsWith('.test.listFiles links stay unfollowed while an explicit linked root can be listed',[StringComparison]::Ordinal)){throw "Mandatory Source case skipped: $taskName"}
        $taskSkipped+=$taskName
    }
}
$taskPassed=$taskInventory.Count-$taskSkipped.Count
$taskSummary=if($taskSkipped.Count){"$taskPassed passed; $($taskSkipped.Count) skipped; 0 failed."}else{"All $taskPassed tests passed."}
if(!$taskLog.Contains($taskSummary,[StringComparison]::Ordinal)){throw 'Incomplete selected test execution summary'}
[ordered]@{compiled_tests=$taskInventory.Count;source_named_tests=$taskWanted.Count;passed=$taskPassed;skipped=@($taskSkipped);failed=0;source_walk_cases=$taskOriginal.source_walk_cases;source_ignore_cases=$taskOriginal.source_ignore_cases;source_error_cases=$taskOriginal.source_error_cases;source_windows_edge_cases=$taskOriginal.source_windows_edge_cases;full_existing_env_gate='passed';inventory=$taskInventory;public_guest_activation=$false}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $taskReceipt 'coverage.json') -Encoding utf8NoBOM
Write-Output $taskLog
Get-Content -LiteralPath (Join-Path $taskReceipt 'coverage.json')

$taskGuestMarkers=[regex]::Matches($taskLog,'(?m)^ENV_GUEST_TEST_INVENTORY=(.+)\r?$')
if($taskGuestMarkers.Count -ne 1){throw 'Missing or duplicate actual guest compiled inventory'}
$taskGuestInventory=@($taskGuestMarkers[0].Groups[1].Value|ConvertFrom-Json)
if(!$taskGuestInventory.Count -or @($taskGuestInventory|Sort-Object -Unique).Count -ne $taskGuestInventory.Count){throw 'Empty or duplicate actual guest test names'}
$taskGuestWanted=@(foreach($taskMatch in [regex]::Matches([IO.File]::ReadAllText((Join-Path $taskRoot 'src/native_env_guest_test.zig')),'(?m)^test "([^"\r\n]+)"')){$taskMatch.Groups[1].Value})
if($ExpectedNodeFsManifestHash){
    if($taskGuestInventory.Count -ne $taskFsOriginal.expected_guest_tests){throw 'Private filesystem actual compiled inventory mismatch'}
    foreach($taskRequired in $taskFsOriginal.required_tests){if(@($taskGuestWanted|Where-Object{$_ -ceq $taskRequired}).Count -ne 1){throw "Mandatory filesystem Source comparator missing: $taskRequired"}}
}
if($ExpectedNodeReaderManifestHash){
    foreach($taskRequired in @('native Env guest Node public reader values and LineScanner match original Source virtual files','native Env guest public decoder exports preserve Source BOM globals and function values','native Env guest Node reader scan and text continuations release every host allocation failure')){
        if(@($taskGuestWanted|Where-Object{$_ -ceq $taskRequired}).Count -ne 1){throw "Mandatory Node reader Source comparator missing: $taskRequired"}
    }
}
foreach($taskName in $taskGuestWanted){if(@($taskGuestInventory|Where-Object{$_.EndsWith('.test.'+$taskName,[StringComparison]::Ordinal)}).Count -ne 1){throw "Guest Source body absent or duplicated: $taskName"}}
foreach($taskName in $taskGuestInventory){
    if(!$taskName.Contains('.test.native Env guest ',[StringComparison]::Ordinal) -and !$taskName.EndsWith('.test_0',[StringComparison]::Ordinal)){throw "Unmapped guest compiler-selected body: $taskName"}
    if($taskName.EndsWith('.test.native Env guest actual compiled inventory',[StringComparison]::Ordinal)){continue}
    $taskPattern='(?m)^\d+/'+$taskGuestInventory.Count+' '+[regex]::Escape($taskName)+'\.\.\.OK\r?$'
    if([regex]::Matches($taskLog,$taskPattern).Count -ne 1){throw "Missing terminal or skipped mandatory guest body: $taskName"}
}
if(!$taskLog.Contains("All $($taskGuestInventory.Count) tests passed.",[StringComparison]::Ordinal)){throw 'Incomplete guest selected execution'}
[ordered]@{actual_compiled_tests=$taskGuestInventory.Count;named_source_tests=$taskGuestWanted.Count;inventory=$taskGuestInventory;passed=$taskGuestInventory.Count;failed=0;skipped=0;source_manifest_sha256=$ExpectedGuestManifestHash;node_reader_manifest_sha256=$ExpectedNodeReaderManifestHash;node_fs_manifest_sha256=$ExpectedNodeFsManifestHash;public_guest_activation=$false;full_env_package_qualified=$false;scope=if($ExpectedNodeFsManifestHash){$taskFsOriginal.scope}elseif($ExpectedNodeReaderManifestHash){$taskNodeOriginal.scope}else{$taskGuestOriginal.scope}}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $taskReceipt 'guest-coverage.json') -Encoding utf8NoBOM

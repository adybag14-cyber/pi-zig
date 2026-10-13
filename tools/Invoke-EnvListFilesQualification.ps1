param(
    [ValidateSet('Debug','ReleaseSafe')][string]$Mode='Debug',
    [Parameter(Mandatory)][string]$ExpectedHead,
    [Parameter(Mandatory)][string]$ExpectedSourceManifestHash,
    [string]$Receipt='verification/env-list-files',
    [int]$OuterSeconds=300
)
$ErrorActionPreference='Stop'
$taskRoot=(Get-Location).ProviderPath
$taskReceipt=[IO.Path]::GetFullPath((Join-Path $taskRoot $Receipt))
if(!$taskReceipt.StartsWith($taskRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Receipt must remain in owned checkout'}
New-Item -ItemType Directory -Path $taskReceipt -Force|Out-Null
$taskHead=(git rev-parse HEAD).Trim()
if($taskHead -cne $ExpectedHead){throw 'Checkout head drift'}
$taskZig=(Get-Command zig -CommandType Application).Source
if((& $taskZig version).Trim() -cne '0.16.0'){throw 'Zig version drift'}
if((Get-FileHash -LiteralPath $taskZig).Hash -cne '086CE9D47BA42F33A514E1A6E04EB1D4A8FA1D75E0868E0213CAAD447C91E864'){throw 'Pinned official Windows Zig executable drift'}
$taskSourceManifest='src/env/fixtures/list-files-source-manifest-e6220e1.json'
if((Get-FileHash -LiteralPath $taskSourceManifest).Hash -cne $ExpectedSourceManifestHash){throw 'Original Source manifest drift'}
$taskOriginal=Get-Content -LiteralPath $taskSourceManifest -Raw|ConvertFrom-Json
if($taskOriginal.upstream -cne 'e6220e1316f86af818a0ccbfe1c09d7e918b41cf'){throw 'Original Source head drift'}
foreach($taskFixture in $taskOriginal.fixtures){if((Get-FileHash -LiteralPath $taskFixture.path).Hash -cne $taskFixture.sha256){throw "Original capture drift: $($taskFixture.path)"}}
if($taskOriginal.source_walk_cases -ne 20 -or $taskOriginal.source_ignore_cases -ne 89 -or $taskOriginal.source_error_cases -ne 6 -or $taskOriginal.source_windows_edge_cases -ne 6){throw 'Required original Source case inventory drift'}
$taskInputs=@(git ls-files|Sort-Object|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})
$taskToolRoot=Split-Path -Parent $taskZig
$taskTools=@(Get-ChildItem -LiteralPath $taskToolRoot -Recurse -File -Force|Sort-Object FullName|ForEach-Object{[ordered]@{path=$_.FullName;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}})
$taskInputs|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskReceipt 'inputs-before.json') -Encoding utf8NoBOM
$taskTools|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskReceipt 'tools-before.json') -Encoding utf8NoBOM
[ordered]@{head=$taskHead;tree=(git rev-parse 'HEAD^{tree}').Trim();upstream=$taskOriginal.upstream;mode=$Mode;source_count=$taskInputs.Count;tool_count=$taskTools.Count;source_manifest_sha256=$ExpectedSourceManifestHash;zig=$taskZig;outer_seconds=$OuterSeconds;test_timeout_seconds=120;public_guest_activation=$false;scope='Native typed Env and genuine daemon listing; full QuickJS Env guest module and full Pi parity remain separate.'}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskReceipt 'source.json') -Encoding utf8NoBOM
$taskStart=[Diagnostics.ProcessStartInfo]::new()
$taskStart.FileName=$taskZig
$taskStart.WorkingDirectory=$taskRoot
$taskStart.UseShellExecute=$false
$taskStart.CreateNoWindow=$true
$taskStart.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
$taskStart.RedirectStandardOutput=$true
$taskStart.RedirectStandardError=$true
$taskArguments=@('build','test-env-list-files','test-env',"-Doptimize=$Mode",'-Duse-llvm=true','-Ddiagnostic-tests=true','-j1','--test-timeout','120s','--summary','all')
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
    $taskProcess.WaitForExit()
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

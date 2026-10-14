$ErrorActionPreference='Stop'
$taskBase='C:\Users\adyba\pi-zig-update-evidence-20261003\hosted-reload-38630143843-20261014'
$taskHead='1e3b0f128ef368448be23954658400e45b63b3a4'
$taskDirs=@(Get-ChildItem -LiteralPath $taskBase -Directory)
if($taskDirs.Count -ne 6){throw 'Expected six token heuristic artifacts'}
$taskCanonical=$null
$taskAudit=@()
foreach($taskDir in $taskDirs){
    $taskResult=Get-Content -LiteralPath (Join-Path $taskDir.FullName 'result.json') -Raw|ConvertFrom-Json
    $taskSource=Get-Content -LiteralPath (Join-Path $taskDir.FullName 'source.json') -Raw|ConvertFrom-Json
    if($taskResult.head -cne $taskHead -or $taskSource.head -cne $taskHead -or $taskResult.status -cne 'passed'){throw 'Candidate identity/status mismatch'}
    if($taskResult.tests -ne 4 -or $taskResult.source_cases -ne 24 -or $taskResult.original_factory_instances -ne 0 -or $taskResult.test_timeout_seconds -ne 120 -or $taskResult.host_await_timeout_ms -ne 10000 -or $taskResult.public_activation -ne $false -or $taskResult.full_factory_qualified -ne $false){throw 'Candidate test inventory/scope/deadline mismatch'}
    $taskInputs=@(Get-Content -LiteralPath (Join-Path $taskDir.FullName 'inputs.json') -Raw|ConvertFrom-Json)
    $taskTools=@(Get-Content -LiteralPath (Join-Path $taskDir.FullName 'tools.json') -Raw|ConvertFrom-Json)
    if($taskInputs.Count -ne 5374 -or $taskTools.Count -ne 19546){throw 'Full source/compiler manifests missing'}
    $taskCanonicalNow=($taskInputs|ForEach-Object{$_.path+'='+$_.sha256}) -join "`n"
    if($null -eq $taskCanonical){$taskCanonical=$taskCanonicalNow}elseif($taskCanonical -cne $taskCanonicalNow){throw 'Cross-platform source bytes differ'}
    $taskInput=@($taskInputs|Where-Object path -eq 'src/extensions/fixtures/sdk-session-reload-b45.input.txt')
    if($taskInput.Count -ne 1 -or $taskInput[0].sha256 -cne '4465ADD379EFA7B278C635A815ED321EE3C85DA7FAB42BEE64C1A7FC355FFB0C'){throw 'Corrected original observer input missing'}
    foreach($taskKind in @('inputs','tools')){
        $taskPost=Get-Content -LiteralPath (Join-Path $taskDir.FullName ($taskKind+'-posthash.json')) -Raw|ConvertFrom-Json
        $taskCount=if($taskKind -eq 'inputs'){5374}else{19546}
        if($taskPost.count -ne $taskCount -or @($taskPost.drift).Count -ne 0){throw 'Frozen input/tool drift'}
    }
    $taskCompile=[IO.File]::ReadAllText((Join-Path $taskDir.FullName 'compile.log'))
    $taskLog=[IO.File]::ReadAllText((Join-Path $taskDir.FullName 'runtime.log'))
    if($taskCompile -notmatch '(?m)^Build Summary:.*steps succeeded' -or $taskCompile -match '\d+/\d+ tests passed'){throw 'Separate compile-only acceptance missing'}
    if($taskLog -notmatch '(?m)^Build Summary:.*4/4 tests passed' -or [regex]::Matches($taskLog,'(?ms)^test-native-sdk-session-reload success\r?\n[^\r\n]*run test 4 pass \(4 total\)').Count -ne 1){throw 'Complete native statistics execution missing'}
    $taskAudit += [ordered]@{artifact=$taskDir.Name;platform=$taskResult.platform;mode=$taskResult.mode;head=$taskHead;tests=4;original_cases=24;source_files=5374;compiler_files=19546;source_post_drift=0;compiler_post_drift=0;result_sha256=(Get-FileHash -LiteralPath (Join-Path $taskDir.FullName 'result.json')).Hash;runtime_log_sha256=(Get-FileHash -LiteralPath (Join-Path $taskDir.FullName 'runtime.log')).Hash}
}
$taskOutput=[ordered]@{status='all_six_downloaded_artifacts_independently_audited';run_id=38630143843;head=$taskHead;upstream='b45e0ebcc5ae2fc42a6f2f23104d10e656e6bedb';original_reference_owner='sdk-session-reload-b45-source24-first-20261014';scope='Original ordinary reload24 on caller-owned receivers, actual shared compat registry reset, method metadata and complete291-position representative host allocation sweep. Production builtin transports, full class/factory and application remain unqualified.';cross_platform_source_bytes_identical=$true;artifacts=$taskAudit;public_activation=$false;full_factory_qualified=$false;full_pi_qualified=$false;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}
[IO.File]::WriteAllText((Join-Path $taskBase 'six-artifacts-audit.json'),(($taskOutput|ConvertTo-Json -Depth 8).Replace("`r`n","`n"))+"`n",[Text.UTF8Encoding]::new($false))
Write-Output ('ORDINARY_RELOAD_ARTIFACTS_QUALIFIED='+$taskAudit.Count)

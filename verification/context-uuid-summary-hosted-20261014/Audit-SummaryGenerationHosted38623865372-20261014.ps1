$ErrorActionPreference='Stop'
$taskBase='C:\Users\adyba\pi-zig-update-evidence-20261003\hosted-summary-generation-38623865372-20261014'
$taskHead='0aa57a8ef9674cd464ee627e6d18ee918ca28327'
$taskDirs=@(Get-ChildItem -LiteralPath $taskBase -Directory)
if($taskDirs.Count -ne 6){throw 'Expected six token heuristic artifacts'}
$taskCanonical=$null
$taskAudit=@()
foreach($taskDir in $taskDirs){
    $taskResult=Get-Content -LiteralPath (Join-Path $taskDir.FullName 'result.json') -Raw|ConvertFrom-Json
    $taskSource=Get-Content -LiteralPath (Join-Path $taskDir.FullName 'source.json') -Raw|ConvertFrom-Json
    if($taskResult.head -cne $taskHead -or $taskSource.head -cne $taskHead -or $taskResult.status -cne 'passed'){throw 'Candidate identity/status mismatch'}
    if($taskResult.tests -ne 8 -or $taskResult.source_cases -ne 73 -or $taskResult.request_cases -ne 28 -or $taskResult.generation_cases -ne 45 -or $taskResult.global_compat_qualified -ne $false -or $taskResult.session_manual_compact_qualified -ne $false -or $taskResult.original_factory_instances -ne 0 -or $taskResult.test_timeout_seconds -ne 120 -or $taskResult.host_await_timeout_ms -ne 10000 -or $taskResult.public_activation -ne $false -or $taskResult.full_factory_qualified -ne $false){throw 'Candidate test inventory/scope/deadline mismatch'}
    $taskInputs=@(Get-Content -LiteralPath (Join-Path $taskDir.FullName 'inputs.json') -Raw|ConvertFrom-Json)
    $taskTools=@(Get-Content -LiteralPath (Join-Path $taskDir.FullName 'tools.json') -Raw|ConvertFrom-Json)
    if($taskInputs.Count -ne 5277 -or $taskTools.Count -ne 19546){throw 'Full source/compiler manifests missing'}
    $taskCanonicalNow=($taskInputs|ForEach-Object{$_.path+'='+$_.sha256}) -join "`n"
    if($null -eq $taskCanonical){$taskCanonical=$taskCanonicalNow}elseif($taskCanonical -cne $taskCanonicalNow){throw 'Cross-platform source bytes differ'}
    foreach($taskKind in @('inputs','tools')){
        $taskPost=Get-Content -LiteralPath (Join-Path $taskDir.FullName ($taskKind+'-posthash.json')) -Raw|ConvertFrom-Json
        $taskCount=if($taskKind -eq 'inputs'){5277}else{19546}
        if($taskPost.count -ne $taskCount -or @($taskPost.drift).Count -ne 0){throw 'Frozen input/tool drift'}
    }
    $taskCompile=[IO.File]::ReadAllText((Join-Path $taskDir.FullName 'compile.log'))
    $taskLog=[IO.File]::ReadAllText((Join-Path $taskDir.FullName 'runtime.log'))
    if($taskCompile -notmatch '(?m)^Build Summary:.*steps succeeded' -or $taskCompile -match '\d+/\d+ tests passed'){throw 'Separate compile-only acceptance missing'}
    if($taskLog -notmatch '(?m)^Build Summary:.*8/8 tests passed'){throw 'All eight summary helper tests missing'}
    foreach($taskTarget in @('test-native-sdk-complete-summarization','test-native-sdk-summary-generation')){
        if([regex]::Matches($taskLog, '(?ms)^'+[regex]::Escape($taskTarget)+' success\r?\n[^\r\n]*run test 4 pass \(4 total\)').Count -ne 1){throw "Target inventory missing $taskTarget"}
    }
    $taskAudit += [ordered]@{artifact=$taskDir.Name;platform=$taskResult.platform;mode=$taskResult.mode;head=$taskHead;tests=8;original_cases=73;source_files=5277;compiler_files=19546;source_post_drift=0;compiler_post_drift=0;result_sha256=(Get-FileHash -LiteralPath (Join-Path $taskDir.FullName 'result.json')).Hash;runtime_log_sha256=(Get-FileHash -LiteralPath (Join-Path $taskDir.FullName 'runtime.log')).Hash}
}
$taskOutput=[ordered]@{status='all_six_downloaded_artifacts_independently_audited';run_id=38623865372;head=$taskHead;upstream='b45e0ebcc5ae2fc42a6f2f23104d10e656e6bedb';original_reference_owner='sdk-summary-generation-b45-source45-first-20261014';scope='Genuine b45 completeSummarization28 and summary generation45 comparisons, native metadata/GC and complete representative host allocation sweeps. Global provider compatibility, manual session compaction and full application remain unqualified.';cross_platform_source_bytes_identical=$true;artifacts=$taskAudit;public_activation=$false;full_factory_qualified=$false;full_pi_qualified=$false;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}
[IO.File]::WriteAllText((Join-Path $taskBase 'six-artifacts-audit.json'),(($taskOutput|ConvertTo-Json -Depth 8).Replace("`r`n","`n"))+"`n",[Text.UTF8Encoding]::new($false))
Write-Output ('SUMMARY_GENERATION_ARTIFACTS_QUALIFIED='+$taskAudit.Count)

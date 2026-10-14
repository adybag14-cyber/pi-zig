$ErrorActionPreference='Stop'
$taskEvidence=$PSScriptRoot
$taskConfigs=@(
 @{directory='hosted-context-restore-38610577795-20261014';run=38610577795;head='6508c242bf1deba37379ee714c6038e671c08e38';source=5176;tests=18;cases=42;targets=@(@{name='test-native-ai-transcript-context';count=4},@{name='test-native-sdk-session-restore';count=4},@{name='test-native-sdk-constructor-phase';count=10});scope='Context20/transcript restore22 and constructor initialization only; full session factory remains unqualified'},
 @{directory='hosted-uuid-38613431173-20261014';run=38613431173;head='b48183066fb9245809a717c63629548ba6760037';source=5209;tests=6;cases=26;targets=@(@{name='test-native-ai-uuid';count=4},@{name='test-native-binary-operators';count=2});scope='Original UUID26 and native operators; production secure Crypto is separate and full application remains unqualified'}
)
foreach($taskConfig in $taskConfigs){
 $taskBase=Join-Path $taskEvidence $taskConfig.directory
 $taskDirs=@(Get-ChildItem -LiteralPath $taskBase -Directory)
 if($taskDirs.Count -ne 6){throw 'Six complete downloaded artifacts required'}
 $taskProfiles=[Collections.Generic.HashSet[string]]::new()
 $taskCanonical=$null
 $taskAudit=@()
 foreach($taskDir in $taskDirs){
  $taskResult=Get-Content -LiteralPath (Join-Path $taskDir.FullName 'result.json') -Raw|ConvertFrom-Json
  $taskSource=Get-Content -LiteralPath (Join-Path $taskDir.FullName 'source.json') -Raw|ConvertFrom-Json
  if($taskResult.head -cne $taskConfig.head -or $taskSource.head -cne $taskConfig.head -or $taskResult.status -cne 'passed'){throw 'Exact source head/status mismatch'}
  if($taskResult.tests -ne $taskConfig.tests -or $taskResult.source_cases -ne $taskConfig.cases -or $taskResult.original_factory_instances -ne 0 -or $taskResult.public_activation -ne $false -or $taskResult.full_factory_qualified -ne $false -or $taskResult.test_timeout_seconds -ne 120 -or $taskResult.host_await_timeout_ms -ne 10000){throw 'Scope/inventory/deadline mismatch'}
  if($taskResult.platform -cnotin @('windows-latest','ubuntu-latest','macos-latest') -or $taskResult.mode -cnotin @('Debug','ReleaseSafe') -or !$taskProfiles.Add($taskResult.platform+'/'+$taskResult.mode)){throw 'Unexpected or duplicate profile'}
  $taskInputs=@(Get-Content -LiteralPath (Join-Path $taskDir.FullName 'inputs.json') -Raw|ConvertFrom-Json)
  $taskTools=@(Get-Content -LiteralPath (Join-Path $taskDir.FullName 'tools.json') -Raw|ConvertFrom-Json)
  if($taskInputs.Count -ne $taskConfig.source -or $taskTools.Count -ne 19546 -or $taskSource.source_count -ne $taskInputs.Count -or $taskSource.tool_count -ne $taskTools.Count){throw 'Full source/compiler inventory mismatch'}
  $taskCanonicalNow=($taskInputs|ForEach-Object{$_.path+'='+$_.sha256}) -join "`n"
  if($null -eq $taskCanonical){$taskCanonical=$taskCanonicalNow}elseif($taskCanonical -cne $taskCanonicalNow){throw 'Cross-platform source bytes differ'}
  foreach($taskKind in @('inputs','tools')){
   $taskPost=Get-Content -LiteralPath (Join-Path $taskDir.FullName ($taskKind+'-posthash.json')) -Raw|ConvertFrom-Json
   $taskCount=if($taskKind -eq 'inputs'){$taskConfig.source}else{19546}
   if($taskPost.count -ne $taskCount -or @($taskPost.drift).Count -ne 0){throw 'Frozen input/tool posthash mismatch'}
  }
  $taskCompile=[IO.File]::ReadAllText((Join-Path $taskDir.FullName 'compile.log'))
  $taskLog=[IO.File]::ReadAllText((Join-Path $taskDir.FullName 'runtime.log'))
  if($taskCompile -notmatch '(?m)^Build Summary:.*steps succeeded' -or $taskCompile -match '\d+/\d+ tests passed'){throw 'Separate compile acceptance missing'}
  if($taskLog -notmatch ('(?m)^Build Summary:.*\b'+$taskConfig.tests+'/'+$taskConfig.tests+' tests passed')){throw 'Complete runtime inventory missing'}
  foreach($taskTarget in $taskConfig.targets){
   $taskPattern='(?ms)^'+[regex]::Escape($taskTarget.name)+' success\r?\n[^\r\n]*run test '+$taskTarget.count+' pass \('+$taskTarget.count+' total\)'
   if([regex]::Matches($taskLog,$taskPattern).Count -ne 1){throw 'Required native artifact did not execute exactly once'}
  }
  $taskAudit+=@{platform=$taskResult.platform;mode=$taskResult.mode;source_files=$taskInputs.Count;compiler_files=$taskTools.Count;tests=$taskResult.tests;source_cases=$taskResult.source_cases;source_post_drift=0;compiler_post_drift=0;result_sha256=(Get-FileHash -LiteralPath (Join-Path $taskDir.FullName 'result.json')).Hash;runtime_sha256=(Get-FileHash -LiteralPath (Join-Path $taskDir.FullName 'runtime.log')).Hash}
 }
 $taskOutput=@{status='all_six_downloaded_artifacts_independently_audited';head=$taskConfig.head;run_id=$taskConfig.run;scope=$taskConfig.scope;cross_platform_source_bytes_identical=$true;artifacts=$taskAudit;public_activation=$false;full_factory_qualified=$false;full_pi_qualified=$false;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}
 [IO.File]::WriteAllText((Join-Path $taskBase 'six-artifacts-audit.json'),(($taskOutput|ConvertTo-Json -Depth 8).Replace("`r`n","`n"))+"`n",[Text.UTF8Encoding]::new($false))
 Write-Output ('HOSTED_ARTIFACTS_AUDITED='+$taskConfig.run+':'+$taskAudit.Count)
}

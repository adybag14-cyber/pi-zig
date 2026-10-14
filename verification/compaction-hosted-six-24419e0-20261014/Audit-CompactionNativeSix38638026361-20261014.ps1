$ErrorActionPreference='Stop'
$taskBase=Join-Path $PSScriptRoot 'hosted-compaction84-24419e0-38638026361-20261014'
$taskHead='24419e00ee8b5af1ebfc96eeffb247e4bd63c257'
$taskDirs=@(Get-ChildItem -LiteralPath $taskBase -Directory)
if($taskDirs.Count -ne 6){throw 'Six downloaded native profiles required'}
$taskProfiles=[Collections.Generic.HashSet[string]]::new();$taskCanonical=$null;$taskAudit=@()
foreach($taskDir in $taskDirs){
 $taskResult=Get-Content -LiteralPath (Join-Path $taskDir.FullName 'result.json') -Raw|ConvertFrom-Json -Depth 10
 $taskSource=Get-Content -LiteralPath (Join-Path $taskDir.FullName 'source.json') -Raw|ConvertFrom-Json
 if($taskResult.head -cne $taskHead -or $taskSource.head -cne $taskHead -or $taskResult.status -cne 'passed' -or $taskResult.tests_each -ne 10 -or $taskResult.partitions -ne 8 -or $taskResult.source_cases -ne 84 -or $taskResult.manual_cases -ne 44 -or $taskResult.automatic_cases -ne 40){throw 'Native exact source/inventory mismatch'}
 if($taskResult.public_activation -ne $false -or $taskResult.full_class_qualified -ne $false -or $taskResult.full_factory_qualified -ne $false -or $taskResult.full_pi_qualified -ne $false -or $taskResult.test_timeout_seconds -ne 120 -or $taskResult.outer_timeout_seconds -ne 300 -or $taskResult.host_await_timeout_ms -ne 10000){throw 'Scope/deadline mismatch'}
 if($taskResult.platform -cnotin @('windows-latest','ubuntu-latest','macos-latest') -or $taskResult.mode -cnotin @('Debug','ReleaseSafe') -or !$taskProfiles.Add($taskResult.platform+'/'+$taskResult.mode)){throw 'Unexpected/duplicate native profile'}
 foreach($taskKind in @('inputs','tools')){
  $taskRows=@(Get-Content -LiteralPath (Join-Path $taskDir.FullName ($taskKind+'.json')) -Raw|ConvertFrom-Json)
  $taskCount=if($taskKind -eq 'inputs'){5488}else{19546}
  $taskPost=Get-Content -LiteralPath (Join-Path $taskDir.FullName ($taskKind+'-posthash.json')) -Raw|ConvertFrom-Json
  if($taskRows.Count -ne $taskCount -or $taskPost.count -ne $taskCount -or @($taskPost.drift).Count -ne 0){throw 'Complete frozen manifest/posthash mismatch'}
  if($taskKind -eq 'inputs'){$taskNow=($taskRows|ForEach-Object{$_.path+'='+$_.sha256})-join "`n";if($null -eq $taskCanonical){$taskCanonical=$taskNow}elseif($taskCanonical -cne $taskNow){throw 'Cross-platform source bytes differ'}}
 }
 $taskCompile=Get-Content -LiteralPath (Join-Path $taskDir.FullName 'compile.process.json') -Raw|ConvertFrom-Json
 if($taskCompile.status -cne 'passed' -or $taskCompile.outer_seconds -ne 1320){throw 'Separate bounded compile did not pass'}
 $taskCoverage=@()
 foreach($taskFamily in @('sdk-manual-compact44','sdk-auto-compact40')){
  $taskTotal=if($taskFamily -eq 'sdk-manual-compact44'){2256}else{2503};$taskPrevious=0;$taskIndices=[Collections.Generic.List[int]]::new()
  foreach($taskShard in 0..7){
   $taskOwner=Get-Content -LiteralPath (Join-Path $taskDir.FullName ("shard-$taskShard.process.json")) -Raw|ConvertFrom-Json
   if($taskOwner.status -cne 'passed' -or $taskOwner.outer_seconds -ne 300){throw 'Bounded native partition did not pass'}
   $taskLog=[IO.File]::ReadAllText((Join-Path $taskDir.FullName ("shard-$taskShard.stderr.log")))
   if($taskLog -notmatch '(?m)^Build Summary:.*\b10/10 tests passed'){throw 'All10 native tests missing'}
   foreach($taskTarget in @('test-native-sdk-session-compaction','test-native-sdk-session-auto-compaction')){if([regex]::Matches($taskLog,'(?ms)^'+[regex]::Escape($taskTarget)+' success\r?\n[^\r\n]*run test 5 pass \(5 total\)').Count -ne 1){throw 'Native artifact inventory mismatch'}}
   $taskRange=@([regex]::Matches($taskLog,'(?m)^EXHAUSTIVE_ALLOCATION_RANGE '+[regex]::Escape($taskFamily)+' (\d+)/(\d+) range=\[(\d+),(\d+)\) total=(\d+)$'))
   if($taskRange.Count -ne 1){throw 'Native allocation range missing/repeated'}
   $taskValues=@($taskRange[0].Groups|Select-Object -Skip 1|ForEach-Object{[long]$_.Value});$taskStart=$taskValues[2];$taskEnd=$taskValues[3]
   if($taskValues[0] -ne $taskShard -or $taskValues[1] -ne 8 -or $taskValues[4] -ne $taskTotal -or $taskStart -ne $taskPrevious -or $taskStart -ne [math]::Floor($taskTotal*$taskShard/8) -or $taskEnd -ne [math]::Floor($taskTotal*($taskShard+1)/8)){throw 'Native universe gap/overlap/change'}
   $taskBaseline=@([regex]::Matches($taskLog,'(?m)^EXHAUSTIVE_ALLOCATION_BASELINE '+[regex]::Escape($taskFamily)+' total=(\d+)$'))
   if($taskBaseline.Count -ne 1 -or [long]$taskBaseline[0].Groups[1].Value -ne $taskTotal){throw 'Independent unlimited baseline absent'}
   $taskBegun=@([regex]::Matches($taskLog,'(?m)^EXHAUSTIVE_ALLOCATION_INDEX_BEGIN '+[regex]::Escape($taskFamily)+' (\d+)$')|ForEach-Object{[int]$_.Groups[1].Value})
   $taskDone=@([regex]::Matches($taskLog,'(?m)^EXHAUSTIVE_ALLOCATION_INDEX_COMPLETE '+[regex]::Escape($taskFamily)+' (\d+)$')|ForEach-Object{[int]$_.Groups[1].Value})
   if($taskBegun.Count -ne ($taskEnd-$taskStart) -or $taskDone.Count -ne $taskBegun.Count){throw 'Native allocation position did not finish'}
   for($taskIndex=0;$taskIndex -lt $taskDone.Count;$taskIndex++){if($taskBegun[$taskIndex] -ne ($taskStart+$taskIndex) -or $taskDone[$taskIndex] -ne ($taskStart+$taskIndex)){throw 'Native position skipped/duplicated'};$taskIndices.Add($taskDone[$taskIndex])}
   $taskComplete="EXHAUSTIVE_ALLOCATION_COMPLETE $taskFamily $taskShard/8 range=[$taskStart,$taskEnd) total=$taskTotal"
   if([regex]::Matches($taskLog,[regex]::Escape($taskComplete)).Count -ne 1){throw 'Native terminal partition marker absent'}
   $taskPrevious=$taskEnd
  }
  if($taskPrevious -ne $taskTotal -or $taskIndices.Count -ne $taskTotal -or @($taskIndices|Sort-Object -Unique).Count -ne $taskTotal){throw 'Native complete universe missing'}
  $taskCoverage+=@{family=$taskFamily;baseline=$taskTotal;completed=$taskIndices.Count;gaps=0;duplicates=0}
 }
 $taskAudit+=@{platform=$taskResult.platform;mode=$taskResult.mode;tests_each=10;partitions=8;source_cases=84;source_files=5488;compiler_files=19546;source_post_drift=0;compiler_post_drift=0;coverage=$taskCoverage;result_sha256=(Get-FileHash -LiteralPath (Join-Path $taskDir.FullName 'result.json')).Hash}
}
$taskReference=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'compaction-posix-source84-5fb-38636729729-20261014/source-qualification.json') -Raw|ConvertFrom-Json -Depth 12
if($taskReference.status -cne 'actual_posix84_independently_audited' -or !$taskReference.full_posix84_rows_identical -or !$taskReference.windows83_platform_independent_rows_identical){throw 'Genuine platform original audit missing'}
@{status='all_six_native_profiles_independently_audited';head=$taskHead;run=38638026361;cross_platform_source_bytes_identical=$true;source_cases=84;reference_source='b45e0ebcc5ae2fc42a6f2f23104d10e656e6bedb';posix_original_run=38636729729;profiles=$taskAudit;public_activation=$false;full_class_qualified=$false;full_factory_qualified=$false;full_pi_qualified=$false;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $taskBase 'six-artifacts-audit.json') -Encoding utf8NoBOM
Write-Output 'COMPACTION84_ALL_SIX_FULL_UNIVERSES_VERIFIED'

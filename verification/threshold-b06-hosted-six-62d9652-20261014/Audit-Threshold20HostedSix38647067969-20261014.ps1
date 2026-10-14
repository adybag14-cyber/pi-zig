$ErrorActionPreference='Stop'
$taskRepo='C:/Users/adyba/pi-zig-native-session-factory-composition-20261013'
$taskHead='62d96523bb3181ef20ba7a8fbe788a0d12860e20'
$taskRoot=Join-Path $PSScriptRoot 'threshold20-hosted-six-62d9652-38647067969-20261014'
$taskAuthorityZip=Join-Path $PSScriptRoot 'threshold20-62d9652-git-authority-20261014.zip'
if(!(Test-Path -LiteralPath $taskAuthorityZip)){& git -C $taskRepo archive --format=zip --output=$taskAuthorityZip $taskHead;if($LASTEXITCODE){throw 'Git authority archive failed'}}
$taskTree=(& git -C $taskRepo rev-parse ($taskHead+'^{tree}')).Trim()
$taskExpected=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
$taskArchive=[IO.Compression.ZipFile]::OpenRead($taskAuthorityZip)
try{
 foreach($entry in $taskArchive.Entries){if(!$entry.Name){continue};$stream=$entry.Open();try{$hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream))}finally{$stream.Dispose()};$taskExpected.Add($entry.FullName,$hash)}
}finally{$taskArchive.Dispose()}
if($taskExpected.Count -ne 5576){throw 'Exact source Git inventory count changed'}
$taskFolders=@(Get-ChildItem -LiteralPath $taskRoot -Directory)
if($taskFolders.Count -ne 6){throw 'Six independent artifacts required'}
$taskResults=@()
foreach($folder in $taskFolders){
 $source=Get-Content -LiteralPath (Join-Path $folder.FullName 'source.json') -Raw|ConvertFrom-Json
 $result=Get-Content -LiteralPath (Join-Path $folder.FullName 'result.json') -Raw|ConvertFrom-Json
 if($source.head -cne $taskHead -or $source.tree -cne $taskTree -or $result.head -cne $taskHead -or $result.status -cne 'passed' -or $result.tests -ne 16 -or $result.source_cases -ne 20 -or $source.original_head -cne 'b06c1f2cf1dea6af8748ddeee18c23587d2cb7c6' -or $source.public_activation -or $result.public_activation -or $result.full_pi_qualified){throw 'Exact artifact scope or head changed'}
 if($folder.Name -cne "native-sdk-compaction-threshold-$($source.platform)-$($source.mode)-$taskHead"){throw 'Artifact profile identity mismatch'}
 $inputs=@(Get-Content -LiteralPath (Join-Path $folder.FullName 'inputs.json') -Raw|ConvertFrom-Json)
 if($inputs.Count -ne $taskExpected.Count -or @($inputs.path|Sort-Object -Unique).Count -ne $taskExpected.Count){throw 'Frozen source inventory incomplete'}
 foreach($row in $inputs){if(!$taskExpected.ContainsKey($row.path) -or $taskExpected[$row.path] -cne $row.sha256){throw "Git source bytes differ at $($row.path)"}}
 foreach($kind in @('inputs','tools')){
  $rows=@(Get-Content -LiteralPath (Join-Path $folder.FullName "$kind.json") -Raw|ConvertFrom-Json)
  $post=Get-Content -LiteralPath (Join-Path $folder.FullName "$kind-posthash.json") -Raw|ConvertFrom-Json
  if($post.count -ne $rows.Count -or @($post.drift).Count -or $post.inventory_drift -or @($rows.path|Sort-Object -Unique).Count -ne $rows.Count){throw 'Whole source/tool freeze not intact'}
  if($kind -eq 'tools' -and ($rows.Count -ne $source.tool_count -or $rows.Count -ne 19546)){throw 'Complete compiler inventory changed'}
 }
 foreach($phase in @('compile','runtime')){
  $owner=Get-Content -LiteralPath (Join-Path $folder.FullName "$phase.process.json") -Raw|ConvertFrom-Json
  if($owner.status -cne 'passed' -or $owner.exit_code -ne 0 -or $owner.outer_seconds -ne $(if($phase -eq 'compile'){1320}else{300}) -or $owner.settle_seconds -ne 10 -or '-j1' -cnotin $owner.argv -or "-Doptimize=$($source.mode)" -cnotin $owner.argv){throw 'Owned terminal/bounds mismatch'}
  $toolRows=@(Get-Content -LiteralPath (Join-Path $folder.FullName 'tools.json') -Raw|ConvertFrom-Json)
  $exe=@($toolRows|Where-Object path -CEQ $owner.executable)
  if($exe.Count -ne 1 -or $exe[0].sha256 -cne $owner.executable_sha256){throw 'Actual executable not frozen compiler'}
  if($phase -eq 'runtime' -and ('120s' -cnotin $owner.argv -or '--test-timeout' -cnotin $owner.argv)){throw 'Native test deadline changed'}
 }
 $log=Get-Content -LiteralPath (Join-Path $folder.FullName 'runtime.stderr.log') -Raw
 if($log -notmatch '(?m)^Build Summary:.*\b16/16 tests passed'){throw 'Actual selected tests did not pass'}
 $inventoryMarkers=@([regex]::Matches($log,'(?m)^COMPACTION_THRESHOLD_TEST_INVENTORY=(\[[^\r\n]*\])'))
 if($inventoryMarkers.Count -ne 1){throw 'Exact compiled test inventory missing'}
 $inventory=@($inventoryMarkers[0].Groups[1].Value|ConvertFrom-Json)
 if($inventory.Count -ne 16 -or @($inventory|Sort-Object -Unique).Count -ne 16){throw 'Actual compiled inventory changed'}
 foreach($name in @('native compaction threshold matches genuine b06 method and live override dispatch','native compaction threshold complete host allocation universe','native compaction threshold ordinary descriptor','native SDK session events constructor hooks match 16 genuine factory Source projection request boundary tool and nested-recorder cases','native SDK session events compaction utilities match original Source values getters and failures','native SDK constructor initialization phase matches66 original live field descriptors and actual native hooks')){
  if(@($inventory|Where-Object{$_.EndsWith('.test.'+$name,[StringComparison]::Ordinal)}).Count -ne 1){throw 'Required exact compiled regression missing'}
 }
 $baseline=@([regex]::Matches($log,'(?m)^EXHAUSTIVE_ALLOCATION_BASELINE compaction-threshold20 total=(\d+)$'))
 if($baseline.Count -ne 1 -or $baseline[0].Groups[1].Value -cne '133' -or $result.baseline -ne 133 -or $result.completed -ne 133 -or $result.missing -ne 0 -or $result.duplicates -ne 0){throw 'Complete baseline133 mismatch'}
 $begun=@([regex]::Matches($log,'(?m)^EXHAUSTIVE_ALLOCATION_INDEX_BEGIN compaction-threshold20 (\d+)$')|ForEach-Object{[int]$_.Groups[1].Value})
 $done=@([regex]::Matches($log,'(?m)^EXHAUSTIVE_ALLOCATION_INDEX_COMPLETE compaction-threshold20 (\d+)$')|ForEach-Object{[int]$_.Groups[1].Value})
 if($begun.Count -ne 133 -or $done.Count -ne 133){throw 'Actual positions missing'}
 for($index=0;$index -lt 133;$index++){if($begun[$index] -ne $index -or $done[$index] -ne $index){throw 'Actual position gap/duplicate'}}
 foreach($marker in @('EXHAUSTIVE_ALLOCATION_RANGE compaction-threshold20 0/1 range=[0,133) total=133','EXHAUSTIVE_ALLOCATION_COMPLETE compaction-threshold20 0/1 range=[0,133) total=133')){if([regex]::Matches($log,'(?m)^'+[regex]::Escape($marker)+'\r?$').Count -ne 1){throw 'Exact terminal range missing'}}
 $taskResults+=@{platform=$source.platform;mode=$source.mode;source=$inputs.Count;compiler=$source.tool_count;tests=16;source_cases=20;host_positions=133;source_git_sha256_all_verified=$true;all_post_drift=0}
}
if(@($taskResults|ForEach-Object{"$($_.platform):$($_.mode)"}|Sort-Object -Unique).Count -ne 6){throw 'Profile repeated or missing'}
$taskAudit=[ordered]@{run=38647067969;head=$taskHead;tree=$taskTree;status='all_six_independently_audited';profiles=$taskResults;total_selected_test_executions=96;total_host_failure_positions=798;genuine_reference_cases=20;genuine_posix_source_capture_qualified=$false;full_factory_qualified=$false;full_pi_qualified=$false;public_activation=$false;auditor_sha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}
$taskAudit|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $taskRoot 'six-artifacts-audit.json') -Encoding utf8NoBOM
$taskAudit|ConvertTo-Json -Depth 8

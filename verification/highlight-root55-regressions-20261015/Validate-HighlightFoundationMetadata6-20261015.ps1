$ErrorActionPreference='Stop'
$taskPrefix=Join-Path $PSScriptRoot 'highlight-root55-foundation-compile-first-20261015'
$taskRaw="$taskPrefix-metadata-probe.stdout.bin"
$taskProbe=Get-Content -Raw "$taskPrefix-metadata-probe.json"|ConvertFrom-Json
$taskCompile=Get-Content -Raw "$taskPrefix.json"|ConvertFrom-Json
$taskPost=Get-Content -Raw "$taskPrefix-posthash.json"|ConvertFrom-Json
if($taskProbe.status -cne 'passed' -or $taskCompile.status -cne 'passed' -or $taskPost.candidate_drift.Count -or $taskPost.control_drift.Count -or $taskPost.absence_drift.Count -or @($taskPost.manifests|Where-Object {$_.drift.Count}).Count -or @($taskPost.inventories|Where-Object {$_.drift.Count}).Count){throw 'Original successful compile/probe/fullpost0 required'}
$taskBytes=[IO.File]::ReadAllBytes($taskRaw);$taskOffset=0;$taskNames=@();$taskVersion=$null
while($taskOffset -lt $taskBytes.Length){
 if($taskOffset+8 -gt $taskBytes.Length){throw 'Truncated metadata header'}
 $taskTag=[BitConverter]::ToUInt32($taskBytes,$taskOffset);$taskLength=[BitConverter]::ToUInt32($taskBytes,$taskOffset+4);$taskOffset+=8
 if($taskLength -gt 1MB -or $taskOffset+$taskLength -gt $taskBytes.Length){throw 'Metadata bound mismatch'}
 if($taskTag -eq 0){$taskVersion=[Text.Encoding]::UTF8.GetString($taskBytes,$taskOffset,$taskLength)}
 elseif($taskTag -eq 3){
  $taskStrings=[BitConverter]::ToUInt32($taskBytes,$taskOffset);$taskCount=[BitConverter]::ToUInt32($taskBytes,$taskOffset+4)
  if($taskCount -ne 6 -or $taskNames.Count -or $taskLength -ne 8+8*$taskCount+$taskStrings){throw 'Exact six-entry metadata array required'}
  $taskStart=$taskOffset+8+8*$taskCount
  for($taskIndex=0;$taskIndex -lt $taskCount;$taskIndex++){
   $taskAt=[BitConverter]::ToUInt32($taskBytes,$taskOffset+8+4*$taskIndex);$taskPanic=[BitConverter]::ToUInt32($taskBytes,$taskOffset+8+4*$taskCount+4*$taskIndex)
   if($taskPanic -or $taskAt -ge $taskStrings){throw 'Unexpected panic/offset metadata'}
   $taskEnd=$taskAt;while($taskEnd -lt $taskStrings -and $taskBytes[$taskStart+$taskEnd] -ne 0){$taskEnd++}
   if($taskEnd -eq $taskStrings){throw 'Unterminated name'}
   $taskNames+=[Text.Encoding]::UTF8.GetString($taskBytes,$taskStart+$taskAt,$taskEnd-$taskAt)
  }
 }else{throw "Unexpected metadata-only tag $taskTag"}
 $taskOffset+=$taskLength
}
$taskExpected=@(
 'native_highlight_legacy32_function_test.test.native legacy32 CJS function matches actual Original32 callers arguments poison descriptors freeze and GC',
 'native_highlight_core_b45_test.test.native full eager21 highlight core matches genuine Original74 factories scanner output token trees classes and frontend',
 'native_highlight_scope_test.test.native highlight inline roots nested actual grammar scanner completes128 levels and recovers',
 'native_highlight_scope_test.test.native highlight inline roots match genuine Original deep7 exact caller self and distinct nested grammar results',
 'native_highlight_core_profile_test.test.native highlight inline profile registration preserves proven host OOM and ordinary guest lookalikes',
 'extensions.native_durable_storage.test_0'
)
if($taskVersion -cne '0.16.0' -or $taskNames.Count -ne 6 -or [string]::Join("`n",$taskNames) -cne [string]::Join("`n",$taskExpected) -or (Get-FileHash -LiteralPath $taskProbe.executable).Hash -cne $taskProbe.executable_sha256){throw 'Actual compiled names/version/artifact mismatch'}
@{binary=$taskProbe.executable;binary_sha256=$taskProbe.executable_sha256;version=$taskVersion;tests=$taskNames;count=6;raw_metadata=$taskRaw;raw_sha256=(Get-FileHash -LiteralPath $taskRaw).Hash;method='Offline exact bounds and six-name validation of original successful Zig0.16 metadata-only probe; no process launched';original_owner_negative_preserved=$true;validator=$PSCommandPath;validator_sha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash;candidate=$taskPost.head;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath "$taskPrefix-metadata.json" -Encoding utf8NoBOM
Write-Output 'ACTUAL_FOUNDATION_METADATA6_VERIFIED_OFFLINE'

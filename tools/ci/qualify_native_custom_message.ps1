param([ValidateSet('Debug','ReleaseSafe')][string]$Mode,[string]$ExpectedHead,[string]$Receipt='verification/native-sdk-custom-message-candidate')
. "$PSScriptRoot/native_qualification_ci.ps1"
$taskRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'));$taskReceipt=Join-Path $taskRoot $Receipt
New-Item -ItemType Directory -Path $taskReceipt -Force > $null
if((git -C $taskRoot rev-parse HEAD).Trim() -cne $ExpectedHead){throw 'Exact custom-message checkout mismatch'}
$taskBase='d0da323437529a19fbb05bb3d3de7855be7f0b93'
git -C $taskRoot fetch --no-tags --depth=1 origin $taskBase
if($LASTEXITCODE -ne 0){throw 'Exact validated custom-message base unavailable'}
git -C $taskRoot diff --exit-code $taskBase -- src vendor build.zig
if($LASTEXITCODE -ne 0){throw 'Product/native fixtures differ from exact d0da base'}
$taskZigInfo=[IO.FileInfo]::new((Get-Command zig).Source);$taskResolved=$taskZigInfo.ResolveLinkTarget($true)
$taskZig=if($taskResolved){$taskResolved.FullName}else{$taskZigInfo.FullName}
if((& $taskZig version).Trim() -cne '0.16.0'){throw 'Pinned Zig version mismatch'}
if($IsWindows -and (Get-FileHash -LiteralPath $taskZig).Hash -cne '086CE9D47BA42F33A514E1A6E04EB1D4A8FA1D75E0868E0213CAAD447C91E864'){throw 'Pinned Windows compiler digest mismatch'}
$taskInputs=Get-CiInventory $taskRoot 'tree' @('.git','.zig-cache','zig-out',[IO.Path]::GetRelativePath($taskRoot,$taskReceipt).Replace('\','/'))
$taskTools=Get-CiInventory (Split-Path -Parent $taskZig)
$taskInputs|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $taskReceipt 'inputs.json') -Encoding utf8NoBOM
$taskTools|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $taskReceipt 'tools.json') -Encoding utf8NoBOM
@{head=$ExpectedHead;product_base=$taskBase;mode=$Mode;os=[Runtime.InteropServices.RuntimeInformation]::OSDescription;source_files=$taskInputs.rows.Count;compiler_files=$taskTools.rows.Count;full_factory_qualified=$false;full_pi_qualified=$false;public_activation=$false}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskReceipt 'source.json') -Encoding utf8NoBOM
try {
 $taskCompile=Invoke-CiOwnedProcess $taskZig @('build','build-native-sdk-custom-message',"-Doptimize=$Mode",'-Duse-llvm=true','-j1','--test-timeout','120s','--summary','all') $taskRoot (Join-Path $taskReceipt 'compile') 1320
 $taskBinaries=@(Get-ChildItem -LiteralPath (Join-Path $taskRoot '.zig-cache/o') -File -Recurse|Where-Object Name -In @('test','test.exe'))
 if($taskBinaries.Count -ne 1){throw 'Cold custom-message compile must emit exactly one test executable'}
 $taskInventory=Read-CiTestMetadata $taskBinaries[0].FullName $taskRoot (Join-Path $taskReceipt 'inventory') 4
 $taskExpected=@([regex]::Matches([IO.File]::ReadAllText((Join-Path $taskRoot 'src/native_sdk_custom_message_test.zig')),'(?m)^test "([^"]+)"')|ForEach-Object {'native_sdk_custom_message_test.test.'+$_.Groups[1].Value})+@('extensions.native_durable_storage.test_0')
 if($taskExpected.Count -ne 4 -or (Compare-Object ($taskExpected|Sort-Object) ($taskInventory.tests|Sort-Object))){throw 'Exact selected custom-message test array mismatch'}
 $taskInventory|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $taskReceipt 'selected-inventory.json') -Encoding utf8NoBOM
 $env:PI_EXHAUSTIVE_ALLOCATION_SHARD='0';$env:PI_EXHAUSTIVE_ALLOCATION_SHARDS='1'
 $taskRuntime=Invoke-CiOwnedProcess $taskZig @('build','test-native-sdk-custom-message',"-Doptimize=$Mode",'-Duse-llvm=true','-j1','--test-timeout','120s','--summary','all') $taskRoot (Join-Path $taskReceipt 'runtime') 300
 $taskLog=[IO.File]::ReadAllText((Join-Path $taskReceipt 'runtime.stderr.log'))
 if($taskLog -notmatch '(?m)^Build Summary:.*\b4/4 tests passed'){throw 'All four custom-message tests required'}
 $taskBaseline=@([regex]::Matches($taskLog,'(?m)^EXHAUSTIVE_ALLOCATION_BASELINE custom-message40 total=(\d+)\r?$'))
 if($taskBaseline.Count -ne 1){throw 'Unique measured custom-message allocation baseline missing'}
 $taskTotal=[int]$taskBaseline[0].Groups[1].Value;if($taskTotal -le 0){throw 'Empty custom-message allocation universe'}
 foreach($taskMarker in @('RANGE','COMPLETE')){
  $taskLine="EXHAUSTIVE_ALLOCATION_$taskMarker custom-message40 0/1 range=[0,$taskTotal) total=$taskTotal"
  if([regex]::Matches($taskLog,'(?m)^'+[regex]::Escape($taskLine)+'\r?$').Count -ne 1){throw 'Exact full custom-message allocation range missing'}
 }
 $taskBegin=@([regex]::Matches($taskLog,'(?m)^EXHAUSTIVE_ALLOCATION_INDEX_BEGIN custom-message40 (\d+)\r?$')|ForEach-Object {[int]$_.Groups[1].Value})
 $taskDone=@([regex]::Matches($taskLog,'(?m)^EXHAUSTIVE_ALLOCATION_INDEX_COMPLETE custom-message40 (\d+)\r?$')|ForEach-Object {[int]$_.Groups[1].Value})
 if($taskBegin.Count -ne $taskTotal -or $taskDone.Count -ne $taskTotal){throw 'Incomplete custom-message allocation universe'}
 for($taskIndex=0;$taskIndex -lt $taskTotal;$taskIndex++){if($taskBegin[$taskIndex] -ne $taskIndex -or $taskDone[$taskIndex] -ne $taskIndex){throw 'Custom-message allocation gap or duplicate'}}
}finally{
 Assert-CiInventory $taskInputs (Join-Path $taskReceipt 'inputs-posthash.json')
 Assert-CiInventory $taskTools (Join-Path $taskReceipt 'tools-posthash.json')
}
@{head=$ExpectedHead;product_base=$taskBase;status='passed';mode=$Mode;tests=4;substantive_tests=3;source_cases=40;allocation_baseline=$taskTotal;allocation_completed=$taskDone.Count;allocation_gaps=0;allocation_duplicates=0;historical_windows_baseline=87;runtime_measured_baseline_authoritative=$true;allocation_scope='Complete measured native allocator universe; no exhaustive C malloc claim';full_factory_qualified=$false;latest_catalog_qualified=$false;full_pi_qualified=$false;public_activation=$false;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskReceipt 'result.json') -Encoding utf8NoBOM

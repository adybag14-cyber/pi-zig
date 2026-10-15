param([string]$ExpectedHead,[string]$Receipt='verification/native-anthropic-oom-diagnostic')
. "$PSScriptRoot/native_qualification_ci.ps1"
$taskRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'));$taskReceipt=Join-Path $taskRoot $Receipt
New-Item -ItemType Directory -Path $taskReceipt -Force > $null
if((git -C $taskRoot rev-parse HEAD).Trim() -cne $ExpectedHead){throw 'Exact diagnostic checkout mismatch'}
$taskBase='4b6d46d4226c8f49fec120132847c0904786ebbc'
git -c gc.auto=0 -c maintenance.auto=false -c pack.threads=2 -c pack.windowMemory=64m -C $taskRoot fetch --no-tags --depth=1 origin $taskBase
if($LASTEXITCODE -ne 0){throw 'Exact integrated product base unavailable'}
$taskChanged=@(git -C $taskRoot diff --name-only $taskBase -- src vendor build.zig build.zig.zon)
if($LASTEXITCODE -ne 0 -or $taskChanged.Count -ne 1 -or $taskChanged[0] -cne 'src/native_ai_claude_request_test.zig'){throw 'Diagnostic must change only its reviewed test file'}
if((Get-FileHash -LiteralPath (Join-Path $taskRoot 'src/native_ai_claude_request_test.zig')).Hash -cne 'A22B2E237BC54EEAAED49AAADF571D6CAF297037F504981CA74FF2D3588BEA38'){throw 'Reviewed diagnostic test bytes mismatch'}
$taskZigInfo=[IO.FileInfo]::new((Get-Command zig).Source);$taskResolved=$taskZigInfo.ResolveLinkTarget($true)
$taskZig=if($taskResolved){$taskResolved.FullName}else{$taskZigInfo.FullName}
if((& $taskZig version).Trim() -cne '0.16.0'){throw 'Pinned Zig version mismatch'}
if($IsWindows -and (Get-FileHash -LiteralPath $taskZig).Hash -cne '086CE9D47BA42F33A514E1A6E04EB1D4A8FA1D75E0868E0213CAAD447C91E864'){throw 'Pinned Windows compiler digest mismatch'}
$taskInputs=Get-CiInventory $taskRoot 'tree' @('.git','.zig-cache','zig-out',[IO.Path]::GetRelativePath($taskRoot,$taskReceipt).Replace('\','/'))
$taskTools=Get-CiInventory (Split-Path -Parent $taskZig)
$taskInputs|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $taskReceipt 'inputs.json') -Encoding utf8NoBOM
$taskTools|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $taskReceipt 'tools.json') -Encoding utf8NoBOM
@{head=$ExpectedHead;product_base=$taskBase;diagnostic_source_commit='7876af33b8a64f1a9671d1e1af76fcc60cf86ea7';mode='Debug';tests=3;full_universe=$true;shard=0;shards=1;diagnostic_only=$true;full_factory_qualified=$false;full_pi_qualified=$false;public_activation=$false;source_files=$taskInputs.rows.Count;compiler_files=$taskTools.rows.Count}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskReceipt 'source.json') -Encoding utf8NoBOM
try {
 $taskCompile=Invoke-CiOwnedProcess $taskZig @('build','build-native-ai-claude5ab-allocation','-Doptimize=Debug','-Duse-llvm=true','-j1','--summary','all') $taskRoot (Join-Path $taskReceipt 'compile') 1500
 $taskBinaries=@(Get-ChildItem -LiteralPath (Join-Path $taskRoot '.zig-cache/o') -File -Recurse|Where-Object Name -In @('test','test.exe'))
 if($taskBinaries.Count -ne 1){throw 'Cold diagnostic compile must emit exactly one test executable'}
 $taskInventory=Read-CiTestMetadata $taskBinaries[0].FullName $taskRoot (Join-Path $taskReceipt 'inventory') 3
 $taskExpected=@([regex]::Matches([IO.File]::ReadAllText((Join-Path $taskRoot 'src/native_ai_claude_request_test.zig')),'(?m)^test "(native Claude5ab every host allocation[^"]+)"')|ForEach-Object {'native_ai_claude_request_test.test.'+$_.Groups[1].Value})+@('extensions.native_durable_storage.test_0')
 if($taskExpected.Count -ne 3 -or (Compare-Object ($taskExpected|Sort-Object) ($taskInventory.tests|Sort-Object) -CaseSensitive)){throw 'Exact three diagnostic tests required'}
 $taskInventory|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $taskReceipt 'selected-inventory.json') -Encoding utf8NoBOM
 $taskRuntime=Invoke-CiOwnedProcess $taskZig @('build','test-native-ai-claude5ab-allocation','-Doptimize=Debug','-Duse-llvm=true','-j1','--test-timeout','600s','--summary','all') $taskRoot (Join-Path $taskReceipt 'runtime') 900
 $taskLog=[IO.File]::ReadAllText((Join-Path $taskReceipt 'runtime.stderr.log'))
 if($taskLog -notmatch '(?m)^Build Summary:.*\b3/3 tests passed' -or $taskLog -notmatch 'run test 3 pass \(3 total\)'){throw 'All three diagnostic tests must execute'}
 foreach($taskLabel in @('anthropic-request','anthropic-pending')){
  $taskBaseline=@([regex]::Matches($taskLog,'(?m)^EXHAUSTIVE_ALLOCATION_BASELINE '+$taskLabel+' total=(\d+)\r?$'))
  if($taskBaseline.Count -ne 1){throw 'Exact allocation baseline missing'}
  $taskTotal=[int]$taskBaseline[0].Groups[1].Value;if($taskTotal -le 0){throw 'Empty allocation universe'}
  foreach($taskMarker in @('RANGE','COMPLETE')){if([regex]::Matches($taskLog,'(?m)^'+[regex]::Escape("EXHAUSTIVE_ALLOCATION_$taskMarker $taskLabel 0/1 range=[0,$taskTotal) total=$taskTotal")+'\r?$').Count -ne 1){throw 'Full allocation range required'}}
  foreach($taskMarker in @('BEGIN','COMPLETE')){
   $taskIndices=@([regex]::Matches($taskLog,'(?m)^EXHAUSTIVE_ALLOCATION_INDEX_'+$taskMarker+' '+$taskLabel+' (\d+)\r?$')|ForEach-Object {[int]$_.Groups[1].Value})
   if($taskIndices.Count -ne $taskTotal){throw 'Incomplete allocation universe'}
   for($taskIndex=0;$taskIndex -lt $taskTotal;$taskIndex++){if($taskIndices[$taskIndex] -ne $taskIndex){throw 'Allocation index gap or duplicate'}}
  }
 }
}finally{
 Assert-CiInventory $taskInputs (Join-Path $taskReceipt 'inputs-posthash.json')
 Assert-CiInventory $taskTools (Join-Path $taskReceipt 'tools-posthash.json')
}
@{head=$ExpectedHead;status='passed';tests=3;diagnostic_only=$true;full_factory_qualified=$false;full_pi_qualified=$false;public_activation=$false}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskReceipt 'result.json') -Encoding utf8NoBOM

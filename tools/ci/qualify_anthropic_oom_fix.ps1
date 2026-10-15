param([ValidateSet('Debug')][string]$Mode,[string]$ExpectedHead,[string]$Receipt='verification/native-anthropic-oom-fix')
. "$PSScriptRoot/native_qualification_ci.ps1"
$taskRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'));$taskReceipt=Join-Path $taskRoot $Receipt
New-Item -ItemType Directory -Path $taskReceipt -Force > $null
if((git -C $taskRoot rev-parse HEAD).Trim() -cne $ExpectedHead){throw 'Exact provider checkout mismatch'}
$taskBase='b6589631553bf5f5d3218e47b08cef5e277dd04f'
git -c gc.auto=0 -c maintenance.auto=false -c pack.threads=2 -c pack.windowMemory=64m -C $taskRoot fetch --no-tags --depth=1 origin $taskBase
if($LASTEXITCODE -ne 0){throw 'Exact integrated product base unavailable'}
git -C $taskRoot diff --exit-code $taskBase -- src vendor build.zig build.zig.zon
if($LASTEXITCODE -ne 0){throw 'Product/native fixtures differ from frozen combined base'}
$taskZigInfo=[IO.FileInfo]::new((Get-Command zig).Source);$taskResolved=$taskZigInfo.ResolveLinkTarget($true)
$taskZig=if($taskResolved){$taskResolved.FullName}else{$taskZigInfo.FullName}
if((& $taskZig version).Trim() -cne '0.16.0'){throw 'Pinned Zig version mismatch'}
if($IsWindows -and (Get-FileHash -LiteralPath $taskZig).Hash -cne '086CE9D47BA42F33A514E1A6E04EB1D4A8FA1D75E0868E0213CAAD447C91E864'){throw 'Pinned Windows compiler digest mismatch'}
$taskInputs=Get-CiInventory $taskRoot 'tree' @('.git','.zig-cache','zig-out',[IO.Path]::GetRelativePath($taskRoot,$taskReceipt).Replace('\','/'))
$taskTools=Get-CiInventory (Split-Path -Parent $taskZig)
$taskInputs|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $taskReceipt 'inputs.json') -Encoding utf8NoBOM
$taskTools|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $taskReceipt 'tools.json') -Encoding utf8NoBOM
$taskBoundary=@{full_factory_qualified=$false;full_pi_qualified=$false;public_activation=$false;default_responses_websocket_qualified=$false;fresh_posix_source_recapture=$false;anthropic_query_beta_qualified=$false;funded_provider_requests=0;user_agent='Native Zig/QuickJS runtime; SDK Node metadata excluded by existing fixture comparator'}
@{head=$ExpectedHead;tree=(git -C $taskRoot rev-parse 'HEAD^{tree}').Trim();product_base=$taskBase;mode=$Mode;os=[Runtime.InteropServices.RuntimeInformation]::OSDescription;source_files=$taskInputs.rows.Count;compiler_files=$taskTools.rows.Count;boundaries=$taskBoundary}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskReceipt 'source.json') -Encoding utf8NoBOM
function Get-ExpectedNames($Sources,$Filter){
 @(foreach($taskSource in $Sources){foreach($taskMatch in [regex]::Matches([IO.File]::ReadAllText((Join-Path $taskRoot ($taskSource.Replace('.','/')+'.zig'))),'(?m)^test "([^"]+)"')){if($taskMatch.Groups[1].Value -match $Filter){$taskSource+'.test.'+$taskMatch.Groups[1].Value}}})
}
$taskComponents=@(
 @{id='anthropic';target='native-ai-claude5ab';count=5;sources=@('src.native_ai_claude_request_test');filter='^native Claude5ab (Anthropic|request owner)';extra=@();source_cases=25;wire_cases=22;allocation_scope='Pending/retained request and codec owner assertions; exhaustive owners in separate target'},
 @{id='anthropic-allocation';target='native-ai-claude5ab-allocation';count=3;sources=@('src.native_ai_claude_request_test');filter='^native Claude5ab every host allocation';extra=@();allocation_scope='Both complete measured request and pending callback owner universes, existing strict helper in full0/1 mode with every ordered index retained'}
)
$taskResults=@()
try {
 foreach($taskComponent in $taskComponents){
  $taskDir=Join-Path $taskReceipt $taskComponent.id;New-Item -ItemType Directory -Path $taskDir -Force > $null
  $taskExpected=@(Get-ExpectedNames $taskComponent.sources $taskComponent.filter|ForEach-Object {$_.Substring(4)})+@('extensions.native_durable_storage.test_0')+$taskComponent.extra
  if($taskExpected.Count -ne $taskComponent.count){throw "Source-selected count mismatch $($taskComponent.id): $($taskExpected.Count)"}
  $taskBefore=@(Get-ChildItem -LiteralPath (Join-Path $taskRoot '.zig-cache/o') -File -Recurse -ErrorAction SilentlyContinue|Where-Object Name -In @('test','test.exe')|ForEach-Object FullName)
  $taskCompile=Invoke-CiOwnedProcess $taskZig @('build',('build-'+$taskComponent.target),"-Doptimize=$Mode",'-Duse-llvm=true','-j1','--summary','all') $taskRoot (Join-Path $taskDir 'compile') 1500
  $taskBinaries=@(Get-ChildItem -LiteralPath (Join-Path $taskRoot '.zig-cache/o') -File -Recurse|Where-Object { $_.Name -in @('test','test.exe') -and $_.FullName -notin $taskBefore })
  if($taskBinaries.Count -ne 1){throw "Compile must emit one new test executable: $($taskComponent.id)"}
  $taskInventory=Read-CiTestMetadata $taskBinaries[0].FullName $taskRoot (Join-Path $taskDir 'inventory') $taskComponent.count
  if(Compare-Object ($taskExpected|Sort-Object) ($taskInventory.tests|Sort-Object) -CaseSensitive){throw "Exact native selected array mismatch: $($taskComponent.id)"}
  $taskInventory|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $taskDir 'selected-inventory.json') -Encoding utf8NoBOM
  $taskRuntime=Invoke-CiOwnedProcess $taskZig @('build',('test-'+$taskComponent.target),"-Doptimize=$Mode",'-Duse-llvm=true','-j1','--test-timeout','600s','--summary','all') $taskRoot (Join-Path $taskDir 'runtime') 1200
  $taskLog=[IO.File]::ReadAllText((Join-Path $taskDir 'runtime.stderr.log'))
  if($taskLog -notmatch ('(?m)^Build Summary:.*\b'+$taskComponent.count+'/'+$taskComponent.count+' tests passed')){throw 'Every selected test must execute'}
  if($taskLog -notmatch ('(?m)run test '+$taskComponent.count+' pass \('+$taskComponent.count+' total\)')){throw 'Exact test execution summary required'}
  if((Get-FileHash -LiteralPath $taskBinaries[0].FullName).Hash -cne $taskInventory.binary_sha256){throw 'Test executable changed after metadata query'}
  $taskSweeps=@()
  if($taskComponent.id -ceq 'anthropic-allocation'){
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
    $taskSweeps+=@{label=$taskLabel;baseline=$taskTotal;completed=$taskTotal;gaps=0;duplicates=0}
   }
  }
  $taskResult=@{head=$ExpectedHead;component=$taskComponent;status='passed';tests=$taskComponent.count;binary_sha256=$taskInventory.binary_sha256;mode=$Mode;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}
  $taskResult.sweeps=$taskSweeps
  $taskResult|ConvertTo-Json -Depth 7|Set-Content -LiteralPath (Join-Path $taskDir 'result.json') -Encoding utf8NoBOM
  $taskResults+=$taskResult
 }
}finally{
 Assert-CiInventory $taskInputs (Join-Path $taskReceipt 'inputs-posthash.json')
 Assert-CiInventory $taskTools (Join-Path $taskReceipt 'tools-posthash.json')
}
@{head=$ExpectedHead;product_base=$taskBase;status='passed';mode=$Mode;components=$taskResults;tests=8;boundaries=$taskBoundary;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 9|Set-Content -LiteralPath (Join-Path $taskReceipt 'result.json') -Encoding utf8NoBOM

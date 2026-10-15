param([ValidateSet('Debug','ReleaseSafe')][string]$Mode,[string]$ExpectedHead,[string]$Receipt='verification/native-ai-json-b06-candidate')
. "$PSScriptRoot/native_ai_ci.ps1"
$taskRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$taskReceipt=Join-Path $taskRoot $Receipt
New-Item -ItemType Directory -Path $taskReceipt -Force > $null
if((git -C $taskRoot rev-parse HEAD).Trim() -cne $ExpectedHead){throw 'CI checkout head mismatch'}
$taskBase='cc9053fbf63f057a63282359f8f49e30a83329e8'
git -C $taskRoot fetch --no-tags --depth=1 origin $taskBase
if($LASTEXITCODE -ne 0){throw 'Exact validated product base unavailable'}
git -C $taskRoot diff --exit-code $taskBase -- src vendor build.zig
if($LASTEXITCODE -ne 0){throw 'Product/native fixtures differ from exact cc9053 base'}
$taskZigInfo=[IO.FileInfo]::new((Get-Command zig).Source)
$taskResolved=$taskZigInfo.ResolveLinkTarget($true)
$taskZig=if($taskResolved){$taskResolved.FullName}else{$taskZigInfo.FullName}
if((& $taskZig version).Trim() -cne '0.16.0'){throw 'Pinned Zig version mismatch'}
if($IsWindows -and (Get-FileHash -LiteralPath $taskZig).Hash -cne '086CE9D47BA42F33A514E1A6E04EB1D4A8FA1D75E0868E0213CAAD447C91E864'){throw 'Windows compiler differs from qualified pinned executable'}
$taskToolRoot=Split-Path -Parent $taskZig
$taskInputs=Get-AiInventory $taskRoot 'tree' @('.git','.zig-cache','zig-out',[IO.Path]::GetRelativePath($taskRoot,$taskReceipt).Replace('\','/'))
$taskTools=Get-AiInventory $taskToolRoot
$taskInputs|ConvertTo-Json -Depth 7|Set-Content -LiteralPath (Join-Path $taskReceipt 'inputs.json') -Encoding utf8NoBOM
$taskTools|ConvertTo-Json -Depth 7|Set-Content -LiteralPath (Join-Path $taskReceipt 'tools.json') -Encoding utf8NoBOM
@{head=$ExpectedHead;tree=(git -C $taskRoot rev-parse 'HEAD^{tree}').Trim();product_base=$taskBase;mode=$Mode;os=[Runtime.InteropServices.RuntimeInformation]::OSDescription;architecture=[Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString();source_files=$taskInputs.rows.Count;tool_files=$taskTools.rows.Count;public_activation=$false;scope='Exact cc9053 private JSON39 and unchanged rawHTTP6; no full provider/factory/catalog qualification'}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskReceipt 'source.json') -Encoding utf8NoBOM
try {
 $taskCompile=Invoke-AiOwnedProcess $taskZig @('build','build-native-ai-json-parse','build-native-ai-http',"-Doptimize=$Mode",'-Duse-llvm=true','-j1','--test-timeout','120s','--summary','all') $taskRoot (Join-Path $taskReceipt 'compile') 1320
 $taskBinaries=@(Get-ChildItem -LiteralPath (Join-Path $taskRoot '.zig-cache/o') -File -Recurse|Where-Object Name -In @('test','test.exe')|Sort-Object FullName)
 if($taskBinaries.Count -ne 2){throw 'Cold candidate must emit exactly two test executables'}
 $taskExpected=@{}
 foreach($taskPair in @(@('json','native_ai_json_parse_test'),@('http','native_ai_http_test'))){
  $taskNames=@([regex]::Matches([IO.File]::ReadAllText((Join-Path $taskRoot "src/$($taskPair[1]).zig")),'(?m)^test "([^"]+)"')|ForEach-Object {$taskPair[1]+'.test.'+$_.Groups[1].Value})+@('extensions.native_durable_storage.test_0')
  if($taskNames.Count -ne 6){throw 'Selected source test inventory changed'}
  $taskExpected[$taskPair[0]]=$taskNames
 }
 $taskInventories=@();$taskSeen=@{}
 foreach($taskBinary in $taskBinaries){
  $taskInventory=Read-AiTestMetadata $taskBinary.FullName $taskRoot (Join-Path $taskReceipt "inventory-$($taskInventories.Count)")
  $taskKind=@($taskExpected.Keys|Where-Object {!(Compare-Object ($taskExpected[$_]|Sort-Object) ($taskInventory.tests|Sort-Object))})
  if($taskKind.Count -ne 1 -or $taskSeen.ContainsKey($taskKind[0])){throw 'Exact emitted test array missing or duplicated'}
  $taskSeen[$taskKind[0]]=$true;$taskInventory.kind=$taskKind[0];$taskInventories+=$taskInventory
 }
 $taskInventories|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $taskReceipt 'selected-inventory.json') -Encoding utf8NoBOM
 $taskRuntime=Invoke-AiOwnedProcess $taskZig @('build','test-native-ai-json-parse','test-native-ai-http',"-Doptimize=$Mode",'-Duse-llvm=true','-j1','--test-timeout','120s','--summary','all') $taskRoot (Join-Path $taskReceipt 'runtime') 300
 $taskLog=[IO.File]::ReadAllText((Join-Path $taskReceipt 'runtime.stderr.log'))
 if($taskLog -notmatch '(?m)Build Summary:.*\b12/12 tests passed'){throw 'All twelve tests must pass'}
 foreach($taskTarget in @('test-native-ai-json-parse','test-native-ai-http')){
  if([regex]::Matches($taskLog,'(?ms)^'+[regex]::Escape($taskTarget)+' success\r?\n[^\r\n]*run test 6 pass \(6 total\)').Count -ne 1){throw "Six selected tests missing: $taskTarget"}
 }
 $taskOriginal=Get-Content -LiteralPath (Join-Path $taskRoot 'src/extensions/fixtures/ai-json-parse-b06.json') -Raw|ConvertFrom-Json
 $taskDelegate=Get-Content -LiteralPath (Join-Path $taskRoot 'src/extensions/fixtures/ai-json-delegate-b06.json') -Raw|ConvertFrom-Json
 if($taskOriginal.rows.Count -ne 33 -or $taskDelegate.rows.Count -ne 6 -or $taskOriginal.sourceHead -cne 'b06c1f2cf1dea6af8748ddeee18c23587d2cb7c6' -or $taskDelegate.sourceHead -cne $taskOriginal.sourceHead){throw 'Original39 immutable observations missing'}
}finally{
 Assert-AiInventory $taskInputs (Join-Path $taskReceipt 'inputs-posthash.json')
 Assert-AiInventory $taskTools (Join-Path $taskReceipt 'tools-posthash.json')
}
@{head=$ExpectedHead;product_base=$taskBase;status='passed';mode=$Mode;tests=12;json_selected=6;http_selected=6;original_json_rows=39;raw_b45_wire_scenarios=12;host_gpa='Complete JSON owner/helper/diagnostic/delegate scope; raw preparation scope unchanged';global_json_parse_replacement=$false;public_activation=$false;full_provider_qualified=$false;latest_catalog_qualified=$false;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskReceipt 'result.json') -Encoding utf8NoBOM

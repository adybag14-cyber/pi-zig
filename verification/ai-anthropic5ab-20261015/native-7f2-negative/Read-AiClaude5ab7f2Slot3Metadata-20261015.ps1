$ErrorActionPreference='Stop'
$taskRoot='C:/Users/adyba/pi-zig-ai-anthropic-bedrock-20261015'
$taskEvidence=$PSScriptRoot
$taskName='native-ai-claude5ab-7f2c066d-debug-extended-third-slot3-20261015'
$taskExpectedHead='7f2c066d9810b8b834b8a182d11c99e5be83616c'
$taskPost=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName-posthash.json") -Raw|ConvertFrom-Json
if($taskPost.candidate -cne $taskExpectedHead -or $taskPost.compile -cne 'passed' -or $taskPost.runtime -notin @('passed','failed') -or $taskPost.source_drift -ne 0 -or $taskPost.tool_drift -ne 0 -or $taskPost.control_drift -ne 0 -or $taskPost.vendor_drift -ne 0 -or @($taskPost.references|Where-Object drift -ne 0).Count -or $taskPost.absence_drift -ne 0){throw 'Matching compiled full-post-zero pair required before metadata gate'}
if((git -C $taskRoot rev-parse HEAD) -cne $taskExpectedHead -or @(git -C $taskRoot status --porcelain).Count){throw 'Exact clean candidate required'}
$taskSource=@(Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName-source-before.json") -Raw|ConvertFrom-Json|ForEach-Object{@{path=(Join-Path $taskRoot $_.path);sha256=$_.sha256}})
$taskTools=@((Get-Content -LiteralPath (Join-Path $taskEvidence 'durable-latest89-full-inspect-53ae-tool-prehash-20261011.json') -Raw|ConvertFrom-Json).inputs)
$taskVendor=@(Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName-vendor-before.json") -Raw|ConvertFrom-Json)
$taskControls=@(Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName-controls-before.json") -Raw|ConvertFrom-Json)
$taskReferences=@('source5ab-full-manifest-20261015.json','durable-19cb534-reference-20261012-all-built-runtime.json','root-current8a-npm-tools-before.json')
$taskRows=@($taskSource)+@($taskTools)+@($taskVendor)+@($taskControls)
foreach($taskFile in $taskReferences){$taskRows+=@(Get-Content -LiteralPath (Join-Path $taskEvidence $taskFile) -Raw|ConvertFrom-Json)}
$taskRows+=@{path=$PSCommandPath;sha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash}
function Assert-Frozen {
 $taskChanged=@($taskRows|Where-Object{!(Test-Path -LiteralPath $_.path -PathType Leaf) -or (Get-FileHash -LiteralPath $_.path).Hash -cne $_.sha256}|ForEach-Object path)
 if($taskChanged.Count){throw ('Metadata full frozen drift: '+($taskChanged -join ','))}
}
Assert-Frozen
$taskBefore=@(Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName-before-binaries.json") -Raw|ConvertFrom-Json)
$taskBinaries=@(Get-ChildItem -LiteralPath (Join-Path $taskRoot '.zig-cache/o') -Filter test.exe -Recurse -File|Where-Object FullName -NotIn $taskBefore)
if($taskBinaries.Count -ne 2){throw 'Exactly two new compiled artifacts required'}
. (Join-Path $taskRoot 'tools/ci/native_qualification_ci.ps1')
function Selected-Names($taskFile,$taskFilter){
 foreach($taskMatch in [regex]::Matches([IO.File]::ReadAllText((Join-Path $taskRoot "src/$taskFile.zig")),'(?m)^test "([^"]+)"')){if($taskMatch.Groups[1].Value -match $taskFilter){$taskFile+'.test.'+$taskMatch.Groups[1].Value}}
}
$taskPrimary=@(Selected-Names 'native_ai_claude_request_test' '^native Claude5ab (Anthropic|request owner)')+@('extensions.native_durable_storage.test_0')
$taskExtended=@(Selected-Names 'native_ai_claude_extended_test' '^native Claude5ab extended')+@(Selected-Names 'native_ai_constrained_sampling_test' '^native constrained sampling')+@(Selected-Names 'native_ai_sdk_headers_test' '^native SDK nullable headers')+@(Selected-Names 'native_node_function_exception_test' '^native node function preserves caught getter')+@(Selected-Names 'native_ai_anthropic_api_error_test' '^native Anthropic SDK errors')+@(Selected-Names 'native_ai_anthropic_sdk_boundary_test' '^native Claude5ab extended')+@('extensions.native_durable_storage.test_0')
if($taskPrimary.Count -ne 5 -or $taskExtended.Count -ne 9){throw 'Exact source-selected14 array required'}
$taskSelected=@();$taskFailure=$null
try{
 foreach($taskBinary in $taskBinaries){
  # Choose only the expected component size; every name is independently
  # obtained from the actual Zig metadata protocol and compared below.
  $taskExtendedArtifact=[Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($taskBinary.FullName)).Contains('native_ai_claude_extended_test.test.native Claude5ab extended')
  $taskExpected=if($taskExtendedArtifact){$taskExtended}else{$taskPrimary}
  $taskId=if($taskExtendedArtifact){'extended9'}else{'source25-five'}
  $taskInventory=Read-CiTestMetadata $taskBinary.FullName $taskRoot (Join-Path $taskEvidence "$taskName-metadata-$taskId") $taskExpected.Count
  if((Get-FileHash -LiteralPath $taskBinary.FullName).Hash -cne $taskInventory.binary_sha256){throw 'Metadata executable changed during query'}
  if(@(Compare-Object ($taskInventory.tests|Sort-Object -CaseSensitive) ($taskExpected|Sort-Object -CaseSensitive) -CaseSensitive).Count){throw 'Exact selected metadata names mismatch'}
  $taskSelected+=@{id=$taskId;metadata=$taskInventory;count=$taskExpected.Count}
 }
 if(@($taskSelected|Where-Object id -eq 'extended9').Count -ne 1 -or @($taskSelected|Where-Object id -eq 'source25-five').Count -ne 1){throw 'Both selected artifacts required'}
 $taskRuntimeLog=[IO.File]::ReadAllText((Join-Path $taskEvidence "$taskName-runtime.stderr.log"))
 if($taskPost.runtime -eq 'passed'){if($taskRuntimeLog -notmatch '(?m)^Build Summary:.*\b14/14 tests passed' -or $taskRuntimeLog -notmatch 'run test 5 pass \(5 total\)' -or $taskRuntimeLog -notmatch 'run test 9 pass \(9 total\)'){throw 'All actual14 selected tests must execute without skips'}}else{if($taskRuntimeLog -notmatch '(?m)^Build Summary:.*\b13/14 tests passed \(1 failed\)' -or $taskRuntimeLog -notmatch 'run test 5 pass \(5 total\)' -or $taskRuntimeLog -notmatch 'run test 8 pass, 1 fail \(9 total\)'){throw 'Exact all14 selected executions required for retained negative'}}
}catch{$taskFailure=$_.Exception.Message}finally{
 Assert-Frozen
 if((git -C $taskRoot rev-parse HEAD) -cne $taskExpectedHead -or @(git -C $taskRoot status --porcelain).Count){throw 'Metadata candidate changed'}
 @{candidate=$taskExpectedHead;source=$taskSource.Count;tools=$taskTools.Count;vendor=$taskVendor.Count;controls=$taskControls.Count;total_frozen_records=$taskRows.Count;full_post_drift=0;selected=$taskSelected;failure=$taskFailure;runtime_status=$taskPost.runtime;status=if($taskFailure){'failed'}elseif($taskPost.runtime -eq 'failed'){'metadata_passed_runtime_negative'}else{'passed'};completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-metadata-qualification.json") -Encoding utf8NoBOM
}
if($taskFailure){throw $taskFailure}


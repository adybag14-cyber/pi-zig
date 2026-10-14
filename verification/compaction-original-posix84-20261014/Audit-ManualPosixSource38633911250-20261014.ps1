$ErrorActionPreference='Stop'
$taskEvidence=$PSScriptRoot
$taskBase=Join-Path $taskEvidence 'manual-posix-source-91b-38633911250-20261014'
$taskCanonical=@(Get-Content -LiteralPath (Join-Path $taskEvidence 'sdk-source-b45-full-manifest-20261014.json') -Raw|ConvertFrom-Json)
$taskSourceMap=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
foreach($taskRow in $taskCanonical){$taskSourceMap.Add($taskRow.relative,$taskRow.sha256)}
$taskWindows=(Get-Content -LiteralPath (Join-Path $taskEvidence 'sdk-session-manual-compaction-b45-source44-first-20261014-output.json') -Raw|ConvertFrom-Json -Depth 100)
$taskPlatforms=[Collections.Generic.HashSet[string]]::new()
$taskAudit=@();$taskPosixRows=$null
foreach($taskDir in @(Get-ChildItem -LiteralPath $taskBase -Directory)){
 $taskResult=Get-Content -LiteralPath (Join-Path $taskDir.FullName 'result.json') -Raw|ConvertFrom-Json -Depth 20
 if($taskResult.head -cne '91b5a42a233c826daf358e603e15a3d105398c37' -or $taskResult.source -cne 'b45e0ebcc5ae2fc42a6f2f23104d10e656e6bedb' -or $taskResult.source_files -ne 1965 -or $taskResult.candidate_files -ne 5463 -or $taskResult.node_tool_files -ne 4560){throw 'Original platform identity/inventory mismatch'}
 $taskCounts=@{source=1965;dependencies=$taskResult.dependency_files;'node-tools'=4560;candidate=5463}
 $taskAllowed=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
 foreach($taskKind in @('source','dependencies','node-tools','candidate')){
  $taskRows=@(Get-Content -LiteralPath (Join-Path $taskDir.FullName ($taskKind+'-before.json')) -Raw|ConvertFrom-Json)
  $taskExpected=switch($taskKind){source{1965}dependencies{$taskResult.dependency_files}'node-tools'{4560}candidate{5463}}
  if($taskRows.Count -ne $taskExpected){throw 'Original full manifest missing'}
  foreach($taskRow in $taskRows){$taskAllowed[$taskRow.path]=$taskRow.sha256.ToUpperInvariant();if($taskKind -eq 'source'){$taskRelative=$taskRow.path.Substring($taskRow.path.IndexOf('/.reference-source/')+'/.reference-source/'.Length);if(!$taskSourceMap.ContainsKey($taskRelative) -or $taskSourceMap[$taskRelative] -cne $taskRow.sha256){throw 'Canonical1965 source bytes differ'}}}
 }
 foreach($taskPhase in @('first','second')){
  $taskOutput=Get-Content -LiteralPath (Join-Path $taskDir.FullName ('manual-compaction-'+$taskPhase+'-output.json')) -Raw|ConvertFrom-Json -Depth 100
  if($taskOutput.sourceHead -cne $taskResult.source -or $taskOutput.cases -ne 44 -or $taskOutput.rows.Count -ne 44 -or $taskOutput.inputSha256 -cne $taskWindows.inputSha256 -or $taskOutput.node.version -cne 'v24.14.0'){throw 'Actual44 original corpus identity changed'}
  $taskOwner=Get-Content -LiteralPath (Join-Path $taskDir.FullName ('manual-compaction-'+$taskPhase+'.process.json')) -Raw|ConvertFrom-Json
  if($taskOwner.status -cne 'passed' -or $taskOwner.outer_seconds -ne 300){throw 'Bounded original owner did not pass'}
  foreach($taskStage in @($taskOutput.before,$taskOutput.after)){foreach($taskCheck in $taskStage){if($taskCheck.drift -ne 0 -or !$taskCounts.ContainsKey($taskCheck.name) -or $taskCheck.count -ne $taskCounts[$taskCheck.name]){throw 'Original internal frozen check failed'}}}
  $taskPost=Get-Content -LiteralPath (Join-Path $taskDir.FullName ('manual-compaction-'+$taskPhase+'-posthash.json')) -Raw|ConvertFrom-Json -Depth 10
  foreach($taskStage in @($taskPost.before,$taskPost.after)){foreach($taskCheck in $taskStage){if(@($taskCheck.drift).Count -ne 0 -or !$taskCounts.ContainsKey($taskCheck.kind) -or $taskCheck.count -ne $taskCounts[$taskCheck.kind]){throw 'Original external frozen check failed'}}}
  $taskObserved=@($taskOutput.observedModules|Where-Object kind -eq 'observed-module')
  foreach($taskModule in $taskObserved){if(!$taskAllowed.ContainsKey($taskModule.path) -or $taskAllowed[$taskModule.path] -cne $taskModule.sha256.ToUpperInvariant()){throw 'Observed original module not in frozen inventory'}}
  $taskCommon=@($taskOutput.rows|Where-Object scenario -cne 'no-model')|ConvertTo-Json -Depth 100 -Compress
  $taskWindowsCommon=@($taskWindows.rows|Where-Object scenario -cne 'no-model')|ConvertTo-Json -Depth 100 -Compress
  if($taskCommon -cne $taskWindowsCommon){throw '43 platform-independent original observations differ'}
  $taskNoModel=@($taskOutput.rows|Where-Object scenario -ceq 'no-model')[0]
  if($taskNoModel.error.message -notmatch '/owned/pi-package/docs/providers.md' -or $taskNoModel.error.message -notmatch '/owned/pi-package/docs/models.md'){throw 'Actual POSIX package input not reflected in retained no-model case'}
  $taskRaw=$taskOutput.rows|ConvertTo-Json -Depth 100 -Compress
  if($null -eq $taskPosixRows){$taskPosixRows=$taskRaw}elseif($taskPosixRows -cne $taskRaw){throw 'POSIX original raw44 double/platform capture differs'}
 }
 if(!$taskPlatforms.Add($taskOutput.platform)){throw 'Duplicate original platform'}
 $taskAudit+=@{platform=$taskOutput.platform;cases=44;common_windows_cases=43;full_double_capture_identical=$true;source_files=1965;dependency_files=$taskResult.dependency_files;node_tool_files=4560;candidate_files=5463;observed_modules=$taskObserved.Count;all_observed_modules_frozen=$true;all_posthash_drift=0}
}
if($taskPlatforms.Count -ne 2 -or !$taskPlatforms.Contains('linux') -or !$taskPlatforms.Contains('darwin')){throw 'Both original POSIX platforms required'}
@{status='actual_posix44_independently_audited';run=38633911250;head='91b5a42a233c826daf358e603e15a3d105398c37';source='b45e0ebcc5ae2fc42a6f2f23104d10e656e6bedb';platforms=$taskAudit;full_posix44_rows_identical=$true;windows43_platform_independent_rows_identical=$true;platform_specific_case_retained='no-model configured documentation path';full_factory_qualified=$false;public_activation=$false;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $taskBase 'source-qualification.json') -Encoding utf8NoBOM
Write-Output 'ACTUAL_POSIX44_AUDITED_BOTH_PLATFORMS'

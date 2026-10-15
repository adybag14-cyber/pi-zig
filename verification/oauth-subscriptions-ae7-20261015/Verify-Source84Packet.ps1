param([string]$Archive=(Join-Path $PSScriptRoot 'source84-qualified-packet.zip'))
$ErrorActionPreference='Stop'
$taskZip=[IO.Compression.ZipFile]::OpenRead([IO.Path]::GetFullPath($Archive))
try {
 function Read-Entry([string]$taskName){
  $taskEntry=$taskZip.GetEntry($taskName);if(!$taskEntry){throw "Missing packet entry $taskName"}
  $taskStream=$taskEntry.Open();try{$taskReader=[IO.StreamReader]::new($taskStream);try{return $taskReader.ReadToEnd()}finally{$taskReader.Dispose()}}finally{$taskStream.Dispose()}
 }
 $taskManifest=@((Read-Entry 'packet-manifest.json')|ConvertFrom-Json)
 if($taskZip.Entries.Count -ne $taskManifest.Count+1){throw 'Packet entry inventory mismatch'}
 $taskNames=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
 foreach($taskRow in $taskManifest){
  if(!$taskNames.Add($taskRow.path)){throw 'Duplicate packet path'}
  $taskEntry=$taskZip.GetEntry($taskRow.path);if(!$taskEntry -or $taskEntry.Length -ne $taskRow.bytes){throw "Packet size mismatch $($taskRow.path)"}
  $taskStream=$taskEntry.Open();try{$taskHasher=[Security.Cryptography.SHA256]::Create();try{$taskHash=[Convert]::ToHexString($taskHasher.ComputeHash($taskStream))}finally{$taskHasher.Dispose()}}finally{$taskStream.Dispose()}
  if($taskHash -cne $taskRow.sha256){throw "Packet digest mismatch $($taskRow.path)"}
 }
 $taskOwner=(Read-Entry 'oauth-subscriptions-ae7-source84-first-20261015.json')|ConvertFrom-Json
 if($taskOwner.status -cne 'passed' -or $taskOwner.exit_code -ne 0 -or $taskOwner.pid -ne 60028 -or $taskOwner.executable_sha256 -cne '63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088'){throw 'Source terminal ownership mismatch'}
 $taskPost=(Read-Entry 'oauth-subscriptions-ae7-source84-first-20261015-posthash.json')|ConvertFrom-Json
 if(@($taskPost.manifests|Where-Object drift -ne 0).Count -or @($taskPost.extra_control_drift).Count -or @($taskPost.absent_dependency_drift).Count -or $taskPost.control_manifest_drift -or $taskPost.historical_absence_records -ne 84){throw 'Source full posthash mismatch'}
 foreach($taskSpec in @(@{name='source';count=1968},@{name='dependencies';count=31064},@{name='node_tools';count=1774})){if(@($taskPost.manifests|Where-Object {$_.name -ceq $taskSpec.name -and $_.files -eq $taskSpec.count}).Count -ne 1){throw 'Full frozen inventory mismatch'}}
 $taskResult=(Read-Entry 'ai-oauth-subscriptions-ae7.json')|ConvertFrom-Json
 if($taskResult.count -ne 84 -or @($taskResult.rows).Count -ne 84 -or @($taskResult.rawDiagnostics).Count -ne 43 -or $taskResult.runtime -cne 'v24.14.0' -or $taskResult.sourceHead -cne 'ae7b16d43b7c78c5b6fa3213fdd1215bb339729d'){throw 'Actual Source84 identity mismatch'}
 if(@($taskResult.rows|Where-Object {$_.result.error.message -match 'Uncontrolled OAuth URL|Controlled queue exhausted'}).Count){throw 'Unexpected fixture control failure'}
 $taskModules=@((Read-Entry 'sourceae7-modules-60028-0-20261015.jsonl') -split "`n"|Where-Object {$_}|ForEach-Object {$_|ConvertFrom-Json})
 foreach($taskSuffix in @('github-copilot.ts','kimi-coding.ts','xai.ts','device-code.ts','provider-env.ts','sleep.ts','github-copilot.json')){if(@($taskModules|Where-Object {$_.kind -ceq 'observed-module' -and $_.path.EndsWith($taskSuffix,[StringComparison]::Ordinal)}).Count -ne 1){throw "Actual Source module missing $taskSuffix"}}
 @{status='passed';packet_payloads=$taskManifest.Count;source_cases=84;raw_source_diagnostics=43;native_qualified=$false;public_activation=$false}|ConvertTo-Json
} finally {$taskZip.Dispose()}

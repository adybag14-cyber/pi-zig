$ErrorActionPreference='Stop'
$taskTree='C:/Users/adyba/pi-zig-native-oauth-chatgpt-20261015'
$taskEvidence=$PSScriptRoot
$taskName='oauth-chatgpt-ae7-source43-first-20261015'
$taskPacket=Join-Path $taskTree 'verification/native-ai-chatgpt-oauth-source43-20261015'
if(Test-Path -LiteralPath $taskPacket){throw 'Refuse Source43 packet replay'}
$taskExpected=Join-Path $taskTree 'src/extensions/fixtures/ai-oauth-chatgpt-ae7.json'
$taskExpectedHash=(Get-FileHash -LiteralPath $taskExpected).Hash
if($taskExpectedHash -cne '61B2B03DADA222EF369EF20C901E64BFF7A17C5238E1E434FC7922FDF623DE24'){throw 'Source43 committed expected drift'}
$taskOwner=Get-Content -Raw -LiteralPath (Join-Path $taskEvidence "$taskName.json")|ConvertFrom-Json
$taskPost=Get-Content -Raw -LiteralPath (Join-Path $taskEvidence "$taskName-posthash.json")|ConvertFrom-Json
$taskResult=Get-Content -Raw -LiteralPath (Join-Path $taskEvidence "$taskName-output.json")|ConvertFrom-Json
$taskFrozen=@(Get-Content -Raw -LiteralPath (Join-Path $taskEvidence "$taskName-extra-before.json")|ConvertFrom-Json)
if($taskOwner.status -cne 'passed' -or $taskOwner.exit_code -ne 0 -or $taskOwner.pid -ne 69972 -or !$taskOwner.identity_captured){throw 'Original Source43 owner is not successful'}
if($taskPost.control_manifest_drift -or @($taskPost.extra_control_drift).Count -or @($taskPost.absent_dependency_drift).Count -or $taskPost.historical_absence_records -ne 84){throw 'Original Source43 controls or absence receipt failed'}
foreach($taskSpec in @(@{name='source';count=1968},@{name='dependencies';count=31064},@{name='node_tools';count=1774})){
 $taskRow=@($taskPost.manifests|Where-Object name -eq $taskSpec.name)
 if($taskRow.Count -ne 1 -or $taskRow[0].files -ne $taskSpec.count -or $taskRow[0].drift -ne 0 -or @($taskRow[0].changed).Count){throw 'Original Source43 full posthash mismatch'}
}
if($taskResult.count -ne 43 -or @($taskResult.rows).Count -ne 43 -or $taskResult.runtime -cne 'v24.14.0' -or $taskResult.sourceHead -cne 'ae7b16d43b7c78c5b6fa3213fdd1215bb339729d'){throw 'Original Source43 result scope changed'}
if(@($taskResult.ownedListeners).Count -ne 6 -or @($taskResult.ownedListeners|Where-Object {$_.pid -ne 69972 -or $_.port -ne 1455 -or $_.address -cne '127.0.0.1' -or !$_.actualServer}).Count){throw 'Original Source43 listener ownership changed'}
if((Get-FileHash -LiteralPath (Join-Path $taskEvidence "$taskName-output.json")).Hash -cne $taskExpectedHash){throw 'Original Source output differs from committed expected'}
foreach($taskRow in $taskFrozen){if((Get-FileHash -LiteralPath $taskRow.path).Hash -cne $taskRow.sha256){throw "Frozen caller/control bytes drifted: $($taskRow.path)"}}
$taskObservedPath=Join-Path $taskEvidence 'sourceae7-modules-69972-0-20261015.jsonl'
$taskObserved=@(Get-Content -LiteralPath $taskObservedPath|ForEach-Object {$_|ConvertFrom-Json})
if($taskObserved.Count -ne 6 -or @($taskObserved|Where-Object externalControl -eq $false).Count -ne 4){throw 'Original Source43 observer scope changed'}
foreach($taskRow in $taskObserved){if((Get-FileHash -LiteralPath $taskRow.path).Hash -ine $taskRow.sha256){throw 'Observed original Source bytes drifted'}}
[void][IO.Directory]::CreateDirectory($taskPacket)
$taskPayload=[Collections.Generic.List[object]]::new()
function Retain-File([string]$taskPath,[string]$taskRelative){
 $taskDestination=Join-Path $taskPacket $taskRelative
 [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($taskDestination))
 [IO.File]::WriteAllBytes($taskDestination,[IO.File]::ReadAllBytes($taskPath))
 $taskOriginalHash=(Get-FileHash -LiteralPath $taskPath).Hash
 if((Get-FileHash -LiteralPath $taskDestination).Hash -cne $taskOriginalHash){throw 'Receipt retention changed bytes'}
 $taskPayload.Add([ordered]@{path=$taskRelative.Replace('\','/');sha256=$taskOriginalHash;bytes=(Get-Item -LiteralPath $taskDestination).Length;original_path=$taskPath})
}
foreach($taskFile in Get-ChildItem -LiteralPath $taskEvidence -Filter "$taskName*"){Retain-File $taskFile.FullName $taskFile.Name}
foreach($taskFileName in @('sourceae7-oauth-chatgpt-capture-20261015.mjs','sourceae7-observe-20261015.mjs','Run-OAuthChatGPTAe7Source43-20261015.ps1','Invoke-OwnedEeSourceJob-20261012.ps1','sourceae7-preparation-controls-20261015.json','sourceae7-preparation-readiness-20261015.json','sourceae7-dependency-contract-audit-20261015.json','sourceae7-modules-69972-0-20261015.jsonl')){Retain-File (Join-Path $taskEvidence $taskFileName) $taskFileName}
Retain-File (Join-Path $taskTree 'src/extensions/fixtures/ai-oauth-chatgpt-ae7.input.mjs') 'ai-oauth-chatgpt-ae7.input.mjs'
Retain-File $taskExpected 'ai-oauth-chatgpt-ae7.json'
foreach($taskRow in $taskObserved|Where-Object externalControl -eq $false){Retain-File $taskRow.path ('original-source/'+($taskRow.path -replace '^.*packages\\ai\\src\\','').Replace('\','/'))}
$taskManifestNames=@('sourceae7-full-manifest-20261015.json','sourceae7-runtime-manifest-20261015.json','sourceae7-node-tools-before-20261015.json')
$taskZipPath=Join-Path $taskPacket 'original-frozen-manifests.zip'
$taskZip=[IO.Compression.ZipFile]::Open($taskZipPath,[IO.Compression.ZipArchiveMode]::Create)
try{foreach($taskFileName in $taskManifestNames){[void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($taskZip,(Join-Path $taskEvidence $taskFileName),$taskFileName,[IO.Compression.CompressionLevel]::Optimal)}}finally{$taskZip.Dispose()}
$taskZip=[IO.Compression.ZipFile]::OpenRead($taskZipPath)
try{
 if($taskZip.Entries.Count -ne 3){throw 'Three original frozen manifests required'}
 foreach($taskEntry in $taskZip.Entries){$taskStream=$taskEntry.Open();try{$taskSha=[Security.Cryptography.SHA256]::HashData($taskStream);$taskEntryHash=[Convert]::ToHexString($taskSha)}finally{$taskStream.Dispose()};if($taskEntryHash -cne (Get-FileHash -LiteralPath (Join-Path $taskEvidence $taskEntry.FullName)).Hash){throw 'Independent retained ZIP entry hash mismatch'}}
}finally{$taskZip.Dispose()}
$taskPayload.Add([ordered]@{path='original-frozen-manifests.zip';sha256=(Get-FileHash -LiteralPath $taskZipPath).Hash;bytes=(Get-Item -LiteralPath $taskZipPath).Length;original_path='byte-identical captured frozen manifests; each ZIP entry independently rehashed'})
[ordered]@{status='retained_original_Source43_receipts_verified';source_cases=43;source_head=$taskResult.sourceHead;source_pid=69972;source_exit=0;source_terminal_utc=$taskOwner.completed_utc;original_full_posthash_utc=$taskPost.completed_utc;source_files=1968;runtime_files=31064;node_tools=1774;historical_absences=84;posthash_drift=0;source_owned_callback_listeners=6;original_observed_modules=6;original_source_modules=4;expected_sha256=$taskExpectedHash;current_frozen_control_bytes_verified=$taskFrozen.Count;retained_files=$taskPayload.Count;source_rerun=$false;native_execution=$false;product_changed=$false;native_qualified=$false;full_pi_qualified=$false;public_activation=$false;retained_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $taskPacket 'retention-verification.json') -Encoding utf8NoBOM
$taskPayload.Add([ordered]@{path='retention-verification.json';sha256=(Get-FileHash -LiteralPath (Join-Path $taskPacket 'retention-verification.json')).Hash;bytes=(Get-Item -LiteralPath (Join-Path $taskPacket 'retention-verification.json')).Length;original_path='new retention check of immutable original receipts'})
$taskPayload|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskPacket 'packet-sha256.json') -Encoding utf8NoBOM
Write-Output ('RETAINED_SOURCE43_FILES='+$taskPayload.Count)

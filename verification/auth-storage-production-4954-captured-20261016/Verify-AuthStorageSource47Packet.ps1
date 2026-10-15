param([string]$Archive=(Join-Path $PSScriptRoot 'source47-packet.zip'),[string]$ExpectedArchiveSha256='',[string]$ExpectedManifestSha256='')
$ErrorActionPreference='Stop'
if($ExpectedArchiveSha256 -and (Get-FileHash -LiteralPath $Archive).Hash -cne $ExpectedArchiveSha256){throw 'Archive hash mismatch'}
$taskZip=[IO.Compression.ZipFile]::OpenRead($Archive)
try{
 function Read-Packet([string]$taskName){
  $taskEntry=$taskZip.GetEntry($taskName)
  if(!$taskEntry){throw "Missing packet entry $taskName"}
  $taskStream=$taskEntry.Open();$taskMemory=[IO.MemoryStream]::new()
  try{$taskStream.CopyTo($taskMemory);return ,$taskMemory.ToArray()}finally{$taskStream.Dispose();$taskMemory.Dispose()}
 }
 function Read-PacketJson([string]$taskName){[Text.Encoding]::UTF8.GetString((Read-Packet $taskName))|ConvertFrom-Json}
 $taskManifestBytes=Read-Packet 'packet-manifest.json'
 $taskManifestHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($taskManifestBytes))
 if($ExpectedManifestSha256 -and $taskManifestHash -cne $ExpectedManifestSha256){throw 'Manifest hash mismatch'}
 $taskManifest=[Text.Encoding]::UTF8.GetString($taskManifestBytes)|ConvertFrom-Json
 if($taskManifest.candidate -cne '6489aeab46cf17a9e29177c08b3408bc0e43750b' -or $taskManifest.source -cne '4954d760504c11df9b2cbdc040346107b6a8153d'){throw 'Packet authority mismatch'}
 if($taskZip.Entries.Count -ne $taskManifest.entries.Count+1 -or @($taskZip.Entries.FullName|Group-Object|Where-Object Count -ne 1).Count){throw 'Archive exact inventory/uniqueness failed'}
 foreach($taskEntry in $taskManifest.entries){
  if($taskEntry.name.Contains('/') -or $taskEntry.name.Contains('\') -or $taskEntry.name -in @('.','..','packet-manifest.json')){throw 'Invalid flat packet entry'}
  $taskBytes=Read-Packet $taskEntry.name
  if($taskBytes.Length -ne $taskEntry.bytes -or [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($taskBytes)) -cne $taskEntry.sha256){throw "Payload hash/length mismatch $($taskEntry.name)"}
 }
 $taskPrefix='auth-storage-production-4954-source47-first-20261015'
 $taskOwner=Read-PacketJson "$taskPrefix.json"
 $taskPost=Read-PacketJson "$taskPrefix-posthash.json"
 $taskOutput=Read-PacketJson "$taskPrefix-output.json"
 $taskAbsence=Read-PacketJson "$taskPrefix-independent-absence.json"
 $taskValidation=Read-PacketJson "$taskPrefix-validation.json"
 $taskPackageBefore=Read-PacketJson "$taskPrefix-package-before.json"
 $taskPackagePost=Read-PacketJson "$taskPrefix-package-post.json"
 if($taskOwner.status -cne 'passed' -or $taskOwner.exit_code -ne 0 -or !$taskOwner.independent_pid_absent -or !$taskOwner.terminal_kernel_handle -or $taskOwner.executable_sha256 -cne '63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088'){throw 'Actual Source terminal identity failed'}
 if($taskPost.candidate_files -ne 7718 -or $taskPost.compiler_files -ne 19546 -or $taskPost.candidate_drift.Count -or $taskPost.candidate_inventory_drift.Count -or $taskPost.compiler_drift.Count -or $taskPost.compiler_inventory_drift.Count -or $taskPost.extra_control_drift.Count -or $taskPost.absent_dependency_drift.Count -or $taskPost.historical_absence_records -ne 84 -or $taskPost.control_manifest_drift -or $taskPost.candidate_head_drift -or $taskPost.source_head_drift -or !$taskPost.expected_still_absent -or $taskPost.owner_failure){throw 'Actual full posthash failed'}
 foreach($taskSpec in @(@{name='source';count=1970},@{name='dependencies';count=31064},@{name='node_tools';count=1774})){
  $taskHashRow=$taskPost.manifests|Where-Object name -ceq $taskSpec.name
  $taskPathRow=$taskPost.path_inventories|Where-Object name -ceq $taskSpec.name
  if($taskHashRow.files -ne $taskSpec.count -or $taskHashRow.drift -ne 0 -or $taskPathRow.count -ne $taskSpec.count -or $taskPathRow.drift.Count){throw "Actual full inventory failed $($taskSpec.name)"}
 }
 if($taskOutput.count -ne 47 -or $taskOutput.rows.Count -ne 47 -or $taskOutput.caseIds.Count -ne 47 -or $taskOutput.sourceHead -cne $taskManifest.source -or $taskOutput.runtime -cne 'v24.14.0'){throw 'Actual Source47 inventory failed'}
 for($taskIndex=0;$taskIndex -lt 47;$taskIndex++){if($taskOutput.rows[$taskIndex].id -cne $taskOutput.caseIds[$taskIndex]){throw 'Ordered Source47 cases differ'}}
 if(@($taskOutput.rows|Where-Object {$_.ok -ne $true -and $_.id -notin @('read-rejects-with-signal','file-malformed-signal-rejection')}).Count){throw 'Unexpected Source failure'}
 if($taskOutput.rawEffects.Count -ne 70 -or $taskOutput.rawErrors.Count -ne 3 -or @($taskOutput.rawErrors|Where-Object {-not $_.stack}).Count -or $taskOutput.rawRevisions.Count -ne 1 -or $taskOutput.rawRevisions[0].Split(':').Count -ne 5){throw 'Raw original effects/errors/revision absent'}
 if(!$taskOutput.ownedTemporaryRemovedAndAbsenceVerified -or !$taskAbsence.independentPIDAbsent -or !$taskAbsence.independentTemporaryAbsent){throw 'Owned process/temporary cleanup failed'}
 $taskPackageHash='83C3BB7619F590C213CC96A24216EB29A819A3EF6DC548607CC037ED276E8DC5'
 if($taskPackageBefore.version -cne '1.3.0' -or $taskPackageBefore.name -cne '@earendil-works/pi-coding-agent' -or !$taskPackageBefore.ordinary_data -or !$taskPackageBefore.source_manifest_contains_exact_data -or $taskPackageBefore.sha256 -cne $taskPackageHash -or $taskPackagePost.sha256 -cne $taskPackageHash -or $taskPackagePost.package_data_drift.Count -or $taskPackagePost.owner_failure){throw 'Consumed actual package ordinary data failed'}
 $taskFrozenPackage=Read-PacketJson "$taskPrefix-package-frozen.json"
 if($taskFrozenPackage.version -cne '1.3.0' -or [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData((Read-Packet "$taskPrefix-package-frozen.json"))) -cne $taskPackageHash){throw 'Frozen package bytes/version failed'}
 $taskExpectedBytes=Read-Packet 'auth-storage-production-4954-source.json'
 $taskExpectedHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($taskExpectedBytes))
 if($taskExpectedHash -cne '96828F1B1E1F8B275A871352086082E1F38A0B34285D2815E61E0707506E688B' -or $taskValidation.expected_sha256 -cne $taskExpectedHash -or !$taskValidation.expected_published_after_terminal_and_full_posthash -or $taskValidation.native_qualified -or $taskValidation.full_pi_qualified){throw 'Expected provenance failed'}
 $taskExpected=[Text.Encoding]::UTF8.GetString($taskExpectedBytes)|ConvertFrom-Json
 if(($taskExpected|ConvertTo-Json -Depth 100 -Compress) -cne ($taskOutput.rows|ConvertTo-Json -Depth 100 -Compress)){throw 'Expected rows differ from actual original Source'}
 @{status='passed';manifest_sha256=$taskManifestHash;payloads=$taskManifest.entries.Count;archive_entries=$taskZip.Entries.Count;source_cases=47;raw_fs_effects=70;original_error_stacks=3;original_revision_fields=5;actual_package_version=$taskFrozenPackage.version;candidate_files=7718;compiler_files=19546;source_files=1970;runtime_files=31064;node_files=1774;historical_absences=84;native_qualified=$false;full_pi_qualified=$false}|ConvertTo-Json -Depth 5
}finally{$taskZip.Dispose()}

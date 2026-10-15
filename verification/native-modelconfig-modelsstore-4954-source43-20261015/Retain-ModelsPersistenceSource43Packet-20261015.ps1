$ErrorActionPreference='Stop'
$taskTree='C:/Users/adyba/pi-zig-native-modelconfig-modelsstore-4954-20261015'
$taskEvidence=$PSScriptRoot
$taskName='models-persistence-4954-source43-first-20261015'
$taskPacket=Join-Path $taskTree 'verification/native-modelconfig-modelsstore-4954-source43-20261015'
if(Test-Path -LiteralPath $taskPacket){throw 'Refuse retained Source43 packet replay'}
$taskExpected=Join-Path $taskTree 'src/extensions/fixtures/sdk-model-config-stores-4954.json'
$taskExpectedHash=(Get-FileHash -LiteralPath $taskExpected).Hash
if($taskExpectedHash -cne '73F249332783BCA14D706659A10E5A4B9F3A7C8417D80AA115F530F3CDCFD434'){throw 'Expected Source43 drift'}
$taskOwner=Get-Content -Raw -LiteralPath (Join-Path $taskEvidence "$taskName.json")|ConvertFrom-Json
$taskPost=Get-Content -Raw -LiteralPath (Join-Path $taskEvidence "$taskName-posthash.json")|ConvertFrom-Json
$taskOutput=Get-Content -Raw -LiteralPath (Join-Path $taskEvidence "$taskName-output.json")|ConvertFrom-Json
if($taskOwner.pid -ne 71032 -or $taskOwner.status -cne 'passed' -or $taskOwner.exit_code -ne 0 -or !$taskOwner.identity_captured){throw 'Original successful Source owner required'}
foreach($taskNameField in @('compiler_drift','candidate_drift','compiler_inventory_drift','candidate_inventory_drift','extra_control_drift','absent_dependency_drift')){if(@($taskPost.$taskNameField).Count){throw 'Original full posthash was not zero'}}
if($taskPost.compiler_files -ne 19546 -or $taskPost.candidate_files -ne 7232 -or $taskPost.historical_absence_records -ne 84 -or $taskPost.control_manifest_drift -or !$taskPost.expected_still_absent){throw 'Original sealed scope mismatch'}
foreach($taskSpec in @(@{name='source';count=1970},@{name='dependencies';count=31064},@{name='node_tools';count=1774})){$taskRow=@($taskPost.manifests|Where-Object name -eq $taskSpec.name);if($taskRow.Count -ne 1 -or $taskRow[0].files -ne $taskSpec.count -or $taskRow[0].drift -ne 0 -or @($taskRow[0].changed).Count){throw 'Original Source full inventory mismatch'}}
if($taskOutput.count -ne 43 -or $taskOutput.rows.Count -ne 43 -or $taskOutput.sourceHead -cne '4954d760504c11df9b2cbdc040346107b6a8153d' -or @($taskOutput.ownedLockDirectoriesRemaining).Count){throw 'Original actual class/filesystem output scope mismatch'}
if((Get-FileHash -LiteralPath (Join-Path $taskEvidence "$taskName-output.json")).Hash -cne $taskExpectedHash){throw 'Actual source output/expected mismatch'}
$taskExtra=@(Get-Content -Raw -LiteralPath (Join-Path $taskEvidence "$taskName-extra-before.json")|ConvertFrom-Json)
foreach($taskRow in $taskExtra){if((Get-FileHash -LiteralPath $taskRow.path).Hash -cne $taskRow.sha256){throw "Original caller/control changed: $($taskRow.path)"}}
[void][IO.Directory]::CreateDirectory($taskPacket)
$taskRows=[Collections.Generic.List[object]]::new()
function Retain([string]$taskSource,[string]$taskRelative){$taskDestination=Join-Path $taskPacket $taskRelative;[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($taskDestination));[IO.File]::WriteAllBytes($taskDestination,[IO.File]::ReadAllBytes($taskSource));$taskHash=(Get-FileHash -LiteralPath $taskSource).Hash;if((Get-FileHash -LiteralPath $taskDestination).Hash -cne $taskHash){throw 'Retained receipt bytes changed'};$taskRows.Add([ordered]@{path=$taskRelative.Replace('\','/');sha256=$taskHash;bytes=(Get-Item -LiteralPath $taskDestination).Length;original_path=$taskSource})}
foreach($taskFile in Get-ChildItem -LiteralPath $taskEvidence -Filter "$taskName*"){if($taskFile.Name -notlike '*candidate-compiler-before.json'){Retain $taskFile.FullName $taskFile.Name}}
foreach($taskFileName in @('source4954-models-persistence-capture-20261015.mjs','source4954-observe-20261015.mjs','Run-ModelsPersistence4954Source43-20261015.ps1','Invoke-OwnedModelsPersistenceSource-20261015.ps1','source4954-preparation-readiness-20261015.json','source4954-dependency-contract-audit-20261015.json','models-persistence-4954-source43-prelaunch-seal-20261015.json','Retain-ModelsPersistenceSource43Packet-20261015.ps1')){Retain (Join-Path $taskEvidence $taskFileName) $taskFileName}
Retain (Join-Path $taskTree 'src/extensions/fixtures/sdk-model-config-stores-4954.input.mjs') 'sdk-model-config-stores-4954.input.mjs'
Retain $taskExpected 'sdk-model-config-stores-4954.json'
$taskObserverFiles=@(Get-ChildItem -LiteralPath $taskEvidence -Filter 'source4954-modules-71032-*-20261015.jsonl')
if(!$taskObserverFiles.Count){throw 'Actual module observer required'}
$taskObserved=@()
foreach($taskFile in $taskObserverFiles){Retain $taskFile.FullName $taskFile.Name;$taskObserved+=@(Get-Content -LiteralPath $taskFile.FullName|ForEach-Object {$_|ConvertFrom-Json}|Where-Object kind -eq 'observed-module')}
foreach($taskRow in $taskObserved){if((Get-FileHash -LiteralPath $taskRow.path).Hash -ine $taskRow.sha256){throw 'Actual observed Source module changed'}}
$taskSourceRoot='C:/Users/adyba/pi-upstream-source-4954d76-20261015'
foreach($taskRelative in @('packages/coding-agent/src/core/model-config.ts','packages/coding-agent/src/core/models-store.ts','packages/coding-agent/src/core/auth-storage.ts','packages/ai/src/models-store.ts','packages/coding-agent/src/utils/paths.ts','packages/coding-agent/src/utils/json.ts','packages/coding-agent/src/utils/text.ts','packages/coding-agent/src/utils/abort.ts')){Retain (Join-Path $taskSourceRoot $taskRelative) ('original-source/'+$taskRelative)}
$taskZipPath=Join-Path $taskPacket 'original-frozen-input-inventories.zip'
$taskManifestNames=@('source4954-full-manifest-20261015.json','source4954-runtime-manifest-20261015.json','source4954-node-tools-before-20261015.json',"$taskName-candidate-compiler-before.json")
$taskZip=[IO.Compression.ZipFile]::Open($taskZipPath,[IO.Compression.ZipArchiveMode]::Create)
try{foreach($taskFileName in $taskManifestNames){[void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($taskZip,(Join-Path $taskEvidence $taskFileName),$taskFileName,[IO.Compression.CompressionLevel]::Optimal)}}finally{$taskZip.Dispose()}
$taskZip=[IO.Compression.ZipFile]::OpenRead($taskZipPath)
try{if($taskZip.Entries.Count -ne 4){throw 'Four full original inventories required'};foreach($taskEntry in $taskZip.Entries){$taskStream=$taskEntry.Open();try{$taskHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($taskStream))}finally{$taskStream.Dispose()};if($taskHash -cne (Get-FileHash -LiteralPath (Join-Path $taskEvidence $taskEntry.FullName)).Hash){throw 'Independent retained inventory entry hash mismatch'}}}finally{$taskZip.Dispose()}
$taskRows.Add([ordered]@{path='original-frozen-input-inventories.zip';sha256=(Get-FileHash -LiteralPath $taskZipPath).Hash;bytes=(Get-Item -LiteralPath $taskZipPath).Length;original_path='four original frozen manifests; ZIP entries independently rehashed'})
[ordered]@{status='original_Source43_receipts_retained_and_verified';source_head=$taskOutput.sourceHead;source_cases=43;source_pid=71032;source_exit=0;source_terminal_utc=$taskOwner.completed_utc;original_full_posthash_utc=$taskPost.completed_utc;source_capture_candidate_head='828e0f3e9bb196d17483de778b25679887ff611d';source_files=1970;runtime_files=31064;node_files=1774;compiler_files=19546;candidate_files=7232;historical_absences=84;original_full_posthash_drift=0;expected_sha256=$taskExpectedHash;observed_modules=$taskObserved.Count;actual_owned_locks_remaining=0;current_caller_control_bytes_verified=$taskExtra.Count;native_qualified=$false;source_rerun=$false;native_execution=$false;full_pi_qualified=$false;public_activation=$false;retained_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskPacket 'retention-verification.json') -Encoding utf8NoBOM
$taskRows.Add([ordered]@{path='retention-verification.json';sha256=(Get-FileHash -LiteralPath (Join-Path $taskPacket 'retention-verification.json')).Hash;bytes=(Get-Item -LiteralPath (Join-Path $taskPacket 'retention-verification.json')).Length;original_path='new retrospective original receipt verification'})
$taskRows|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskPacket 'packet-sha256.json') -Encoding utf8NoBOM
Write-Output ('RETAINED_ORIGINAL_MODELS_SOURCE43_PAYLOADS='+$taskRows.Count)

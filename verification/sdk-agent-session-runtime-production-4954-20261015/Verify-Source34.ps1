param([string]$ProofRoot=$PSScriptRoot)
$ErrorActionPreference='Stop'
$taskQualification=Get-Content -LiteralPath (Join-Path $ProofRoot 'source34-qualification.json') -Raw|ConvertFrom-Json
$taskEntries=@(Get-Content -LiteralPath (Join-Path $ProofRoot 'source34-qualified-archive-entries.json') -Raw|ConvertFrom-Json)
$taskArchive=Join-Path $ProofRoot 'source34-qualified-evidence.zip'
if((Get-FileHash -LiteralPath $taskArchive).Hash -ine $taskQualification.archive_sha256){throw 'Historical proof archive SHA mismatch'}
if($taskQualification.status -cne 'Source_passed' -or $taskQualification.cases -ne 34 -or $taskQualification.owner.status -cne 'passed' -or $taskQualification.owner.exit_code -ne 0 -or $taskQualification.absence.present){throw 'Actual Source terminal/absence evidence required'}
foreach($taskProperty in $taskQualification.post.PSObject.Properties){if($taskProperty.Name -like '*_drift' -and $taskProperty.Value -ne 0){throw 'Historical fullpost drift'}}
if($taskQualification.post.candidate_files -ne 7259 -or $taskQualification.post.reference_files -ne 1970 -or $taskQualification.post.dependencies_files -ne 31064 -or $taskQualification.post.node_files -ne 1774 -or $taskQualification.post.compiler_files -ne 19546 -or $taskQualification.post.controls_files -ne 11 -or $taskQualification.post.declared_absent_records -ne 84){throw 'Historical fullfreeze universe mismatch'}
if($taskQualification.native_compiled -or $taskQualification.native_runtime_qualified -or $taskQualification.default_production_graph_qualified -or $taskQualification.public_activation){throw 'Source proof must preserve native/default/application qualification boundary'}
$taskZip=[IO.Compression.ZipFile]::OpenRead($taskArchive)
try{
 if($taskZip.Entries.Count -ne $taskEntries.Count -or $taskEntries.Count -ne $taskQualification.archive_entries){throw 'Raw proof ZIP entry inventory mismatch'}
 foreach($taskRow in $taskEntries){
  if($taskRow.entry -match '(^/|\\|(^|/)\.\.(/|$))'){throw 'Unsafe proof entry path'}
  $taskEntry=$taskZip.GetEntry($taskRow.entry)
  if(!$taskEntry -or $taskEntry.Length -ne $taskRow.bytes){throw 'Raw proof entry missing or size mismatch'}
  $taskStream=$taskEntry.Open()
  try{$taskHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($taskStream))}finally{$taskStream.Dispose()}
  if($taskHash -ine $taskRow.sha256){throw 'Raw proof entry SHA mismatch'}
 }
}finally{$taskZip.Dispose()}
$taskFixture=Join-Path $ProofRoot '../../src/extensions/fixtures/sdk-agent-session-runtime-production-4954.json'
$taskInput=Join-Path $ProofRoot '../../src/extensions/fixtures/sdk-agent-session-runtime-production-4954.input.txt'
if((Get-FileHash -LiteralPath $taskFixture).Hash -ine $taskQualification.expected_sha256 -or(Get-FileHash -LiteralPath $taskInput).Hash -ine $taskQualification.input_sha256){throw 'Accepted genuine Source/input bytes changed'}
$taskCaptured=Get-Content -LiteralPath $taskFixture -Raw|ConvertFrom-Json
if($taskCaptured.cases -ne 34 -or @($taskCaptured.rows).Count -ne 34 -or $taskCaptured.sourceHead -cne $taskQualification.original_source){throw 'Incomplete genuine Source fixture'}
[ordered]@{status='verified_historical_Source34';archive_entries=$taskEntries.Count;fullpost_zero=$true;owned_pid=$taskQualification.owner.pid;historical_pid_absent=$true;native_qualified=$false;package_metadata_version=$taskQualification.package_metadata.actualConfigVersion}|ConvertTo-Json

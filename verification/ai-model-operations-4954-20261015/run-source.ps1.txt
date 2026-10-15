param([Parameter(Mandatory)][ValidatePattern('^[a-z0-9-]+$')][string]$Attempt,[Parameter(Mandatory)][ValidateSet(3)][int]$Slot)
$ErrorActionPreference='Stop'
$taskRoot='C:/Users/adyba/pi-zig-ai-model-operations-source-20261015'
$taskEvidence='C:/Users/adyba/pi-zig-update-evidence-20261003'
$taskName="ai-model-operations-4954-source-$Attempt-20261015"
$taskExpected=Join-Path $taskRoot 'src/extensions/fixtures/ai-model-operations-4954.json'
if(Test-Path -LiteralPath $taskExpected){throw 'Preserve accepted expected data; this owner accepts only the first genuine capture'}
if(Test-Path -LiteralPath (Join-Path $PSScriptRoot "$taskName-owner.json")){throw 'Fresh unique capture attempt required'}
$taskPython='C:/Python314/python.exe'
$taskFreeze=Join-Path $PSScriptRoot 'freeze-inputs.py'
& $taskPython $taskFreeze pre $taskName
if($LASTEXITCODE -ne 0){throw 'Complete prehash/admission prerequisite failed'}
$taskFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
if($taskFree -lt 2MB){throw 'Fresh2GiB Source admission denied'}
@{status='admitted';slot=$Slot;source_only=$true;free_kib=$taskFree;required_kib=2MB;heap_mb=256;deadline_seconds=300;settle_seconds=10;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $PSScriptRoot "$taskName-admission.json") -Encoding utf8NoBOM
$taskOutput=Join-Path $PSScriptRoot "$taskName-output.json"
try {
 & (Join-Path $PSScriptRoot 'Invoke-ExactSourceProcess.ps1') -Name $taskName -Arguments @('--max-old-space-size=256','--import',([Uri](Join-Path $taskEvidence 'source4954-observe-20261015.mjs')).AbsoluteUri,(Join-Path $PSScriptRoot 'capture-source.mjs'),$taskOutput,(Join-Path $taskRoot 'src/extensions/fixtures/ai-model-operations-4954.input.txt')) -EnvironmentOverrides @{PI_SOURCE_ORACLE_CONTROL_MANIFEST=(Join-Path $PSScriptRoot "$taskName-oracle-controls.json")}
} finally {
 & $taskPython $taskFreeze post $taskName
 if($LASTEXITCODE -ne 0){throw 'Complete frozen input posthash failed; no expected acceptance'}
}
$taskOwner=Get-Content -LiteralPath (Join-Path $PSScriptRoot "$taskName-owner.json") -Raw|ConvertFrom-Json
if($taskOwner.status -cne 'passed' -or $taskOwner.exit_code -ne 0){throw 'Terminal successful original Source owner required'}
$taskPidState=Get-CimInstance Win32_Process -Filter "ProcessId = $($taskOwner.pid)"
if($taskPidState -and [Math]::Abs((([DateTimeOffset]$taskPidState.CreationDate).UtcDateTime-([DateTimeOffset]$taskOwner.created_utc).UtcDateTime).Ticks) -le 10){throw 'Owned Source PID still present after terminal completion'}
$taskDocument=Get-Content -LiteralPath $taskOutput -Raw|ConvertFrom-Json
if($taskDocument.sourceHead -cne '4954d760504c11df9b2cbdc040346107b6a8153d' -or !$taskDocument.canonicalModelsErrorIdentity -or $taskDocument.cases -ne 88 -or $taskDocument.rows.Count -ne $taskDocument.cases){throw 'Complete actual original88 helper artifact required'}
Copy-Item -LiteralPath $taskOutput -Destination $taskExpected
@{status='source-qualified-native-unrun';cases=$taskDocument.cases;source_head=$taskDocument.sourceHead;candidate_head=(git -C $taskRoot rev-parse HEAD);owner_pid=$taskOwner.pid;owned_absence_verified=$true;expected_sha256=(Get-FileHash -LiteralPath $taskExpected).Hash;raw_diagnostics_sha256=(Get-FileHash -LiteralPath "$taskOutput.raw-diagnostics.json").Hash;native_compiled=$false;native_replayed=$false;full_pi_qualified=$false;public_activation=$false}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'qualification.json') -Encoding utf8NoBOM
Write-Output "ORIGINAL_MODEL_OPERATION_CASES=$($taskDocument.cases)"

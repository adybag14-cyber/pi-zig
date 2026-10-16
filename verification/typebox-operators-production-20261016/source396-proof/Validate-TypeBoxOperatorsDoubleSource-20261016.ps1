#requires -Version 7.0
$ErrorActionPreference='Stop'
$evidence=$PSScriptRoot
$tree='C:/Users/adyba/pi-zig-typebox-operators-production-20261016'
$candidate='3ed99011a6f53a7ffb1392fac759ffdf0b0b843b'
$expected=Join-Path $tree 'src/extensions/fixtures/typebox-operators-production.expected.json'
if(Test-Path -LiteralPath $expected){throw 'Refuse authored/previous expected data'}
if((git -C $tree rev-parse HEAD).Trim() -cne $candidate -or (git -C $tree status --porcelain)){throw 'Expected publication requires exact clean captured checkpoint'}
$outputs=@();$receipts=@()
foreach($attempt in @('first','second')){
    $name="typebox-operators-source-$attempt-20261016"
    $validation=Get-Content -LiteralPath (Join-Path $evidence "$name-validation.json") -Raw|ConvertFrom-Json
    $process=Get-Content -LiteralPath (Join-Path $evidence "$name.json") -Raw|ConvertFrom-Json
    $post=Get-Content -LiteralPath (Join-Path $evidence "$name-posthash.json") -Raw|ConvertFrom-Json
    if($validation.status -cne 'genuine_source_capture_qualified' -or $validation.candidate -cne $candidate -or $validation.cases -ne 396 -or $validation.full_posthash_drift -ne 0 -or $process.status -cne 'passed' -or $process.exit_code -ne 0){throw 'Both actual terminal passes required'}
    if(@($post.manifests|Where-Object{$_.drift.Count -or $_.path_drift.Count}).Count -or @($post.candidate_drift).Count -or @($post.candidate_path_drift).Count -or @($post.compiler_drift).Count -or @($post.compiler_path_drift).Count -or @($post.control_drift).Count -or $post.control_manifest_drift -or @($post.absence_drift).Count -or !$post.expected_still_absent){throw 'Both full zero-drift captures required'}
    if(Get-CimInstance Win32_Process -Filter "ProcessId = $($process.pid)"){throw 'Actual Source process still alive'}
    $path=Join-Path $evidence "$name-output.json"
    if((Get-FileHash -LiteralPath $path).Hash -cne $validation.output_sha256){throw 'Actual output changed after terminal validation'}
    $outputs+=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
    $receipts+=[ordered]@{attempt=$attempt;pid=$process.pid;created_utc=$process.created_utc;validation_sha256=(Get-FileHash -LiteralPath (Join-Path $evidence "$name-validation.json")).Hash;process_sha256=(Get-FileHash -LiteralPath (Join-Path $evidence "$name.json")).Hash;posthash_sha256=(Get-FileHash -LiteralPath (Join-Path $evidence "$name-posthash.json")).Hash;output_sha256=$validation.output_sha256}
}
$firstRows=$outputs[0].rows|ConvertTo-Json -Depth 100 -Compress
$secondRows=$outputs[1].rows|ConvertTo-Json -Depth 100 -Compress
if($firstRows -cne $secondRows -or $outputs[0].inputSha256 -cne $outputs[1].inputSha256 -or $outputs[0].closureSha256 -cne $outputs[1].closureSha256 -or $outputs[0].packageSha256 -cne $outputs[1].packageSha256 -or $outputs[0].version -cne '1.3.27'){throw 'Actual full Source double-capture disagreement'}
$inventory=Get-Content -LiteralPath (Join-Path $evidence 'operator-probe-inventory-20261016.json') -Raw|ConvertFrom-Json
if($inventory.count -ne 396 -or @($outputs[0].rows).Count -ne 396){throw 'Actual case inventory incomplete'}
for($i=0;$i -lt 396;$i++){if($outputs[0].rows[$i].name -cne $inventory.cases[$i]){throw 'Actual case missing or reordered'}}
Copy-Item -LiteralPath (Join-Path $evidence 'typebox-operators-source-first-20261016-output.json') -Destination $expected
[ordered]@{status='genuine_typebox_operator_double_source_qualified';captured_candidate=$candidate;version='1.3.27';cases=396;double_capture_rows_exact=$true;both_actual_terminals_passed=$true;all_full_posthash_and_path_drift=0;historical_absence_contracts=84;expected_published_only_after_both_terminal_and_agreement=$true;expected_sha256=(Get-FileHash -LiteralPath $expected).Hash;input_sha256=$outputs[0].inputSha256;closure_sha256=$outputs[0].closureSha256;package_sha256=$outputs[0].packageSha256;captures=$receipts;native_compiled=$false;native_qualified=$false;full_HOST_GPA=$false;C_malloc_exhaustive=$false;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 7|Set-Content -LiteralPath (Join-Path $evidence 'double-source396.validation.json') -Encoding utf8NoBOM
Get-Content -LiteralPath (Join-Path $evidence 'double-source396.validation.json') -Raw

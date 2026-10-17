$ErrorActionPreference='Stop'
$container='C:\Users\adyba\pi-zig'
$run=Join-Path $container 'evidence/root-typebox-stack-diagnostic-08bd-v4-20261017-143801'
$before=Get-Content -Raw -LiteralPath "$run/before.json"|ConvertFrom-Json
$audit=Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'audit.json')|ConvertFrom-Json -Depth 60
$paths=@('src/extensions/engine.zig','src/native_typebox_compile_production_test.zig','src/extensions/fixtures/typebox-operators-production.expected.json')
$pins=@(foreach($relative in $paths){
 $row=@($before.source|Where-Object relative -CEQ $relative)
 if($row.Count-ne1-or(Get-FileHash -LiteralPath $row[0].path).Hash-cne$row[0].sha256){throw 'Exact tested source/fixture payload changed'}
 $row[0]
})
$engine=Get-Content -Raw -LiteralPath $pins[0].path
$test=Get-Content -Raw -LiteralPath $pins[1].path
if($engine-notmatch'stack_limit:\s*usize\s*=\s*1024\s*\*\s*1024'-or$test-match'\.stack_limit\s*='-or[regex]::Matches($test,'\.host_await_timeout_ms\s*=\s*10000').Count-ne3){throw 'Preserved1MiB/default and10s awaits source binding'}
$expected=Get-Content -Raw -LiteralPath $pins[2].path|ConvertFrom-Json -Depth 60
if($expected.rows.Count-ne396-or($expected.rows[391]|ConvertTo-Json -Compress -Depth 50)-cne($audit.functional_mismatch.expected|ConvertTo-Json -Compress -Depth 50)){throw 'Raw mismatch expected row differs from genuine unchanged Source396 fixture'}
$record=[ordered]@{status='additive_source_binding_checks_passed';audit_sha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'audit.json')).Hash;source_pins=$pins;genuine_Source396_rows=396;raw_mismatch_expected_row391_exact=$true;Engine_guard_bytes=1048576;test_stack_override_absent=$true;guest_await_occurrences10000=3;candidate_current_head_not_used_as_new_execution=$true;jobs_executed=$false}
ConvertTo-Json -InputObject $record -Depth 8|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'source-binding-addendum.json') -Encoding utf8NoBOM
[pscustomobject]@{status=$record.status;sha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'source-binding-addendum.json')).Hash}|ConvertTo-Json

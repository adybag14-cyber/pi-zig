#requires -Version 7.0
param([string]$Packet = (Join-Path $PSScriptRoot 'source396-proof'))
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
function Read-Json([string]$name) { Get-Content -LiteralPath (Join-Path $Packet $name) -Raw | ConvertFrom-Json }
function Assert-Hash([string]$path, [string]$expected) {
    if ((Get-FileHash -LiteralPath $path).Hash -cne $expected.ToUpperInvariant()) { throw "Hash mismatch: $path" }
}
function Verify-Archive([string]$name, [object[]]$index) {
    $archive = [IO.Compression.ZipFile]::OpenRead((Join-Path $Packet $name))
    try {
        if ($archive.Entries.Count -ne $index.Count) { throw "Archive entry count mismatch: $name" }
        $seen = @{}
        foreach ($row in $index) {
            if ($seen.ContainsKey($row.entry)) { throw "Duplicate archive index entry: $($row.entry)" }
            $seen[$row.entry] = $true
            $entry = $archive.GetEntry($row.entry)
            if (!$entry) { throw "Missing archive entry: $($row.entry)" }
            $stream = $entry.Open()
            try { $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream)) }
            finally { $stream.Dispose() }
            if ($hash -cne $row.sha256.ToUpperInvariant()) { throw "Archive bytes changed: $($row.entry)" }
        }
    } finally { $archive.Dispose() }
}
$payloads = @(Read-Json 'payloads.sha256.json')
if ($payloads.Count -ne 34) { throw 'Expected 34 original proof payloads' }
$payloadNames = @{}
foreach ($row in $payloads) {
    if ($payloadNames.ContainsKey($row.path) -or [IO.Path]::GetFileName($row.path) -cne $row.path) { throw 'Invalid or duplicate payload path' }
    $payloadNames[$row.path] = $true
    Assert-Hash (Join-Path $Packet $row.path) $row.sha256
}
if (@(Get-ChildItem -LiteralPath $Packet -File).Count -ne 35) { throw 'Unexpected proof packet files' }
$frozen = @(Read-Json 'frozen-inventories.index.json')
$bodies = @(Read-Json 'observed-source-modules.index.json')
if ($frozen.Count -ne 5 -or $bodies.Count -ne 371) { throw 'Original archive inventory incomplete' }
Verify-Archive 'original-frozen-inventories.zip' $frozen
Verify-Archive 'observed-source-modules.zip' $bodies
$moduleHashes = @{}
foreach ($row in $bodies) {
    if ($moduleHashes.ContainsKey($row.original_path)) { throw 'Duplicate observed module path' }
    $moduleHashes[$row.original_path] = $row.sha256
}
$proof = Read-Json 'double-source396.validation.json'
$candidate = '3ed99011a6f53a7ffb1392fac759ffdf0b0b843b'
if ($proof.status -cne 'genuine_typebox_operator_double_source_qualified' -or $proof.captured_candidate -cne $candidate -or $proof.cases -ne 396 -or !$proof.double_capture_rows_exact -or !$proof.both_actual_terminals_passed -or $proof.all_full_posthash_and_path_drift -ne 0 -or $proof.native_compiled -or $proof.native_qualified -or $proof.full_HOST_GPA -or $proof.C_malloc_exhaustive) { throw 'Invalid historical qualification boundary' }
Assert-Hash (Join-Path $root 'src/extensions/fixtures/typebox-operators-production.expected.json') $proof.expected_sha256
Assert-Hash (Join-Path $root 'src/extensions/fixtures/typebox-operators-production.input.txt') $proof.input_sha256
Assert-Hash (Join-Path $PSScriptRoot 'reachable-closure.json') $proof.closure_sha256
$inventory = Read-Json 'operator-probe-inventory-20261016.json'
if ($inventory.count -ne 396 -or $inventory.input_sha256 -ine $proof.input_sha256) { throw 'Probe inventory mismatch' }
$rowsJson = @()
foreach ($attempt in @('first', 'second')) {
    $prefix = "typebox-operators-source-$attempt-20261016"
    $receipt = @($proof.captures | Where-Object attempt -CEQ $attempt)
    if ($receipt.Count -ne 1) { throw 'Missing unique capture receipt' }
    $receipt = $receipt[0]
    foreach ($pair in @(@('-validation.json', 'validation_sha256'), @('.json', 'process_sha256'), @('-posthash.json', 'posthash_sha256'), @('-output.json', 'output_sha256'))) {
        Assert-Hash (Join-Path $Packet ($prefix + $pair[0])) $receipt.($pair[1])
    }
    $validation = Read-Json "$prefix-validation.json"
    $process = Read-Json "$prefix.json"
    $post = Read-Json "$prefix-posthash.json"
    if ($validation.status -cne 'genuine_source_capture_qualified' -or $validation.candidate -cne $candidate -or $validation.cases -ne 396 -or $validation.full_posthash_drift -ne 0 -or $validation.observed_typebox_modules -ne 369 -or $validation.source_pid -ne $receipt.pid -or $process.pid -ne $receipt.pid -or $process.status -cne 'passed' -or $process.exit_code -ne 0) { throw 'Actual terminal capture receipt mismatch' }
    if (@($post.manifests | Where-Object { $_.drift.Count -or $_.path_drift.Count }).Count -or @($post.candidate_drift).Count -or @($post.candidate_path_drift).Count -or @($post.compiler_drift).Count -or @($post.compiler_path_drift).Count -or @($post.control_drift).Count -or $post.control_manifest_drift -or @($post.absence_drift).Count -or !$post.expected_still_absent -or $post.absence_contracts -ne 84) { throw 'Historical full posthash drift' }
    $log = Join-Path $Packet "observed-modules-$attempt.jsonl"
    Assert-Hash $log $validation.module_log_sha256
    $modules = @(Get-Content -LiteralPath $log | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object kind -CEQ 'observed-module')
    if ($modules.Count -ne 371 -or @($modules | Where-Object { $_.path -match '[\\/]node_modules[\\/]typebox[\\/]' }).Count -ne 369) { throw 'Observed actual TypeBox graph mismatch' }
    foreach ($module in $modules) {
        if (!$moduleHashes.ContainsKey($module.path) -or $moduleHashes[$module.path] -cne $module.sha256.ToUpperInvariant()) { throw 'Observed module bytes missing from archive' }
    }
    $output = Read-Json "$prefix-output.json"
    if ($output.version -cne '1.3.27' -or $output.packageSha256 -ine $proof.package_sha256 -or $output.inputSha256 -ine $proof.input_sha256 -or $output.closureSha256 -ine $proof.closure_sha256 -or @($output.rows).Count -ne 396) { throw 'Capture authority mismatch' }
    for ($i = 0; $i -lt 396; $i++) { if ($output.rows[$i].name -cne $inventory.cases[$i]) { throw "Probe missing or reordered: $i" } }
    $rowsJson += ConvertTo-Json -InputObject $output.rows -Depth 100 -Compress
}
if ($rowsJson[0] -cne $rowsJson[1]) { throw 'Double capture rows differ' }
[ordered]@{ status = 'saved_source396_proof_verified'; captured_candidate = $candidate; cases = 396; original_payloads = 34; frozen_inventories = 5; observed_original_modules = 371; observed_typebox_modules_per_capture = 369; expected_sha256 = $proof.expected_sha256; historical_full_posthash_drift = 0; native_compiled = $false; native_qualified = $false; full_HOST_GPA = $false; C_malloc_exhaustive = $false } | ConvertTo-Json

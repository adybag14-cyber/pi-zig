#requires -Version 7.0
$ErrorActionPreference='Stop'
$packet=Join-Path $PSScriptRoot 'source15-proof'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
function Json([string]$name){Get-Content -LiteralPath (Join-Path $packet $name) -Raw|ConvertFrom-Json}
function Hash([string]$path,[string]$sha){if((Get-FileHash -LiteralPath $path).Hash -cne $sha.ToUpperInvariant()){throw "Proof hash mismatch: $path"}}
function Archive([string]$name,[object[]]$index){
    $zip=[IO.Compression.ZipFile]::OpenRead((Join-Path $packet $name))
    try{
        if($zip.Entries.Count -ne $index.Count){throw "Archive count mismatch: $name"}
        $seen=@{}
        foreach($row in $index){
            if($seen.ContainsKey($row.entry)){throw 'Duplicate archive index entry'};$seen[$row.entry]=$true
            $entry=$zip.GetEntry($row.entry);if(!$entry){throw 'Missing archived original bytes'}
            $stream=$entry.Open();try{$sha=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream))}finally{$stream.Dispose()}
            if($sha -cne $row.sha256.ToUpperInvariant()){throw "Archive body drift: $($row.entry)"}
        }
    }finally{$zip.Dispose()}
}
$payloads=@(Json 'payloads.sha256.json')
if($payloads.Count -ne 20 -or @(Get-ChildItem -LiteralPath $packet -File).Count -ne 21){throw 'Original Source15 packet incomplete'}
$seen=@{}
foreach($payload in $payloads){
    if($seen.ContainsKey($payload.path) -or [IO.Path]::GetFileName($payload.path) -cne $payload.path){throw 'Invalid proof payload path'}
    $seen[$payload.path]=$true;Hash (Join-Path $packet $payload.path) $payload.sha256
}
$frozen=@(Json 'frozen-inventories.index.json');$modules=@(Json 'observed-modules.index.json')
if($frozen.Count -ne 4 -or $modules.Count -ne 1338){throw 'Archived inventory universe mismatch'}
Archive 'frozen-inventories.zip' $frozen
Archive 'observed-modules.zip' $modules
$name='sdk-async-brand-source-first-20261016'
$validation=Json "$name-validation.json";$process=Json "$name.json";$post=Json "$name-posthash.json";$output=Json "$name-output.json";$inventory=Json 'sdk-async-brand-probe-inventory-20261016.json'
if($validation.status -cne 'genuine_source_capture_qualified' -or $validation.candidate -cne '57b2a460339be829e87d217f01449fabf977349d' -or $validation.cases -ne 15 -or $validation.source_pid -ne 22264 -or $validation.source_exit -ne 0 -or $validation.full_posthash_drift -ne 0 -or $validation.observed_typebox_modules -ne 668 -or !$validation.expected_still_absent -or $validation.native_qualified){throw 'Historical capture qualification mismatch'}
if($process.pid -ne 22264 -or $process.status -cne 'passed' -or $process.exit_code -ne 0 -or !$process.identity_captured){throw 'Actual terminal process receipt mismatch'}
if(@($post.manifests|Where-Object{$_.drift.Count -or $_.path_drift.Count}).Count -or @($post.candidate_drift).Count -or @($post.candidate_path_drift).Count -or @($post.compiler_drift).Count -or @($post.compiler_path_drift).Count -or @($post.control_drift).Count -or $post.control_manifest_drift -or @($post.absence_drift).Count -or $post.absence_contracts -ne 84 -or !$post.expected_still_absent){throw 'Historical full posthash/absence drift'}
if($post.manifests.Count -ne 3 -or $post.manifests[0].files -ne 1970 -or $post.manifests[1].files -ne 31064 -or $post.manifests[2].files -ne 1774 -or $post.compiler_files -ne 19546 -or $post.candidate_files -ne 8454){throw 'Full freeze inventory counts mismatch'}
$sha='D0B06269EC1B29C9C8A679DB3E73305820FB0BD0667C9B288C0961EB4D80D2E5'
if($output.packageVersion -cne '1.3.0' -or $output.packageRootOverride.Replace('\','/').TrimEnd('/') -cne 'C:/Users/adyba/pi-upstream-source-4954d76-20261015/packages/coding-agent'){throw 'Actual current Source package metadata authority mismatch'}
Hash (Join-Path $packet "$name-output.json") $sha
Hash (Join-Path $root 'src/extensions/fixtures/sdk-async-brand-4954.expected.json') $sha
Hash (Join-Path $root 'src/extensions/fixtures/sdk-async-brand-4954.input.mjs') $output.inputSha256
if($validation.output_sha256 -cne $sha -or $output.authority -cne '4954d760504c11df9b2cbdc040346107b6a8153d' -or $output.typeboxVersion -cne '1.3.27' -or $output.typeboxPackageSha256 -cne 'c59ddfd977ce941f1e8ee8b0a0b14396c332fa27cc5fa6fa165227ffd5a3992f' -or $output.cases -ne 15 -or @($output.rows).Count -ne 15 -or $inventory.count -ne 15 -or $inventory.input_sha256 -cne $output.inputSha256){throw 'Actual Source authority/probe identity mismatch'}
for($i=0;$i -lt 15;$i++){if($output.rows[$i].name -cne $inventory.cases[$i]){throw "Actual Source row missing/reordered: $i"}}
if($output.brandAuthority -cne 'actual node:util.types.isAsyncFunction' -or $output.rows[0].value.tag -cne '[object AsyncFunction]' -or $output.rows[0].value.async -ne $false){throw 'Genuine brand authority or prototype-only negative control mismatch'}
$observed=@(Get-Content -LiteralPath (Join-Path $packet 'observed-modules.jsonl')|ForEach-Object{$_|ConvertFrom-Json}|Where-Object kind -eq 'observed-module')
Hash (Join-Path $packet 'observed-modules.jsonl') $validation.module_log_sha256
if($observed.Count -ne 1338 -or @($observed|Where-Object{$_.path -match '[\\/]node_modules[\\/]typebox[\\/]'}).Count -ne 668){throw 'Actual observed TypeBox graph mismatch'}
$moduleHashes=@{};foreach($module in $modules){if($moduleHashes.ContainsKey($module.original_path)){throw 'Duplicate observed module path'};$moduleHashes[$module.original_path]=$module.sha256}
foreach($module in $observed){if(!$moduleHashes.ContainsKey($module.path) -or $moduleHashes[$module.path] -cne $module.sha256.ToUpperInvariant()){throw 'Observed module bytes absent or changed'}}
[ordered]@{status='saved_source15_proof_verified';captured_candidate=$validation.candidate;cases=15;payloads=20;frozen_inventories=4;observed_modules=1338;observed_typebox_modules=668;actual_node_pid=22264;actual_exit=0;historical_full_posthash_drift=0;expected_sha256=$sha;native_compiled=$false;native_qualified=$false;default_selected=$false}|ConvertTo-Json

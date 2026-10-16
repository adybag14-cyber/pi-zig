#requires -Version 7.0
# Saved Source39 proof verifier: original V2 runner/Node terminal0/fullpost0.
# Requires independent Root review of every original physical version.
$ErrorActionPreference='Stop'
$packet=Join-Path $PSScriptRoot 'source39-proof'
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
            if($row.recorded_metadata -and $entry.Length -ne [uint64]$row.recorded_metadata.size){throw 'Archived original physical byte size mismatch'}
            $stream=$entry.Open();try{$sha=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream))}finally{$stream.Dispose()}
            if($sha -cne $row.sha256.ToUpperInvariant()){throw "Archive body drift: $($row.entry)"}
        }
    }finally{$zip.Dispose()}
}
$payloads=@(Json 'payloads.sha256.json')
if($payloads.Count -ne 29 -or @(Get-ChildItem -LiteralPath $packet -File).Count -ne 30){throw 'Original Source39 packet incomplete'}
$seen=@{}
foreach($payload in $payloads){
    if($seen.ContainsKey($payload.path) -or [IO.Path]::GetFileName($payload.path) -cne $payload.path){throw 'Invalid proof payload path'}
    $seen[$payload.path]=$true;Hash (Join-Path $packet $payload.path) $payload.sha256
}
$frozen=@(Json 'frozen-inventories.index.json');$modules=@(Json 'observed-modules.index.json')
$physical=@(Json 'physical-files.index.json');$versions=@(Json 'physical-versions.index.json')
if($frozen.Count -ne 4 -or $modules.Count -ne 1488 -or $physical.Count -ne 36 -or $versions.Count -ne 39){throw 'Archived universe mismatch'}
Archive 'frozen-inventories.zip' $frozen
Archive 'observed-modules.zip' $modules
Archive 'physical-files.zip' $physical
Archive 'physical-versions.zip' $versions
$name='sdk-module-policy-source-first-20261016'
$review=Json 'sdk-module-policy-source-first-20261016-root-review.json';$independent=Json 'sdk-module-policy-source-first-independent-review.json'
$validation=Json "$name-validation.json";$process=Json "$name.json";$post=Json "$name-posthash.json";$output=Json "$name-output.json";$inventory=Json 'sdk-module-policy-probe-inventory-20261016.json'
$sha='0DDCAB7DC649CBA5AC7147C722CE0AB98C9465E9B74290F57CD92C1A1FE89F27'
if($review.status -cne 'root_independently_reviewed_genuine_source39' -or $review.candidate -cne 'c735c1f1b74822f23cca2d79802e27f687ee76e2' -or $review.actual_node_pid -ne 73800 -or $review.actual_node_exit -ne 0 -or $review.wrapper_exit -ne 0 -or $review.original_rows -ne 39 -or $review.row_order_drift -ne 0 -or $review.full_posthash_drift -ne 0 -or !$review.expected_absent_at_review -or $review.native_qualified -or $review.output_sha256 -cne $sha){throw 'Explicit Root acceptance mismatch'}
if($validation.status -cne 'genuine_source_capture_qualified' -or $validation.candidate -cne $review.candidate -or $validation.source_pid -ne 73800 -or $validation.source_exit -ne 0 -or $validation.cases -ne 39 -or $validation.observed_modules -ne 1488 -or $validation.observed_typebox_modules -ne 668 -or @($validation.retained_loaded_physical_versions).Count -ne 8 -or $validation.output_sha256 -cne $sha -or $validation.module_log_sha256 -cne $review.module_log_sha256 -or !$validation.expected_still_absent){throw 'Original positive V2 validation receipt mismatch'}
if($independent.wrapper_exit -ne 0 -or @($independent.row_order_drift).Count -or @($independent.original_write_versions).Count -ne 39 -or @($independent.final_physical_files).Count -ne 36){throw 'Original independent audit mismatch'}
if($process.pid -ne 73800 -or $process.status -cne 'passed' -or $process.exit_code -ne 0 -or !$process.identity_captured -or $process.executable_sha256 -cne '63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088'){throw 'Actual terminal process receipt mismatch'}
$absence=Json 'sdk-module-policy-source-first-node-absence.json'
if($absence.pid -ne 73800 -or $absence.actual_matches -ne 0){throw 'Independent Node absence receipt mismatch'}
$admission=Json 'sdk-module-policy-source-first-manual16GiB-admission.json'
if($admission.status -cne 'manual_fresh16GiB_admitted' -or $admission.required_kib -ne 16777216 -or $admission.free_kib -lt $admission.required_kib){throw 'Fresh16GiB admission missing'}
if(@($post.manifests|Where-Object{$_.drift.Count -or $_.path_drift.Count}).Count -or @($post.candidate_drift).Count -or @($post.candidate_path_drift).Count -or @($post.compiler_drift).Count -or @($post.compiler_path_drift).Count -or @($post.control_drift).Count -or $post.control_manifest_drift -or @($post.absence_drift).Count -or $post.absence_contracts -ne 84 -or !$post.expected_still_absent){throw 'Historical full posthash/absence drift'}
if($post.manifests.Count -ne 3 -or $post.manifests[0].files -ne 1970 -or $post.manifests[1].files -ne 31064 -or $post.manifests[2].files -ne 1774 -or $post.compiler_files -ne 19546 -or $post.candidate_files -ne 8537){throw 'Full freeze inventory counts mismatch'}
Hash (Join-Path $packet "$name-output.json") $sha
Hash (Join-Path $root 'src/extensions/fixtures/sdk-module-policy-4954.expected.json') $sha
Hash (Join-Path $PSScriptRoot 'capture-module-policy-supplement.mjs') $output.driverSha256
if($output.driverSha256.ToUpperInvariant() -cne $inventory.input_sha256.ToUpperInvariant() -or $output.authority -cne '4954d760504c11df9b2cbdc040346107b6a8153d' -or $output.cases -ne 39 -or $output.rows.Count -ne 39 -or $inventory.count -ne 39){throw 'Actual Source/control identity mismatch'}
if($output.packageVersion -cne '1.3.0' -or $output.packageSha256 -cne '83c3bb7619f590c213cc96a24216eb29a819a3ef6dc548607cc037ed276e8dc5' -or $output.packageRootOverride.Replace('\','/') -cne 'C:/Users/adyba/pi-upstream-source-4954d76-20261015/packages/coding-agent' -or $output.typeboxVersion -cne '1.3.27' -or $output.typeboxPackageSha256 -cne 'c59ddfd977ce941f1e8ee8b0a0b14396c332fa27cc5fa6fa165227ffd5a3992f' -or $output.jitiVersion -cne '2.7.0' -or $output.jitiPackageSha256 -cne 'aab8aafc42d9aeec14a6e2fe0e15ea1514c0c205a624055a7e776f2ec456283c'){throw 'Actual package metadata authority mismatch'}

for($i=0;$i -lt 39;$i++){if($output.rows[$i].name -cne $inventory.cases[$i]){throw "Actual Source row missing/reordered: $i"}}
$observed=@(Get-Content -LiteralPath (Join-Path $packet 'observed-modules.jsonl')|ForEach-Object{$_|ConvertFrom-Json}|Where-Object kind -eq 'observed-module')
Hash (Join-Path $packet 'observed-modules.jsonl') $review.module_log_sha256
if($observed.Count -ne 1488 -or @($observed|Where-Object{$_.path -match '[\\/]node_modules[\\/]typebox[\\/]'}).Count -ne 668){throw 'Actual observed module graph mismatch'}
for($i=0;$i -lt 1488;$i++){if($observed[$i].path -cne $modules[$i].original_path -or $observed[$i].sha256.ToUpperInvariant() -cne $modules[$i].sha256){throw 'Original observed module bytes missing/reordered'}}
if(@($modules|Where-Object origin -eq 'original current body').Count -ne 1480 -or @($modules|Where-Object origin -eq 'original retained created physical version').Count -ne 8){throw 'Intentional loaded physical version accounting mismatch'}
for($i=0;$i -lt 39;$i++){
    $row=$output.physical[$i];$version=$versions[$i]
    $bodySha=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($row.bytes)))
    if($row.path -cne $version.original_path -or $row.label -cne $version.label -or $row.sha256.ToUpperInvariant() -cne $bodySha -or $version.sha256 -cne $bodySha -or [Text.Encoding]::UTF8.GetByteCount($row.bytes) -ne [uint64]$row.size){throw 'Original written physical version identity mismatch'}
    foreach($key in @('ino','size','mtimeNs','ctimeNs','birthtimeNs')){if($row.$key -cne $version.recorded_metadata.$key){throw 'Original physical version metadata drift'}}
}
for($i=0;$i -lt 36;$i++){
    $row=$output.physicalFinal[$i];$file=$physical[$i]
    if($row.path -cne $file.original_path -or $row.sha256.ToUpperInvariant() -cne $file.sha256){throw 'Original final physical file identity mismatch'}
    foreach($key in @('ino','size','mtimeNs','ctimeNs','birthtimeNs')){if($row.$key -cne $file.recorded_metadata.$key){throw 'Original final physical metadata drift'}}
}
foreach($version in $validation.retained_loaded_physical_versions){if(@($versions|Where-Object{$_.original_path -ceq $version.path -and $_.sha256 -ceq $version.sha256.ToUpperInvariant() -and $_.label -ceq 'created'}).Count -ne 1){throw 'Root reviewed original loaded version missing'}}
[ordered]@{status='saved_source39_proof_verified';captured_candidate=$review.candidate;cases=39;payloads=29;frozen_inventories=4;observed_modules=1488;observed_typebox_modules=668;physical_versions=39;final_physical_files=36;actual_node_pid=73800;actual_node_exit=0;original_wrapper_exit=0;explicit_root_review=$true;historical_full_posthash_drift=0;expected_sha256=$sha;native_compiled=$false;native_qualified=$false;default_selected=$false}|ConvertTo-Json

#requires -Version 7.0
$ErrorActionPreference='Stop'
$packet=Join-Path $PSScriptRoot 'source44-proof'
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
if($payloads.Count -ne 25 -or @(Get-ChildItem -LiteralPath $packet -File).Count -ne 26){throw 'Original Source44 packet incomplete'}
$seen=@{}
foreach($payload in $payloads){
    if($seen.ContainsKey($payload.path) -or [IO.Path]::GetFileName($payload.path) -cne $payload.path){throw 'Invalid proof payload path'}
    $seen[$payload.path]=$true;Hash (Join-Path $packet $payload.path) $payload.sha256
}
$frozen=@(Json 'frozen-inventories.index.json');$modules=@(Json 'observed-modules.index.json');$physical=@(Json 'actual-physical-files.index.json')
if($frozen.Count -ne 4 -or $modules.Count -ne 719 -or $physical.Count -ne 3){throw 'Archived inventory universe mismatch'}
Archive 'frozen-inventories.zip' $frozen
Archive 'observed-modules.zip' $modules
Archive 'actual-physical-files.zip' $physical
$name='sdk-runtime-helper-source-first-20261016'
$validation=Json "$name-validation.json";$process=Json "$name.json";$post=Json "$name-posthash.json";$output=Json "$name-output.json";$inventory=Json 'sdk-runtime-helper-probe-inventory-20261016.json'
if($validation.status -cne 'genuine_source_capture_qualified' -or $validation.candidate -cne '067ba9cecff114b77312f747d241f2ce6e7147b5' -or $validation.cases -ne 44 -or $validation.source_pid -ne 63940 -or $validation.source_exit -ne 0 -or $validation.full_posthash_drift -ne 0 -or $validation.observed_typebox_modules -ne 668 -or !$validation.expected_still_absent -or $validation.native_qualified){throw 'Historical capture qualification mismatch'}
if($process.pid -ne 63940 -or $process.status -cne 'passed' -or $process.exit_code -ne 0 -or !$process.identity_captured){throw 'Actual terminal process receipt mismatch'}
if(@($post.manifests|Where-Object{$_.drift.Count -or $_.path_drift.Count}).Count -or @($post.candidate_drift).Count -or @($post.candidate_path_drift).Count -or @($post.compiler_drift).Count -or @($post.compiler_path_drift).Count -or @($post.control_drift).Count -or $post.control_manifest_drift -or @($post.absence_drift).Count -or $post.absence_contracts -ne 84 -or !$post.expected_still_absent){throw 'Historical full posthash/absence drift'}
if($post.manifests.Count -ne 3 -or $post.manifests[0].files -ne 1970 -or $post.manifests[1].files -ne 31064 -or $post.manifests[2].files -ne 1774 -or $post.compiler_files -ne 19546 -or $post.candidate_files -ne 8413){throw 'Full freeze inventory counts mismatch'}
$sha='94AEC310834B683D9F70D2F50498C84CFFF03D4EB9E8C5EC18674DC0569663C3'
if($output.packageVersion -cne '1.3.0' -or $output.packageName -cne '@earendil-works/pi-coding-agent' -or $output.packageRootOverride -cne 'C:/Users/adyba/pi-upstream-source-4954d76-20261015/packages/coding-agent/'){throw 'Actual current Source package metadata authority mismatch'}
Hash (Join-Path $packet "$name-output.json") $sha
Hash (Join-Path $root 'src/extensions/fixtures/sdk-runtime-helpers-4954.expected.json') $sha
Hash (Join-Path $root 'src/extensions/fixtures/sdk-runtime-helpers-4954.input.mjs') $output.inputSha256
if($validation.output_sha256 -cne $sha -or $output.authority -cne '4954d760504c11df9b2cbdc040346107b6a8153d' -or $output.typeboxVersion -cne '1.3.27' -or $output.typeboxPackageSha256 -cne 'c59ddfd977ce941f1e8ee8b0a0b14396c332fa27cc5fa6fa165227ffd5a3992f' -or $output.cases -ne 44 -or @($output.rows).Count -ne 44 -or $inventory.count -ne 44 -or $inventory.input_sha256 -cne $output.inputSha256){throw 'Actual Source authority/probe identity mismatch'}
for($i=0;$i -lt 44;$i++){if($output.rows[$i].name -cne $inventory.cases[$i]){throw "Actual Source row missing/reordered: $i"}}
$observed=@(Get-Content -LiteralPath (Join-Path $packet 'observed-modules.jsonl')|ForEach-Object{$_|ConvertFrom-Json}|Where-Object kind -eq 'observed-module')
Hash (Join-Path $packet 'observed-modules.jsonl') $validation.module_log_sha256
if($observed.Count -ne 719 -or @($observed|Where-Object{$_.path -match '[\\/]node_modules[\\/]typebox[\\/]'}).Count -ne 668){throw 'Actual observed TypeBox graph mismatch'}
$moduleHashes=@{};foreach($module in $modules){if($moduleHashes.ContainsKey($module.original_path)){throw 'Duplicate observed module path'};$moduleHashes[$module.original_path]=$module.sha256}
foreach($module in $observed){if(!$moduleHashes.ContainsKey($module.path) -or $moduleHashes[$module.path] -cne $module.sha256.ToUpperInvariant()){throw 'Observed module bytes absent or changed'}}
$physicalValidation=Json "$name-physical-validation.json";$physicalBefore=Json "$name-output.json.physical-before.json";$physicalAfter=Json "$name-output.json.physical-after.json"
Hash (Join-Path $packet "$name-output.json.physical-before.json") $physicalValidation.baseline_sha256
Hash (Join-Path $packet "$name-output.json.physical-after.json") $physicalValidation.after_sha256
if($physicalValidation.status -cne 'actual_physical_fixtures_retained' -or $physicalValidation.files -ne 3 -or @($physicalBefore.inventory).Count -ne 1 -or $physicalBefore.inventory[0].kind -cne 'directory' -or @($physicalAfter.inventory|Where-Object kind -eq 'file').Count -ne 3){throw 'Actual physical baseline/after-state evidence missing'}
foreach($file in @($physicalAfter.inventory|Where-Object kind -eq 'file')){if(@($physical|Where-Object{$_.entry -ceq $file.path -and $_.sha256 -ceq $file.sha256.ToUpperInvariant()}).Count -ne 1 -or !$file.ino -or !$file.mtimeNs -or !$file.ctimeNs -or !$file.birthtimeNs){throw 'Actual physical bytes/metadata evidence mismatch'}}
[ordered]@{status='saved_source44_proof_verified';captured_candidate=$validation.candidate;cases=44;payloads=25;frozen_inventories=4;observed_modules=719;observed_typebox_modules=668;actual_physical_files=3;actual_node_pid=63940;actual_exit=0;historical_full_posthash_drift=0;expected_sha256=$sha;native_compiled=$false;native_qualified=$false;default_selected=$false}|ConvertTo-Json

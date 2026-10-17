$ErrorActionPreference='Stop'
$container='C:\Users\adyba\pi-zig'
$rows=[Collections.Generic.List[object]]::new();$paths=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$blobs=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
function Add-ProofFile([string]$Path,[string]$Role){
 $full=[IO.Path]::GetFullPath($Path);if(!$full.StartsWith($container+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Proof escapes container'}
 if(!$paths.Add($full)){return};$item=Get-Item -LiteralPath $full
 if($item.PSIsContainer-or($item.Attributes-band[IO.FileAttributes]::ReparsePoint)-or$item.Extension-in@('.exe','.pdb')){throw 'Regular non-executable proof file required'}
 $sha=(Get-FileHash -LiteralPath $full).Hash;$member='blobs/'+$sha
 $rows.Add([ordered]@{container_relative_path=$full.Substring($container.Length+1).Replace([char]92,[char]47);original_path=$full;role=$Role;bytes=$item.Length;sha256=$sha;blob_member=$member})
 if(!$blobs.ContainsKey($sha)){$blobs.Add($sha,[ordered]@{member=$member;bytes=$item.Length;sha256=$sha;representative_original_path=$full})}
}
function Add-Run([string]$Parent,[string]$Id,[string]$Role){
 $parentPath=Join-Path $container ('evidence/'+$Parent);$run=Join-Path $parentPath $Id
 foreach($file in Get-ChildItem -LiteralPath $run -File){Add-ProofFile $file.FullName $Role}
 foreach($file in Get-ChildItem -LiteralPath $parentPath -File){
  if($file.Name.StartsWith($Id,[StringComparison]::Ordinal)-or$file.Name-match'^(Run-|Prepare-|README\.md$|prepared(-manifest)?\.json$|selection150\.json$|static-checks\.json$|.*grant\.template\.json$|root-grant\.template\.json$)'){Add-ProofFile $file.FullName ($Role+'; parent control/outer receipt')}
 }
}
$scopes=@(
 @{parent='root-c3-focused34-c83-prepared-20261017';id='root-c3-focused34-c83-20261017-130914';role='CURRENT c83 focused34 raw pass; part of current150'},
 @{parent='graph0-c3-json11-corev4-prepared-20261017';id='root-c3-core116-v4-20261017-125810';role='CURRENT c83 core116 raw pass; part of current150'},
 @{parent='graph0-c3-json11-corev4-prepared-20261017';id='root-c3-json11-20261017-125224';role='Separate c83 JSON11 repeat; NOT added to current150'},
 @{parent='graph0-c3-retained150-v2-prepared-20261017';id='root-c3-core116-20261017-120712';role='HISTORICAL8a negative: foundation6 pass then async26 compile failure'},
 @{parent='graph0-c3-retained150-v2-prepared-20261017';id='root-c3-focused34-20261017-115902';role='HISTORICAL8a focused34 pass; NOT current150 execution'},
 @{parent='graph0-c3-core116-v3-prepared-20261017';id='root-c3-core116-v3-20261017-121714';role='HISTORICALee6 negative: JSONHTTP20 failed before fetch bootstrap'},
 @{parent='root-graph0-c3-native-prepared-20261016';id='root-graph0-c3-20261016-230927';role='HISTORICALC3 v1 negative: queued8 pass, binding compile bool error'},
 @{parent='root-graph0-c3-native-v2-prepared-20261017';id='root-graph0-c3-v2-20261016-234029';role='HISTORICAL8a C3 v2 queued8+binding3 pass; null top-level count preserved, NOT current c83 focused11'}
)
foreach($scope in $scopes){Add-Run $scope.parent $scope.id $scope.role}
foreach($folder in @('c3-current150-independent-async-review-20261017','c3-core116-json11-independent-async-review-20261017','graph0-c3-two-run-independent-async-review-20261017')){foreach($file in Get-ChildItem -LiteralPath (Join-Path $container ('evidence/'+$folder)) -File){Add-ProofFile $file.FullName 'Independent audit or its exact helper/source provenance'}}
$candidate=Join-Path $container 'worktrees/root-graph0-c3-qualification'
$sourceLeaves=@('vendor/quickjs/quickjs.c','vendor/quickjs/quickjs.h','src/extensions/engine.zig','src/extensions/native_async_function.zig','src/extensions/native_async_body.zig','src/extensions/native_extension_dynamic_import_graph0.zig','src/native_dynamic_import_graph0_test.zig','src/native_extension_graph0_binding_test.zig','src/native_extension_graph0_binding_controls.zig','src/extensions/native_worker.zig','src/native_ai_json_parse_test.zig','src/extensions/native_ai_openai_sdk_request.zig','build.zig','tools/ci/native_qualification_ci.ps1','tools/ci/Invoke-NativeTestProtocol.ps1')
$tested=Get-Content -Raw -LiteralPath (Join-Path $container 'evidence/graph0-c3-json11-corev4-prepared-20261017/root-c3-core116-v4-20261017-125810/before.json')|ConvertFrom-Json
foreach($leaf in $sourceLeaves){$file=Join-Path $candidate $leaf;$pin=@($tested.source|Where-Object relative -CEQ $leaf);if($pin.Count-ne1-or(Get-FileHash -LiteralPath $file).Hash-cne$pin[0].sha256){throw 'Current source leaf differs from testedc83'};Add-ProofFile $file 'Exact tested c83 source/control leaf; remainder identified in full source inventories'}
Add-ProofFile (Join-Path $container 'evidence/durable-latest89-full-inspect-53ae-tool-prehash-20261011.json') 'Complete original compiler authority; historical internal paths unchanged'
Add-ProofFile $PSCommandPath 'New reversible content-addressed packaging source'
$readme=@'
# Current c83 C3 regression proof, with original negatives preserved

CURRENT accepted source is c83c8b1364ef92479c83e8d7db8459372f4d7bf1, C DA14DFBB7E73DED032E9FCD742FD2E49FDAF45273F48D24D6089018539601614 and H A79E75A40D34C9E7CAFB9AB31359B7EE925FE205636603F2022CF764CFC18346. The current focused34 run130914 and core116 run125810 independently report every original selected metadata entry and every ordered start/result with flags0, full source10658/compiler19546/control seals, exact installed artifacts and terminal owner absence. Their recorded source/compiler rows are identical. Independent acceptance2EECCCB4... combines only these two CURRENT-head runs.

The current union is150 execution entries across98 unique full names:134 named occurrences representing96 unique named tests,15 executions of storage test_0, and one Engine anonymous test. Imported Engine/JSON/async-generator names also repeat. Neither150 unique tests nor a sum with the separate JSON replay is claimed. The earlier same-head JSON11 replay is included as repeated execution evidence; it contributes no additional current150 selection. Accepted core auditE2ED2827... and current union acceptance2EECCCB4... are retained with their exact audit source.

Historical proof scopes remain separate and all original bytes remain unchanged. Included negatives are original8a core async26 compilation failure after foundation6 passed; ee6 JSONHTTP20 failure before actual fetch bootstrap; and original C3 binding compilation bool error after queued8 passed. Historical8a focused34 and C3 queued8+binding3 passes are context only, not re-described as c83 executions. The original focused-v2 actual_metadata_total:null is preserved; its independent audit derives8+3=11 from raw metadata/results. Current-c83 focused11 is a SEPARATE future gate and is not established by this packet.

Compact archive layout: path-list.json records EVERY original logical proof path, original absolute path, role, byte length, SHA256 and blob_member. Each unique original byte content is stored ONCE at blobs/<SHA256>. Multiple full-seal or empty-stream paths can reference one blob without losing any original bytes or identities. Reconstruct an original file by reading its listed blob bytes; do not reinterpret or rewrite historical paths inside JSON/logs. member-manifest.json inventories all unique blobs and control members. This is content deduplication only, not receipt normalization or omission of duplicate logical paths. package-verification.json confirms every ZIP member's decompression hash and every path-to-blob length/hash mapping.

The raw payload contains all direct files of the eight listed original run directories, their parent drivers/grants/manifests and matching outer receipts, independent audits, original compiler authority, and tested source/control leaves. Out/cache directories are intentionally not recursively copied. All readable full seals and raw protocol/stdout/stderr files in those run directories are represented. Root's unrelated source and runtime dependencies are not consumed by this packaging.

EXCLUDED: installed executable/PDB payloads, all compiler-cache contents and compiler binaries. They remain local only, identified by original artifact/tool manifests, and are NOT durably stored by this ZIP. No binary/debugger reproduction claim is made. The fifteen included source/control leaves match the tested c83 inventory; complete source inventories identify all other files, but this is not an entire source checkout. Publication of a matching source checkpoint and any Main intake are Root's separate actions.

Scope is current C3 regression evidence. It is not full SDK/default application/Graph2/runtime-restoration acceptance, complete TypeBox396 parity, exhaustive C-malloc qualification, or a release. Generator-GPA/recovery stderr is preserved, including explicit coverage limitations; flags remain0. No test/build/Node/native job or Main edit is performed by this audit/package. The packet is PREPARED for publication; creation is not a publication claim.
'@
$readmePath=Join-Path $PSScriptRoot 'README.md';if(Test-Path -LiteralPath $readmePath){throw 'Existing prepared package refused'}
$readme|Set-Content -LiteralPath $readmePath -Encoding utf8NoBOM
$pathList=[ordered]@{schema=1;status='prepared_not_publication';created_utc=[DateTimeOffset]::UtcNow.ToString('o');current_head=$tested.candidate_head;scopes=$scopes;logical_file_count=$rows.Count;files=$rows.ToArray()}
$pathListPath=Join-Path $PSScriptRoot 'path-list.json';ConvertTo-Json -InputObject $pathList -Depth 16|Set-Content -LiteralPath $pathListPath -Encoding utf8NoBOM
$controls=@([ordered]@{member='README.md';path=$readmePath;bytes=(Get-Item -LiteralPath $readmePath).Length;sha256=(Get-FileHash -LiteralPath $readmePath).Hash},[ordered]@{member='path-list.json';path=$pathListPath;bytes=(Get-Item -LiteralPath $pathListPath).Length;sha256=(Get-FileHash -LiteralPath $pathListPath).Hash})
$manifest=[ordered]@{schema=1;layout='content-addressed raw blobs plus complete original-path mapping';logical_file_count=$rows.Count;unique_blob_count=$blobs.Count;control_members=$controls;blobs=@($blobs.Values|Sort-Object member);excluded=@('Executable/PDB payloads','Mutable compiler caches','Compiler payloads');published=$false}
$manifestPath=Join-Path $PSScriptRoot 'member-manifest.json';ConvertTo-Json -InputObject $manifest -Depth 12|Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM
$zipPath=Join-Path $PSScriptRoot 'raw-proof.zip';$stream=[IO.File]::Open($zipPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
try{$zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$true);try{foreach($blob in $blobs.Values){[IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,$blob.representative_original_path,$blob.member,[IO.Compression.CompressionLevel]::Optimal)|Out-Null};foreach($control in $controls){[IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,$control.path,$control.member,[IO.Compression.CompressionLevel]::Optimal)|Out-Null};[IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,$manifestPath,'member-manifest.json',[IO.Compression.CompressionLevel]::Optimal)|Out-Null}finally{$zip.Dispose()}}finally{$stream.Dispose()}
$verification=@();$zip=[IO.Compression.ZipFile]::OpenRead($zipPath)
try{
 if($zip.Entries.Count-ne$blobs.Count+3){throw 'ZIP member count differs'}
 $checks=@($blobs.Values)+@($controls)+@([ordered]@{member='member-manifest.json';bytes=(Get-Item -LiteralPath $manifestPath).Length;sha256=(Get-FileHash -LiteralPath $manifestPath).Hash})
 foreach($item in $checks){$entry=$zip.GetEntry($item.member);if(!$entry-or$entry.Length-ne$item.bytes){throw 'ZIP member missing/length mismatch'};$input=$entry.Open();try{$hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($input))}finally{$input.Dispose()};if($hash-cne$item.sha256){throw 'Decompression hash mismatch'};$verification+=,[ordered]@{member=$item.member;bytes=$entry.Length;sha256=$hash;match=$true}}
 foreach($row in $rows){$blob=$blobs[$row.sha256];if(!$blob-or$blob.member-cne$row.blob_member-or$blob.bytes-ne$row.bytes){throw 'Logical proof mapping mismatch'}}
}finally{$zip.Dispose()}
$receipt=[ordered]@{status='passed';zip_bytes=(Get-Item -LiteralPath $zipPath).Length;zip_sha256=(Get-FileHash -LiteralPath $zipPath).Hash;path_list_sha256=(Get-FileHash -LiteralPath $pathListPath).Hash;member_manifest_sha256=(Get-FileHash -LiteralPath $manifestPath).Hash;logical_paths=$rows.Count;unique_blobs=$blobs.Count;zip_members=$verification.Count;decompression_hash_drift=0;logical_mapping_drift=0;verified=$verification;published=$false;new_jobs=0}
ConvertTo-Json -InputObject $receipt -Depth 12|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'package-verification.json') -Encoding utf8NoBOM
[pscustomobject]$receipt|Select-Object status,zip_bytes,zip_sha256,path_list_sha256,member_manifest_sha256,logical_paths,unique_blobs,zip_members,decompression_hash_drift,logical_mapping_drift|ConvertTo-Json

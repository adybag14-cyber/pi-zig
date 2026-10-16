$ErrorActionPreference='Stop'
$container='C:\Users\adyba\pi-zig'
$v1=Join-Path $container 'evidence\root-retry698-native-prepared-20261016'
$v2=Join-Path $container 'evidence\root-retry698-native-v2-prepared-20261016'
$v1run=Join-Path $v1 'root-native-retry160-20261016-222744'
$v2run=Join-Path $v2 'root-native-retry160-v2-20261016-225410'
$candidate=Join-Path $container 'worktrees\root-retry698-qualification'
$members=[Collections.Generic.List[object]]::new()
function AddFile([string]$Path,[string]$Role){
 $full=[IO.Path]::GetFullPath($Path)
 if(!$full.StartsWith($container+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Package input escapes container'}
 $item=Get-Item -LiteralPath $full
 if($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Package input is not regular file'}
 $relative=$full.Substring($container.Length+1).Replace('\','/')
 if(@($members|Where-Object member -CEQ $relative).Count){throw 'Duplicate member'}
 $members.Add([ordered]@{member=$relative;original_path=$full;role=$Role;bytes=$item.Length;sha256=(Get-FileHash -LiteralPath $full).Hash})
}
foreach($dir in @($v1,$v2,$v1run,$v2run)){
 foreach($file in Get-ChildItem -LiteralPath $dir -File){AddFile $file.FullName 'unchanged original control or raw execution receipt'}
}
foreach($dir in @('root-retry698-negative-independent-async-review-20261016','root-retry698-positive-independent-async-review-20261016')){
 foreach($file in Get-ChildItem -LiteralPath (Join-Path $container "evidence\$dir") -File){AddFile $file.FullName 'independent audit, preserves original observations'}
}
foreach($relative in @('src/native_upstream_698a_retry_test.zig','src/extensions/fixtures/upstream-698a-retry-source160.json','src/extensions/fixtures/upstream-698a-retry-source160.input.mjs','src/extensions/native_ai_error_classification.zig','src/ai/retry.zig','src/durable/backend/json.zig','tools/ci/native_qualification_ci.ps1','tools/ci/Invoke-NativeTestProtocol.ps1')){AddFile (Join-Path $candidate $relative) 'exact tested source leaf or canonical owner/protocol'}
AddFile (Join-Path $container 'evidence\durable-latest89-full-inspect-53ae-tool-prehash-20261011.json') 'original complete compiler authority manifest; paths remain historical'
$readme=@'
# Retry698 native component proof

This packet preserves the original failed v1 execution and the subsequent successful v2 execution, including complete recorded source/compiler seals, raw metadata and runtime streams, owner identities and absences, grants, drivers, original negative audit A9D9D501..., v2 source review FF5BAB56..., and independent positive acceptance 038BF3DE.... Original files are included byte for byte at their container-relative member paths; historical paths inside receipts are unchanged.

V1 b44c9b34... compiled executable870E2DBA..., queried three actual tests, then panicked at index0 before classification on a direct JSON integer union access. No v1 test completion or later test execution is claimed. Root's narrow e6478ec3 correction uses checked asInteger without altering160 expected cases; its patch is preserved.

V2 d72194c600abd19da9a125ec0d3a1969656a27e2 freshly compiled executableAE3D937BF9B142DD72239FA56DC8C46D11BCF0C45A81AC19357AF6B68230889B using only the two explicitly disposable v1 compiler caches. All three actual metadata entries ran: complete genuine Source160 VM comparison, typed36 comparison, and imported storage test_0. Raw results show all three ordered starts/results with zero flags, terminal exit0, empty runtime stderr, complete saved source10637/compiler19546 phase seals with no drift, matching artifacts, and owner absence. Acceptance is limited to this exact retry component. It establishes no full SDK, latest Models, whole-application, TypeBox, or runtime-restoration qualification.

Executable and PDB payloads for both runs, compiler caches, and compiler binaries are EXCLUDED. They remain local at the original out/bin and cache paths; the artifact receipts and protected-prior manifest retain their hashes and locations. These excluded payloads are not durably stored by this ZIP. No binary or debugger reproduction claim is made. The complete compiler inventory is included as authority metadata. No raw profile/cache payloads are copied. Original Source160 capture provenance remains separately published; its exact accepted JSON and caller are included here.

member-manifest.json inventories every payload member by size and SHA256. The ZIP additionally includes this manifest; package-verification.json records a complete streamed decompression/hash verification. ZIP timestamps are packaging metadata, not execution times. No original proof, driver, grant, or fixture is rewritten.
'@
$readmePath=Join-Path $PSScriptRoot 'README.md'
if(Test-Path -LiteralPath $readmePath){throw 'Refuse existing package README'}
$readme|Set-Content -LiteralPath $readmePath -Encoding utf8NoBOM
AddFile $readmePath 'new package scope and exclusions'
AddFile $PSCommandPath 'new reversible packaging source'
$manifest=[ordered]@{schema=1;status='prepared_public_proof_not_publication_claim';created_utc=[DateTimeOffset]::UtcNow.ToString('o');scope='exact retry component d72194c6; v1 negative preserved';payload_count=$members.Count;excluded=@('Both original out/bin/test.exe payloads','Both original out/bin/test.pdb payloads','Both disposable compiler cache directories','Compiler executable/library payloads');members=$members.ToArray()}
$manifestPath=Join-Path $PSScriptRoot 'member-manifest.json'
if(Test-Path -LiteralPath $manifestPath){throw 'Refuse existing manifest'}
ConvertTo-Json -InputObject $manifest -Depth 12|Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM
$zipPath=Join-Path $PSScriptRoot 'raw-proof.zip'
$stream=[IO.File]::Open($zipPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
try{
 $zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$true)
 try{
  foreach($row in $members){[IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,$row.original_path,$row.member,[IO.Compression.CompressionLevel]::Optimal)|Out-Null}
  [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,$manifestPath,'member-manifest.json',[IO.Compression.CompressionLevel]::Optimal)|Out-Null
 }finally{$zip.Dispose()}
}finally{$stream.Dispose()}
$verification=@()
$zip=[IO.Compression.ZipFile]::OpenRead($zipPath)
try{
 if($zip.Entries.Count -ne $members.Count+1){throw 'ZIP count mismatch'}
 foreach($row in @($members.ToArray())+@([ordered]@{member='member-manifest.json';sha256=(Get-FileHash -LiteralPath $manifestPath).Hash;bytes=(Get-Item -LiteralPath $manifestPath).Length})){
  $entry=$zip.GetEntry($row.member);if(!$entry -or $entry.Length -ne $row.bytes){throw 'ZIP missing/length mismatch'}
  $input=$entry.Open();try{$hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($input))}finally{$input.Dispose()}
  if($hash -cne $row.sha256){throw 'ZIP decompression hash mismatch'}
  $verification+=,[ordered]@{member=$row.member;bytes=$entry.Length;sha256=$hash;match=$true}
 }
}finally{$zip.Dispose()}
$receipt=[ordered]@{status='passed';zip_sha256=(Get-FileHash -LiteralPath $zipPath).Hash;zip_bytes=(Get-Item -LiteralPath $zipPath).Length;manifest_sha256=(Get-FileHash -LiteralPath $manifestPath).Hash;payload_count=$members.Count;zip_count=$verification.Count;decompression_hash_drift=0;verified=$verification;published=$false;new_native_or_node_jobs=0}
ConvertTo-Json -InputObject $receipt -Depth 10|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'package-verification.json') -Encoding utf8NoBOM
$receipt|Select-Object status,zip_sha256,zip_bytes,manifest_sha256,payload_count,zip_count,decompression_hash_drift|ConvertTo-Json

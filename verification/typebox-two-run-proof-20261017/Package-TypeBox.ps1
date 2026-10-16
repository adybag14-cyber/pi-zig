$ErrorActionPreference='Stop'
$container='C:\Users\adyba\pi-zig'
$members=[Collections.Generic.List[object]]::new()
function Add-ProofFile([string]$Path,[string]$Role){
 $full=[IO.Path]::GetFullPath($Path);if(!$full.StartsWith($container+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Input escapes container'}
 $item=Get-Item -LiteralPath $full;if($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Regular file required'}
 $name=$full.Substring($container.Length+1).Replace('\','/')
 if(@($members|Where-Object member -CEQ $name).Count){return}
 $members.Add([ordered]@{member=$name;original_path=$full;role=$Role;bytes=$item.Length;sha256=(Get-FileHash -LiteralPath $full).Hash})
}
foreach($folder in @('root-typebox-component-first38a8-20261016','root-typebox-component-second1f9-20261017')){
 $run=Join-Path $container "evidence\$folder"
 foreach($file in Get-ChildItem -LiteralPath $run -File){Add-ProofFile $file.FullName 'original raw execution receipt, unchanged'}
 $before=Get-Content -Raw -LiteralPath "$run\before.json"|ConvertFrom-Json
 foreach($control in $before.controls){if((Get-FileHash -LiteralPath $control.path).Hash -cne $control.sha256){throw 'Recorded control drift'};Add-ProofFile $control.path 'exact original control or compiler authority'}
}
foreach($folder in @('root-typebox-component-prepared-20261016','root-typebox-component-v2-prepared-20261017','root-typebox-component-v2-independent-async-review-20261017','typebox-two-run-independent-async-review-20261017')){
 foreach($file in Get-ChildItem -LiteralPath (Join-Path $container "evidence\$folder") -File){Add-ProofFile $file.FullName 'prepared controls or independent source/raw-proof review'}
}
$candidate=Join-Path $container 'worktrees\root-typebox-qualification'
foreach($relative in @('src/native_typebox_compile_production_test.zig','src/extensions/native_typebox_compile_ir.zig','src/extensions/native_typebox_operators_production.zig','src/extensions/engine.zig','vendor/quickjs/quickjs.c','vendor/quickjs/quickjs.h','src/extensions/fixtures/typebox-compile-production.input.mjs','src/extensions/fixtures/typebox-compile-production.json','src/extensions/fixtures/ai-model-schemas-partial-4954.input.mjs','src/extensions/fixtures/ai-model-schemas-partial-4954.json','src/extensions/fixtures/typebox-operators-production.input.txt','src/extensions/fixtures/typebox-operators-production.expected.json')){Add-ProofFile (Join-Path $candidate $relative) 'exact second-run source/fixture leaf; full candidate inventory is preserved separately'}
$readme=@'
# TypeBox component two-run raw proof

Both original native executions remain FAILED overall. This packet preserves original bytes, control/grant records, complete saved inventories, raw metadata/runtime streams, and the independent review of the successor and both executions. It is prepared for publication; creation is not proof of publication.

First run: exact38a8e606c159a8e918142b4e1b5210c4af707ac8, executableE6B13E703F04B6176CE3F34FB6890A71ADD65A44F0B4462A29C217828BF7661D. Actual four test result flags1,0,1,0: Source80 and Source396 failed; Source52 and storage passed. The successor changes only the narrowly reviewed raw[] IR fallback, producing a fresh owned VM array after captured-node precedence. First-run outputs and receipts remain immutable.

Second run: exact1f9eee9e5e5672167f70b032beaa167a5a99556a, executableE2E091FCADDBC9192143E634F235483CC957DC727073D2E046E0D9729B450927. Actual four result flags0,0,1,0: complete Source80, complete Source52, and storage passed. Source396 reports one mismatch at index391, generic-default-instantiation-limit-recovery. Expected Error/Type instantiation is excessively deep and possibly infinite with assign129/create792; actual RangeError/Maximum call stack size exceeded with assign28/create186. The recovered literal matches. There is no Source396 completion marker and no full TypeBox pass. The runtime process's exit0 does not override protocol failure.

Independent audit568A4BC1... checks raw metadata and ordered start/result frames, complete source10631/tree10631/vendor1336/compiler19546/control9 inventories across seven later phase/final seals per run, original compiler authority, owners/deadlines/absence, current installed executable/PDB hashes, matching current cache executable identity, PE16MiB reserve, and unchanged Engine1MiB default. Dynamic frame size is not measured here. Root's old E6/PDB frame investigation is a SEPARATE compiled authority and is not packaged or extended to the successor. Compiler caches are explicitly mutable disposable build state; only the current matching cache executable is bound between phases. Old installed artifacts remain separate and unchanged.

Executable/PDB payloads, compiler payloads, cache contents, and the separate old frame/PDB measurement packet are EXCLUDED. Artifact receipts retain their exact hashes and local paths. Excluded binary/PDB/cache payloads are retained locally and are not durably stored by this ZIP; no binary/debugger reproduction claim is made. Original fixture/golden bytes and narrow tested source leaves are included, with complete source inventories identifying the remainder. Historical paths inside original JSON/logs remain unchanged.

Scope: exact component observations only. No full TypeBox, full SDK/latest Models, whole Pi application, GPA, exhaustive C allocation, dynamic-frame, runtime-restoration, or deployment qualification is established. No native/compiler/Node job was launched by this audit/package. Main was not edited. The manifest inventories every payload; the archive additionally contains that manifest. Every member is decompressed and SHA256 checked before a package verification receipt is issued.
'@
$readmePath=Join-Path $PSScriptRoot 'README.md';if(Test-Path -LiteralPath $readmePath){throw 'Existing package refused'}
$readme|Set-Content -LiteralPath $readmePath -Encoding utf8NoBOM
Add-ProofFile $readmePath 'new package scope/exclusions'
Add-ProofFile $PSCommandPath 'new packaging source'
$manifest=[ordered]@{schema=1;created_utc=[DateTimeOffset]::UtcNow.ToString('o');status='prepared_public_proof_not_publication';scope='two genuine failed TypeBox component runs; scoped second-run80/52/storage passes and remaining396negative';payload_count=$members.Count;excluded=@('Both installed executable/PDB payloads','Compiler payloads','Mutable compiler cache contents','Separate old E6/PDB frame measurement packet');members=$members.ToArray()}
$manifestPath=Join-Path $PSScriptRoot 'member-manifest.json'
ConvertTo-Json -InputObject $manifest -Depth 12|Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM
$zipPath=Join-Path $PSScriptRoot 'raw-proof.zip'
$stream=[IO.File]::Open($zipPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
try{$zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$true);try{foreach($row in $members){[IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,$row.original_path,$row.member,[IO.Compression.CompressionLevel]::Optimal)|Out-Null};[IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,$manifestPath,'member-manifest.json',[IO.Compression.CompressionLevel]::Optimal)|Out-Null}finally{$zip.Dispose()}}finally{$stream.Dispose()}
$verified=@();$zip=[IO.Compression.ZipFile]::OpenRead($zipPath)
try{
 if($zip.Entries.Count -ne $members.Count+1){throw 'ZIP count mismatch'}
 foreach($row in @($members.ToArray())+@([ordered]@{member='member-manifest.json';bytes=(Get-Item -LiteralPath $manifestPath).Length;sha256=(Get-FileHash -LiteralPath $manifestPath).Hash})){
  $entry=$zip.GetEntry($row.member);if(!$entry -or $entry.Length -ne $row.bytes){throw 'Missing/length mismatch'}
  $input=$entry.Open();try{$hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($input))}finally{$input.Dispose()}
  if($hash -cne $row.sha256){throw 'Decompression hash mismatch'}
  $verified+=,[ordered]@{member=$row.member;bytes=$entry.Length;sha256=$hash;match=$true}
 }
}finally{$zip.Dispose()}
$receipt=[ordered]@{status='passed';zip_bytes=(Get-Item -LiteralPath $zipPath).Length;zip_sha256=(Get-FileHash -LiteralPath $zipPath).Hash;manifest_sha256=(Get-FileHash -LiteralPath $manifestPath).Hash;payload_count=$members.Count;zip_count=$verified.Count;decompression_hash_drift=0;verified=$verified;published=$false;new_native_or_node_jobs=0}
ConvertTo-Json -InputObject $receipt -Depth 10|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'package-verification.json') -Encoding utf8NoBOM
[pscustomobject]$receipt|Select-Object status,zip_bytes,zip_sha256,manifest_sha256,payload_count,zip_count,decompression_hash_drift|ConvertTo-Json

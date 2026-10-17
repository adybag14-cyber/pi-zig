$ErrorActionPreference='Stop'
$container='C:\Users\adyba\pi-zig'
$run=Join-Path $container 'evidence/root-typebox-stack-diagnostic-08bd-v4-20261017-143801'
$parent=Join-Path $container 'evidence/typebox-stack-diagnostic-driver-prepared-20261017'
$id=Split-Path $run -Leaf
function Hash($p){(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash}
function ReadJson($p){Get-Content -Raw -LiteralPath $p|ConvertFrom-Json -Depth 64}
$before=ReadJson "$run/before.json"
$readinessPath=Join-Path $container 'evidence/typebox-stack-observer-08bd-capacity-source-prepared-20261017/source-readiness.json'
$readiness=ReadJson $readinessPath
if($readiness.head-cne$before.candidate_head){throw 'Actual source readiness/head mismatch'}
if(Test-Path -LiteralPath (Join-Path $PSScriptRoot 'raw-proof.zip')){throw 'Fresh archive required; preserve any prior archive'}
$paths=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach($file in Get-ChildItem -LiteralPath $run -File){[void]$paths.Add($file.FullName)}
foreach($file in Get-ChildItem -LiteralPath $parent -File|Where-Object{$_.Name-like"$id-*"}){[void]$paths.Add($file.FullName)}
foreach($row in $before.controls){
 if($row.path-match '\.pi-zig-workspace\.json$'-or$row.path-match '^C:\\Program Files\\'){continue}
 if((Hash $row.path)-cne$row.sha256){throw 'Immutable driver/control source drift'}
 [void]$paths.Add($row.path)
}
foreach($dir in @('root-typebox-08bd-matching-symbols-20261017','root-typebox-08bd-trace-analysis-20261017','typebox-stack-observer-08bd-capacity-source-prepared-20261017','typebox-stack-observer-e0e-source-prepared-20261017')){foreach($file in Get-ChildItem -LiteralPath (Join-Path $container ('evidence/'+$dir)) -File){[void]$paths.Add($file.FullName)}}
$correlation=Join-Path $container 'evidence/root-typebox-08bd-independent-correlation-20261017.json';[void]$paths.Add($correlation)
foreach($row in (ReadJson $correlation).inputs){$p=Join-Path (Join-Path $container 'evidence') $row.path;if($p-match '\\functional-installed\\bin\\test\.(exe|pdb)$'){continue};if((Hash $p)-cne$row.sha256){throw 'Original Min source/input drift'};[void]$paths.Add($p)}
# Preserve exact LLVM owner's distinct historical helper bytes, not a newer
# shared owner substituted for its executed78DE helper.
foreach($row in (ReadJson (Join-Path $container 'evidence/root-typebox-08bd-matching-symbols-20261017/before.json'))){if($row.path-like'*.ps1'){if((Hash $row.path)-cne$row.sha256){throw 'Original LLVM helper source drift'};[void]$paths.Add($row.path)}}
foreach($name in @('audit.json','README.md','path-list.json')){$p=Join-Path (Join-Path $container 'evidence/typebox-e0-v3-independent-async-audit-20261017') $name;[void]$paths.Add($p)}
$sourceRows=@($readiness.source_files)
foreach($relative in @('vendor/quickjs/quickjs.c','vendor/quickjs/quickjs.h')){$sourceRows+=@($before.source|Where-Object relative -CEQ $relative)}
$sourceRows+=@($before.source|Where-Object{$_.relative-match '^src/extensions/fixtures/typebox-.*(input|expected|production\.json)'})
$snapshots=@(foreach($source in $sourceRows|Sort-Object relative -Unique){
 $original=Join-Path 'C:\Users\adyba\pi-zig\worktrees\typebox-stack-observer' $source.relative
 if((Hash $original)-cne$source.sha256){throw 'Exact08bd source/fixture changed before capture'}
 $snapshot=Join-Path (Join-Path $PSScriptRoot 'source') $source.relative
 $directory=Split-Path $snapshot -Parent
 if(!(Test-Path -LiteralPath $directory)){New-Item -ItemType Directory -Path $directory -Force|Out-Null}
 if(Test-Path -LiteralPath $snapshot){throw 'Fresh source snapshot required'}
 Copy-Item -LiteralPath $original -Destination $snapshot -ErrorAction Stop
 if((Hash $snapshot)-cne$source.sha256){throw 'Byte-preserved source snapshot mismatch'}
 [void]$paths.Add($snapshot)
 [pscustomobject]@{original_path=$original;snapshot=$snapshot.Substring($PSScriptRoot.Length+1).Replace([char]92,[char]47);bytes=(Get-Item -LiteralPath $snapshot).Length;sha256=$source.sha256}
})
ConvertTo-Json -InputObject ([ordered]@{executed_candidate=$before.candidate_head;intake_base='c852223b2591059fccad3e746c31751365c368e0';files=$snapshots}) -Depth 8|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'source-manifest.json') -Encoding utf8NoBOM
$local=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
foreach($group in @('controls','functional')){
 $artifact=ReadJson "$run/$group-final-artifacts.json"
 foreach($entry in @($artifact.installed)+@($artifact.cached_executables)){$local[$entry.path]=[pscustomobject]@{path=$entry.path;sha256=$entry.sha256;bytes=(Get-Item -LiteralPath $entry.path).Length;publication_payload_included=$false;retained_locally=$true;needed_for='Retained artifact/symbol/cache identity and future exact proof review; no retirement authorized'}}
}
ConvertTo-Json -InputObject ([ordered]@{status='excluded_local_artifact_payloads_retained';files=@($local.Values|Sort-Object path);additional_exclusions=@('All mutable compiler/global cache payloads','19546-file compiler payloads','System PowerShell/LLVM executables','Current mutable workspace layout');deletion_authorized=$false}) -Depth 8|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'local-needed-ledger.json') -Encoding utf8NoBOM
foreach($name in @('Audit-08bd.ps1','audit.json','Check-SourceBinding.ps1','source-binding-addendum.json','Package-08bd.ps1','README.md','source-manifest.json','local-needed-ledger.json')){[void]$paths.Add((Join-Path $PSScriptRoot $name))}
$prefix=$container+'\'
$rows=@(foreach($path in $paths|Sort-Object -CaseSensitive){
 if(!$path.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Source/evidence path escaped container'}
 $item=Get-Item -LiteralPath $path -ErrorAction Stop
 if($item.PSIsContainer-or($item.Attributes-band[IO.FileAttributes]::ReparsePoint)-or$path-match '\.(exe|pdb)$'){throw 'Only regular nonexecutable source/evidence payloads allowed'}
 $hash=Hash $path
 [pscustomobject]@{original_path=$path;relative=$path.Substring($prefix.Length).Replace([char]92,[char]47);bytes=$item.Length;sha256=$hash;member='content/'+$hash.ToLowerInvariant()+'.bin'}
})
$members=@($rows|Group-Object sha256|ForEach-Object{$entry=$_.Group[0];[pscustomobject]@{member=$entry.member;bytes=$entry.bytes;sha256=$entry.sha256;original_paths=@($_.Group.original_path)}}|Sort-Object member)
$list=[ordered]@{status='exact_raw_publication_pathlist';executed_candidate=$before.candidate_head;intake_base='c852223b2591059fccad3e746c31751365c368e0';scope='Complete instrumented diagnostic trace; control10 pass; functional0/0/1/0 negative';files=$rows;logical_raw_bytes=($rows|Measure-Object bytes -Sum).Sum;unique_raw_bytes=($members|Measure-Object bytes -Sum).Sum;original_execution_identity_rewritten=$false}
ConvertTo-Json -InputObject $list -Depth 8|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'path-list.json') -Encoding utf8NoBOM
ConvertTo-Json -InputObject ([ordered]@{format='content-addressed exact original bytes';members=$members}) -Depth 8|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'member-manifest.json') -Encoding utf8NoBOM
$zipPath=Join-Path $PSScriptRoot 'raw-proof.zip'
$output=[IO.File]::Open($zipPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
$zip=[IO.Compression.ZipArchive]::new($output,[IO.Compression.ZipArchiveMode]::Create,$false)
try{
 foreach($member in $members){
  $source=$member.original_paths[0]
  if((Hash $source)-cne$member.sha256){throw 'Original content changed before packaging'}
  $entry=$zip.CreateEntry($member.member,[IO.Compression.CompressionLevel]::Optimal)
  $input=[IO.File]::OpenRead($source);$destination=$entry.Open()
  try{$input.CopyTo($destination,1048576)}finally{$destination.Dispose();$input.Dispose()}
 }
 foreach($name in @('README.md','path-list.json','member-manifest.json')){
  $entry=$zip.CreateEntry($name,[IO.Compression.CompressionLevel]::Optimal);$input=[IO.File]::OpenRead((Join-Path $PSScriptRoot $name));$destination=$entry.Open()
  try{$input.CopyTo($destination,1048576)}finally{$destination.Dispose();$input.Dispose()}
 }
}finally{$zip.Dispose();$output.Dispose()}
$inputZip=[IO.Compression.ZipFile]::OpenRead($zipPath)
$verified=@();$buffer=[byte[]]::new(1048576)
try{
 if($inputZip.Entries.Count-ne$members.Count+3){throw 'Unexpected ZIP member inventory'}
 foreach($member in $members){
  $entry=$inputZip.GetEntry($member.member);if($null-eq$entry-or$entry.Length-ne$member.bytes){throw 'ZIP member missing/length mismatch'}
  $stream=$entry.Open();$hasher=[Security.Cryptography.IncrementalHash]::CreateHash([Security.Cryptography.HashAlgorithmName]::SHA256)
  try{while(($count=$stream.Read($buffer,0,$buffer.Length))-gt0){$hasher.AppendData($buffer,0,$count)};$digest=[Convert]::ToHexString($hasher.GetHashAndReset())}finally{$hasher.Dispose();$stream.Dispose()}
  if($digest-cne$member.sha256){throw 'Decompressed content hash mismatch'}
  foreach($original in $member.original_paths){if((Hash $original)-cne$member.sha256){throw 'Original source/evidence drift after packaging'}}
  $verified+=,[pscustomobject]@{member=$member.member;bytes=$member.bytes;sha256=$digest}
 }
 foreach($name in @('README.md','path-list.json','member-manifest.json')){
  $entry=$inputZip.GetEntry($name);$stream=$entry.Open();$hasher=[Security.Cryptography.IncrementalHash]::CreateHash([Security.Cryptography.HashAlgorithmName]::SHA256)
  try{while(($count=$stream.Read($buffer,0,$buffer.Length))-gt0){$hasher.AppendData($buffer,0,$count)};$digest=[Convert]::ToHexString($hasher.GetHashAndReset())}finally{$hasher.Dispose();$stream.Dispose()}
  if($digest-cne(Hash (Join-Path $PSScriptRoot $name))){throw 'Decompressed direct manifest mismatch'}
 }
}finally{$inputZip.Dispose()}
$verification=[ordered]@{status='streaming_archive_all_members_decompression_verified';archive='raw-proof.zip';archive_bytes=(Get-Item -LiteralPath $zipPath).Length;archive_sha256=Hash $zipPath;logical_original_files=$rows.Count;unique_content_members=$members.Count;total_zip_members=$members.Count+3;logical_raw_bytes=$list.logical_raw_bytes;unique_raw_bytes=$list.unique_raw_bytes;path_list_sha256=Hash (Join-Path $PSScriptRoot 'path-list.json');member_manifest_sha256=Hash (Join-Path $PSScriptRoot 'member-manifest.json');decompressed_members=$verified;original_mapping_hash_drift=0;payload_executable_PDB_cache_included=$false;new_compiler_LLVM_AST_Node_native_jobs=0;uploaded=$false}
ConvertTo-Json -InputObject $verification -Depth 8|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'package-verification.json') -Encoding utf8NoBOM
[pscustomobject]@{status=$verification.status;files=$rows.Count;members=$members.Count;zip_bytes=$verification.archive_bytes;zip_sha256=$verification.archive_sha256;pathlist_sha256=$verification.path_list_sha256;member_manifest_sha256=$verification.member_manifest_sha256;verification_sha256=Hash (Join-Path $PSScriptRoot 'package-verification.json')}|ConvertTo-Json

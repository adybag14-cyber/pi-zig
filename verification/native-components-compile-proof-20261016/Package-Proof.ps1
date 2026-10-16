$ErrorActionPreference='Stop'
$base='C:\Users\adyba\pi-zig\evidence'
$archive=Join-Path $PSScriptRoot 'raw-proof.zip'
$manifestPath=Join-Path $PSScriptRoot 'member-manifest.json'
$verificationPath=Join-Path $PSScriptRoot 'package-verification.json'
foreach($output in @($archive,$manifestPath,$verificationPath)){if(Test-Path -LiteralPath $output){throw 'Refuse existing package output'}}
$packets=@('root-components-compile-20261016','root-components-compile-v2-20261016','root-components-compile-v3-20261016','root-components-compile-v4-20261016')
$members=[Collections.Generic.List[object]]::new()
$names=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
function Add-Member([string]$Source,[string]$Member,[string]$Role){
 $file=Get-Item -LiteralPath $Source
 if($file.PSIsContainer -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Nonregular proof input'}
 if($Member -match '(^|/)(out|bin|cache|\.zig-cache|zig-out)(/|$)' -or $Member -match '\.(exe|pdb|dll|o|obj|lib|a)$' -or $Member.Contains('..') -or $Member.Contains('\') -or !$names.Add($Member)){throw 'Forbidden/duplicate archive member'}
 if($file.Extension -notin @('.json','.ps1','.log','.bin') -or ($file.Extension -eq '.bin' -and !$file.Name.EndsWith('.stdout.bin'))){throw 'Unexpected raw proof file kind'}
 $members.Add([ordered]@{member=$Member;original_path=$file.FullName;bytes=$file.Length;sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash;role=$Role})
}
foreach($packet in $packets){
 $dir=Join-Path $base $packet
 foreach($file in Get-ChildItem -LiteralPath $dir -File -Force){Add-Member $file.FullName ($packet+'/'+$file.Name) 'original_top_level_raw_packet'}
}
if($members.Count -ne 61){throw 'Expected exact61 raw top-level files'}
$reviewDir=Join-Path $base 'root-components-compile-independent-auth-20261016'
$copyDir=Join-Path $PSScriptRoot 'independent-review';if(Test-Path -LiteralPath $copyDir){throw 'Refuse copied review overwrite'}
New-Item -ItemType Directory -Path $copyDir|Out-Null
foreach($name in @('review.json','review-supplement.json','Review-Components.ps1','Review-Supplement.ps1')){
 $source=Join-Path $reviewDir $name;$copy=Join-Path $copyDir $name
 Copy-Item -LiteralPath $source -Destination $copy
 if((Get-FileHash -LiteralPath $source).Hash -cne (Get-FileHash -LiteralPath $copy).Hash){throw 'Independent review copy mismatch'}
 Add-Member $source ('independent-review/'+$name) 'byte_exact_independent_review_copy'
}
if((Get-FileHash -LiteralPath (Join-Path $copyDir 'review.json')).Hash -cne '3A6445E64181D7CCAD022472DADA0436CC33DEB2CF4FC0BE6D2E12B1099386CC' -or (Get-FileHash -LiteralPath (Join-Path $copyDir 'review-supplement.json')).Hash -cne '1E000C7A0F9109C727351D79AD2A205F06B5562239D672ECEAF16023BD6DCBAE'){throw 'Accepted review identity differs'}
$ordered=@($members|Sort-Object member -CaseSensitive)
$zipStream=[IO.File]::Open($archive,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
try{
 $zip=[IO.Compression.ZipArchive]::new($zipStream,[IO.Compression.ZipArchiveMode]::Create,$true)
 try{
  foreach($member in $ordered){
   $entry=$zip.CreateEntry($member.member,[IO.Compression.CompressionLevel]::Optimal)
   $input=[IO.File]::OpenRead($member.original_path);try{$target=$entry.Open();try{$input.CopyTo($target)}finally{$target.Dispose()}}finally{$input.Dispose()}
  }
 }finally{$zip.Dispose()}
}finally{$zipStream.Dispose()}
$zipHash=(Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash
$verified=@();$zip=[IO.Compression.ZipFile]::OpenRead($archive)
try{
 if($zip.Entries.Count -ne 65){throw 'Archive member count differs'}
 foreach($member in $ordered){
  $entry=$zip.GetEntry($member.member);if($null -eq $entry -or $entry.Length -ne $member.bytes){throw 'Archive entry missing/length differs'}
  $stream=$entry.Open();try{$hasher=[Security.Cryptography.SHA256]::Create();try{$hash=[Convert]::ToHexString($hasher.ComputeHash($stream))}finally{$hasher.Dispose()}}finally{$stream.Dispose()}
  if($hash -cne $member.sha256){throw 'Decompressed member SHA mismatch'}
  $verified+=@{member=$member.member;bytes=$entry.Length;compressed_bytes=$entry.CompressedLength;sha256=$hash;decompressed_sha256_match=$true}
 }
}finally{$zip.Dispose()}
foreach($member in $ordered){if((Get-Item -LiteralPath $member.original_path).Length -ne $member.bytes -or (Get-FileHash -Algorithm SHA256 -LiteralPath $member.original_path).Hash -cne $member.sha256){throw 'Original proof changed during packaging'}}
foreach($packet in $packets){$now=@(Get-ChildItem -LiteralPath (Join-Path $base $packet) -File -Force|ForEach-Object{$packet+'/'+$_.Name});$expected=@($ordered|Where-Object{$_.member.StartsWith($packet+'/')}|ForEach-Object member);if(@(Compare-Object $now $expected -CaseSensitive).Count){throw 'Top-level packet inventory changed'}}
$manifest=[ordered]@{status='prepared_byte_exact_component_compile_metadata_proof';scope='Mixed-head compilation and metadata only;29entries25named+4storage;zero runtime tests';archive='raw-proof.zip';archive_sha256=$zipHash;archive_bytes=(Get-Item -LiteralPath $archive).Length;members_count=65;original_packet_top_level_members=61;independent_review_members=4;members=$ordered;excluded='All nested out/bin/executables/PDB/DLL/objects/caches; local binaries are not saved or moved'}
$manifest|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM
$verification=[ordered]@{status='passed_all_members_decompressed_sha256_and_original_postcheck';prepared_utc=[DateTimeOffset]::UtcNow.ToString('o');archive_sha256=$zipHash;manifest_sha256=(Get-FileHash -LiteralPath $manifestPath).Hash;members_verified=$verified.Count;decompressed_bytes=($verified|Measure-Object bytes -Sum).Sum;sha_mismatches=0;length_mismatches=0;original_source_posthash_drift=0;original_top_level_inventory_drift=0;runtime_tests_executed=0;compiler_jobs=0;node_jobs=0;product_edits=0;Main_edits=0;publication_status='prepared_only_Root_Main_intake_pending';members=$verified;package_file_seals=@(@('README.md','Package-Proof.ps1','member-manifest.json')+@('independent-review/review.json','independent-review/review-supplement.json','independent-review/Review-Components.ps1','independent-review/Review-Supplement.ps1')|ForEach-Object{@{path=$_;sha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $_)).Hash}})}
$verification|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $verificationPath -Encoding utf8NoBOM
@{status=$verification.status;archive_sha256=$zipHash;archive_bytes=$manifest.archive_bytes;manifest_sha256=$verification.manifest_sha256;verification_sha256=(Get-FileHash -LiteralPath $verificationPath).Hash;members=65;decompressed_bytes=$verification.decompressed_bytes;runtime_tests_executed=0}|ConvertTo-Json -Compress

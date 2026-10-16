$ErrorActionPreference='Stop'
$run='C:/Users/adyba/pi-zig/evidence/retry698a-runtime-free-captures/root-source160-81ec-watch-20261016-220726'
$journal=$run+'.launcher';$runId=Split-Path -Leaf $run
$audit='C:/Users/adyba/pi-zig/evidence/source160-independent-async-review-20261016'
$watch='C:/Users/adyba/pi-zig/evidence/root-source160-grants-20261016'
$manifest=Get-Content -LiteralPath "$run/external-artifact-manifest.json" -Raw|ConvertFrom-Json
$config=Get-Content -LiteralPath "$run/capture-config.json" -Raw|ConvertFrom-Json
$files=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
function Add-Member([string]$Entry,[string]$Source,[string]$Kind,[string]$ExpectedHash){
 if($Entry.Contains('..') -or $Entry.StartsWith('/') -or $Entry.Contains('\')){throw 'Unsafe ZIP entry'}
 if($files.ContainsKey($Entry)){throw 'Duplicate ZIP entry'}
 $item=Get-Item -LiteralPath $Source
 if($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Only regular proof files may be packaged'}
 $hash=(Get-FileHash -LiteralPath $Source).Hash
 if($ExpectedHash -and $hash -cne $ExpectedHash){throw 'Original manifested proof changed'}
 $files.Add($Entry,@{entry=$Entry;source_path=$item.FullName;bytes=$item.Length;sha256=$hash;kind=$Kind;byte_identical_original=$true})
}
foreach($row in $manifest.rows){
 $full=[IO.Path]::GetFullPath($row.path)
 if($full.StartsWith([IO.Path]::GetFullPath($journal)+'\',[StringComparison]::OrdinalIgnoreCase)){$entry='launcher/'+[IO.Path]::GetRelativePath($journal,$full).Replace('\','/')}
 elseif($full.StartsWith([IO.Path]::GetFullPath($run)+'\',[StringComparison]::OrdinalIgnoreCase)){$entry='run/'+[IO.Path]::GetRelativePath($run,$full).Replace('\','/')}
 else{throw 'Original artifact member escapes exact run/journal'}
 Add-Member $entry $full 'original_external_manifest_member' $row.sha256
}
if($files.Count -ne 152){throw 'All original152 manifested files required'}
foreach($name in @('external-artifact-manifest.json','external-handoff.json')){Add-Member ('run/'+$name) (Join-Path $run $name) 'terminal_file_created_after_original_snapshot' $null}
foreach($name in @('Wait-ApproveSource160.ps1',($runId+'.json'),($runId+'-approver.json'),($runId+'-approver-terminal.json'))){Add-Member ('watcher/'+$name) (Join-Path $watch $name) 'original_Root_watcher_provenance' $null}
foreach($name in @('acceptance.json','addendum.json','Audit-Source160.ps1')){Add-Member ('independent-audit/'+$name) (Join-Path $audit $name) 'independent_audit' $null}
foreach($row in $config.module_files){Add-Member ('observed-modules/'+[IO.Path]::GetFileName($row.path)) $row.path 'exact_observed_module_input_copy' $row.sha256}
Add-Member 'README.md' (Join-Path $PSScriptRoot 'README.md') 'publication_scope' $null
Add-Member 'Package-Source160.ps1' $PSCommandPath 'packaging_source' $null
$record=[ordered]@{schema=1;kind='genuine_runtime_free_Source160_raw_proof_publication_packet';candidate_head=$config.candidate_head;source_head=$config.source_head;cases=160;original_manifest_members=152;complete_run_and_launcher_included=$true;watcher_files=4;observed_module_input_copies=4;profile_binary_included_only_because_original_manifest_member=$true;excluded_unmanifested_binaries_caches_profiles=$true;expected_created=$false;native_replay_executed=$false;runtime_recovery_claimed=$false;global_hold_lifted=$false;published=$false;self_entry='member-manifest.json';self_excluded_from_member_list_to_avoid_hash_cycle=$true;members=@($files.Values|Sort-Object entry -CaseSensitive);prepared_utc=[DateTimeOffset]::UtcNow.ToString('o')}
$manifestPath=Join-Path $PSScriptRoot 'member-manifest.json';if(Test-Path -LiteralPath $manifestPath){throw 'Refuse member manifest overwrite'}
$record|ConvertTo-Json -Depth 7|Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM
Add-Type -AssemblyName System.IO.Compression
$zipPath=Join-Path $PSScriptRoot 'raw-proof.zip'
$stream=[IO.File]::Open($zipPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
$zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$false)
try{
 foreach($row in @($record.members)+@(@{entry='member-manifest.json';source_path=$manifestPath})){
  $entry=$zip.CreateEntry($row.entry,[IO.Compression.CompressionLevel]::Optimal)
  $source=[IO.File]::OpenRead($row.source_path);$output=$entry.Open()
  try{$source.CopyTo($output)}finally{$output.Dispose();$source.Dispose()}
 }
}finally{$zip.Dispose();$stream.Dispose()}
$verify=[IO.Compression.ZipFile]::OpenRead($zipPath)
$count=0
try{
 if($verify.Entries.Count -ne $record.members.Count+1){throw 'ZIP member count mismatch'}
 foreach($row in @($record.members)+@(@{entry='member-manifest.json';sha256=(Get-FileHash -LiteralPath $manifestPath).Hash;bytes=(Get-Item -LiteralPath $manifestPath).Length})){
  $entry=$verify.GetEntry($row.entry);if(!$entry -or $entry.Length -ne $row.bytes){throw 'ZIP missing/truncated member'}
  $input=$entry.Open();try{$hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($input))}finally{$input.Dispose()}
  if($hash -cne $row.sha256){throw 'Decompressed member hash mismatch'}
  $count++
 }
}finally{$verify.Dispose()}
$verification=[ordered]@{status='passed';zip_sha256=(Get-FileHash -LiteralPath $zipPath).Hash;zip_bytes=(Get-Item -LiteralPath $zipPath).Length;member_manifest_sha256=(Get-FileHash -LiteralPath $manifestPath).Hash;decompressed_members_verified=$count;member_drift=0;original_manifest_members=152;acceptance_sha256=(Get-FileHash -LiteralPath (Join-Path $audit 'acceptance.json')).Hash;addendum_sha256=(Get-FileHash -LiteralPath (Join-Path $audit 'addendum.json')).Hash;original_files_modified=$false;new_jobs_launched=$false;published=$false;verified_utc=[DateTimeOffset]::UtcNow.ToString('o')}
$verification|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'package-verification.json') -Encoding utf8NoBOM
$verification|ConvertTo-Json

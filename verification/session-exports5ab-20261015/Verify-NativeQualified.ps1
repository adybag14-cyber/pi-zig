$ErrorActionPreference='Stop'
$qualification=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'native-qualification.json') -Raw|ConvertFrom-Json
if($qualification.status -cne 'qualified_windows_ordinary_session_exports_and_bash' -or $qualification.qualified_code_head -cne '671e2285ee8cd2a5c7dc9c657249b2e01313018e' -or $qualification.total_tests_passed -ne 12 -or $qualification.all_digest_and_recorded_inventory_drift -ne 0){throw 'Qualification identity failed'}
$manifest=@(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'native-raw-artifact-manifest.json') -Raw|ConvertFrom-Json)
$zipPath=Join-Path $PSScriptRoot $qualification.raw_archive
if((Get-FileHash -LiteralPath $zipPath).Hash -cne $qualification.raw_archive_sha256){throw 'Native archive digest failed'}
$zip=[IO.Compression.ZipFile]::OpenRead($zipPath)
try{
 $files=@($zip.Entries|Where-Object{!$_.FullName.EndsWith('/') -and !$_.FullName.EndsWith('\')})
 if($files.Count -ne $manifest.Count -or $manifest.Count -ne 135){throw 'Native archive inventory failed'}
 foreach($row in $manifest){
  $entry=@($files|Where-Object{$_.FullName.Replace('\','/') -ceq ('native-raw/'+$row.path)})
  if($entry.Count -ne 1 -or $entry[0].Length -ne $row.bytes){throw "Native archive path/size failed: $($row.path)"}
  $stream=$entry[0].Open();try{$hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream))}finally{$stream.Dispose()}
  if($hash -cne $row.sha256){throw "Native archive file digest failed: $($row.path)"}
 }
 function Read-ArchivedJson([string]$name){$entry=@($files|Where-Object{$_.FullName.Replace('\','/') -ceq ('native-raw/'+$name)});if($entry.Count -ne 1){throw "Missing archived JSON $name"};$reader=[IO.StreamReader]::new($entry[0].Open(),[Text.Encoding]::UTF8);try{$reader.ReadToEnd()|ConvertFrom-Json}finally{$reader.Dispose()}}
 foreach($phase in @('compile-third','runtime-second')){
  $post=Read-ArchivedJson "ordinary-session-exports5ab-native-$phase-20261015-posthash.json"
  if($post.status -cne 'passed' -or $post.candidate_head -cne $qualification.qualified_code_head -or $post.native_source -ne 5756 -or $post.original -ne 1967 -or $post.dependencies -ne 31064 -or $post.node_tools -ne 1774 -or $post.compiler_files -ne 19546 -or $post.shell_tools -ne 368){throw "Terminal full-freeze identity failed: $phase"}
  foreach($key in @('native_drift','native_inventory_drift','original_drift','original_inventory_drift','dependency_drift','node_tool_drift','compiler_drift','control_drift','shell_tool_drift','shell_inventory_drift')){if($post.$key -ne 0){throw "Terminal input drift: $phase/$key"}}
 }
 $audit=Read-ArchivedJson 'ordinary-session-exports5ab-native-git-blob-audit-20261015.json'
 if($audit.status -cne 'all_frozen_inputs_match_exact_git_blobs' -or $audit.files -ne 5756 -or $audit.candidate -cne $qualification.qualified_code_head -or !$audit.owned_pid_absent){throw 'Exact Git blob audit failed'}
 $html=@($manifest|Where-Object{$_.path.EndsWith('/export.html')})
 if($html.Count -ne 1 -or $html[0].bytes -ne 274284 -or $html[0].sha256 -cne $qualification.html_sha256){throw 'Actual native HTML identity failed'}
}finally{$zip.Dispose()}
$repoRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
foreach($pair in @(@('sdk-session-exports5ab-source.json','source20_expected_sha256'),@('sdk-session-exports5ab-more-source.json','source22_expected_sha256'),@('sdk-session-exports5ab-source-session.input.txt','genuine_persistent_input_sha256'))){$path=Join-Path $repoRoot ('src/extensions/fixtures/'+$pair[0]);if((Get-FileHash -LiteralPath $path).Hash -cne $qualification.($pair[1])){throw "Genuine fixture changed: $($pair[0])"}}
[pscustomobject]@{status='OFFLINE_NATIVE_SESSION_EXPORTS_PROOF_VERIFIED';qualified_code=$qualification.qualified_code_head;archive_files=$manifest.Count;tests=12;source_cases=42;html_bytes=274284;full_constructor_qualified=$false;full_pi_qualified=$false;public_activation=$false}|ConvertTo-Json

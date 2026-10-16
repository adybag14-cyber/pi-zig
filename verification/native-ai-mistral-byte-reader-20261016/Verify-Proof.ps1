param([Parameter(Mandatory)][string]$Archive)
$ErrorActionPreference='Stop'
$taskZip=[IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $Archive))
try{
 $taskReader=[IO.StreamReader]::new($taskZip.GetEntry('archive-manifest.json').Open())
 try{$taskManifest=$taskReader.ReadToEnd()|ConvertFrom-Json}finally{$taskReader.Dispose()}
 foreach($taskPayload in $taskManifest.payloads){
  $taskEntry=$taskZip.GetEntry($taskPayload.entry)
  if(!$taskEntry-or$taskEntry.Length-ne$taskPayload.length){throw "Entry mismatch: $($taskPayload.entry)"}
  $taskStream=$taskEntry.Open()
  try{$taskHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($taskStream))}finally{$taskStream.Dispose()}
  if($taskHash-cne$taskPayload.sha256){throw "Payload drift: $($taskPayload.entry)"}
 }
 [ordered]@{status='passed';archive_sha256=(Get-FileHash -LiteralPath $Archive).Hash;candidate=$taskManifest.candidate;outcome=$taskManifest.outcome;payloads=$taskManifest.payloads.Count;entries=$taskZip.Entries.Count;full_source30_qualified=$false;full_source20_qualified=$false;public_activation=$false}|ConvertTo-Json
}finally{$taskZip.Dispose()}

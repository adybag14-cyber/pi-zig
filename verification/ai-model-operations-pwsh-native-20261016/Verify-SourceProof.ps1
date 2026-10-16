#requires -Version 7.0
param([string]$ArchivePath=(Join-Path (Split-Path $PSScriptRoot -Parent) 'ai-model-operations-4954-20261015/source88-proof.zip'),[string]$ExpectedFixturePath)
$ErrorActionPreference='Stop'
function Hash-Bytes([byte[]]$Bytes){$algorithm=[Security.Cryptography.SHA256]::Create();try{return [BitConverter]::ToString($algorithm.ComputeHash($Bytes)).Replace('-','')}finally{$algorithm.Dispose()}}
function Read-ZipBytes($Entry){$taskStream=$Entry.Open();$buffer=[IO.MemoryStream]::new();try{$taskStream.CopyTo($buffer);return ,$buffer.ToArray()}finally{$taskStream.Dispose();$buffer.Dispose()}}
$archiveBytes=[IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $ArchivePath).Path)
if((Hash-Bytes $archiveBytes) -cne '155DF89C7AAB8FCF8C6DDB2A8369ACE5E3BE33D710076CBC38A5305BF0B72821'){throw 'Original Source88 archive digest mismatch'}
$stream=[IO.MemoryStream]::new($archiveBytes,$false)
$archive=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Read,$false)
try {
 $entries=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
 foreach($entry in $archive.Entries){$name=$entry.FullName;if(!$name-or$name.StartsWith('/')-or$name.Contains('\')-or$name.Contains(':')-or@($name.Split('/')|Where-Object{$_ -in @('','..','.')}).Count){throw 'Unsafe archive entry'};if(!$entries.TryAdd($name,$entry)){throw 'Duplicate archive entry'}}
 if($entries.Count -ne 55){throw 'Exact original archive55 entries required'}
 $manifestBytes=Read-ZipBytes $entries['proof-manifest.json']
 if((Hash-Bytes $manifestBytes) -cne '58859EDE5DC668BB41E863619AA6093AC970A0419F2E15E164211538CBD55E42'){throw 'Original proof manifest changed'}
 $manifest=@([Text.Encoding]::UTF8.GetString($manifestBytes)|ConvertFrom-Json -AsHashtable)
 if($manifest.Count -ne 54){throw 'Exact original54 payloads required'}
 $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
 foreach($row in $manifest){if(!$seen.Add($row.relative)-or!$entries.ContainsKey($row.relative)){throw 'Manifest entry missing/duplicated'};$bytes=Read-ZipBytes $entries[$row.relative];if($bytes.Length -ne $row.bytes-or(Hash-Bytes $bytes) -cne $row.sha256){throw "Original payload hash mismatch: $($row.relative)"}}
 if($seen.Count+1 -ne $entries.Count){throw 'Unmanifested archive entry'}
 function Read-Record([string]$Name){[Text.Encoding]::UTF8.GetString((Read-ZipBytes $entries[$Name]))|ConvertFrom-Json -AsHashtable}
 $prefix='ai-model-operations-4954-source-first-20261015'
 $outputBytes=Read-ZipBytes $entries["$prefix-output.json"]
 if((Hash-Bytes $outputBytes) -cne '99244517F5B7A85811380EE6BE2D587D962402F16ADF94D341F1F287DEAD6AE0'){throw 'Original Source golden changed'}
 if($ExpectedFixturePath-and(Hash-Bytes ([IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $ExpectedFixturePath).Path))) -cne (Hash-Bytes $outputBytes)){throw 'Live expected is not the original Source golden'}
 $document=Read-Record "$prefix-output.json"
 if($document.sourceHead -cne '4954d760504c11df9b2cbdc040346107b6a8153d'-or$document.cases -ne 88-or$document.rows.Count -ne 88-or!$document.canonicalModelsErrorIdentity){throw 'Genuine original88/class identity missing'}
 if(@($document.rows|ForEach-Object name|Sort-Object -Unique).Count -ne 88){throw 'Duplicate original cases'}
 $rawBytes=Read-ZipBytes $entries["$prefix-output.json.raw-diagnostics.json"]
 if((Hash-Bytes $rawBytes) -cne 'C2583EEFFBDC88796A9149C7692C6A158A3FDA36934DBE0B69855FD9920C9320'){throw 'Raw diagnostics changed'}
 $raw=Read-Record "$prefix-output.json.raw-diagnostics.json"
 if(@($raw.diagnostics|Where-Object kind -ceq 'raw-sentinel').Count -ne 20-or@($raw.diagnostics|Where-Object kind -ceq 'vm-error').Count -ne 8-or@($raw.diagnostics|Where-Object kind -ceq 'ModelsError').Count -ne 4){throw 'Complete raw diagnostic corpus required'}
 $owner=Read-Record "$prefix-owner.json"
 if($owner.status -cne 'passed'-or$owner.exit_code -ne 0-or$owner.pid -ne 56660-or!$owner.retained_handle-or!$owner.raw_initial_command_line){throw 'Original successful exact owner missing'}
 $pre=Read-Record "$prefix-prehash.json";$post=Read-Record "$prefix-posthash.json"
 foreach($pair in @{candidate=7685;source=1970;dependencies=31064;node=1774;compiler=19546;controls=13}.GetEnumerator()){if($pre.sets[$pair.Key].Count -ne $pair.Value){throw 'Original full inventory changed'}}
 foreach($row in $post.manifests){if($row.drift -ne 0){throw 'Original frozen-file drift'}}
 foreach($key in $post.Keys){if($key.EndsWith('_drift')-and$post[$key]){throw "Original inventory drift: $key"}}
 if($post.unexpected_candidate_untracked_paths.Count){throw 'Unexpected original candidate paths'}
 $audit=Read-Record 'independent-source-audit.json'
 if($audit.status -cne 'passed_original_source88_native_unrun'-or$audit.unexpected_outcomes.Count-or$audit.native_compilation_performed-or$audit.native_replay_performed){throw 'Original proof scope changed'}
 [ordered]@{status='passed';verifier='PowerShell7/.NET only';source_cases=88;archive_entries=55;payloads=54;original_archive_unchanged=$true;python_executed=$false;native_qualification_claimed=$false}
} finally {$archive.Dispose();$stream.Dispose()}

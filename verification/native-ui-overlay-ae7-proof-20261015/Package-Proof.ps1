param(
 [string]$Repository='C:/Users/adyba/pi-zig-ui-overlay-ae7-20261015',
 [string]$Evidence='C:/Users/adyba/pi-zig-update-evidence-20261003',
 [string]$Source='C:/Users/adyba/pi-upstream-source-ae7b16d-20261015'
)
$ErrorActionPreference='Stop'
$qualified='039f31088beaa1f42252bcd6f1df1ac67c5a53f8'
$baseline='56d51c4f84867941e2966df98d11ac3af6795394'
$payloadRoot=Join-Path $PSScriptRoot 'payloads'
$origins=[Collections.Generic.List[object]]::new()
function Bytes-Sha([byte[]]$Bytes){
 $sha=[Security.Cryptography.SHA256]::Create()
 try{return [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-','')}finally{$sha.Dispose()}
}
function Git-Bytes([string[]]$Arguments){
 $start=[Diagnostics.ProcessStartInfo]::new()
 $start.FileName='git';$start.WorkingDirectory=$Repository;$start.UseShellExecute=$false;$start.CreateNoWindow=$true
 $start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
 foreach($argument in $Arguments){$start.ArgumentList.Add($argument)}
 $process=[Diagnostics.Process]::new();$process.StartInfo=$start
 if(!$process.Start()){throw 'Cannot read local git object'}
 $stream=[IO.MemoryStream]::new()
 try{
  $process.StandardOutput.BaseStream.CopyTo($stream)
  $errorText=$process.StandardError.ReadToEnd();$process.WaitForExit()
  if($process.ExitCode -ne 0){throw "Git object read failed: $errorText"}
  return ,$stream.ToArray()
 }finally{$stream.Dispose();$process.Dispose()}
}
function Store-Bytes([byte[]]$Bytes,[string]$Relative,[string]$Origin,[string]$Expected=''){
 $target=Join-Path $payloadRoot $Relative
 [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))|Out-Null
 $actual=Bytes-Sha $Bytes
 if($Expected -and $actual -cne $Expected.ToUpperInvariant()){throw "Payload identity mismatch: $Origin"}
 if(Test-Path -LiteralPath $target){
  if((Get-FileHash -LiteralPath $target).Hash -cne $actual){throw "Conflicting archive target $Relative"}
 }else{[IO.File]::WriteAllBytes($target,$Bytes)}
 $origins.Add([ordered]@{path=('payloads/'+$Relative.Replace('\','/'));origin=$Origin;bytes=$Bytes.Length;sha256=$actual})
 return $actual
}
function Copy-Payload([string]$Path,[string]$Relative,[string]$Expected=''){
 return Store-Bytes ([IO.File]::ReadAllBytes($Path)) $Relative $Path $Expected
}
foreach($file in Get-ChildItem -LiteralPath $Evidence -File -Filter 'ui-overlay-ae7*'){
 Copy-Payload $file.FullName ('evidence/'+$file.Name)|Out-Null
}
foreach($name in @(
 'sourceae7-modules-55332-0-20261015.jsonl',
 'sourceae7-full-manifest-20261015.json',
 'sourceae7-runtime-manifest-20261015.json',
 'sourceae7-node-tools-before-20261015.json',
 'sourceae7-dependency-contract-audit-20261015.json',
 'sourceae7-preparation-controls-20261015.json',
 'sourceae7-preparation-readiness-20261015.json',
 'sourceae7-observe-20261015.mjs',
 'durable-latest89-full-inspect-53ae-tool-prehash-20261011.json',
 'Invoke-OwnedEeSourceJob-20261012.ps1'
)){
 Copy-Payload (Join-Path $Evidence $name) ('references/'+$name)|Out-Null
}
$frozenSource=@(Get-Content -Raw -LiteralPath (Join-Path $Evidence 'sourceae7-full-manifest-20261015.json')|ConvertFrom-Json)
foreach($relative in @('LICENSE','package.json','package-lock.json','packages/coding-agent/package.json','packages/tui/package.json','packages/coding-agent/src/modes/interactive/interactive-mode.ts','packages/tui/src/tui.ts')){
 $path=Join-Path $Source $relative
 $pin=@($frozenSource|Where-Object{[IO.Path]::GetFullPath($_.path) -ieq [IO.Path]::GetFullPath($path)})
 if($pin.Count -ne 1){throw "Primary Source file absent from full frozen inventory: $relative"}
 Copy-Payload $path ('original-source/'+$relative) $pin[0].sha256|Out-Null
}
# Retain every actual control version, including historical runner bytes.
$controls=@(Get-ChildItem -LiteralPath $Evidence -File -Filter 'ui-overlay-ae7*-controls-before.json')+
          @(Get-Item -LiteralPath (Join-Path $Evidence 'ui-overlay-ae7-source12-first-20261015-extra-before.json'))
$seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach($manifest in $controls){
 foreach($pin in @(Get-Content -Raw -LiteralPath $manifest.FullName|ConvertFrom-Json)){
  if(!$seen.Add($pin.sha256)){continue}
  $bytes=$null;$origin=$pin.path
  if((Test-Path -LiteralPath $pin.path -PathType Leaf) -and (Get-FileHash -LiteralPath $pin.path).Hash -ceq $pin.sha256){
   $bytes=[IO.File]::ReadAllBytes($pin.path)
  }else{
   $root=[IO.Path]::GetFullPath($Repository).TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
   $path=[IO.Path]::GetFullPath($pin.path)
   if(!$path.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)){throw "Historical external control not recoverable: $path"}
   $relative=$path.Substring($root.Length).Replace('\','/')
   $commits=[Text.Encoding]::UTF8.GetString((Git-Bytes @('rev-list',$qualified,'--',$relative))) -split '\r?\n'
   foreach($commit in $commits|Where-Object{$_}){
    $candidate=Git-Bytes @('cat-file','blob',($commit+':'+$relative))
    if((Bytes-Sha $candidate) -ceq $pin.sha256){$bytes=$candidate;$origin='git:'+ $commit+':'+$relative;break}
   }
   if($null -eq $bytes){throw "Historical control SHA not found in local git: $($pin.path)"}
  }
  Store-Bytes $bytes ('controls/'+$pin.sha256.ToLowerInvariant()+'/'+[IO.Path]::GetFileName($pin.path)) $origin $pin.sha256|Out-Null
 }
}
Store-Bytes (Git-Bytes @('diff','--binary','--full-index',$baseline,$qualified,'--')) 'qualified-code.patch' ('git diff '+$baseline+'..'+$qualified)|Out-Null
Store-Bytes (Git-Bytes @('diff','--name-only','d04dbecd983c26d277215b7089a969867c49f9c1',$qualified,'--')) 'unit-to-final-paths.txt' 'git diff d04dbecd..039f3108 --name-only'|Out-Null
$origins|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'payload-origins.json') -Encoding utf8NoBOM
$files=@(Get-ChildItem -LiteralPath $PSScriptRoot -Recurse -Force -File|Where-Object{$_.Name -notin @('proof-manifest.json','proof-manifest.sha256')}|Sort-Object FullName|ForEach-Object{
 [ordered]@{path=[IO.Path]::GetRelativePath($PSScriptRoot,$_.FullName).Replace('\','/');bytes=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}
})
[ordered]@{schema_version=1;qualified_candidate=$qualified;unit_candidate='d04dbecd983c26d277215b7089a969867c49f9c1';payload_files=$files.Count;files=$files}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'proof-manifest.json') -Encoding utf8NoBOM
((Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'proof-manifest.json')).Hash+'  proof-manifest.json')|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'proof-manifest.sha256') -Encoding ascii
$totalBytes=0L
foreach($file in $files){$totalBytes+=[long]$file['bytes']}
[ordered]@{status='packaged_without_source_or_native_execution';files=$files.Count;bytes=$totalBytes;manifest_sha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'proof-manifest.json')).Hash}|ConvertTo-Json

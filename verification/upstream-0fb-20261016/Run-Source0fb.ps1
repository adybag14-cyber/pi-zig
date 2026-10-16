$ErrorActionPreference='Stop'
$root='C:\Users\adyba\pi-upstream-audit-0fbdbd3-20261016'
$taskRoot='C:\Users\adyba\pi-zig-upstream-0fb-20261016'
$base='C:\Users\adyba\pi-zig-update-evidence-20261003'
$sources=Get-Content -LiteralPath "$root\source0fb-full-manifest.json" -Raw|ConvertFrom-Json
$deps=Get-Content -LiteralPath "$root\source0fb-runtime-manifest.json" -Raw|ConvertFrom-Json
$node=Get-Content -LiteralPath "$base\source4954-node-tools-before-20261015.json" -Raw|ConvertFrom-Json
$absences=Get-Content -LiteralPath "$base\env-readable-pipe-source4954-absence84-resume-20261016.json" -Raw|ConvertFrom-Json
if($sources.Count-ne1970-or$deps.Count-ne31064-or$node.Count-ne1774-or$absences.Count-ne84){throw 'Full authority cardinality mismatch'}
$controls=@(Get-ChildItem -LiteralPath "$taskRoot\src\extensions\fixtures" -Filter 'upstream-0fb-*.input.txt'|ForEach-Object{[ordered]@{path=$_.FullName;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}})
$controls+=@('source0fb-observe.mjs','capture-source0fb.mjs','Invoke-ExactSourceProcess.ps1','Run-Source0fb.ps1')|ForEach-Object{$path=Join-Path $root $_;[ordered]@{path=$path;sha256=(Get-FileHash -LiteralPath $path).Hash}}
$candidates=@('src/ai/retry.zig','src/extensions/native_durable_compaction_policy.zig','src/extensions/native_durable_compaction_task.zig','src/extensions/native_durable_generation_task.zig','src/extensions/retryable-provider-pattern.txt')|ForEach-Object{$path=Join-Path $taskRoot $_;[ordered]@{path=$path;sha256=(Get-FileHash -LiteralPath $path).Hash}}
$controls|ConvertTo-Json -Depth 4|Set-Content -LiteralPath "$root\source0fb-controls-manifest.json" -Encoding utf8
$candidates|ConvertTo-Json -Depth 4|Set-Content -LiteralPath "$root\source0fb-candidate-manifest.json" -Encoding utf8
function Test-Authority([string]$phase){
 $count=0
 foreach($entry in @($sources)+@($deps)+@($node)+@($controls)+@($candidates)){
  if((Get-FileHash -LiteralPath $entry.path -Algorithm SHA256).Hash-ine$entry.sha256){throw "Authority changed in $phase : $($entry.path)"};$count++
 }
 foreach($entry in $absences){foreach($path in @($entry.runtime,$entry.source.Replace('pi-upstream-source-4954d76-20261015','pi-upstream-source-0fbdbd3-20261016'))){if(Test-Path -LiteralPath $path){throw "Actual optional/historical absence no longer holds: $path"}}}
 [ordered]@{phase=$phase;utc=[DateTime]::UtcNow.ToString('o');hashed_files=$count;source=$sources.Count;dependencies=$deps.Count;node=$node.Count;controls=$controls.Count;candidates=$candidates.Count;actual_absences=$absences.Count}|ConvertTo-Json|Set-Content -LiteralPath "$root\source0fb-$phase.json" -Encoding utf8
}
Test-Authority 'before'
try{
 & "$root\Invoke-ExactSourceProcess.ps1" -Name 'source0fb-controls-corrected' -Arguments @('--max-old-space-size=256','--import','file:///C:/Users/adyba/pi-upstream-audit-0fbdbd3-20261016/source0fb-observe.mjs',"$root\capture-source0fb.mjs","$taskRoot\src\extensions\fixtures\upstream-0fb-source.json")
}finally{Test-Authority 'after'}

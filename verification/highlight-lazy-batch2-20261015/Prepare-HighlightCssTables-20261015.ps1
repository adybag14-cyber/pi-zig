$ErrorActionPreference='Stop'
$taskSource='C:/Users/adyba/pi-upstream-source-b45e0eb-20261014/node_modules/highlight.js/lib/languages/css.js'
$taskTarget='C:/Users/adyba/pi-zig-highlight-lazy-batch1-20261015/src/extensions/native_highlight_grammar_css.zig'
if(Test-Path -LiteralPath $taskTarget){throw 'Fresh CSS body target required'}
$taskText=Get-Content -LiteralPath $taskSource -Raw
$taskOutput=[Text.StringBuilder]::new()
[void]$taskOutput.AppendLine('//! Actual highlight.js 10.7.3 CSS tables in original declaration order; body follows.')
$taskCounts=@{}
foreach($taskName in @('TAGS','MEDIA_FEATURES','PSEUDO_CLASSES','PSEUDO_ELEMENTS','ATTRIBUTES')){
 $taskMatch=[regex]::Match($taskText,'(?s)const '+$taskName+' = \[(.*?)\]')
 if(!$taskMatch.Success){throw "Original table absent: $taskName"}
 [void]$taskOutput.AppendLine('const '+$taskName.ToLowerInvariant()+' = [_][]const u8{')
 $taskCount=0
 foreach($taskLine in ($taskMatch.Groups[1].Value -split "`n")){
  $taskLine=$taskLine.Trim()
  if(!$taskLine -or $taskLine.StartsWith('//')){continue}
  $taskEntry=[regex]::Match($taskLine,'^''([A-Za-z0-9-]+)''\s*,?\s*(?://.*)?$')
  if(!$taskEntry.Success){throw "Unexpected original CSS table syntax: $taskLine"}
  [void]$taskOutput.AppendLine('    "'+$taskEntry.Groups[1].Value+'",')
  $taskCount++
 }
 [void]$taskOutput.AppendLine('};')
 $taskCounts[$taskName]=$taskCount
}
[IO.File]::WriteAllText($taskTarget,$taskOutput.ToString(),[Text.UTF8Encoding]::new($false))
@{source=$taskSource;source_sha256=(Get-FileHash -LiteralPath $taskSource).Hash;tables=$taskCounts;scope='Exact lexical source string tables only; Source reverse/join/spread behavior remains native body work, no expected fixture generated'}|ConvertTo-Json -Depth 4|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'highlight-css-original-tables-20261015.json') -Encoding utf8NoBOM

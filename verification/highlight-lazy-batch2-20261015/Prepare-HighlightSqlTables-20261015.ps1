$ErrorActionPreference='Stop'
$taskSource='C:/Users/adyba/pi-upstream-source-b45e0eb-20261014/node_modules/highlight.js/lib/languages/sql.js'
$taskTarget='C:/Users/adyba/pi-zig-highlight-lazy-batch1-20261015/src/extensions/native_highlight_grammar_sql.zig'
if((Test-Path -LiteralPath $taskTarget) -and (Get-Content -LiteralPath $taskTarget -TotalCount 1) -cne '//! Actual highlight.js 10.7.3 SQL tables in original declaration order; body follows.'){throw 'Refuse to replace an authored SQL body'}
$taskText=Get-Content -LiteralPath $taskSource -Raw
$taskOutput=[Text.StringBuilder]::new()
[void]$taskOutput.AppendLine('//! Actual highlight.js 10.7.3 SQL tables in original declaration order; body follows.')
$taskCounts=@{}
foreach($taskName in @('LITERALS','MULTI_WORD_TYPES','TYPES','NON_RESERVED_WORDS','RESERVED_WORDS','RESERVED_FUNCTIONS','POSSIBLE_WITHOUT_PARENS','COMBOS')){
 $taskMatch=[regex]::Match($taskText,'(?sm)const '+$taskName+' = \[(.*?)^\s*\];')
 if(!$taskMatch.Success){throw "Original SQL table absent: $taskName"}
 [void]$taskOutput.AppendLine('const '+$taskName.ToLowerInvariant()+' = [_][]const u8{')
 $taskCount=0
 foreach($taskLine in ($taskMatch.Groups[1].Value -split "`n")){
  $taskLine=$taskLine.Trim()
  if(!$taskLine -or $taskLine.StartsWith('//')){continue}
  $taskEntry=[regex]::Match($taskLine,'^[''"]([A-Za-z0-9_ -]+)[''"]\s*,?\s*(?://.*)?$')
  if(!$taskEntry.Success){throw "Unexpected original SQL table syntax: $taskLine"}
  [void]$taskOutput.AppendLine('    "'+$taskEntry.Groups[1].Value+'",')
  $taskCount++
 }
 [void]$taskOutput.AppendLine('};')
 $taskCounts[$taskName]=$taskCount
}
[IO.File]::WriteAllText($taskTarget,$taskOutput.ToString(),[Text.UTF8Encoding]::new($false))
@{source=$taskSource;source_sha256=(Get-FileHash -LiteralPath $taskSource).Hash;tables=$taskCounts;scope='Exact lexical string tables only; Source iteration/filter/includes/map/coercion behavior remains native body work, no expected fixture generated'}|ConvertTo-Json -Depth 4|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'highlight-sql-original-tables-20261015.json') -Encoding utf8NoBOM

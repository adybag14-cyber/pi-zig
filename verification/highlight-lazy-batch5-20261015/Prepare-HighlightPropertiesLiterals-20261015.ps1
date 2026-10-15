$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Highlight-JsLiteral-Inputs-20261015.ps1')
$taskSource='C:/Users/adyba/pi-upstream-source-b45e0eb-20261014/node_modules/highlight.js/lib/languages/properties.js'
$taskTarget='C:/Users/adyba/pi-zig-highlight-lazy-batch5-20261015/src/extensions/native_highlight_grammar_properties.zig'
if(Test-Path -LiteralPath $taskTarget){throw 'Fresh properties target required'}
$taskText=Get-Content -LiteralPath $taskSource -Raw
$taskValues=[ordered]@{}
foreach($taskName in @('WS0','WS1','KEY_ALPHANUM','KEY_OTHER')){
 $taskMatch=[regex]::Match($taskText,'var\s+'+$taskName+'\s*=\s*''((?:\\.|[^''\\])*)''')
 if(!$taskMatch.Success){throw 'Original properties literal absent'}
 $taskValues[$taskName.ToLowerInvariant()]=Decode-JsString $taskMatch.Groups[1].Value
}
$taskStart=$taskText.IndexOf('var DELIM_AND_VALUE =')
$taskEnd=$taskText.IndexOf('};',$taskStart)
if($taskStart -lt 0 -or $taskEnd -lt 0){throw 'Original value body absent'}
$taskMatches=[regex]::Matches($taskText.Substring($taskStart,$taskEnd-$taskStart),'begin:\s*''((?:\\.|[^''\\])*)''')
if($taskMatches.Count -ne 2){throw 'Original two continuation literals required'}
$taskValues['escaped_backslashes']=Decode-JsString $taskMatches[0].Groups[1].Value
$taskValues['continued_line']=Decode-JsString $taskMatches[1].Groups[1].Value
$taskLines=@('//! Actual highlight.js10.7.3 properties literal inputs; body follows.')
foreach($taskEntry in $taskValues.GetEnumerator()){
 $taskEscaped=$taskEntry.Value.Replace('\','\\').Replace('"','\"').Replace("`n",'\n').Replace("`r",'\r').Replace("`t",'\t').Replace([string][char]12,'\x0c')
 $taskLines+='const '+$taskEntry.Key+' = "'+$taskEscaped+'";'
}
[IO.File]::WriteAllText($taskTarget,($taskLines -join "`n")+"`n",[Text.UTF8Encoding]::new($false))
@{source=$taskSource;sha256=(Get-FileHash -LiteralPath $taskSource).Hash;literal_inputs=$taskValues;scope='Original input strings decoded lexically; no grammar execution or expected output generated'}|ConvertTo-Json -Depth 4|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'highlight-properties-original-literals-20261015.json') -Encoding utf8NoBOM

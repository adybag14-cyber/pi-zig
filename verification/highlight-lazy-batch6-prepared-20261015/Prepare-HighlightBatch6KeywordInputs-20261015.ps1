$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Highlight-JsLiteral-Inputs-20261015.ps1')
$taskOriginal='C:/Users/adyba/pi-upstream-source-b45e0eb-20261014/node_modules/highlight.js/lib/languages'
$taskNative='C:/Users/adyba/pi-zig-highlight-lazy-batch6-20261015/src/extensions'
$taskReceipts=@()
foreach($taskName in @('vhdl','avrasm','tcl','axapta')) {
 $taskSource=Join-Path $taskOriginal "$taskName.js"
 $taskTarget=Join-Path $taskNative "native_highlight_grammar_$taskName.zig"
 if(Test-Path -LiteralPath $taskTarget){throw 'Fresh keyword target required'}
 $taskText=Get-Content -LiteralPath $taskSource -Raw
 $taskLines=@('//! Actual highlight.js10.7.3 static keyword inputs; factory body follows.')
 $taskCounts=@{}
 if($taskName -ceq 'axapta') {
  foreach($taskField in @('NORMAL_KEYWORDS','BUILT_IN_KEYWORDS','LITERAL_KEYWORDS')) {
   $taskSection=[regex]::Match($taskText,'(?s)const '+$taskField+' = \[(.*?)\];')
   if(!$taskSection.Success){throw 'Original keyword array absent'}
   $taskTokens=[regex]::Matches($taskSection.Groups[1].Value,'''((?:\\.|[^''\\])*)''')
   $taskLines+='const source_'+$taskField+' = [_][]const u8{'
   foreach($taskToken in $taskTokens) { $taskValue=Decode-JsString $taskToken.Groups[1].Value; $taskLines+='"'+$taskValue.Replace('\','\\').Replace('"','\"')+'",' }
   $taskLines+='};'; $taskCounts[$taskField]=$taskTokens.Count
  }
 } else {
  $taskPattern=if($taskName -ceq 'tcl'){'(?sm)^\s*keywords:(.*?)(?=^\s*contains:)'}else{'(?sm)^\s*keywords:\s*\{(.*?)^\s*\},'}
  $taskBlock=[regex]::Match($taskText,$taskPattern)
  if(!$taskBlock.Success){throw 'Original keyword block absent'}
  $taskBody=[regex]::Replace($taskBlock.Groups[1].Value,'(?m)//.*$|/\*.*?\*/','')
  $taskFields=if($taskName -ceq 'tcl'){@('keyword')}elseif($taskName -ceq 'avrasm'){@('keyword','built_in','meta')}else{@('keyword','built_in','literal')}
  foreach($taskField in $taskFields) {
   $taskSection=if($taskName -ceq 'tcl'){$taskBody}else{[regex]::Match($taskBody,'(?sm)^\s*'+$taskField+'\s*:(.*?)(?=^\s*[a-zA-Z_$][a-zA-Z0-9_$]*\s*:|\z)').Groups[1].Value}
   $taskTokens=[regex]::Matches($taskSection,'''((?:\\.|[^''\\])*)''|"((?:\\.|[^"\\])*)"')
   if(!$taskTokens.Count){throw 'Original keyword literals absent'}
   $taskValue=''; foreach($taskToken in $taskTokens){$taskValue+=Decode-JsString $(if($taskToken.Groups[1].Success){$taskToken.Groups[1].Value}else{$taskToken.Groups[2].Value})}
   $taskLines+='const source_'+$taskField+' = "'+$taskValue.Replace('\','\\').Replace('"','\"')+'";'; $taskCounts[$taskField]=$taskTokens.Count
  }
 }
 [IO.File]::WriteAllText($taskTarget,($taskLines -join "`n")+"`n",[Text.UTF8Encoding]::new($false))
 $taskReceipts+=@{factory=$taskName;source=$taskSource;source_sha256=(Get-FileHash -LiteralPath $taskSource).Hash;fields=$taskCounts;scope='Lexical static inputs only; no factory evaluation, no expected results generated'}
}
$taskReceipts|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'highlight-batch6-original-keyword-inputs-20261015.json') -Encoding utf8NoBOM

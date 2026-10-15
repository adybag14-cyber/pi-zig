$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Highlight-JsLiteral-Inputs-20261015.ps1')
$taskOriginal='C:/Users/adyba/pi-upstream-source-b45e0eb-20261014/node_modules/highlight.js/lib/languages'
$taskNative='C:/Users/adyba/pi-zig-highlight-lazy-batch8-20261015/src/extensions'
$taskSpecs=@(
 @{n='sas';p='(?s)const SAS_KEYWORDS =(.*?);';f=@('text')},
 @{n='lasso';p='(?s)const LASSO_KEYWORDS = \{(.*?)\n  \};';f=@('literal','built_in','keyword')},
 @{n='cos';p='(?s)const COS_KEYWORDS =(.*?);';f=@('text')},
 @{n='clojure';p='(?s)const keywords = \{(.*?)\n  \};';f=@('builtin-name')},
 @{n='elixir';p='(?s)const ELIXIR_KEYWORDS = \{(.*?)\n  \};';f=@('keyword')}
)
$taskReceipts=@()
foreach($taskSpec in $taskSpecs) {
 $taskSource=Join-Path $taskOriginal "$($taskSpec.n).js"
 $taskTarget=Join-Path $taskNative "native_highlight_grammar_$($taskSpec.n).zig"
 if(Test-Path -LiteralPath $taskTarget){throw 'Fresh keyword input target required'}
 $taskText=Get-Content -LiteralPath $taskSource -Raw
 $taskBlock=[regex]::Match($taskText,$taskSpec.p)
 if(!$taskBlock.Success){throw "Actual keyword block absent $($taskSpec.n)"}
 $taskBody=[regex]::Replace($taskBlock.Groups[1].Value,'(?m)^\s*//[^\r\n]*','')
 $taskLines=@('//! Actual highlight.js 10.7.3 static keyword inputs; native factory follows.')
 $taskCounts=@{}
 foreach($taskField in $taskSpec.f) {
  $taskSection=if($taskField -ceq 'text'){$taskBody}else{[regex]::Match($taskBody,'(?sm)^\s*[''"]?'+[regex]::Escape($taskField)+'[''"]?\s*:(.*?)(?=^\s*[''"]?[a-zA-Z_$][a-zA-Z0-9_$-]*[''"]?\s*:|\z)').Groups[1].Value}
  $taskTokens=[regex]::Matches($taskSection,'''((?:\\.|[^''\\])*)''|"((?:\\.|[^"\\])*)"')
  if(!$taskTokens.Count){throw "Actual keyword literals absent $($taskSpec.n):$taskField"}
  $taskValue=''; foreach($taskToken in $taskTokens){$taskValue+=Decode-JsString $(if($taskToken.Groups[1].Success){$taskToken.Groups[1].Value}else{$taskToken.Groups[2].Value})}
  if($taskSpec.n -ceq 'haxe' -and $taskField -ceq 'keyword'){$taskValue+='Int Float String Bool Dynamic Void Array '}
  $taskLines+='const source_'+$taskField.Replace('-','_')+' = "'+$taskValue.Replace('\','\\').Replace('"','\"')+'";'; $taskCounts[$taskField]=$taskTokens.Count
 }
 if($taskSpec.n -ceq 'vbscript') {
  $taskSection=[regex]::Match($taskText,'(?s)const BUILT_IN_FUNCTIONS = \((.*?)\)\.split').Groups[1].Value
  $taskValue=''; foreach($taskToken in [regex]::Matches($taskSection,'''((?:\\.|[^''\\])*)''')){$taskValue+=Decode-JsString $taskToken.Groups[1].Value}
  if(!$taskValue){throw 'VBScript function inputs absent'}
  $taskLines+='const source_functions = "'+$taskValue.Replace('\','\\').Replace('"','\"')+'";'
 }
 [IO.File]::WriteAllText($taskTarget,($taskLines -join "`n")+"`n",[Text.UTF8Encoding]::new($false))
 $taskReceipts+=@{factory=$taskSpec.n;source=$taskSource;source_sha256=(Get-FileHash -LiteralPath $taskSource).Hash;fields=$taskCounts;scope='Original static keyword inputs only; no grammar execution or expected result generation'}
}
$taskReceipts|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'highlight-batch8-third5-original-keyword-inputs-20261015.json') -Encoding utf8NoBOM

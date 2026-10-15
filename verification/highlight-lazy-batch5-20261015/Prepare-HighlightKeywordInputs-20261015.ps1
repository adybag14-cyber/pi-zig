$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Highlight-JsLiteral-Inputs-20261015.ps1')
$taskOriginal='C:/Users/adyba/pi-upstream-source-b45e0eb-20261014/node_modules/highlight.js/lib/languages'
$taskNative='C:/Users/adyba/pi-zig-highlight-lazy-batch5-20261015/src/extensions'
$taskReceipts=@()
foreach($taskName in @('gams','cmake','r')){
 $taskSource=Join-Path $taskOriginal "$taskName.js"
 $taskTarget=Join-Path $taskNative "native_highlight_grammar_$taskName.zig"
 if(Test-Path -LiteralPath $taskTarget){throw 'Fresh grammar keyword target required'}
 $taskText=Get-Content -LiteralPath $taskSource -Raw
 $taskPattern=if($taskName -ceq 'gams'){'(?sm)const KEYWORDS = \{(.*?)^\s*\};'}else{'(?sm)^\s*keywords:\s*\{(.*?)^\s*\},'}
 $taskBlock=[regex]::Match($taskText,$taskPattern)
 if(!$taskBlock.Success){throw 'Original keyword input block absent'}
 $taskBody=[regex]::Replace($taskBlock.Groups[1].Value,'(?m)^\s*//.*$','')
 $taskFields=if($taskName -ceq 'cmake'){@('keyword')}else{@('keyword','literal','built_in')}
 $taskLines=@('//! Original highlight.js10.7.3 keyword inputs; actual factory body follows.')
 $taskCounts=@{}
 foreach($taskField in $taskFields){
  $taskSection=[regex]::Match($taskBody,'(?sm)^\s*'+$taskField+'\s*:(.*?)(?=^\s*[a-zA-Z_$][a-zA-Z0-9_$]*\s*:|\z)')
  if(!$taskSection.Success){throw 'Original keyword field absent'}
  $taskTokens=[regex]::Matches($taskSection.Groups[1].Value,'''((?:\\.|[^''\\])*)''|"((?:\\.|[^"\\])*)"')
  if(!$taskTokens.Count){throw 'Original keyword string inputs absent'}
  $taskValue=''
  foreach($taskToken in $taskTokens){$taskValue+=Decode-JsString $(if($taskToken.Groups[1].Success){$taskToken.Groups[1].Value}else{$taskToken.Groups[2].Value})}
  $taskEscaped=$taskValue.Replace('\','\\').Replace('"','\"').Replace("`n",'\n').Replace("`r",'\r').Replace("`t",'\t')
  $taskLines+='const source_'+$taskField+' = "'+$taskEscaped+'";'
  $taskCounts[$taskField]=@{literal_fragments=$taskTokens.Count;bytes=$taskValue.Length}
 }
 [IO.File]::WriteAllText($taskTarget,($taskLines -join "`n")+"`n",[Text.UTF8Encoding]::new($false))
 $taskReceipts+=@{factory=$taskName;source=$taskSource;source_sha256=(Get-FileHash -LiteralPath $taskSource).Hash;fields=$taskCounts;scope='Original static input strings transcribed lexically; no grammar execution, no expected result generated'}
}
$taskReceipts|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'highlight-batch5-original-keyword-inputs-20261015.json') -Encoding utf8NoBOM

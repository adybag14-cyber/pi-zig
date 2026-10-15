$ErrorActionPreference='Stop'
$taskSource='C:/Users/adyba/pi-upstream-source-b45e0eb-20261014/node_modules/highlight.js/lib/languages/dns.js'
$taskTarget='C:/Users/adyba/pi-zig-highlight-lazy-batch5-20261015/src/extensions/native_highlight_grammar_dns.zig'
if(Test-Path -LiteralPath $taskTarget){throw 'Fresh DNS target required'}
function Decode-JsString([string]$raw){
 $output=[Text.StringBuilder]::new()
 for($index=0;$index -lt $raw.Length;$index++){
  $char=$raw[$index]
  if($char -ne '\'){[void]$output.Append($char);continue}
  $index++;if($index -ge $raw.Length){throw 'Unterminated Source escape'}
  $escape=$raw[$index]
  switch -CaseSensitive ($escape){
   'n'{[void]$output.Append([char]10)}
   'r'{[void]$output.Append([char]13)}
   't'{[void]$output.Append([char]9)}
   'f'{[void]$output.Append([char]12)}
   'v'{[void]$output.Append([char]11)}
   'b'{[void]$output.Append([char]8)}
   '0'{[void]$output.Append([char]0)}
   'x'{if($index+2 -ge $raw.Length){throw 'Short hex escape'};[void]$output.Append([char][Convert]::ToInt32($raw.Substring($index+1,2),16));$index+=2}
   'u'{if($index+4 -ge $raw.Length){throw 'Short Unicode escape'};[void]$output.Append([char][Convert]::ToInt32($raw.Substring($index+1,4),16));$index+=4}
   default{[void]$output.Append($escape)}
  }
 }
 return $output.ToString()
}
$taskMatches=[regex]::Matches((Get-Content -LiteralPath $taskSource -Raw),'begin:\s*''((?:\\.|[^''\\])*)''')
if($taskMatches.Count -ne 2){throw 'Original two DNS number string literals required'}
$taskValues=@($taskMatches|ForEach-Object{Decode-JsString $_.Groups[1].Value})
if($taskValues[0].Length -lt 1000 -or $taskValues[1].Length -gt 200){throw 'Original DNS literal inventory mismatch'}
$taskLines=@('//! Actual highlight.js10.7.3 DNS literal inputs; factory body follows.')
for($taskIndex=0;$taskIndex -lt 2;$taskIndex++){
 $taskEscaped=$taskValues[$taskIndex].Replace('\','\\').Replace('"','\"').Replace("`n",'\n').Replace("`r",'\r').Replace("`t",'\t')
 $taskLines+='const '+@('ipv6_pattern','ipv4_pattern')[$taskIndex]+' = "'+$taskEscaped+'";'
}
[IO.File]::WriteAllText($taskTarget,($taskLines -join "`n")+"`n",[Text.UTF8Encoding]::new($false))
@{source=$taskSource;sha256=(Get-FileHash -LiteralPath $taskSource).Hash;ipv6_bytes=$taskValues[0].Length;ipv4_bytes=$taskValues[1].Length;scope='Original literal inputs decoded lexically including JS identity escape; no Source execution or expected output generated'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'highlight-dns-original-literals-20261015.json') -Encoding utf8NoBOM

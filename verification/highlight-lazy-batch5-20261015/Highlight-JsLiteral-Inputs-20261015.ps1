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

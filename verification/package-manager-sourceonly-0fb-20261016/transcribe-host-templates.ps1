# Text-only transcription of pinned template literals into native Zig bodies.
# Does not execute JavaScript, Source controls, Zig or a native candidate.
$ErrorActionPreference='Stop'
$sourcePath='C:\Users\adyba\pi-upstream-runtime-19cb534-20261012\node_modules\hosted-git-info\lib\hosts.js'
if((Get-FileHash $sourcePath).Hash -ne 'B9941C9D4F3D9166A4ABFA41899E519B66CC5AE0FBC7360EA3AE81EFFB62A140'){throw 'Pinned hosts.js changed'}
$source=[IO.File]::ReadAllText($sourcePath)
$output=[Collections.Generic.List[string]]::new()
$output.Add('//! Native transcriptions of the pinned hosted-git-info template arrows.')
$output.Add('const h = @import("native_hosted_git_template_values.zig");')
$output.Add('const v = h.v; const c = v.c; const Scope = v.Scope;')
$script:temporary=0
$script:statements=$null
function Literal([string]$value){return 'try s.text('+($value|ConvertTo-Json -Compress)+')'}
function Emit([string]$expr){$script:temporary++;$name='temporary'+$script:temporary;$script:statements.Add('    const '+$name+' = '+$expr+';');return $name}
function Split-Outside([string]$value,[char]$separator){$items=[Collections.Generic.List[string]]::new();$depth=0;$quote=$false;$start=0;for($i=0;$i -lt $value.Length;$i++){if($value[$i] -eq "'"){$quote=!$quote};if(!$quote){if($value[$i] -eq '('){$depth++};if($value[$i] -eq ')'){$depth--};if($value[$i] -eq $separator -and $depth -eq 0){$items.Add($value.Substring($start,$i-$start));$start=$i+1}}};$items.Add($value.Substring($start));return ,$items.ToArray()}
function Expression([string]$value){
 $value=$value.Trim()
 $plus=Split-Outside $value '+'
 if($plus.Length -gt 1){$result=Expression $plus[0];for($i=1;$i -lt $plus.Length;$i++){$right=Expression $plus[$i];$result=Emit ('try s.concat('+$result+', '+$right+')')};return $result}
 if($value -match '^(.+?)\s*\|\|\s*(''.*'')$'){$first=Expression $Matches[1];$fallback=Literal $Matches[2].Substring(1,$Matches[2].Length-2);return Emit ('if (s.truthy('+$first+')) '+$first+' else '+$fallback)}
 if($value -match "^'(.*)'$"){return Literal $Matches[1]}
 if($value -match '^(maybeJoin|maybeEncode|hashformat)\((.*)\)$'){$function=$Matches[1];$arguments=Split-Outside $Matches[2] ',';$converted=@($arguments|ForEach-Object{Expression $_});switch($function){'maybeJoin'{return Emit ('try h.join(&s, &.{ '+($converted -join ', ')+' })')};'maybeEncode'{return Emit ('try h.encode(&s, '+$converted[0]+')')};'hashformat'{return Emit ('try s.call(field_hashformat, c.pi_js_undefined(), &.{ '+$converted[0]+' })')}}}
 if($value -notmatch '^\w+$'){throw "Unsupported pinned expression: $value"};return 'field_'+$value
}
$templates=[regex]::Matches($source,'(?s)(\w+):\s*\(\{\s*([^}]+)\}\)\s*=>\s*`([^`]*)`')
$inventory=@()
for($index=0;$index -lt $templates.Count;$index++){
 $match=$templates[$index];$script:temporary=0;$script:statements=[Collections.Generic.List[string]]::new();$group='defaults';foreach($hostName in @('github','bitbucket','gitlab','gist','sourcehut')){if($match.Index -gt $source.IndexOf("hosts.$hostName =")){$group=$hostName}}
 $name=$match.Groups[1].Value;$fields=@($match.Groups[2].Value.Split(',')|ForEach-Object{$_.Trim()});$body=$match.Groups[3].Value
 $output.Add('pub fn template'+$index+'(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {')
 $output.Add('    var s: Scope = .{ .engine = engine }; defer s.deinit(); const input = h.arg(args, 0);')
 foreach($field in $fields){if([regex]::IsMatch($body,'\b'+[regex]::Escape($field)+'\b')){$output.Add('    const field_'+$field+' = try s.get(input, "'+$field+'");')}else{$output.Add('    _ = try s.get(input, "'+$field+'");')}}
 $script:statements.Add('    var result = try s.text("");');$cursor=0
 foreach($interpolation in [regex]::Matches($body,'\$\{([^}]+)\}')){if($interpolation.Index -gt $cursor){$literal=Literal $body.Substring($cursor,$interpolation.Index-$cursor);$script:statements.Add('    result = try s.concat(result, '+$literal+');')};$expr=Expression $interpolation.Groups[1].Value;$script:statements.Add('    result = try s.concat(result, try s.stringify('+$expr+'));');$cursor=$interpolation.Index+$interpolation.Length}
 if($cursor -lt $body.Length){$script:statements.Add('    result = try s.concat(result, '+(Literal $body.Substring($cursor))+');')}
 foreach($statement in $script:statements){$output.Add($statement)};$output.Add('    return c.JS_DupValue(engine.context, result);');$output.Add('}')
 $inventory += [ordered]@{index=$index;group=$group;name=$name;fields=$fields;original_template=$body}
}
if($templates.Count -ne 35){throw "Pinned template inventory changed: $($templates.Count)"}
$destination=Join-Path $PSScriptRoot '..\..\src\extensions\native_hosted_git_template_bodies.zig'
[IO.File]::WriteAllText([IO.Path]::GetFullPath($destination),($output -join "`n")+"`n",[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'host-template-transcription.json'),([ordered]@{source=$sourcePath;sha256=(Get-FileHash $sourcePath).Hash;templates=$inventory}|ConvertTo-Json -Depth 7)+"`n",[Text.UTF8Encoding]::new($false))

# Author static native constructor-operation literals from pinned Source expressions.
# This does not execute TypeScript, create expected observations, or build/run Zig.
$ErrorActionPreference='Stop'
$script:nodes=[Collections.Generic.List[object]]::new()
$script:tokens=@();$script:position=0
function Node($value){$index=$script:nodes.Count;$script:nodes.Add($value);return $index}
function Peek {if($script:position -lt $script:tokens.Count){return $script:tokens[$script:position].value};return '<eof>'}
function Take {$value=Peek;$script:position++;return $value}
function Expect($value){$actual=Take;if($actual -cne $value){throw "Expected $value, got $actual at token$script:position"}}
function Tokens([string]$text){
 $pattern='(?sx)\s+|/\*.*?\*/|//[^\r\n]*|"(?:\\.|[^"\\])*"|''(?:\\.|[^''\\])*''|`(?:\\.|[^`\\])*`|\.\.\.|[A-Za-z_$][A-Za-z0-9_$]*|[0-9]+(?:\.[0-9]+)?|.'
 return @([regex]::Matches($text,$pattern)|Where-Object {$_.Value -notmatch '^\s+$|^/\*|^//'}|ForEach-Object {@{value=$_.Value;offset=$_.Index}})
}
function String-Value([string]$token){
 if($token.StartsWith('"')){return ($token|ConvertFrom-Json)}
 if($token.StartsWith("'")){$body=$token.Substring(1,$token.Length-2);return [regex]::Replace($body,'\\(.)',{param($m)switch($m.Groups[1].Value){'n'{"`n"};'r'{"`r"};'t'{"`t"};default{$m.Groups[1].Value}}})}
 throw 'Not a string literal'
}
function Expression {
 $token=Take
 if($token -eq 'Type'){Expect '.';$name=Take;Expect '(';$args=[Collections.Generic.List[int]]::new();while((Peek) -ne ')'){$args.Add((Expression));if((Peek) -ne ')'){Expect ',';if((Peek) -eq ')'){break}}};Expect ')';return (Node @{kind='call';name=$name;args=@($args)})}
 if($token -eq '{'){$fields=[Collections.Generic.List[object]]::new();while((Peek) -ne '}'){if((Peek) -eq '...'){[void](Take);$fields.Add(@{key='';spread=$true;value=(Expression)})}else{$key=Take;if($key.StartsWith('"') -or $key.StartsWith("'")){$key=String-Value $key};Expect ':';$fields.Add(@{key=$key;spread=$false;value=(Expression)})};if((Peek) -ne '}'){Expect ',';if((Peek) -eq '}'){break}}};Expect '}';return (Node @{kind='object';fields=@($fields)})}
 if($token -eq '['){$items=[Collections.Generic.List[object]]::new();while((Peek) -ne ']'){$spread=(Peek) -eq '...';if($spread){[void](Take)};$items.Add(@{spread=$spread;value=(Expression)});if((Peek) -ne ']'){Expect ',';if((Peek) -eq ']'){break}}};Expect ']';return (Node @{kind='array';items=@($items)})}
 if($token -eq 'true' -or $token -eq 'false'){return (Node @{kind='boolean';value=$token})}
 if($token -eq 'undefined'){return (Node @{kind='undefined'})}
 if($token -match '^[0-9]'){return (Node @{kind='number';value=$token})}
 if($token.StartsWith('"') -or $token.StartsWith("'")){return (Node @{kind='string';value=(String-Value $token)})}
 if($token.StartsWith('`')){$body=$token.Substring(1,$token.Length-2);$parts=[Collections.Generic.List[int]]::new();$offset=0;foreach($match in [regex]::Matches($body,'\$\{([A-Za-z_$][A-Za-z0-9_$]*)\}')){$parts.Add((Node @{kind='string';value=$body.Substring($offset,$match.Index-$offset)}));$parts.Add((Node @{kind='reference';value=$match.Groups[1].Value}));$offset=$match.Index+$match.Length};$parts.Add((Node @{kind='string';value=$body.Substring($offset)}));return (Node @{kind='template';items=@($parts)})}
 if((Peek) -eq '('){[void](Take);$args=[Collections.Generic.List[int]]::new();while((Peek) -ne ')'){$args.Add((Expression));if((Peek) -ne ')'){Expect ',';if((Peek) -eq ')'){break}}};Expect ')';return (Node @{kind='helper';name=$token;args=@($args)})}
 return (Node @{kind='reference';value=$token})
}
function Parse-Expression([string]$text){$script:tokens=Tokens $text;$script:position=0;return (Expression)}
$root='C:/Users/adyba/pi-upstream-source-4954d76-20261015/packages/ai/src/providers'
$declarations=[Collections.Generic.List[object]]::new();$helpers=[Collections.Generic.List[object]]::new()
foreach($file in @('model-schema.ts','compat-schema.ts')){
 $text=Get-Content -Raw -LiteralPath (Join-Path $root $file)
 foreach($match in [regex]::Matches($text,'(?m)^function (modelImageResizeOptions|sessionAffinityFormat|thinkingTokenBudgetField|percentileCutoffs|optionalCompatBoolean|optionalSessionAffinityFormat)\((\w+)')){
  $tail=$text.Substring($match.Index);$return=[regex]::Match($tail,'\breturn\s+');if(!$return.Success){throw 'Helper return missing'};$node=Parse-Expression $tail.Substring($return.Index+$return.Length);$helpers.Add(@{name=$match.Groups[1].Value;parameter=$match.Groups[2].Value;node=$node})
 }
 foreach($match in [regex]::Matches($text,'(?m)^(export )?const (\w+) =\s*')){
  $name=$match.Groups[2].Value
  $node=if($name -eq 'ProviderCompatProperties'){Node @{kind='merge_provider'}}else{Parse-Expression $text.Substring($match.Index+$match.Length)}
  $declarations.Add(@{name=$name;exported=$match.Groups[1].Success;node=$node;module=if($file -eq 'model-schema.ts'){'model'}else{'compat'}})
 }
}
function Quote([string]$value){$builder=[Text.StringBuilder]::new();[void]$builder.Append('"');foreach($char in $value.ToCharArray()){switch([int]$char){34{[void]$builder.Append('\"')};92{[void]$builder.Append('\\')};10{[void]$builder.Append('\n')};13{[void]$builder.Append('\r')};9{[void]$builder.Append('\t')};default{[void]$builder.Append($char)}}};[void]$builder.Append('"');return $builder.ToString()}
$out=[Text.StringBuilder]::new()
[void]$out.AppendLine('//! Static Zig constructor expressions ported from pinned model/compat Source. No schema JSON or guest implementation.')
[void]$out.AppendLine('pub const Id = u16; pub const Field = struct { key: []const u8, value: Id, spread: bool = false }; pub const Element = struct { value: Id, spread: bool = false }; pub const Call = struct { name: [:0]const u8, args: []const Id };')
[void]$out.AppendLine('pub const Node = union(enum) { string: []const u8, number: f64, boolean: bool, undef: void, reference: []const u8, array: []const Element, object: []const Field, call: Call, helper: Call, template: []const Id, merge_provider: void };')
[void]$out.AppendLine('pub const Module = enum { model, compat }; pub const Declaration = struct { name: [:0]const u8, exported: bool, node: Id, module: Module }; pub const Helper = struct { name: []const u8, parameter: [:0]const u8, node: Id };')
[void]$out.AppendLine('pub const nodes = [_]Node{')
foreach($node in $script:nodes){$body=switch($node.kind){
 'string'{'.{ .string = '+(Quote $node.value)+' }'}
 'number'{'.{ .number = '+$node.value+' }'}
 'boolean'{'.{ .boolean = '+$node.value+' }'}
 'undefined'{'.{ .undef = {} }'}
 'reference'{'.{ .reference = '+(Quote $node.value)+' }'}
 'template'{'.{ .template = &.{ '+($node.items -join ', ')+' } }'}
 'merge_provider'{'.{ .merge_provider = {} }'}
 'call'{'.{ .call = .{ .name = '+(Quote $node.name)+', .args = &.{ '+($node.args -join ', ')+' } } }'}
 'helper'{'.{ .helper = .{ .name = '+(Quote $node.name)+', .args = &.{ '+($node.args -join ', ')+' } } }'}
 'array'{'.{ .array = &.{ '+((@($node.items)|ForEach-Object {'.{ .value = '+$_.value+', .spread = '+$_.spread.ToString().ToLowerInvariant()+' }'}) -join ', ')+' } }'}
 'object'{'.{ .object = &.{ '+((@($node.fields)|ForEach-Object {'.{ .key = '+(Quote $_.key)+', .value = '+$_.value+', .spread = '+$_.spread.ToString().ToLowerInvariant()+' }'}) -join ', ')+' } }'}
 default{throw 'Unknown native operation'}
};[void]$out.AppendLine('    '+$body+',')}
[void]$out.AppendLine('};');[void]$out.AppendLine('pub const declarations = [_]Declaration{');foreach($declaration in $declarations){[void]$out.AppendLine('    .{ .name = '+(Quote $declaration.name)+', .exported = '+$declaration.exported.ToString().ToLowerInvariant()+', .node = '+$declaration.node+', .module = .'+$declaration.module+' },')};[void]$out.AppendLine('};')
[void]$out.AppendLine('pub const helpers = [_]Helper{');foreach($helper in $helpers){[void]$out.AppendLine('    .{ .name = '+(Quote $helper.name)+', .parameter = '+(Quote $helper.parameter)+', .node = '+$helper.node+' },')};[void]$out.AppendLine('};')
$destination='C:/Users/adyba/pi-zig-native-model-schemas-partial-4954-20261015/src/extensions/native_ai_model_schema_program.zig'
[IO.File]::WriteAllText($destination,$out.ToString().Replace("`r`n","`n"))
[ordered]@{nodes=$script:nodes.Count;declarations=$declarations.Count;helpers=$helpers.Count;source_files=@('model-schema.ts','compat-schema.ts')|ForEach-Object {@{path=(Join-Path $root $_);sha256=(Get-FileHash -LiteralPath (Join-Path $root $_)).Hash}};output=$destination;typescript_executed=$false;source_oracle_executed=$false;schema_json_stub=$false;zig_built_or_run=$false}|ConvertTo-Json -Depth 5

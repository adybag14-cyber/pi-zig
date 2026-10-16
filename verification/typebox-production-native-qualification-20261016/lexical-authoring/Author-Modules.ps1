. C:/Users/adyba/tmp-typebox-lexical-repair-20261016/Author-Functions.ps1
$objects=Get-Content -Raw -LiteralPath C:/Users/adyba/tmp-typebox-compile-production-20261016/reference-asts.json | ConvertFrom-Json -Depth 1024
$modules=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
foreach($p in $objects.PSObject.Properties){$modules[$p.Name]=$p.Value}
function Resolve([string]$module,[string]$source){$root='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012/node_modules/typebox/build/';return ([IO.Path]::GetRelativePath($root,[IO.Path]::GetFullPath([IO.Path]::Combine($root,[IO.Path]::GetDirectoryName($module),$source)))-replace'\\','/')}
$header=@'
//! Direct native bodies from pinned typebox@1.3.27. Source-only pending qualification.
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const o = @import("native_typebox_compile_ops.zig");
const ordinary = @import("native_node_function.zig");
const class = @import("native_class.zig");
const sdk = @import("native_sdk.zig");
const c = js.c;
const Engine = js.Engine;
'@
$report=[Collections.Generic.List[object]]::new()
foreach($module in @('guard/emit.mjs','guard/guard.mjs')){
$script:seq=if($module-eq'guard/emit.mjs'){480}else{1718}
 if($module-in@('system/arguments/arguments.mjs')){continue}
 $script:functions.Clear();$ctx=Ctx;$ctx.this='c.pi_js_undefined()';$ctx.module=$module;$ast=$modules[$module]
 foreach($st in $ast.body){if($st.type-eq'ImportDeclaration'){$path=Resolve $module $st.source.value;foreach($sp in $st.specifiers){$name=switch($sp.type){'ImportNamespaceSpecifier'{'*'}'ImportDefaultSpecifier'{'default'}default{$sp.imported.name}};$ctx.imports[$sp.local.name]=(Q $path)+', '+(Q $name)}}}
 Declare $ast.body $ctx
 $exports=[Collections.Generic.List[object]]::new()
 foreach($st in $ast.body){if($st.type-eq'ExportNamedDeclaration'){$decl=$st.declaration;if($decl.type-eq'FunctionDeclaration'){$exports.Add(@{local=$decl.id.name;name=$decl.id.name})}elseif($decl.type-eq'VariableDeclaration'){foreach($d in $decl.declarations){if($d.id.type-eq'Identifier'){$exports.Add(@{local=$d.id.name;name=$d.id.name})}}};foreach($sp in $st.specifiers){if(!$st.source){$exports.Add(@{local=$sp.local.name;name=$sp.exported.name})}}}}
 try {
  foreach($st in $ast.body){$n=if($st.type-eq'ExportNamedDeclaration'){$st.declaration}else{$st};if($n.type-eq'FunctionDeclaration'){$v=Fn $n $ctx $n.id.name;SetBinding $n.id $v $ctx}}
  foreach($entry in $exports){if($ctx.vars.ContainsKey($entry.local)){$v=Read $ctx $entry.local;Add $ctx ('try s.put(namespace, '+(Q $entry.name)+', '+$v+');')}}
  foreach($st in $ast.body){$n=if($st.type-eq'ExportNamedDeclaration'){$st.declaration}else{$st};if($n.type-in@('VariableDeclaration','ExpressionStatement')){S $n $ctx}elseif($n.type-eq'ClassDeclaration'){Bind $n.id $ctx;$v=MakeClass $n $ctx $n.id.name;SetBinding $n.id $v $ctx;$exports.Add(@{local=$n.id.name;name=$n.id.name})}}
  foreach($entry in $exports){if($ctx.vars.ContainsKey($entry.local)){$v=Read $ctx $entry.local;Add $ctx ('try s.put(namespace, '+(Q $entry.name)+', '+$v+');')}}
  $bindings=[Collections.Generic.List[string]]::new();foreach($entry in $exports){if($ctx.vars.ContainsKey($entry.local)){$bindings.Add('try s.put(bindings,'+(Q $entry.name)+',try s.text('+(Q $ctx.vars[$entry.local])+'));')}}
  $preamble='pub fn prepare(e: *Engine, graph: c.JSValue) !void { var s: Scope = .{ .engine=e }; defer s.deinit(); const modules=try s.get(graph,"modules"); const namespace=try s.get(modules,'+(Q $module)+'); const frame=try o.frame(&s,c.pi_js_null()); try s.put(frame,"@this",c.pi_js_undefined()); try s.put(try s.get(graph,"frames"),'+(Q $module)+',frame); const bindings=try s.object(); try s.put(try s.get(graph,"bindings"),'+(Q $module)+',bindings); '+"`n"+($ctx.lines-join"`n")+"`n"+($bindings-join"`n")+"`n}"
  $text=$header+"`n"+(Cleanup $preamble)+"`n"+($script:functions-join"`n")+"`n"
  foreach($match in [regex]::Matches($text,'(?m)^_ = (v\d+);$')){$name=$match.Groups[1].Value;if([regex]::Matches($text,'\b'+$name+'\b').Count-gt2){$text=[regex]::Replace($text,'(?m)^_ = '+$name+';\r?\n','')}}
  foreach($match in [regex]::Matches($text,'\b((?:loop|iteration_body)\d+): ')){$name=$match.Groups[1].Value;if([regex]::Matches($text,'\b'+$name+'\b').Count-eq1){$text=$text.Replace($name+': ','')}}
  foreach($match in [regex]::Matches($text,'(?m)^const (v\d+) = ')){$name=$match.Groups[1].Value;if([regex]::Matches($text,'\b'+$name+'\b').Count-eq1){$text=[regex]::Replace($text,'(?m)^const '+$name+' = ','_ = ')}}
  $file='native_typebox_compile_body_'+(($module-replace'\.mjs$','')-replace'[^A-Za-z0-9_]','_')+'.zig'
  [IO.File]::WriteAllText('C:/Users/adyba/pi-zig-typebox-production-qualification-20261016/src/extensions/'+$file,$text,[Text.UTF8Encoding]::new($false))
  $report.Add(@{module=$module;file=$file;status='authored';functions=$script:functions.Count;classes=@($ast.body|Where-Object{($_.type-eq'ClassDeclaration')-or($_.declaration.type-eq'ClassDeclaration')}).Count})
 }catch{$report.Add(@{module=$module;status='needs_authoring';reason="$_"})}
}
$report|ConvertTo-Json -Depth 20|Set-Content -LiteralPath C:/Users/adyba/tmp-typebox-lexical-repair-20261016/authoring-report.json -Encoding utf8
$report|Group-Object status|Select-Object Name,Count
$report|Where-Object { $_.status -ne 'authored' }|ForEach-Object{"$($_.module): $($_.reason)"}

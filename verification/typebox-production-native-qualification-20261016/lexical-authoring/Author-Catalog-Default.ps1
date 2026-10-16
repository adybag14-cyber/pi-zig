. C:/Users/adyba/tmp-typebox-compile-production-20261016/Author-Functions.ps1
$objects=Get-Content -Raw -LiteralPath C:/Users/adyba/tmp-typebox-compile-production-20261016/reference-asts.json|ConvertFrom-Json -Depth 1024
$modules=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
foreach($p in $objects.PSObject.Properties){$modules[$p.Name]=$p.Value}
function Resolve([string]$module,[string]$source){$root='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012/node_modules/typebox/build/';return ([IO.Path]::GetRelativePath($root,[IO.Path]::GetFullPath([IO.Path]::Combine($root,[IO.Path]::GetDirectoryName($module),$source)))-replace'\\','/')}
$selected=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach($module in $modules.Keys){if($module-match'^(guard/|compile/|schema/|system/locale/|system/unreachable/)' -or $module-match'^value/(assert|check|clean|clone|codec|convert|create|default|errors|parse|pipeline)/' -or $module-in@('value/index.mjs','value/value.mjs','value/shared/union_priority_sort.mjs','value/shared/optional_undefined.mjs','type/types/_codec.mjs')){[void]$selected.Add($module)}}
$report=Get-Content -Raw -LiteralPath C:/Users/adyba/tmp-typebox-compile-production-20261016/authoring-report.json|ConvertFrom-Json
$authored=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal);foreach($row in $report){if($row.status-eq'authored'-and$selected.Contains($row.module)){$authored[$row.module]=$row.file}}
$cache=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
function Exports([string]$module){
 if($cache.ContainsKey($module)){return ,$cache[$module]};$out=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal);$cache[$module]=$out
 if(!$selected.Contains($module)){return ,$out}
 $ast=$modules[$module];$imports=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
 foreach($st in $ast.body){if($st.type-eq'ImportDeclaration'){$path=Resolve $module $st.source.value;foreach($sp in $st.specifiers){$name=switch($sp.type){'ImportNamespaceSpecifier'{'*'}'ImportDefaultSpecifier'{'default'}default{$sp.imported.name}};$imports[$sp.local.name]=@{module=$path;name=$name}}}}
 foreach($st in $ast.body){switch($st.type){
 'ExportNamedDeclaration'{if($st.declaration){$decl=$st.declaration;if($decl.type-in@('FunctionDeclaration','ClassDeclaration')){$out[$decl.id.name]=@{module=$module;name=$decl.id.name;own=$true}}elseif($decl.type-eq'VariableDeclaration'){foreach($d in $decl.declarations){if($d.id.type-eq'Identifier'){$out[$d.id.name]=@{module=$module;name=$d.id.name;own=$true}}}}};foreach($sp in $st.specifiers){$out[$sp.exported.name]=if($st.source){@{module=(Resolve $module $st.source.value);name=$sp.local.name}}elseif($imports.ContainsKey($sp.local.name)){$imports[$sp.local.name]}else{@{module=$module;name=$sp.local.name}}}}
 'ExportAllDeclaration'{$path=Resolve $module $st.source.value;if($st.exported){$out[$st.exported.name]=@{module=$path;name='*'}}elseif($selected.Contains($path)){$dependency=Exports $path;foreach($name in $dependency.get_Keys()){if($name-cne'default'){$out[$name]=$dependency[$name]}}}}
 'ExportDefaultDeclaration'{$name=$st.declaration.name;if($name){$out['default']=if($imports.ContainsKey($name)){$imports[$name]}else{@{module=$module;name=$name}}}}
 }}
 return ,$out
}
$order=[Collections.Generic.List[string]]::new();$visited=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
function Visit([string]$module){if(!$selected.Contains($module)-or!$visited.Add($module)){return};foreach($st in $modules[$module].body){if($st.source){Visit (Resolve $module $st.source.value)}};$order.Add($module)}
Visit 'compile/index.mjs';foreach($module in ($selected|Sort-Object)){Visit $module}
$lines=[Collections.Generic.List[string]]::new();$lines.Add('//! Dependency assembly for actual typebox@1.3.27 Compile/Validator.');$lines.Add('const js=@import("native_js_values.zig"); const Scope=@import("native_sdk_prompt_scope.zig").Scope; const c=js.c; const Engine=js.Engine;')
$lines.Add('pub fn allocate(e:*Engine,graph:c.JSValue)!void {var s:Scope=.{.engine=e};defer s.deinit();const modules=try s.object();try s.put(graph,"modules",modules);try s.put(graph,"frames",try s.object());try s.put(graph,"bindings",try s.object());')
foreach($module in ($selected|Sort-Object)){$lines.Add('try s.put(modules,'+(Q $module)+',try s.object());')};$lines.Add('}')
function AliasLines([string]$module){$out=[Collections.Generic.List[string]]::new();$exports=Exports $module;foreach($name in ($exports.get_Keys()|Sort-Object)){$entry=$exports[$name];if($entry.own -and $entry.module-eq$module){continue};if(!$selected.Contains($entry.module)-and$entry.module-notmatch'^(type/|system/|format/)'){continue};$src='try s.get(modules,'+(Q $entry.module)+')';$value=if($entry.name-eq'*'){$src}else{'try s.get('+ $src+','+(Q $entry.name)+')'};$out.Add('try s.put(try s.get(modules,'+(Q $module)+'),'+(Q $name)+','+$value+');')};return ,$out}
$lines.Add('pub fn prepare(e:*Engine,graph:c.JSValue)!void {var s:Scope=.{.engine=e};defer s.deinit();const modules=try s.get(graph,"modules");')
foreach($module in $order){if($authored.ContainsKey($module)){$lines.Add('try @import('+(Q $authored[$module])+').prepare(e,graph);')};foreach($line in (AliasLines $module)){$lines.Add($line)}};$lines.Add('}')
$lines.Add('pub fn refresh(e:*Engine,graph:c.JSValue)!void {var s:Scope=.{.engine=e};defer s.deinit();const modules=try s.get(graph,"modules");');foreach($module in $order){foreach($line in (AliasLines $module)){$lines.Add($line)}};$lines.Add('}')
[IO.File]::WriteAllText('C:/Users/adyba/tmp-typebox-lexical-repair-20261016/catalog-default-output.zig',($lines-join"`n"),[Text.UTF8Encoding]::new($false))
@{selected=$selected.Count;authored=$authored.Count;modules=@($order);external=@('Type','Memory','Settings','Format','Hashing','Arguments','Environment')}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath C:/Users/adyba/tmp-typebox-lexical-repair-20261016/catalog-default-inventory.json -Encoding utf8
Write-Output "Selected $($selected.Count); authored $($authored.Count) native leaves"

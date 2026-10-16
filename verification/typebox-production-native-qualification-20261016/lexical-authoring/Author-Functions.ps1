$ErrorActionPreference='Stop'
$script:seq=0
$script:functions=[Collections.Generic.List[string]]::new()
function Q([string]$x){$r='"';foreach($c in $x.ToCharArray()){switch([int]$c){34{$r+='\"'}92{$r+='\\'}10{$r+='\n'}13{$r+='\r'}9{$r+='\t'}default{if([int]$c-lt32){$r+='\x'+([int]$c).ToString('x2')}else{$r+=$c}}}};return $r+'"'}
function Add($ctx,[string]$line){[void]$ctx.lines.Add($line)}
function Fresh([string]$prefix='v'){$script:seq++;return $prefix+$script:seq}
function T($ctx,[string]$expression){$name=Fresh;Add $ctx "const $name = $expression;";return $name}
function Dict {return ,([Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal))}
function Ctx($parent=$null){$c=@{lines=[Collections.Generic.List[string]]::new();vars=(Dict);imports=(Dict);module='';loop='';continue='';iterators=@();this='receiver'};if($parent){foreach($k in $parent.vars.get_Keys()){$c.vars[$k]=$parent.vars[$k]};$c.imports=$parent.imports;$c.module=$parent.module;$c.this=$parent.this;$c.loop=$parent.loop;$c.continue=$parent.continue;$c.iterators=$parent.iterators};return $c}
function Bind($pattern,$ctx,[bool]$force=$false){if(!$pattern){return};switch($pattern.type){'Identifier'{if($force -or !$ctx.vars.ContainsKey($pattern.name)){$ctx.vars[$pattern.name]=Fresh 'binding'}}'ArrayPattern'{foreach($e in $pattern.elements){Bind $e $ctx $force}}'ObjectPattern'{foreach($p in $pattern.properties){if($p.type-eq'RestElement'){Bind $p.argument $ctx $force}else{Bind $p.value $ctx $force}}}'RestElement'{Bind $pattern.argument $ctx $force}'AssignmentPattern'{Bind $pattern.left $ctx $force}default{throw "binding $($pattern.type)"}}}
function Declare($body,$ctx){foreach($st in $body){$n=if($st.type-eq'ExportNamedDeclaration'){$st.declaration}else{$st};if(!$n){continue};if($n.type-eq'VariableDeclaration'){foreach($d in $n.declarations){Bind $d.id $ctx $true}}elseif($n.type-in@('FunctionDeclaration','ClassDeclaration')){Bind $n.id $ctx $true}}}
function Read($ctx,[string]$name){if($ctx.vars.ContainsKey($name)){return T $ctx ('try o.lookup(&s, frame, '+(Q $ctx.vars[$name])+')')};if($ctx.imports.ContainsKey($name)){return T $ctx ('try o.importValue(&s, graph, '+$ctx.imports[$name]+')')};if($name-eq'undefined'){return 'c.pi_js_undefined()'};return T $ctx ('try s.global('+(Q $name)+')')}
function SetBinding($pattern,$v,$ctx){switch($pattern.type){'Identifier'{Add $ctx ('try o.assign(&s, frame, '+(Q $ctx.vars[$pattern.name])+', '+$v+');')}'AssignmentPattern'{$temp=T $ctx ('default_value: { if (!c.JS_IsUndefined('+$v+')) break :default_value '+$v+'');$right=X $pattern.right $ctx;Add $ctx ('break :default_value '+$right+'; };');SetBinding $pattern.left $temp $ctx}'ArrayPattern'{$it=Fresh 'destructure';Add $ctx ('var '+$it+' = try o.iterator(e, '+$v+');');Add $ctx ('defer '+$it+'.deinit();');Add $ctx ('errdefer '+$it+'.closePreserving();');foreach($p in $pattern.elements){if($p.type-eq'RestElement'){$arr=T $ctx 'try s.array()';Add $ctx ('while (try '+$it+'.next()) |item| { defer e.freeValue(item); try o.append(&s, '+$arr+', item); }');SetBinding $p.argument $arr $ctx}else{$item=T $ctx ('try s.own(if ('+$it+'.closed) c.pi_js_undefined() else (try '+$it+'.next()) orelse c.pi_js_undefined())');if($p){SetBinding $p $item $ctx}}};Add $ctx ('try '+$it+'.close();')}'ObjectPattern'{foreach($p in $pattern.properties){if($p.type-eq'RestElement'){throw 'object pattern rest not authored'};$key=if($p.computed){$raw=X $p.key $ctx;T $ctx "try o.propertyKey(&s, $raw)"}else{T $ctx ('try s.text('+(Q $(if($p.key.type-eq'Identifier'){$p.key.name}else{$p.key.value}))+')')};$item=T $ctx "try s.own(try js.getKey(e, $v, $key))";SetBinding $p.value $item $ctx}}default{throw "set pattern $($pattern.type)"}}}
function Ref($n,$ctx){if($n.type-eq'Identifier'){return @{kind='binding';key=$ctx.vars[$n.name];name=$n.name}};if($n.type-ne'MemberExpression'){throw "reference $($n.type)"};$obj=X $n.object $ctx;$key=if($n.computed){$raw=X $n.property $ctx;T $ctx "try o.propertyKey(&s, $raw)"}else{T $ctx ('try s.text('+(Q $n.property.name)+')')};return @{kind='property';obj=$obj;key=$key}}
function GetRef($r,$ctx){if($r.kind-eq'binding'){return Read $ctx $r.name};return T $ctx ('try s.own(try js.getKey(e, '+$r.obj+', '+$r.key+'))')}
function PutRef($r,$v,$ctx){if($r.kind-eq'binding'){Add $ctx ('try o.assign(&s, frame, '+(Q $r.key)+', '+$v+');')}else{Add $ctx ('try js.setKey(e, '+$r.obj+', '+$r.key+', '+$v+');')}}
function X($n,$ctx,[string]$inferred=''){
 if(!$n){return 'c.pi_js_undefined()'}
 switch($n.type){
 'Literal'{if($n.regex){$p=T $ctx ('try s.text('+(Q $n.regex.pattern)+')');$f=T $ctx ('try s.text('+(Q $n.regex.flags)+')');$ctor=T $ctx 'try s.global("RegExp")';return T $ctx "try o.construct(&s, $ctor, &.{$p, $f})"};if($n.bigint){$ctor=T $ctx 'try s.global("BigInt")';$str=T $ctx ('try s.text('+(Q $n.bigint)+')');return T $ctx "try s.call($ctor, c.pi_js_undefined(), &.{$str})"};if($null-eq$n.value){return 'c.pi_js_null()'};if($n.value-is[string]){return T $ctx ('try s.text('+(Q $n.value)+')')};if($n.value-is[bool]){return ('o.boolean(&s, '+$n.value.ToString().ToLower()+')')};return ('c.JS_NewFloat64(e.context, '+([string]$n.value)+')')}
 'Identifier'{return Read $ctx $n.name}
 'ChainExpression'{return X $n.expression $ctx}
 'ThisExpression'{return $ctx.this}
 'ArrayExpression'{$out=T $ctx 'try s.array()';foreach($p in $n.elements){if($p.type-eq'SpreadElement'){$v=X $p.argument $ctx;Add $ctx "try o.spreadArray(&s, $out, $v);"}elseif(!$p){Add $ctx "try o.arrayHole(&s, $out);"}else{$v=X $p $ctx;Add $ctx "try o.append(&s, $out, $v);"}};return $out}
 'ObjectExpression'{$out=T $ctx 'try s.object()';foreach($p in $n.properties){if($p.type-eq'SpreadElement'){$v=X $p.argument $ctx;Add $ctx "try js.spreadInto(e, $out, $v);";continue};if($p.kind-ne'init'){throw "object getter $($p.kind)"};$key=if($p.computed){$raw=X $p.key $ctx;T $ctx "try o.propertyKey(&s, $raw)"}else{T $ctx ('try s.text('+(Q $(if($p.key.type-eq'Identifier'){$p.key.name}else{$p.key.value}))+')')};$v=X $p.value $ctx $(if($p.key.type-eq'Identifier'){$p.key.name}else{$p.key.value});Add $ctx "try o.defineKey(&s, $out, $key, $v);"};return $out}
 'MemberExpression'{$r=Ref $n $ctx;return GetRef $r $ctx}
 'CallExpression'{if($n.callee.type-eq'MemberExpression'){$r=Ref $n.callee $ctx;$receiver=$r.obj;$fn=GetRef $r $ctx}else{$receiver='c.pi_js_undefined()';$fn=X $n.callee $ctx};$params=[Collections.Generic.List[string]]::new();$spread=@($n.arguments|Where-Object { $_.type -eq 'SpreadElement' }).Count;if($spread){$arr=X ([pscustomobject]@{type='ArrayExpression';elements=$n.arguments}) $ctx;return T $ctx "try o.callSpread(&s, $fn, $receiver, $arr)"};foreach($arg in $n.arguments){[void]$params.Add((X $arg $ctx))};return T $ctx ('try s.call('+$fn+', '+$receiver+', &.{'+($params-join', ')+ '})')}
 'NewExpression'{$fn=X $n.callee $ctx;$params=[Collections.Generic.List[string]]::new();foreach($arg in $n.arguments){if($arg.type-eq'SpreadElement'){throw 'construct spread'};[void]$params.Add((X $arg $ctx))};return T $ctx ('try o.construct(&s, '+$fn+', &.{'+($params-join', ')+ '})')}
 'ClassExpression'{return MakeClass $n $ctx $inferred}
 'BinaryExpression'{$left=X $n.left $ctx;$right=X $n.right $ctx;switch($n.operator){'==='{return "o.boolean(&s, s.equal($left, $right))"}'!=='{return "o.boolean(&s, !s.equal($left, $right))"}'in'{return T $ctx "o.boolean(&s, try js.hasKey(e, $right, $left))"}'instanceof'{return T $ctx "try o.instanceOf(&s, $left, $right)"}default{$op=@{'+'=0;'-'=1;'*'=2;'/'=3;'<'=4;'<='=5;'>'=6;'>='=7;'%'=8;'**'=9;'&'=10;'|'=11;'<<'=12;'>>'=13};if(!$op.ContainsKey($n.operator)){throw "binary $($n.operator)"};return T $ctx ('try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, '+$op[$n.operator]+', '+$left+', '+$right+')))')}}}
 'LogicalExpression'{$left=X $n.left $ctx;$label=Fresh 'logical';$out=Fresh;Add $ctx "const $out = $label`: {";$condition=switch($n.operator){'&&'{"!s.truthy($left)"}'||'{"s.truthy($left)"}'??'{"!c.JS_IsNull($left) and !c.JS_IsUndefined($left)"}default{throw 'logical'}};Add $ctx "if ($condition) break :$label $left;";$right=X $n.right $ctx;Add $ctx "break :$label $right; };";return $out}
 'ConditionalExpression'{$test=X $n.test $ctx;$label=Fresh 'conditional';$out=Fresh;Add $ctx "const $out = $label`: { if (s.truthy($test)) {";$a=X $n.consequent $ctx;Add $ctx "break :$label $a; } else {";$b=X $n.alternate $ctx;Add $ctx "break :$label $b; } };";return $out}
 'UnaryExpression'{if($n.operator-eq'delete'){$r=Ref $n.argument $ctx;return T $ctx ('try o.deleteKey(&s, '+$r.obj+', '+$r.key+')')};$v=X $n.argument $ctx;switch($n.operator){'!'{return "o.boolean(&s, !s.truthy($v))"}'typeof'{return T $ctx "try o.typeOf(&s, $v)"}'-'{return T $ctx "try o.negate(&s, $v)"}'+'{return T $ctx "try o.toNumber(&s, $v)"}'void'{Add $ctx "_ = $v;";return 'c.pi_js_undefined()'}default{throw "unary $($n.operator)"}}}
 'UpdateExpression'{$r=Ref $n.argument $ctx;$old=GetRef $r $ctx;$fn=if($n.operator-eq'++'){'JS_PiIncrement'}else{'JS_PiDecrement'};$new=T $ctx "try s.own(try e.checked(c.$fn(e.context, $old)))";PutRef $r $new $ctx;return $(if($n.prefix){$new}else{$old})}
 'AssignmentExpression'{$r=Ref $n.left $ctx;if($n.operator-eq'='){$v=X $n.right $ctx}else{$left=GetRef $r $ctx;$right=X $n.right $ctx;$op=@{'+='=0;'-='=1;'*='=2;'/='=3;'|='=11;'&='=10};if(!$op.ContainsKey($n.operator)){throw "assignment $($n.operator)"};$v=T $ctx ('try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, '+$op[$n.operator]+', '+$left+', '+$right+')))')};PutRef $r $v $ctx;return $v}
 'SequenceExpression'{$r='c.pi_js_undefined()';foreach($p in $n.expressions){$r=X $p $ctx};return $r}
 'TemplateLiteral'{$out=T $ctx ('try s.text('+(Q $n.quasis[0].value.cooked)+')');for($i=0;$i-lt$n.expressions.Count;$i++){$expr=X $n.expressions[$i] $ctx;$str=T $ctx "try s.stringify($expr)";$out=T $ctx "try s.concat($out, $str)";$part=T $ctx ('try s.text('+(Q $n.quasis[$i+1].value.cooked)+')');$out=T $ctx "try s.concat($out, $part)"};return $out}
 {$_-in@('ArrowFunctionExpression','FunctionExpression','FunctionDeclaration')}{return Fn $n $ctx $inferred}
 default{throw "expression $($n.type) in $($ctx.module) at $($n.start)"}
 }
}
function Block($body,$ctx){$child=Ctx $ctx;Declare $body $child;foreach($st in $body){if($st.type-eq'FunctionDeclaration'){$v=Fn $st $child $st.id.name;SetBinding $st.id $v $child}};foreach($st in $body){if($st.type-ne'FunctionDeclaration'){S $st $child}};foreach($line in $child.lines){Add $ctx $line}}
function S($n,$ctx){switch($n.type){
 'BlockStatement'{Block $n.body $ctx}
 'VariableDeclaration'{foreach($d in $n.declarations){Bind $d.id $ctx;$v=X $d.init $ctx $(if($d.id.type-eq'Identifier'){$d.id.name}else{''});SetBinding $d.id $v $ctx}}
 'ExpressionStatement'{$v=X $n.expression $ctx;Add $ctx "_ = $v;"}
 'ReturnStatement'{$v=X $n.argument $ctx;foreach($it in $ctx.iterators){Add $ctx ("try $it.close();")};Add $ctx "return c.JS_DupValue(e.context, $v);"}
 'ThrowStatement'{$v=X $n.argument $ctx;Add $ctx "_ = c.JS_Throw(e.context, c.JS_DupValue(e.context, $v)); return js.capture(e);"}
 'IfStatement'{$v=X $n.test $ctx;Add $ctx "if (s.truthy($v)) {";S $n.consequent $ctx;Add $ctx '}';if($n.alternate){Add $ctx 'else {';S $n.alternate $ctx;Add $ctx '}'}}
 'ForOfStatement'{$v=X $n.right $ctx;$it=Fresh 'iterator';$next=Fresh 'next';$label=Fresh 'loop';Add $ctx "var $it = try o.iterator(e, $v); defer $it.deinit(); errdefer $it.closePreserving();";Add $ctx "$label`: while (try $it.next()) |$next| { defer e.freeValue($next);";$child=Ctx $ctx;$child.loop=$label;$child.continue="continue :$label;";$child.iterators=@($it)+$ctx.iterators;$iteration=Fresh 'iteration';Add $ctx "const $iteration = try o.frame(&s, frame);";if($n.left.type-eq'VariableDeclaration'){$p=$n.left.declarations[0].id;Bind $p $child $true;SetBinding $p $next $child}else{PutRef (Ref $n.left $child) $next $child};S $n.body $child;foreach($line in $child.lines){Add $ctx ([regex]::Replace($line,'(?<![.\w])frame\b',$iteration))};Add $ctx '}';Add $ctx "try $it.close();"}
 'WhileStatement'{$label=Fresh 'loop';$child=Ctx $ctx;$child.loop=$label;$child.continue="continue :$label;";Add $ctx "$label`: while (true) {";$test=X $n.test $ctx;Add $ctx "if (!s.truthy($test)) break :$label;";S $n.body $child;foreach($line in $child.lines){Add $ctx $line};Add $ctx '}'}
 'ForStatement'{if($n.init){if($n.init.type-eq'VariableDeclaration'){S $n.init $ctx}else{$v=X $n.init $ctx;Add $ctx "_ = $v;"}};$label=Fresh 'loop';$body=Fresh 'iteration_body';$child=Ctx $ctx;$child.loop=$label;$child.continue="break :$body;";Add $ctx "$label`: while (true) {";if($n.test){$test=X $n.test $ctx;Add $ctx "if (!s.truthy($test)) break :$label;"};Add $ctx "$body`: {";S $n.body $child;foreach($line in $child.lines){Add $ctx $line};Add $ctx '}';if($n.update){$v=X $n.update $ctx;Add $ctx "_ = $v;"};Add $ctx '}'}
 'BreakStatement'{Add $ctx ('break :'+$ctx.loop+';')}
 'ContinueStatement'{Add $ctx $ctx.continue}
 'EmptyStatement'{}
 'SwitchStatement'{$value=X $n.discriminant $ctx;$label=Fresh 'switch_block';$entered=Fresh 'entered';Add $ctx "var $entered = false; $label`: {";$child=Ctx $ctx;$child.loop=$label;foreach($case in $n.cases){if($case.test){$test=X $case.test $child;Add $child "if ($entered or s.equal($value, $test)) { $entered = true;"}else{Add $child "if (!$entered) {"};foreach($st in $case.consequent){S $st $child};Add $child '}'};Add $child "break :$label;";foreach($line in $child.lines){Add $ctx $line};Add $ctx '}'}
 'ExportNamedDeclaration'{if($n.declaration){S $n.declaration $ctx}}
 'ImportDeclaration'{}
 'FunctionDeclaration'{}
 default{throw "statement $($n.type) in $($ctx.module) at $($n.start)"}
}}
function Fn($n,$ctx,[string]$inferred=''){
 if($ctx.module-eq'schema/build.mjs'-and$n.id.name-eq'CreateEvaluatedCheck'){$fn=Fresh 'native_lower';$script:functions.Add('fn '+$fn+'(e:*Engine,_:c.JSValue,args:[]const c.JSValue,roots:[]const c.JSValue) anyerror!c.JSValue {return @import("native_typebox_compile_ir.zig").createCheck(e,roots[0],args[0],args[1]);}');return T $ctx ('try s.own(try ordinary.create(e,"CreateEvaluatedCheck",2,'+$fn+',&.{graph,frame}))')}
 $fn=Fresh 'body';$child=Ctx $ctx;$child.lines.Clear();$child.iterators=@();$child.loop='';$child.continue='';$child.this='receiver';if($n.type-eq'ArrowFunctionExpression'){$child.this=T $child 'try o.lookup(&s, frame, "@this")'}
 foreach($p in $n.params){Bind $p $child $true};if($n.body.type-eq'BlockStatement'){Declare $n.body.body $child}
 $lines=[Collections.Generic.List[string]]::new();[void]$lines.Add('var s: Scope = .{ .engine = e }; defer s.deinit();');[void]$lines.Add('const graph = roots[0];');[void]$lines.Add('const frame = try o.frame(&s, roots[1]);');if($n.type-ne'ArrowFunctionExpression'){[void]$lines.Add('try s.put(frame, "@this", receiver);')}
 $i=0;foreach($p in $n.params){if($p.type-eq'RestElement'){$v=T $child ('try o.rest(&s, args, '+$i+')');SetBinding $p.argument $v $child}else{$v=if($i-eq0){'if (args.len > 0) args[0] else c.pi_js_undefined()'}else{"if (args.len > $i) args[$i] else c.pi_js_undefined()"};$tmp=T $child $v;SetBinding $p $tmp $child};$i++}
 if($n.body.type-eq'BlockStatement'){Block $n.body.body $child}else{$v=X $n.body $child;Add $child "return c.JS_DupValue(e.context, $v);"}
 foreach($line in $child.lines){[void]$lines.Add($line)};if(!$lines.Count-or$lines[$lines.Count-1]-notmatch'(^|; )return '){[void]$lines.Add('return c.pi_js_undefined();')}
 $body='fn '+$fn+'(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {'+"`n"+($lines-join"`n")+"`n}"
 $body=Cleanup $body
 [void]$script:functions.Add($body)
 $len=0;foreach($p in $n.params){if($p.type-in@('AssignmentPattern','RestElement')){break};$len++};$name=if($n.id){$n.id.name}else{$inferred}
 if($n.type-in@('ArrowFunctionExpression','MethodExpression')){$cf=$fn+'C';[void]$script:functions.Add('fn '+$cf+'(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue { const e = Engine.fromContext(ctx.?); return '+$fn+'(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err); }');return T $ctx ('try o.arrow(&s, '+(Q $name)+', '+$len+', '+$cf+', &.{graph, frame})')}
 return T $ctx ('try s.own(try ordinary.create(e, '+(Q $name)+', '+$len+', '+$fn+', &.{graph, frame}))')
}
function MakeClass($n,$ctx,[string]$inferred='') {
 $name=if($n.id){$n.id.name}else{$inferred};$super=if($n.superClass){X $n.superClass $ctx}else{'c.pi_js_undefined()'}
 $proto=T $ctx $(if($n.superClass){'try o.derivedPrototype(&s, '+$super+')'}else{'try s.object()'})
 $constructor=@($n.body.body|Where-Object {$_.kind-eq'constructor'})[0]
 $fn=Fresh 'constructor';$child=Ctx $ctx;$child.iterators=@();$child.loop='';$child.continue='';$child.this='receiver'
 foreach($p in $constructor.value.params){Bind $p $child $true};Declare $constructor.value.body.body $child
 $i=0;foreach($p in $constructor.value.params){$v=T $child "if (args.len > $i) args[$i] else c.pi_js_undefined()";SetBinding $p $v $child;$i++}
 $statements=@($constructor.value.body.body)
 if($n.superClass){$superCall=$statements[0].expression;if($superCall.type-ne'CallExpression'-or$superCall.callee.type-ne'Super'){throw 'derived constructor without immediate actual super'};$params=[Collections.Generic.List[string]]::new();foreach($p in $superCall.arguments){$params.Add((X $p $child))};Add $child ('const receiver = try o.constructWithTarget(&s, roots[2], target, &.{'+($params-join', ')+'});');$statements=@($statements|Select-Object -Skip 1)}else{Add $child 'const receiver = try s.own(try class.object(e, target));'}
 Add $child 'try s.put(frame, "@this", receiver);';Block $statements $child;Add $child 'return c.JS_DupValue(e.context, receiver);'
 $code='fn '+$fn+'(e: *Engine, target: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue { var s: Scope = .{.engine=e}; defer s.deinit(); const graph=roots[0]; const frame=try o.frame(&s,roots[1]);'+"`n"+($child.lines-join"`n")+"`n}"
 $script:functions.Add((Cleanup $code))
 $len=0;foreach($p in $constructor.value.params){if($p.type-in@('AssignmentPattern','RestElement')){break};$len++}
 $result=T $ctx ('try s.own(try class.constructor(e, '+(Q $name)+', '+$len+', '+$proto+', '+$fn+', &.{graph, frame, '+$super+'}))')
 if($n.superClass){Add $ctx ('try o.setPrototype(&s, '+$result+', '+$super+');')}
 foreach($method in $n.body.body){if($method.kind-eq'constructor'){continue};if($method.kind-ne'method'-or$method.computed){throw 'class computed/getter method'};$method.value.type='MethodExpression';$methodName=$method.key.name;$function=Fn $method.value $ctx $methodName;Add $ctx ('try o.method(&s, '+$(if($method.static){$result}else{$proto})+', '+(Q $methodName)+', '+$function+');')}
 return $result
}
function Cleanup([string]$body) {
 foreach($parameter in @('receiver','args','target','roots')){if([regex]::Matches($body,'\b'+$parameter+'\b').Count-eq1){$body=$body-replace ('\b'+$parameter+': '),'_: '}}
 foreach($local in @('graph','frame','namespace')){if([regex]::Matches($body,'\b'+$local+'\b').Count-eq1){$body=$body-replace ('\bconst '+$local+'\s*='),'_ ='}}
 return $body
}

$ErrorActionPreference='Stop'
$taskRoot='C:/Users/adyba/pi-zig-highlight-complete191-root55-20261015'
$taskIndex='C:/Users/adyba/pi-upstream-source-b45e0eb-20261014/node_modules/highlight.js/lib/index.js'
$taskTarget=Join-Path $taskRoot 'src/extensions/native_highlight_index191.zig'
if(Test-Path -LiteralPath $taskTarget){throw 'Fresh actual-index target required'}
$taskNames=@([regex]::Matches((Get-Content -LiteralPath $taskIndex -Raw),"hljs\.registerLanguage\('([^']+)', require\('./languages/([^']+)'\)\);")|ForEach-Object{if($_.Groups[1].Value -cne $_.Groups[2].Value){throw 'Canonical index import mismatch'};$_.Groups[1].Value})
if($taskNames.Count -ne 191 -or @($taskNames|Sort-Object -Unique).Count -ne 191){throw 'Exact actual191 canonical order required'}
$taskLines=@(
'//! Actual highlight.js10.7.3 index registration sequence, private/unqualified.',
'//! Static index names were transcribed from the authoritative installed index.',
'const std = @import("std");',
'const em = @import("engine.zig");',
'const Scope = @import("native_highlight_scope.zig").Scope;',
'const audit = @import("native_highlight_registration_audit.zig");',
'const c = em.c;',
'pub const order = [_][]const u8{'
)
foreach($taskName in $taskNames){$taskLines+='    "'+$taskName+'",'}
$taskLines+=@(
'};',
'fn ordinal(comptime name: []const u8) usize {',
'    for (order, 0..) |candidate, index| if (std.mem.eql(u8, candidate, name)) return index;',
'    @compileError("Eager factory absent from actual index191");',
'}',
'pub fn install(engine: *em.Engine, core: c.JSValue, eager: c.JSValue) !void {',
'    try audit.install(engine, core, order);',
'    var s: Scope = .{ .engine = engine };',
'    defer s.deinit();',
'    inline for (@import("native_highlight_core.zig").eager_order) |name| {',
'        const factory = try s.get(eager, name);',
'        if (!c.JS_IsFunction(engine.context, factory)) return error.NativeActualEagerFactoryRequired;',
'        audit.cacheFactory(engine, ordinal(name), factory);',
'    }',
'}',
'pub fn cachedFactory(engine: *em.Engine, index: usize) c.JSValue {',
'    return audit.cachedFactory(engine, index);',
'}',
'pub fn factoryAt(engine: *em.Engine, comptime index: usize) !c.JSValue {',
'    const cached = audit.cachedFactory(engine, index);',
'    if (!c.JS_IsUndefined(cached)) return c.JS_DupValue(engine.context, cached);',
'    const factory = try switch (index) {'
)
$taskSpecial=@{c=@{module='c_family';mode='false'};cpp=@{module='c_family';mode='true'};javascript=@{module='js_family';mode='false'};typescript=@{module='js_family';mode='true'}}
for($taskIndexNumber=0;$taskIndexNumber -lt $taskNames.Count;$taskIndexNumber++){
 $taskName=$taskNames[$taskIndexNumber]
 $taskModule=if($taskSpecial.ContainsKey($taskName)){$taskSpecial[$taskName].module}else{$taskName.Replace('-','_')}
 if(!(Test-Path -LiteralPath (Join-Path $taskRoot "src/extensions/native_highlight_grammar_$taskModule.zig"))){throw 'Actual compiled factory body absent'}
 $taskArgs=if($taskSpecial.ContainsKey($taskName)){'engine, '+$taskSpecial[$taskName].mode}else{'engine'}
 $taskLines+='        '+$taskIndexNumber+' => @import("native_highlight_grammar_'+$taskModule+'.zig").create('+$taskArgs+'),'
}
$taskLines+=@(
'        else => unreachable,',
'    };',
'    audit.cacheFactory(engine, index, factory);',
'    return factory;',
'}',
'pub fn registerAll(engine: *em.Engine, core: c.JSValue) !void {',
'    if (audit.complete(engine, core)) return;',
'    var s: Scope = .{ .engine = engine };',
'    defer s.deinit();',
'    audit.begin(engine);',
'    defer audit.stop(engine);',
'    inline for (order, 0..) |name, index| {',
'        // Actual JS evaluates the registerLanguage getter before require().',
'        const register = try s.get(core, "registerLanguage");',
'        const text = try s.text(name);',
'        const factory = try s.own(try factoryAt(engine, index));',
'        _ = try s.call(register, core, &.{ text, factory });',
'    }',
'    if (!audit.finish(engine)) return error.NativeActualGrammarRegistrationRequired;',
'}',
'pub fn ready(engine: *em.Engine, core: c.JSValue) bool {',
'    return audit.complete(engine, core);',
'}',
''
)
[IO.File]::WriteAllText($taskTarget,($taskLines -join "`n"),[Text.UTF8Encoding]::new($false))
@{source_index=$taskIndex;source_sha256=(Get-FileHash -LiteralPath $taskIndex).Hash;canonical_count=191;canonical_order=$taskNames;scope='Static canonical import/registration list only; actual native create APIs, no grammar evaluation or expected results generated';output=$taskTarget;output_sha256=(Get-FileHash -LiteralPath $taskTarget).Hash}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'native-highlight-index191-source-order-20261015.json') -Encoding utf8NoBOM

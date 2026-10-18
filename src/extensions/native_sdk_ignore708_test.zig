//! No expected Source JSON authored. Genuine original replay remains separate.
const std=@import("std");
const em=@import("engine.zig");
const supplier=@import("native_sdk_ignore708.zig");
const c=em.c;
test "private consumed ignore708 actual gitwildmatch parent cache live methods and GC" {
    const engine=try em.Engine.init(std.testing.allocator,.{}); defer engine.deinit();
    var env:std.process.Environ.Map=.init(std.testing.allocator); defer env.deinit();
    try @import("native_process.zig").install(engine,std.testing.io,&env,&.{"private-ignore708-controls"});
    const factory=try supplier.createDefault(engine); defer engine.freeValue(factory);
    const again=try supplier.createDefault(engine); defer engine.freeValue(again);
    try std.testing.expect(c.JS_IsFunction(engine.context,factory)); try std.testing.expect(!c.JS_IsConstructor(engine.context,factory)); try std.testing.expect(c.JS_IsStrictEqual(engine.context,factory,again));
    try std.testing.expect(!engine.native_module_values.contains("ignore"));
    const root=c.JS_GetGlobalObject(engine.context); defer engine.freeValue(root);
    if(c.JS_DefinePropertyValueStr(engine.context,root,"privateIgnore708",c.JS_DupValue(engine.context,factory),c.JS_PROP_C_W_E)<0)return error.JavaScriptException;
    const module=try engine.evalModule(@embedFile("fixtures/sdk-ignore708-consumed.input.txt") ++
        \\const rows=runIgnore708ConsumedCases(privateIgnore708),get=id=>rows.find(row=>row.id===id).value;
        \\if(rows.length!==246||new Set(rows.map(row=>row.id)).size!==246)throw Error('authored original caller count');
        \\if(!get('basic/path/0').ignored||get('basic/path/1').ignored||!get('parent-blocked/path/2').ignored||get('parent-reincluded/path/2').ignored)throw Error('real negation and parent exclusion');
        \\if(get('directory/path/0').ignored||!get('directory/path/1').ignored||get('literal-not-minimatch/path/0').ignored||!get('literal-not-minimatch/path/2').ignored)throw Error('directory semantics and actual gitignore grammar');
        \\if(!get('literal-escapes/path/5').ignored||get('literal-escapes/path/6').ignored)throw Error('escaped d is literal, not regexp digit');
        \\if(!get('cache-invalidation').unchanged||!get('cache-invalidation').changed||!get('cache-invalidation').inherited||get('cache-invalidation').child)throw Error('actual parent cache and invalidation');
        \\if(!get('live-ignores-receiver').raw||!get('live-add-receiver').same)throw Error('ordinary receiver and raw return');
        \\for(const kind of ['tag','pattern','forEach','indexOf','regex-test'])if(!get('raw-'+kind))throw Error('raw event identity '+kind);
        \\if(get('raw-cached-regex-second-read').reads!==2||!get('raw-cached-regex-second-read').raw)throw Error('live regex cache second read');
        \\globalThis.retainedIgnore708=privateIgnore708().add(['*.log','!keep.log']);
    ,"private-ignore708-controls.mjs"); defer engine.freeValue(module);
    c.JS_RunGC(engine.runtime);
    const result=try engine.eval("if(!retainedIgnore708.ignores('x.log')||retainedIgnore708.ignores('keep.log'))throw Error('retained matcher rules');delete globalThis.retainedIgnore708;delete globalThis.privateIgnore708;","private-ignore708-gc.js",c.JS_EVAL_TYPE_GLOBAL); defer engine.freeValue(result);
}

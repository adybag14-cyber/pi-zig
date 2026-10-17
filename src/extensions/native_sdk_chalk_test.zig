//! Source-only semantic controls. Full primary observation equality awaits an
//! authorized genuine capture; no expected Source JSON has been authored.
const std = @import("std");
const em = @import("engine.zig");
const c = em.c;
test "private consumed Chalk6 actual callable yellow ANSI level and raw-error controls" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator); defer environment.deinit();
    try environment.put("FORCE_COLOR", "0");
    try @import("native_process.zig").install(engine, std.testing.io, &environment, &.{"sdk-chalk6-control"});
    try @import("native_node_os.zig").install(engine);
    const chalk = try @import("native_sdk_chalk.zig").createDefault(engine); defer engine.freeValue(chalk);
    const again = try @import("native_sdk_chalk.zig").createDefault(engine); defer engine.freeValue(again);
    try std.testing.expect(c.JS_IsFunction(engine.context, chalk));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, chalk, again));
    try std.testing.expect(!engine.native_module_values.contains("chalk"));
    const root = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(root);
    if (c.JS_DefinePropertyValueStr(engine.context, root, "privateChalk", c.JS_DupValue(engine.context, chalk), c.JS_PROP_C_W_E) < 0) return @import("native_js_values.zig").capture(engine);
    const module = try engine.evalModule(@embedFile("fixtures/sdk-chalk6-consumed.input.txt") ++
        \\const rows=runChalkConsumedCases(privateChalk);
        \\if(rows.length!==86||new Set(rows.map(row=>row.id)).size!==86)throw Error('authored consumed observation count');
        \\const get=id=>rows.find(row=>row.id===id).value;
        \\if(privateChalk.level!==0||get('style/1/plain')!=='\x1b[33mwarning\x1b[39m'||get('style/0/plain')!=='warning')throw Error('actual consumed ANSI/no-color branch');
        \\if(!get('factory-option-raw-throw').raw||!get('raw-symbol-level-getter').raw||!get('disabled-still-coerces').raw)throw Error('raw error/coercion boundary');
        \\if(get('factory-option-read-order').trace.length!==4||get('factory-live-final-value').reads!==4)throw Error('actual live option evaluation');
        \\if(get('descriptors').styleFlags.configurable||get('descriptors').styleFlags.writable||get('descriptors').styleFlags.enumerable)throw Error('cached actual getter descriptor');
        \\globalThis.retainedChalkBuilder=privateChalk.constructor({level:1}).yellow;
    , "private-chalk6-controls.mjs"); defer engine.freeValue(module);
    c.JS_RunGC(engine.runtime);
    const retained = try engine.eval("if(retainedChalkBuilder('x')!=='\\x1b[33mx\\x1b[39m')throw Error('retained actual captures');delete globalThis.retainedChalkBuilder;delete globalThis.privateChalk;", "private-chalk6-gc.js", c.JS_EVAL_TYPE_GLOBAL); defer engine.freeValue(retained);
}

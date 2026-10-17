//! Actual patched-script compile/run controls; no unpatched-CJS/body-validator claim.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const script = @import("native_node_commonjs_script.zig");
fn truth(s: *v.Scope, source: []const u8) !void {
    const result = try s.own(try s.engine.eval(source, "owned-script-observer.js", c.JS_EVAL_TYPE_GLOBAL));
    try std.testing.expect(c.JS_ToBool(s.engine.context, result) == 1);
}
test "CommonJS patched script compile only precedes arbitrary actual script execution" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    const prepared = try script.prepare(engine, try s.text("globalThis.ownedScriptExecutions=(globalThis.ownedScriptExecutions||0)+1;41;"), try s.text("C:/owned/physical-script.cjs"));
    defer prepared.deinit();
    try truth(&s, "globalThis.ownedScriptExecutions===undefined");
    c.JS_RunGC(engine.runtime);
    const result = try s.own(try script.run(&prepared));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, result, c.JS_NewInt32(engine.context, 41)));
    try truth(&s, "ownedScriptExecutions===1");
}
test "CommonJS patched script returns a real five parameter VM function with arbitrary valid body grammar" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    const code = "(function(exports,require,module,__filename,__dirname){class Box{#value=5;get(){return this.#value}};const obj={...{a:2}};function* seq(){yield 3};exports.value=new Box().get()+obj.a+[...seq()][0];exports.thisSame=this===exports;exports.moduleSame=module.exports===exports;exports.file=__filename;exports.dir=__dirname;exports.required=require('owned');return 47;})";
    const prepared = try script.prepare(engine, try s.text(code), try s.text("C:/owned/arbitrary-grammar.cjs"));
    defer prepared.deinit();
    const function = try s.own(try script.run(&prepared));
    try std.testing.expect(c.JS_IsFunction(engine.context, function));
    const fixture = try s.own(try engine.eval("({exports:{},require:function(id){return id+':actual'}})", "owned-script-fixture.js", c.JS_EVAL_TYPE_GLOBAL));
    const exports = try s.get(fixture, "exports");
    const result = try s.call(function, exports, &.{ exports, try s.get(fixture, "require"), fixture, try s.text("C:/owned/arbitrary-grammar.cjs"), try s.text("C:/owned") });
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, result, c.JS_NewInt32(engine.context, 47)));
    const serialized = try engine.stringify(exports); defer engine.gpa.free(serialized);
    try std.testing.expectEqualStrings("{\"value\":10,\"thisSame\":true,\"moduleSame\":true,\"file\":\"C:/owned/arbitrary-grammar.cjs\",\"dir\":\"C:/owned\",\"required\":\"owned:actual\"}", serialized);
}
test "CommonJS patched script syntax failure precedes body and retains physical filename" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    try std.testing.expectError(error.JavaScriptException, script.prepare(engine, try s.text("globalThis.ownedInvalidBody=true;const = ;"), try s.text("C:/owned/physical-invalid.cjs")));
    const reason = engine.captured_exception orelse return error.MissingScriptSyntaxReason;
    const stack = try engine.toString(try s.get(reason, "stack")); defer engine.gpa.free(stack);
    try std.testing.expect(std.mem.indexOf(u8, stack, "C:/owned/physical-invalid.cjs") != null);
    try truth(&s, "globalThis.ownedInvalidBody===undefined");
}
test "CommonJS patched script preserves raw completion and thrown object without Promise adoption" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    _ = try s.own(try engine.eval("globalThis.ownedRawPromise=Promise.resolve(53);globalThis.ownedRawReason={actual:true}", "owned-script-raw-fixture.js", c.JS_EVAL_TYPE_GLOBAL));
    const promise_script = try script.prepare(engine, try s.text("ownedRawPromise"), try s.text("C:/owned/raw-promise.cjs"));
    defer promise_script.deinit();
    const result = try s.own(try script.run(&promise_script));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, result, try s.global("ownedRawPromise")));
    const throwing = try script.prepare(engine, try s.text("throw ownedRawReason"), try s.text("C:/owned/raw-throw.cjs"));
    defer throwing.deinit();
    try std.testing.expectError(error.JavaScriptException, script.run(&throwing));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, engine.captured_exception.?, try s.global("ownedRawReason")));
}

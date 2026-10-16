//! Actual shared graph and Source replay entry point. No stand-in compiler.
const std = @import("std");
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const c = js.c;
fn gc(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = em.Engine.fromContext(context.?);
    c.JS_RunGC(e.runtime);
    return c.pi_js_undefined();
}
fn readBefore(e: *em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: @import("extensions/native_typebox_operators_runtime.zig").Scope = .{ .engine = e };
    defer s.deinit();
    return c.JS_DupValue(e.context, try @import("extensions/native_typebox_operators_runtime.zig").get(&s, roots[0], "m0_Before"));
}
fn lexicalOrderControl(e: *em.Engine) !void {
    const rt = @import("extensions/native_typebox_operators_runtime.zig");
    var scope: rt.Scope = .{ .engine = e };
    defer scope.deinit();
    const env = try rt.environment(&scope, c.pi_js_null());
    try rt.declare(&scope, env, "m0_Before");
    const global = try scope.own(c.JS_GetGlobalObject(e.context));
    try scope.put(global, "nativeTypeBoxReadBefore", try scope.own(try @import("extensions/native_node_function.zig").create(e, "readBefore", 0, readBefore, &.{env})));
    const pending = try scope.own(try e.evalModule(
        \\let guest,native;try{Before}catch(error){guest={reference:error instanceof ReferenceError,name:error.name}}const Before=1;try{nativeTypeBoxReadBefore()}catch(error){native={reference:error instanceof ReferenceError,name:error.name}}if(JSON.stringify(guest)!==JSON.stringify(native)||!native?.reference)throw Error(JSON.stringify({scope:'actual guest and native module TDZ',guest,native}));export const pass=true;
    , "actual-typebox-native-lexical-tdz.mjs"));
    _ = try scope.own(try e.awaitValue(pending));
    try rt.bind(&scope, env, "m0_Before", c.JS_NewInt32(e.context, 1));
    const initialized = try scope.own(try e.evalModule("if(nativeTypeBoxReadBefore()!==1)throw Error('native module lexical initialization');export const pass=true;", "actual-typebox-native-lexical-initialized.mjs"));
    _ = try scope.own(try e.awaitValue(initialized));
}
pub fn graph(e: *em.Engine) !c.JSValue {
    return @import("extensions/native_typebox_production_graph.zig").create(e) catch |err| {
        std.debug.print("Actual shared TypeBox graph: {s}\n", .{e.last_error orelse "no diagnostic"});
        return err;
    };
}
pub fn replay(e: *em.Engine, actual: c.JSValue, source: c.JSValue) !void {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const global = try s.own(c.JS_GetGlobalObject(e.context));
    try s.put(global, "gc", try s.own(try e.checked(c.JS_NewCFunction(e.context, gc, "gc", 0))));
    try s.put(global, "actualSchemaType", try s.get(actual, "Type"));
    try s.put(global, "actualSchemaSystem", actual);
    try s.put(global, "actualSchemaCompiler", try s.get(actual, "Compiler"));
    try s.put(global, "typeboxCompileProductionSource", source);
    const pending = try s.own(try e.evalModule(@embedFile("extensions/fixtures/typebox-compile-production.input.mjs") ++
        \\const expected=typeboxCompileProductionSource.rows,actual=typeboxCompileProductionObservation.rows;if(expected.length!==actual.length)throw Error(JSON.stringify({scope:'actual TypeBox Compile',expected:expected.length,actual:actual.length}));for(let index=0;index<expected.length;index++){if(JSON.stringify(expected[index])!==JSON.stringify(actual[index]))throw Error(JSON.stringify({index,expected:expected[index],actual:actual[index]}))}export const pass=true;
    , "actual-typebox-compile-production.mjs"));
    _ = try s.own(try e.awaitValue(pending));
}
test "actual TypeBox Compile Validator matches complete genuine Source80" {
    const e = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer e.deinit();
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const bytes = @embedFile("extensions/fixtures/typebox-compile-production.json");
    const source = try s.own(try e.checked(c.JS_ParseJSON(e.context, bytes.ptr, bytes.len, "genuine-typebox-compile-source80.json")));
    const actual = try s.own(try graph(e));
    replay(e, actual, source) catch |err| {
        std.debug.print("Actual TypeBox Source80 replay: {s}\n", .{e.last_error orelse "no diagnostic"});
        return err;
    };
    std.debug.print("TYPEBOX_COMPILE_SOURCE_PARITY cases=80 actual_shared_graph=true native_ir=true full_HOST_GPA=false C_malloc_exhaustive=false\n", .{});
}
test "actual provider schemas Partial and Memory match genuine Source52 on shared compiler graph" {
    const e = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer e.deinit();
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const bytes = @embedFile("extensions/fixtures/ai-model-schemas-partial-4954.json");
    const source = try s.own(try e.checked(c.JS_ParseJSON(e.context, bytes.ptr, bytes.len, "genuine-typebox-schema-source52.json")));
    const actual = try s.own(try graph(e));
    @import("native_ai_model_schemas_partial_test.zig").replay(e, try s.get(actual, "Type"), actual, try s.get(actual, "Schemas"), try s.get(actual, "Compiler"), source) catch |err| {
        std.debug.print("Actual TypeBox Source52 replay: {s}\n", .{e.last_error orelse "no diagnostic"});
        return err;
    };
    std.debug.print("TYPEBOX_PROVIDER_SCHEMA_SOURCE_PARITY cases=52 actual_shared_graph=true full_HOST_GPA=false C_malloc_exhaustive=false\n", .{});
}
test "actual TypeBox generic operators match complete genuine Source396 on shared compiler graph" {
    const e = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer e.deinit();
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    try lexicalOrderControl(e);
    const bytes = @embedFile("extensions/fixtures/typebox-operators-production.expected.json");
    const source = try s.own(try e.checked(c.JS_ParseJSON(e.context, bytes.ptr, bytes.len, "genuine-typebox-operators-source396.json")));
    const actual = try s.own(try graph(e));
    const global = try s.own(c.JS_GetGlobalObject(e.context));
    try s.put(global, "gc", try s.own(try e.checked(c.JS_NewCFunction(e.context, gc, "gc", 0))));
    try s.put(global, "TypeBoxOperatorGraph", actual);
    try s.put(global, "TypeBoxOperatorSource", source);
    const pending = try s.own(try e.evalModule(@embedFile("extensions/fixtures/typebox-operators-production.input.txt") ++
        \\const expected=TypeBoxOperatorSource.rows,actual=TypeBoxOperatorRows;if(TypeBoxOperatorSource.version!=='1.3.27'||TypeBoxOperatorSource.cases!==396||expected.length!==396||actual.length!==396)throw Error('actual TypeBox operator Source396 scope');for(let index=0;index<396;index++){if(JSON.stringify(expected[index])!==JSON.stringify(actual[index]))throw Error(JSON.stringify({scope:'actual shared TypeBox operators',index,expected:expected[index],actual:actual[index]}))}export const pass=true;
    , "actual-typebox-operators-source396-shared.mjs"));
    _ = try s.own(try e.awaitValue(pending));
    std.debug.print("TYPEBOX_OPERATOR_SOURCE_PARITY cases=396 actual_shared_graph=true full_HOST_GPA=false C_malloc_exhaustive=false\n", .{});
}

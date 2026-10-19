//! ECMAScript template literal controls for the actual linked compiler.
//! Untagged templates eagerly apply intrinsic ToString; tagged substitutions
//! remain raw. The oracle is the original Node/V8 language contract and
//! ECMA-262 2026 13.2.8.6, not the prior mutable-concat compiler lowering.
const std = @import("std");
const v = @import("extensions/native_public_values.zig");
const c = v.c;
const Engine = v.em.Engine;

fn evaluate(engine: *Engine, source: []const u8) !c.JSValue {
    return engine.eval(source, "actual-template-literal.js", c.JS_EVAL_TYPE_GLOBAL);
}
fn run(engine: *Engine, source: []const u8) !void { engine.freeValue(try evaluate(engine, source)); }
fn check(engine: *Engine, source: []const u8) !void {
    const value = try evaluate(engine, source); defer engine.freeValue(value);
    try std.testing.expect(c.JS_IsBool(value));
    try std.testing.expect(c.JS_ToBool(engine.context, value) == 1);
}
fn raw(engine: *Engine, source: []const u8, flags: c_int) !c.JSValue {
    const text = try engine.gpa.dupeZ(u8, source); defer engine.gpa.free(text);
    return c.JS_Eval(engine.context, text.ptr, source.len, "actual-template-literal.js", flags);
}
fn jobs(engine: *Engine) !void {
    var count: usize = 0;
    while (c.JS_IsJobPending(engine.runtime)) {
        if (count == 16) return error.TemplateJobLimit;
        count += 1;
        var context: ?*c.JSContext = null;
        try std.testing.expect(c.JS_ExecutePendingJob(engine.runtime, &context) > 0);
        try std.testing.expect(!c.JS_HasException(engine.context));
    }
    engine.finishJob();
}

test "VM template literal intrinsic interpolation ignores mutable String and concat" {
    const engine = try Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    try check(engine,
        \\(()=>{const OriginalString=String;const descriptor=Object.getOwnPropertyDescriptor(OriginalString.prototype,"concat");let hits=0;
        \\Object.defineProperty(OriginalString.prototype,"concat",{configurable:true,get(){hits++;throw new Error("concat must not be read")}});
        \\globalThis.String=function(){throw new Error("global String must not be called")};
        \\try{return `a${42}b${null}c`==="a42bnullc"&&`plain`==="plain"&&hits===0}
        \\finally{globalThis.String=OriginalString;Object.defineProperty(OriginalString.prototype,"concat",descriptor)}})()
    );
}
test "VM template literal converts each substitution with string hint before the next expression" {
    const engine = try Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    try check(engine,
        \\(()=>{const trace=[];function item(name,value){trace.push("expr:"+name);return {[Symbol.toPrimitive](hint){trace.push(name+":"+hint);return value}}}
        \\const result=`head${item("a",17)}middle${item("b",23n)}tail`;
        \\return result==="head17middle23tail"&&trace.join("|")==="expr:a|a:string|expr:b|b:string"})()
    );
}
test "VM template literal observes ordinary ToPrimitive fallback once before later work" {
    const engine = try Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    try check(engine,
        \\(()=>{const trace=[];const value={get [Symbol.toPrimitive](){trace.push("exotic");return undefined},
        \\get toString(){trace.push("get:string");return function(){trace.push("call:string");return {}}},
        \\get valueOf(){trace.push("get:value");return function(){trace.push("call:value");return "converted"}}};
        \\const result=`${value}${(trace.push("later"),"done")}`;
        \\return result==="converteddone"&&trace.join("|")==="exotic|get:string|call:string|get:value|call:value|later"})()
    );
}
test "VM template literal ordinary conversion throw preserves identity and skips later substitutions" {
    const engine = try Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    try check(engine,
        \\(()=>{const reason={};let later=0;try{`before${{toString(){throw reason}}}${++later}`}
        \\catch(error){return error===reason&&later===0}return false})()
    );
}
test "VM template literal rejects Symbol conversion before a later expression" {
    const engine = try Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    try check(engine,
        \\(()=>{let caught=0,later=0;const symbol=Symbol("s");for(const value of [symbol,Object(symbol)]){try{`${value}${++later}`}
        \\catch(error){if(error instanceof TypeError)caught++}}return caught===2&&later===0})()
    );
}
test "VM template literal keeps cooked empty multiline wide and nested results" {
    const engine = try Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    try check(engine,
        \\(()=>{let current=1;const changed={toString(){current=7;return "a"}};
        \\return ``===""&&`${undefined}${null}${true}${-0}${23n}`==="undefinednulltrue023"&&
        \\`a\n\u03bb${"X"}\u{1F600}`==="a\n\u03bbX\u{1F600}"&&
        \\`${changed}${`${current}`}`==="a7"})()
    );
}
test "VM template literal conversions bracket an actual Await in source order" {
    const engine = try Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    try run(engine,
        \\globalThis.templateTrace=[];globalThis.templateGate=new Promise(resolve=>globalThis.templateResolve=resolve);
        \\globalThis.templatePending=(async()=>`a${(templateTrace.push("first"),{toString(){templateTrace.push("first:string");return "A"}})}b${await templateGate}c${(templateTrace.push("last"),{toString(){templateTrace.push("last:string");return "C"}})}`)();
    );
    const pending = try evaluate(engine, "templatePending"); defer engine.freeValue(pending);
    c.JS_PromiseMarkAsHandled(engine.context, pending);
    try check(engine, "templateTrace.join('|')==='first|first:string'");
    try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(engine.context, pending));
    try run(engine, "templateResolve({toString(){templateTrace.push('middle:string');return 'B'}});");
    try jobs(engine);
    try check(engine, "templateTrace.join('|')==='first|first:string|middle:string|last|last:string'");
    try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, c.JS_PromiseState(engine.context, pending));
    const result = c.JS_PromiseResult(engine.context, pending); defer engine.freeValue(result);
    const expected = try engine.checked(c.JS_NewString(engine.context, "aAbBcC")); defer engine.freeValue(expected);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, result, expected));
}
test "VM template literal early conversion rejection prevents a later Await expression" {
    const engine = try Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    try run(engine,
        \\globalThis.templateReason={};globalThis.templateLaterCount=0;
        \\globalThis.templatePending=(async()=>`${{toString(){throw templateReason}}}${await (++templateLaterCount)}`)();
    );
    const pending = try evaluate(engine, "templatePending"); defer engine.freeValue(pending);
    c.JS_PromiseMarkAsHandled(engine.context, pending);
    try std.testing.expectEqual(c.JS_PROMISE_REJECTED, c.JS_PromiseState(engine.context, pending));
    const reason = c.JS_PromiseResult(engine.context, pending); defer engine.freeValue(reason);
    const expected = try evaluate(engine, "templateReason"); defer engine.freeValue(expected);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, expected));
    try check(engine, "templateLaterCount===0");
    try jobs(engine);
}
test "VM template literal tagged calls retain raw values receiver and cached frozen template identity" {
    const engine = try Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    try check(engine,
        \\(()=>{let conversions=0;const raw={toString(){conversions++;throw new Error("raw")}};const symbol=Symbol("s");let first;
        \\const receiver={tag(strings,a,b){if(this!==receiver||a!==raw||b!==symbol)return false;
        \\if(!Object.isFrozen(strings)||!Object.isFrozen(strings.raw)||strings[0]!=="a"||strings[1]!=="b"||strings[2]!=="c")return false;
        \\if(first&&first!==strings)return false;first=strings;return true}};
        \\function site(){return receiver.tag`a${raw}b${symbol}c`}
        \\return site()&&site()&&conversions===0})()
    );
}
test "VM template literal tagged invalid escapes preserve raw strings and undefined cooked entries" {
    const engine = try Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    try check(engine,
        \\((strings)=>strings[0]===undefined&&strings.raw[0]==="\\unicode"&&Object.isFrozen(strings)&&Object.isFrozen(strings.raw))`\unicode`
    );
}
test "VM template literal untagged invalid escape remains a compile-time SyntaxError" {
    const engine = try Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const result = try raw(engine, "`\\unicode`", c.JS_EVAL_TYPE_GLOBAL);
    try std.testing.expect(c.JS_IsException(result));
    const reason = c.JS_GetException(engine.context); defer engine.freeValue(reason);
    const constructor = try evaluate(engine, "SyntaxError"); defer engine.freeValue(constructor);
    try std.testing.expect(c.JS_IsInstanceOf(engine.context, reason, constructor) == 1);
}

const Cleanup = enum { none, ordinary, flagged, native_oom };
const Probe = struct {
    engine: *Engine,
    class_id: c.JSClassID = 0,
    made: bool = false,
    retired: u32 = 0,
    later: u32 = 0,
    caught: u32 = 0,
    cleanup: Cleanup = .none,
    cleanup_reason: c.JSValue = c.pi_js_undefined(),
    original: c.JSValue = c.pi_js_undefined(),
    body_reason: c.JSValue = c.pi_js_undefined(),
    fn deinit(self: *Probe) void {
        self.cleanup = .none;
        self.engine.freeValue(self.cleanup_reason); self.engine.freeValue(self.original); self.engine.freeValue(self.body_reason);
        self.engine.deinit(); active = null;
    }
};
var active: ?*Probe = null;
fn finalize(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const p: *Probe = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    p.retired += 1;
    switch (p.cleanup) {
        .none => {},
        .ordinary, .flagged => { _ = c.JS_Throw(p.engine.context, c.JS_DupValue(p.engine.context, p.cleanup_reason)); },
        .native_oom => {
            _ = p.engine.throwNativeOutOfMemoryFatal();
            const reason = c.JS_GetException(p.engine.context);
            p.cleanup_reason = c.JS_DupValue(p.engine.context, reason);
            _ = c.JS_Throw(p.engine.context, reason);
        },
    }
}
fn make(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const p = active.?;
    if (p.made) return c.JS_ThrowInternalError(context, "Template control needs one holder");
    const value = c.JS_NewObjectClass(context, p.class_id);
    if (!c.JS_IsException(value)) { p.made = true; _ = c.JS_SetOpaque(value, p); }
    return value;
}
fn later(_: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const p = active.?; p.later += 1; return c.JS_NewInt32(p.engine.context, @intCast(p.retired));
}
fn caught(_: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    active.?.caught += 1; return c.pi_js_undefined();
}
fn fatal(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const p = active.?;
    _ = p.engine.throwNativeOutOfMemoryFatal();
    const reason = c.JS_GetException(context);
    p.body_reason = c.JS_DupValue(context, reason);
    return c.JS_Throw(context, reason);
}
fn install(s: *v.Scope) !void {
    const global = try v.global(s, "globalThis");
    inline for (.{ .{ "templateMake", make }, .{ "templateLater", later }, .{ "templateCaught", caught }, .{ "templateFatal", fatal } }) |entry| {
        const function = try v.own(s, try s.engine.checked(c.JS_NewCFunction(s.engine.context, entry[1], entry[0], 0)));
        try v.put(s, global, entry[0], function);
    }
    try v.put(s, global, "templateOriginal", active.?.original);
}
fn setup(p: *Probe) !void {
    active = p;
    _ = c.JS_NewClassID(p.engine.runtime, &p.class_id);
    const definition: c.JSClassDef = .{ .class_name = "Actual template interpolation operand holder", .finalizer = finalize };
    if (c.JS_NewClass(p.engine.runtime, p.class_id, &definition) < 0) return error.OutOfMemory;
    p.original = try p.engine.checked(c.JS_NewError(p.engine.context));
    if (p.cleanup == .ordinary or p.cleanup == .flagged) {
        p.cleanup_reason = try p.engine.checked(c.JS_NewError(p.engine.context));
        if (p.cleanup == .flagged) c.JS_SetUncatchableError(p.engine.context, p.cleanup_reason);
    }
    var scope: v.Scope = .{ .engine = p.engine };
    try v.owned.finishVoid(&scope, install(&scope));
}
const successful_operand =
    \\function templateOperand(){const value=templateMake();value.toString=function(){return "X"};return value}
;
const ordinary_operand =
    \\function templateOperand(){const value=templateMake();value.toString=function(){throw templateOriginal};return value}
;
const fatal_operand =
    \\function templateOperand(){const value=templateMake();value.toString=function(){return templateFatal()};return value}
;
const interpolate =
    \\(()=>{try{return `${templateOperand()}${templateLater()}`}catch(error){templateCaught();return error===templateOriginal}})()
;
fn expectedFatal(p: *Probe, expected: c.JSValue) !void {
    const reason = c.JS_GetException(p.engine.context); defer p.engine.freeValue(reason);
    try std.testing.expect(c.JS_IsStrictEqual(p.engine.context, reason, expected));
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expectEqual(@as(u32, 1), p.retired);
    try std.testing.expectEqual(@as(u32, 0), p.later);
    try std.testing.expectEqual(@as(u32, 0), p.caught);
}

test "VM template literal retires the sole converted operand before the next expression" {
    var p: Probe = .{ .engine = try Engine.init(std.testing.allocator, .{}) }; defer p.deinit(); try setup(&p);
    try run(p.engine, successful_operand);
    const value = try evaluate(p.engine, interpolate); defer p.engine.freeValue(value);
    const expected = try p.engine.checked(c.JS_NewString(p.engine.context, "X1")); defer p.engine.freeValue(expected);
    try std.testing.expect(c.JS_IsStrictEqual(p.engine.context, value, expected));
    try std.testing.expectEqual(@as(u32, 1), p.retired);
    try std.testing.expectEqual(@as(u32, 1), p.later);
}
test "VM template literal operand retirement native fatal preempts an ordinary conversion throw" {
    var p: Probe = .{ .engine = try Engine.init(std.testing.allocator, .{}), .cleanup = .native_oom }; defer p.deinit(); try setup(&p);
    try run(p.engine, ordinary_operand);
    const generation = p.engine.native_allocation_generation;
    const value = try raw(p.engine, interpolate, c.JS_EVAL_TYPE_GLOBAL);
    try std.testing.expect(c.JS_IsException(value));
    try expectedFatal(&p, p.cleanup_reason);
    try std.testing.expectEqual(generation +% 1, p.engine.native_allocation_generation);
    try std.testing.expect(c.pi_js_native_allocation_error_generation(p.cleanup_reason) != 0);
}
test "VM template literal conversion native fatal survives a later flagged cleanup event" {
    var p: Probe = .{ .engine = try Engine.init(std.testing.allocator, .{}), .cleanup = .flagged }; defer p.deinit(); try setup(&p);
    try run(p.engine, fatal_operand);
    const generation = p.engine.native_allocation_generation;
    const value = try raw(p.engine, interpolate, c.JS_EVAL_TYPE_GLOBAL);
    try std.testing.expect(c.JS_IsException(value));
    try expectedFatal(&p, p.body_reason);
    try std.testing.expect(!c.JS_IsStrictEqual(p.engine.context, p.body_reason, p.cleanup_reason));
    try std.testing.expectEqual(generation +% 1, p.engine.native_allocation_generation);
    try std.testing.expect(c.pi_js_native_allocation_error_generation(p.body_reason) != 0);
}
test "VM template literal successful conversion retirement fatal blocks later expression and guest catch" {
    var p: Probe = .{ .engine = try Engine.init(std.testing.allocator, .{}), .cleanup = .native_oom }; defer p.deinit(); try setup(&p);
    try run(p.engine, successful_operand);
    const generation = p.engine.native_allocation_generation;
    const value = try raw(p.engine, interpolate, c.JS_EVAL_TYPE_GLOBAL);
    try std.testing.expect(c.JS_IsException(value));
    try expectedFatal(&p, p.cleanup_reason);
    try std.testing.expectEqual(generation +% 1, p.engine.native_allocation_generation);
}
test "VM template literal preserves the original ordinary conversion throw through ordinary operand cleanup" {
    var p: Probe = .{ .engine = try Engine.init(std.testing.allocator, .{}), .cleanup = .ordinary }; defer p.deinit(); try setup(&p);
    try run(p.engine, ordinary_operand);
    try check(p.engine, interpolate);
    try std.testing.expectEqual(@as(u32, 1), p.retired);
    try std.testing.expectEqual(@as(u32, 0), p.later);
    try std.testing.expectEqual(@as(u32, 1), p.caught);
    try std.testing.expect(!c.JS_HasException(p.engine.context));
}
test "VM template literal current bytecode serializes and executes eager intrinsic interpolation" {
    const engine = try Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const source =
        \\(()=>{let value=1;return `a${{toString(){value=7;return "X"}}}b${value}`})()
    ;
    const compiled = try engine.checked(try raw(engine, source, c.JS_EVAL_TYPE_GLOBAL | c.JS_EVAL_FLAG_COMPILE_ONLY)); defer engine.freeValue(compiled);
    var length: usize = 0;
    const bytes = c.JS_WriteObject(engine.context, &length, compiled, c.JS_WRITE_OBJ_BYTECODE);
    if (bytes == null) return error.TemplateBytecodeWriteFailed;
    defer c.js_free(engine.context, bytes);
    try std.testing.expect(length > 5);
    try std.testing.expectEqual(@as(u8, 29), bytes[0]);
    const restored = try engine.checked(c.JS_ReadObject(engine.context, bytes, length, c.JS_READ_OBJ_BYTECODE)); defer engine.freeValue(restored);
    c.JS_RunGC(engine.runtime);
    const result = try engine.checked(c.JS_EvalFunction(engine.context, c.JS_DupValue(engine.context, restored))); defer engine.freeValue(result);
    const expected = try engine.checked(c.JS_NewString(engine.context, "aXb7")); defer engine.freeValue(expected);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, result, expected));
}
test "VM template literal old opcode version is rejected before bytecode consumption" {
    const engine = try Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const compiled = try engine.checked(try raw(engine, "`a${1}`", c.JS_EVAL_TYPE_GLOBAL | c.JS_EVAL_FLAG_COMPILE_ONLY)); defer engine.freeValue(compiled);
    var length: usize = 0;
    const bytes = c.JS_WriteObject(engine.context, &length, compiled, c.JS_WRITE_OBJ_BYTECODE);
    if (bytes == null) return error.TemplateBytecodeWriteFailed;
    defer c.js_free(engine.context, bytes);
    try std.testing.expect(length > 5);
    try std.testing.expectEqual(@as(u8, 29), bytes[0]);
    // Actual writer output, changing only its obsolete version discriminator.
    bytes[0] = 28;
    const rejected = c.JS_ReadObject(engine.context, bytes, length, c.JS_READ_OBJ_BYTECODE);
    try std.testing.expect(c.JS_IsException(rejected));
    const reason = c.JS_GetException(engine.context); defer engine.freeValue(reason);
    const message = try engine.checked(c.JS_GetPropertyStr(engine.context, reason, "message")); defer engine.freeValue(message);
    const expected = try engine.checked(c.JS_NewString(engine.context, "invalid version (28 expected=29)")); defer engine.freeValue(expected);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, message, expected));
}

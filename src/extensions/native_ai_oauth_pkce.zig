//! c268154c auth/oauth/pkce.ts: one genuine async declaration and one Await.
//! The VM owns the outer Promise and digest suspension. WebCrypto, encoder,
//! iterator, coercion and string hooks remain the actual live guest operations.
const x = @import("native_ai_auth_helper_values.zig");
const c = x.c;
const af = x.af;
const js = @import("native_js_values.zig");

pub fn create(engine: *x.em.Engine) !c.JSValue {
    try engine.checkNativeEntry();
    var invocation: x.em.Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&invocation);
    var scope: x.Scope = .{ .engine = engine };
    var o: x.Ops = .{ .s = &scope };
    return x.finishInvocation(engine, &invocation, x.owned.finishValue(&scope, createBody(&o)));
}
fn createBody(o: *x.Ops) !c.JSValue {
    const exports = try o.object();
    try o.put(exports, "generatePKCE", try o.own(try af.createResumable(o.s.engine, "generatePKCE", 0, generateBody, &.{})));
    return c.JS_DupValue(o.s.engine.context, exports);
}
/// Internal lexical calls enter the same genuine body. No Promise transport or
/// extra async wrapper is introduced around its Source Await.
pub fn generate(engine: *x.em.Engine) !c.JSValue {
    try engine.checkNativeEntry();
    var invocation: x.em.Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&invocation);
    var scope: x.Scope = .{ .engine = engine };
    var o: x.Ops = .{ .s = &scope };
    return x.finishInvocation(engine, &invocation, x.owned.finishValue(&scope, generateCall(&o)));
}
fn generateCall(o: *x.Ops) !c.JSValue {
    const function = try o.own(try af.createResumable(o.s.engine, "generatePKCE", 0, generateBody, &.{}));
    return c.JS_DupValue(o.s.engine.context, try o.call(function, c.pi_js_undefined(), &.{}));
}
fn generateBody(engine: *x.em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var scope: x.Scope = .{ .engine = engine };
    var o: x.Ops = .{ .s = &scope };
    return x.owned.finishAction(&scope, advance(&o, state, completion, input));
}
fn advance(o: *x.Ops, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) {
        try @import("native_async_body.zig").enterRejectedContinuation(o.s.engine);
        return .{ .thrown = c.JS_DupValue(o.s.engine.context, input) };
    }
    if (completion == .start) {
        const owner = try o.cell();
        af.replaceState(o.s.engine, state, c.JS_DupValue(o.s.engine.context, owner));
        const bytes = try o.own(try builtin(o.s.engine, "Uint8Array", &.{c.JS_NewInt32(o.s.engine.context, 32)}));
        try o.put(owner, "verifierBytes", bytes);
        try randomValues(o.s.engine, bytes);
        const verifier = try o.own(try encode(o.s.engine, bytes));
        try o.put(owner, "verifier", verifier);
        // Source evaluates the encoder before the later crypto.subtle read.
        const encoder = try o.own(try builtin(o.s.engine, "TextEncoder", &.{}));
        try o.put(owner, "encoder", encoder);
        const data = try o.own(try invokeValue(o.s.engine, encoder, "encode", &.{verifier}));
        try o.put(owner, "data", data);
        return .{ .awaited = try digestValue(o.s.engine, data) };
    }
    const challenge = try o.own(try challengeValue(o.s.engine, input));
    const result = try o.object();
    try o.put(result, "verifier", try o.get(state.*, "verifier"));
    try o.put(result, "challenge", challenge);
    return .{ .returned = c.JS_DupValue(o.s.engine.context, result) };
}

fn encode(engine: *x.em.Engine, bytes: c.JSValue) !c.JSValue {
    var scope: x.Scope = .{ .engine = engine };
    var o: x.Ops = .{ .s = &scope };
    return x.owned.finishValue(&scope, encodeBody(&o, bytes));
}
fn encodeBody(o: *x.Ops, bytes: c.JSValue) !c.JSValue {
    const iterator = try o.own(try iteratorRecord(o.s.engine, bytes));
    var pending = x.owned.Completion.initValue(o.s.engine, encodeLoop(o.s.engine, iterator));
    const selected = try pending.finishAction();
    if (selected == .thrown) {
        // IteratorClose is a Source operation. An ordinary close failure does
        // not replace the pending throw; a real native fatal still has priority.
        var close = x.owned.Completion.initVoid(o.s.engine, closeIterator(o.s.engine, iterator));
        const closed = close.finishAction() catch |err| {
            var fatal = x.owned.Completion.initAction(o.s.engine, @as(anyerror!af.Action, err));
            fatal.release(selected.thrown);
            return fatal.finishValue();
        };
        var original = x.owned.Completion.initAction(o.s.engine, selected);
        switch (closed) { .returned, .thrown => |value| original.release(value), .awaited => unreachable }
        return original.finishValue();
    }
    return switch (selected) { .returned => |value| value, else => unreachable };
}
fn iteratorRecord(engine: *x.em.Engine, bytes: c.JSValue) !c.JSValue {
    var scope: x.Scope = .{ .engine = engine };
    var o: x.Ops = .{ .s = &scope };
    return x.owned.finishValue(&scope, iteratorRecordBody(&o, bytes));
}
fn iteratorRecordBody(o: *x.Ops, bytes: c.JSValue) !c.JSValue {
    // JS_GetIterator retires Symbol.iterator's method before the next getter.
    const iterator = try o.own(try acquireIterator(o.s.engine, bytes));
    const next = try o.get(iterator, "next");
    const record = try o.cell();
    try o.put(record, "iterator", iterator);
    try o.put(record, "next", next);
    try o.put(record, "closed", c.pi_js_bool(o.s.engine.context, 1));
    try o.put(record, "binary", try o.text(""));
    return c.JS_DupValue(o.s.engine.context, record);
}
fn truth(engine: *x.em.Engine, value: c.JSValue, name: [*:0]const u8) !bool {
    var scope: x.Scope = .{ .engine = engine };
    var o: x.Ops = .{ .s = &scope };
    const result: anyerror!c.JSValue = if (o.get(value, name)) |v| c.pi_js_bool(engine.context, @intFromBool(o.truthy(v))) else |err| err;
    return c.JS_ToBool(engine.context, try x.owned.finishValue(&scope, result)) == 1;
}
fn nextByte(engine: *x.em.Engine, record: c.JSValue) !c.JSValue {
    var scope: x.Scope = .{ .engine = engine };
    var o: x.Ops = .{ .s = &scope };
    return x.owned.finishValue(&scope, nextByteBody(&o, record));
}
fn nextByteBody(o: *x.Ops, record: c.JSValue) !c.JSValue {
    try o.s.engine.checkNativeEntry();
    // IteratorStep/IteratorValue failures mark the record done and do not close.
    try o.put(record, "closed", c.pi_js_bool(o.s.engine.context, 1));
    const entry = try o.call(try o.get(record, "next"), try o.get(record, "iterator"), &.{});
    if (!c.JS_IsObject(entry)) return js.typeError(o.s.engine, "Iterator result is not an object");
    if (try truth(o.s.engine, entry, "done")) return c.pi_js_undefined();
    const value = try o.get(entry, "value");
    try o.put(record, "closed", c.pi_js_bool(o.s.engine.context, 0));
    return c.JS_DupValue(o.s.engine.context, value);
}
fn appendNext(engine: *x.em.Engine, record: c.JSValue) !bool {
    var scope: x.Scope = .{ .engine = engine };
    var o: x.Ops = .{ .s = &scope };
    return c.JS_ToBool(engine.context, try x.owned.finishValue(&scope, appendNextBody(&o, record))) == 1;
}
fn appendNextBody(o: *x.Ops, record: c.JSValue) !c.JSValue {
    // The IteratorStep result and done getter are retired before the Source body.
    const byte = try o.own(try nextByte(o.s.engine, record));
    if (try truth(o.s.engine, record, "closed")) return c.pi_js_bool(o.s.engine.context, 0);
    const string = try o.own(try charCodeValue(o.s.engine, byte));
    const combined = try o.binary(0, try o.get(record, "binary"), string);
    try o.put(record, "binary", combined);
    return c.pi_js_bool(o.s.engine.context, 1);
}
fn encodeLoop(engine: *x.em.Engine, record: c.JSValue) !c.JSValue {
    while (try appendNext(engine, record)) {}
    try retireIterator(engine, record);
    var scope: x.Scope = .{ .engine = engine };
    var o: x.Ops = .{ .s = &scope };
    const initial = try x.owned.finishValue(&scope, btoaBody(&o, record));
    const first = try replaceOwned(engine, initial, "\\+", "-");
    const second = try replaceOwned(engine, first, "/", "_");
    return replaceOwned(engine, second, "=", "");
}
fn btoaBody(o: *x.Ops, record: c.JSValue) !c.JSValue {
    return c.JS_DupValue(o.s.engine.context, try o.call(try o.global("btoa"), c.pi_js_undefined(), &.{try o.get(record, "binary")}));
}
fn replaceOwned(engine: *x.em.Engine, input: c.JSValue, pattern: []const u8, replacement: []const u8) !c.JSValue {
    var scope: x.Scope = .{ .engine = engine };
    var o: x.Ops = .{ .s = &scope };
    return x.owned.finishValue(&scope, replaceBody(&o, input, pattern, replacement));
}
fn replaceBody(o: *x.Ops, input: c.JSValue, pattern: []const u8, replacement: []const u8) !c.JSValue {
    const receiver = try o.own(input);
    const method = try o.get(receiver, "replace");
    const literal = try x.guest.construct(o.s, o.s.engine.intrinsic_regexp_constructor, &.{ try o.text(pattern), try o.text("g") });
    return c.JS_DupValue(o.s.engine.context, try o.call(method, receiver, &.{ literal, try o.text(replacement) }));
}
fn closeIterator(engine: *x.em.Engine, record: c.JSValue) !void {
    var scope: x.Scope = .{ .engine = engine };
    var o: x.Ops = .{ .s = &scope };
    return x.owned.finishVoid(&scope, closeIteratorBody(&o, record));
}
fn closeIteratorBody(o: *x.Ops, record: c.JSValue) !void {
    if (try truth(o.s.engine, record, "closed")) return;
    try o.put(record, "closed", c.pi_js_bool(o.s.engine.context, 1));
    const iterator = try o.get(record, "iterator");
    const method = try o.get(iterator, "return");
    if (x.nullish(method)) return;
    // Only the abrupt-body path enters this helper. IteratorClose with an
    // existing throw ignores a normal return value, including primitives.
    _ = try o.call(method, iterator, &.{});
}

fn builtin(engine: *x.em.Engine, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    var scope: x.Scope = .{ .engine = engine };
    var o: x.Ops = .{ .s = &scope };
    return x.owned.finishValue(&scope, builtinBody(&o, name, args));
}
fn builtinBody(o: *x.Ops, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    const constructor = try o.global(name);
    return c.JS_DupValue(o.s.engine.context, try x.guest.construct(o.s, constructor, args));
}
fn randomValues(engine: *x.em.Engine, bytes: c.JSValue) !void {
    var scope: x.Scope = .{ .engine = engine };
    var o: x.Ops = .{ .s = &scope };
    return x.owned.finishVoid(&scope, randomValuesBody(&o, bytes));
}
fn randomValuesBody(o: *x.Ops, bytes: c.JSValue) !void {
    _ = try o.invoke(try o.global("crypto"), "getRandomValues", &.{bytes});
}
fn invokeValue(engine: *x.em.Engine, receiver: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    var scope: x.Scope = .{ .engine = engine };
    var o: x.Ops = .{ .s = &scope };
    const result: anyerror!c.JSValue = if (o.invoke(receiver, name, args)) |value| c.JS_DupValue(engine.context, value) else |err| err;
    return x.owned.finishValue(&scope, result);
}
fn digestValue(engine: *x.em.Engine, data: c.JSValue) !c.JSValue {
    var scope: x.Scope = .{ .engine = engine };
    var o: x.Ops = .{ .s = &scope };
    return x.owned.finishValue(&scope, digestValueBody(&o, data));
}
fn digestValueBody(o: *x.Ops, data: c.JSValue) !c.JSValue {
    const subtle = try o.get(try o.global("crypto"), "subtle");
    const method = try o.get(subtle, "digest");
    return c.JS_DupValue(o.s.engine.context, try o.call(method, subtle, &.{ try o.text("SHA-256"), data }));
}
fn challengeValue(engine: *x.em.Engine, hash: c.JSValue) !c.JSValue {
    var scope: x.Scope = .{ .engine = engine };
    var o: x.Ops = .{ .s = &scope };
    return x.owned.finishValue(&scope, challengeValueBody(&o, hash));
}
fn challengeValueBody(o: *x.Ops, hash: c.JSValue) !c.JSValue {
    const bytes = try o.own(try builtin(o.s.engine, "Uint8Array", &.{hash}));
    return encode(o.s.engine, bytes);
}
fn retireIterator(engine: *x.em.Engine, record: c.JSValue) !void {
    var scope: x.Scope = .{ .engine = engine };
    var o: x.Ops = .{ .s = &scope };
    return x.owned.finishVoid(&scope, retireIteratorBody(&o, record));
}
fn retireIteratorBody(o: *x.Ops, record: c.JSValue) !void {
    try o.put(record, "iterator", c.pi_js_undefined());
    try o.put(record, "next", c.pi_js_undefined());
}

fn acquireIterator(engine: *x.em.Engine, bytes: c.JSValue) !c.JSValue {
    var scope: x.Scope = .{ .engine = engine };
    var o: x.Ops = .{ .s = &scope };
    return x.owned.finishValue(&scope, acquireIteratorBody(&o, bytes));
}
fn acquireIteratorBody(o: *x.Ops, bytes: c.JSValue) !c.JSValue {
    const symbol = try o.accept(c.JS_GetIteratorSymbol(o.s.engine.context));
    const method = try o.getKey(bytes, symbol);
    if (!c.JS_IsFunction(o.s.engine.context, method)) return js.typeError(o.s.engine, "value is not iterable");
    const iterator = try o.call(method, bytes, &.{});
    // JS_GetIterator2 validates before JS_GetIterator retires the method.
    if (!c.JS_IsObject(iterator)) return js.typeError(o.s.engine, "not an object");
    return c.JS_DupValue(o.s.engine.context, iterator);
}
fn charCodeValue(engine: *x.em.Engine, byte: c.JSValue) !c.JSValue {
    var scope: x.Scope = .{ .engine = engine };
    var o: x.Ops = .{ .s = &scope };
    return x.owned.finishValue(&scope, charCodeValueBody(&o, byte));
}
fn charCodeValueBody(o: *x.Ops, byte: c.JSValue) !c.JSValue {
    // OP_call_method retires String/fromCharCode before += coerces its result.
    return c.JS_DupValue(o.s.engine.context, try o.invoke(try o.global("String"), "fromCharCode", &.{byte}));
}

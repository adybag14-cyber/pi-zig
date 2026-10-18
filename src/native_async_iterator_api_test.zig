//! Genuine VM controls for the thin C iterator-acquisition export. No adapter.
const std = @import("std");
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
const c = em.c;
fn acquire(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.JS_PiGetAsyncIterator(context, if (argc > 0) argv[0] else c.pi_js_undefined());
}
fn install(engine: *em.Engine) !void {
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    const function = try engine.checked(c.JS_NewCFunction(engine.context, acquire, "nativeAcquire", 1));
    if (c.JS_DefinePropertyValueStr(engine.context, global, "nativeAcquire", function, c.JS_PROP_C_W_E) < 0) return js.capture(engine);
}
fn script(source: []const u8) !void {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    try install(engine);
    const pending = try engine.eval(source, "native-async-iterator-api-control.js", c.JS_EVAL_TYPE_GLOBAL); defer engine.freeValue(pending);
    const result = try engine.awaitValue(pending); defer engine.freeValue(result);
    try std.testing.expect(c.JS_ToBool(engine.context, result) == 1);
}
test "native async iterator API actual async override identity receiver and lazy next" {
    try script(
        \\(async()=>{let sync=0,reads=0,receiver=false;const iterator={get next(){reads++;return async()=>({done:true})}};const input={get [Symbol.asyncIterator](){return function(){receiver=this===input;return iterator}},get [Symbol.iterator](){sync++;throw Error('sync fallback')}};const actual=nativeAcquire(input);if(actual!==iterator||!receiver||sync||reads)throw Error('async acquisition');await actual.next();if(reads!==1)throw Error('premature next lookup');return true})()
    );
}
test "native async iterator API genuine VM for-await array string thenable fallback" {
    try script(
        \\(async()=>{async function consume(input){const rows=[];for await(const item of input)rows.push(item);return rows}const value=[Promise.resolve(1),{then(resolve){resolve(2)}},3];if(JSON.stringify(await consume(nativeAcquire(value)))!==JSON.stringify(await consume(value)))throw Error('array for-await');if(JSON.stringify(await consume(nativeAcquire('a\u{1F642}b')))!==JSON.stringify(await consume('a\u{1F642}b')))throw Error('string code points');return true})()
    );
}
test "native async iterator API acquisition ignores mutable global Symbol binding" {
    try script(
        \\(async()=>{const original=globalThis.Symbol;const input=[Promise.resolve(9)];try{globalThis.Symbol=null;const result=await nativeAcquire(input).next();if(result.done||result.value!==9)throw Error('global Symbol consulted');return true}finally{globalThis.Symbol=original}})()
    );
}
test "native async iterator API captures synchronous next once and borrows input" {
    try script(
        \\(async()=>{let reads=0,calls=0,receiver=true;const input={owned:42,[Symbol.asyncIterator]:null,[Symbol.iterator](){return this},get next(){reads++;return function(){receiver&&=this===input;return{done:calls++>0,value:Promise.resolve(7)}}}};const iterator=nativeAcquire(input);if(reads!==1||input.owned!==42)throw Error('acquisition snapshot');Object.defineProperty(input,'next',{value(){throw Error('reread')}});const first=await iterator.next(),second=await iterator.next();if(!receiver||reads!==1||first.value!==7||first.done||!second.done)throw Error('captured next');return true})()
    );
}
test "native async iterator API raw getter next and thenable rejection identities" {
    try script(
        \\(async()=>{const marker={owned:true};for(const symbol of [Symbol.asyncIterator,Symbol.iterator]){const input={get [symbol](){throw marker}};try{nativeAcquire(input);throw Error('accepted getter')}catch(error){if(error!==marker)throw error}}const sync={ [Symbol.iterator](){return this},next(){throw marker}};let pending;try{pending=nativeAcquire(sync).next()}catch{throw Error('sync throw instead of Promise')}try{await pending;throw Error('accepted next')}catch(error){if(error!==marker)throw error}const rejected={ [Symbol.iterator](){return this},next(){return{done:false,value:{get then(){throw marker}}}}};try{await nativeAcquire(rejected).next();throw Error('accepted then')}catch(error){if(error!==marker)throw error}return true})()
    );
}
test "native async iterator API real return throw and language break closing" {
    try script(
        \\(async()=>{const marker={owned:true};let returns=0,throws=0,receiver=true;const input={ [Symbol.iterator](){return this},next(){return{done:false,value:1}},get return(){return function(value){receiver&&=this===input;returns++;return{done:true,value:Promise.resolve(value)}}},get throw(){return function(value){receiver&&=this===input;throws++;return{done:false,value:Promise.resolve(value)}}}};const iterator=nativeAcquire(input);const a=await iterator.return(marker),b=await iterator.throw(marker);if(a.value!==marker||!a.done||b.value!==marker||b.done||returns!==1||throws!==1||!receiver)throw Error('delegated return/throw');for await(const item of nativeAcquire(input)){if(item!==1)throw Error('value');break}if(returns!==2)throw Error('language close');delete input.throw;try{await nativeAcquire(input).throw(marker);throw Error('accepted missing throw')}catch(error){if(!(error instanceof TypeError))throw error}if(returns!==3)throw Error('missing throw closes');return true})()
    );
}
test "native async iterator API invalid values and iterator results are actual VM errors" {
    try script(
        \\(async()=>{for(const input of [null,undefined,1,{}, {[Symbol.asyncIterator]:1}, {[Symbol.iterator](){return 1}}]){try{nativeAcquire(input);throw Error('accepted input')}catch(error){if(!(error instanceof TypeError))throw error}}const iterator=nativeAcquire({[Symbol.iterator](){return this},next(){return 1}});try{await iterator.next();throw Error('accepted result')}catch(error){if(!(error instanceof TypeError))throw error}return true})()
    );
}
test "native async iterator API preserves pending ordinary and fatal entry without getters" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const input = try engine.eval("globalThis.iteratorEntryReads=0;({get [Symbol.asyncIterator](){iteratorEntryReads++;throw Error('unexpected')}})", "iterator-entry-control.js", c.JS_EVAL_TYPE_GLOBAL); defer engine.freeValue(input);
    for ([_]bool{ false, true }) |fatal| {
        const reason = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(reason);
        if (fatal) c.JS_SetUncatchableError(engine.context, reason);
        try std.testing.expect(c.JS_IsUncatchableError(reason) == fatal);
        _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason));
        const result = c.JS_PiGetAsyncIterator(engine.context, input);
        try std.testing.expect(c.JS_IsException(result) and c.JS_HasException(engine.context));
        const actual = c.JS_GetException(engine.context); defer engine.freeValue(actual);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, actual));
        try std.testing.expect(c.JS_IsUncatchableError(actual) == fatal);
    }
    const reads = try engine.eval("iteratorEntryReads", "iterator-entry-count.js", c.JS_EVAL_TYPE_GLOBAL); defer engine.freeValue(reads);
    var count: i32 = -1; if (c.JS_ToInt32(engine.context, &count, reads) < 0) return js.capture(engine);
    try std.testing.expectEqual(@as(i32, 0), count);
}
test "native async iterator API same-runtime cross-context adapter realm" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const other = c.JS_NewContext(engine.runtime) orelse return error.OutOfMemory; defer c.JS_FreeContext(other);
    const input = try engine.eval("[1,2]", "iterator-realm-input.js", c.JS_EVAL_TYPE_GLOBAL); defer engine.freeValue(input);
    const first = try engine.checked(c.JS_PiGetAsyncIterator(engine.context, input)); defer engine.freeValue(first);
    const second = c.JS_PiGetAsyncIterator(other, input); defer c.JS_FreeValue(other, second);
    try std.testing.expect(!c.JS_IsException(second));
    const a = try engine.checked(c.JS_GetPrototype(engine.context, first)); defer engine.freeValue(a);
    const b = c.JS_GetPrototype(other, second); defer c.JS_FreeValue(other, b);
    try std.testing.expect(!c.JS_IsException(b) and !c.JS_IsStrictEqual(engine.context, a, b));
    const next = c.JS_GetPropertyStr(other, second, "next"); defer c.JS_FreeValue(other, next);
    const promise = c.JS_Call(other, next, second, 0, null); defer c.JS_FreeValue(other, promise);
    try std.testing.expect(!c.JS_IsException(promise));
    const settled = try engine.awaitValue(promise); defer engine.freeValue(settled);
    const value = try engine.checked(c.JS_GetPropertyStr(engine.context, settled, "value")); defer engine.freeValue(value);
    var actual: i32 = 0; if (c.JS_ToInt32(engine.context, &actual, value) < 0) return js.capture(engine);
    try std.testing.expectEqual(@as(i32, 1), actual);
}
var finalized: bool = false;
fn finalizer(_: ?*c.JSRuntime, _: c.JSValue) callconv(.c) void { finalized = true; }
fn selfIterator(context: ?*c.JSContext, receiver: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue { return c.JS_DupValue(context, receiver); }
fn doneNext(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const result = c.JS_NewObject(context);
    if (c.JS_IsException(result)) return result;
    if (c.JS_DefinePropertyValueStr(context, result, "done", c.pi_js_bool(context, 1), c.JS_PROP_C_W_E) < 0) {
        const reason = c.JS_GetException(context);
        c.JS_FreeValue(context, result);
        return c.JS_Throw(context, reason);
    }
    return result;
}
test "native async iterator API adapter owns sync iterator until released and GC" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    finalized = false;
    var class: c.JSClassID = 0; _ = c.JS_NewClassID(engine.runtime, &class);
    const definition: c.JSClassDef = .{ .class_name = "Iterator API owned input", .finalizer = finalizer };
    if (c.JS_NewClass(engine.runtime, class, &definition) < 0) return error.OutOfMemory;
    const input = try engine.checked(c.JS_NewObjectClass(engine.context, class));
    var input_owned = true; defer if (input_owned) engine.freeValue(input);
    const next = try engine.checked(c.JS_NewCFunction(engine.context, doneNext, "next", 0));
    if (c.JS_DefinePropertyValueStr(engine.context, input, "next", next, c.JS_PROP_C_W_E) < 0) return js.capture(engine);
    const symbol = c.JS_GetIteratorSymbol(engine.context); defer engine.freeValue(symbol);
    const atom = c.JS_ValueToAtom(engine.context, symbol); if (atom == c.JS_ATOM_NULL) return js.capture(engine); defer c.JS_FreeAtom(engine.context, atom);
    const method = try engine.checked(c.JS_NewCFunction(engine.context, selfIterator, "iterator", 0));
    if (c.JS_DefinePropertyValue(engine.context, input, atom, method, c.JS_PROP_C_W_E) < 0) return js.capture(engine);
    const iterator = try engine.checked(c.JS_PiGetAsyncIterator(engine.context, input));
    var iterator_owned = true; defer if (iterator_owned) engine.freeValue(iterator);
    engine.freeValue(input); input_owned = false;
    c.JS_RunGC(engine.runtime); try std.testing.expect(!finalized);
    engine.freeValue(iterator); iterator_owned = false;
    c.JS_RunGC(engine.runtime); try std.testing.expect(finalized);
}
var getter_calls: usize = 0;
var method_calls: usize = 0;
var result_finalized: bool = false;
var result_class: c.JSClassID = 0;
fn resultFinalizer(_: ?*c.JSRuntime, _: c.JSValue) callconv(.c) void { result_finalized = true; }
fn pendingMethod(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    method_calls += 1;
    return c.JS_NewObjectClass(context, result_class);
}
fn pendingGetter(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, mode: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    getter_calls += 1;
    const exception = c.JS_Throw(context, c.JS_DupValue(context, roots[0]));
    // Mode0 obeys the C callback contract. Mode1 deliberately violates it;
    // observed method/cleanup counts are recorded, never a no-work guarantee.
    return if (mode == 0) exception else c.JS_DupValue(context, roots[1]);
}
fn returnCaptured(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue { return c.JS_DupValue(context, roots[0]); }
test "native async iterator API flagged returned data without pending is not a fatal event" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const value = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(value);
    c.JS_SetUncatchableError(engine.context, value);
    try std.testing.expect(c.JS_IsUncatchableError(value));
    const input = try engine.checked(c.JS_NewObject(engine.context)); defer engine.freeValue(input);
    var roots = [_]c.JSValue{value};
    const method = try engine.checked(c.JS_NewCFunctionData2(engine.context, returnCaptured, "iterator", 0, 0, roots.len, &roots));
    const symbol = c.JS_GetAsyncIteratorSymbol(engine.context); defer engine.freeValue(symbol);
    const atom = c.JS_ValueToAtom(engine.context, symbol); if (atom == c.JS_ATOM_NULL) return js.capture(engine); defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DefinePropertyValue(engine.context, input, atom, method, c.JS_PROP_C_W_E) < 0) return js.capture(engine);
    const iterator = try engine.checked(c.JS_PiGetAsyncIterator(engine.context, input)); defer engine.freeValue(iterator);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, value, iterator));
    try std.testing.expect(!c.JS_HasException(engine.context) and c.JS_IsUncatchableError(value));
}
test "native async iterator API new pending reason cleanup and callback convention control" {
    for ([_]c_int{ 0, 1 }) |mode| {
        const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
        getter_calls = 0; method_calls = 0; result_finalized = false; result_class = 0;
        _ = c.JS_NewClassID(engine.runtime, &result_class);
        const definition: c.JSClassDef = .{ .class_name = "Iterator API returned result cleanup", .finalizer = resultFinalizer };
        if (c.JS_NewClass(engine.runtime, result_class, &definition) < 0) return error.OutOfMemory;
        const reason = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(reason);
        c.JS_SetUncatchableError(engine.context, reason);
        const input = try engine.checked(c.JS_NewObject(engine.context)); defer engine.freeValue(input);
        const method = try engine.checked(c.JS_NewCFunction(engine.context, pendingMethod, "iteratorMethod", 0)); defer engine.freeValue(method);
        var roots = [_]c.JSValue{ reason, method };
        const getter = try engine.checked(c.JS_NewCFunctionData2(engine.context, pendingGetter, "iteratorGetter", 0, mode, roots.len, &roots));
        const symbol = c.JS_GetAsyncIteratorSymbol(engine.context); defer engine.freeValue(symbol);
        const atom = c.JS_ValueToAtom(engine.context, symbol); if (atom == c.JS_ATOM_NULL) return js.capture(engine); defer c.JS_FreeAtom(engine.context, atom);
        if (c.JS_DefinePropertyGetSet(engine.context, input, atom, getter, c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
        const result = c.JS_PiGetAsyncIterator(engine.context, input);
        try std.testing.expect(c.JS_IsException(result) and c.JS_HasException(engine.context));
        const actual = c.JS_GetException(engine.context); defer engine.freeValue(actual);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, actual, reason) and c.JS_IsUncatchableError(actual));
        try std.testing.expectEqual(@as(usize, 1), getter_calls);
        if (mode == 0) try std.testing.expectEqual(@as(usize, 0), method_calls);
        if (method_calls != 0) try std.testing.expect(result_finalized);
        if (mode == 1) std.debug.print("iterator API native callback convention violation observation: getter={d} method={d} owned_result_finalized={}\n", .{ getter_calls, method_calls, result_finalized });
    }
}
var cleanup_context: ?*c.JSContext = null;
var cleanup_fatal: c.JSValue = undefined;
var cleanup_tail: c.JSValue = undefined;
var cleanup_slot: c.JSValue = undefined;
var cleanup_original: c.JSValue = undefined;
var cleanup_classes: [3]c.JSClassID = .{ 0, 0, 0 };
var cleanup_counts: [3]usize = .{ 0, 0, 0 };
var incoming_fatal: bool = false;
var original_marked: bool = false;
fn resultCleanup(_: ?*c.JSRuntime, _: c.JSValue) callconv(.c) void {
    cleanup_counts[0] += 1;
    if (cleanup_context) |ctx| {
        if (incoming_fatal) {
            const owned = cleanup_slot; cleanup_slot = c.pi_js_undefined();
            _ = c.JS_Throw(ctx, owned);
        } else _ = c.JS_Throw(ctx, c.JS_DupValue(ctx, cleanup_fatal));
    }
}
fn originalCleanup(_: ?*c.JSRuntime, _: c.JSValue) callconv(.c) void {
    cleanup_counts[1] += 1;
    if (cleanup_context) |ctx| if (!c.JS_IsUndefined(cleanup_slot)) {
        const owned = cleanup_slot; cleanup_slot = c.pi_js_undefined();
        _ = c.JS_Throw(ctx, owned);
    };
}
fn displacedCleanup(_: ?*c.JSRuntime, _: c.JSValue) callconv(.c) void {
    cleanup_counts[2] += 1;
    if (cleanup_context) |ctx| _ = c.JS_Throw(ctx, c.JS_DupValue(ctx, cleanup_tail));
}
fn cleanupMethod(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const result = c.JS_NewObjectClass(context, cleanup_classes[0]);
    if (c.JS_IsException(result)) return result;
    const reason = c.JS_NewError(context);
    if (c.JS_IsException(reason)) { c.JS_FreeValue(context, result); return reason; }
    const token = c.JS_NewObjectClass(context, cleanup_classes[1]);
    if (c.JS_IsException(token)) {
        const failure = c.JS_GetException(context);
        c.JS_FreeValue(context, result); c.JS_FreeValue(context, reason);
        return c.JS_Throw(context, failure);
    }
    if (c.JS_DefinePropertyValueStr(context, reason, "cleanupToken", token, c.JS_PROP_C_W_E) < 0) {
        const failure = c.JS_GetException(context);
        c.JS_FreeValue(context, result); c.JS_FreeValue(context, reason);
        return c.JS_Throw(context, failure);
    }
    if (incoming_fatal) c.JS_SetUncatchableError(context, reason);
    original_marked = c.JS_IsUncatchableError(reason);
    cleanup_original = reason; // Borrowed identity only: no additional refcount.
    _ = c.JS_Throw(context, reason); // Sole owned original is transferred.
    return result; // Deliberate native callback convention violation control.
}
test "native async iterator API nested result and displaced finalizers preserve first fatal" {
    for ([_]bool{ false, true }) |fatal_first| {
        const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
        cleanup_context = engine.context; defer cleanup_context = null;
        incoming_fatal = fatal_first; original_marked = false; cleanup_counts = .{ 0, 0, 0 }; cleanup_classes = .{ 0, 0, 0 };
        const definitions = [_]c.JSClassDef{
            .{ .class_name = "Iterator API result finalizer", .finalizer = resultCleanup },
            .{ .class_name = "Iterator API original finalizer", .finalizer = originalCleanup },
            .{ .class_name = "Iterator API displaced finalizer", .finalizer = displacedCleanup },
        };
        for (&cleanup_classes, definitions) |*class, definition| {
            _ = c.JS_NewClassID(engine.runtime, class);
            if (c.JS_NewClass(engine.runtime, class.*, &definition) < 0) return error.OutOfMemory;
        }
        cleanup_fatal = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(cleanup_fatal);
        c.JS_SetUncatchableError(engine.context, cleanup_fatal);
        cleanup_tail = try engine.checked(c.JS_NewObject(engine.context)); defer engine.freeValue(cleanup_tail);
        cleanup_slot = try engine.checked(c.JS_NewObjectClass(engine.context, cleanup_classes[2])); defer engine.freeValue(cleanup_slot);
        const input = try engine.checked(c.JS_NewObject(engine.context)); defer engine.freeValue(input);
        const symbol = c.JS_GetAsyncIteratorSymbol(engine.context); defer engine.freeValue(symbol);
        const atom = c.JS_ValueToAtom(engine.context, symbol); if (atom == c.JS_ATOM_NULL) return js.capture(engine); defer c.JS_FreeAtom(engine.context, atom);
        const method = try engine.checked(c.JS_NewCFunction(engine.context, cleanupMethod, "iteratorCleanupControl", 0));
        if (c.JS_DefinePropertyValue(engine.context, input, atom, method, c.JS_PROP_C_W_E) < 0) return js.capture(engine);
        const result = c.JS_PiGetAsyncIterator(engine.context, input);
        try std.testing.expect(c.JS_IsException(result) and c.JS_HasException(engine.context));
        const actual = c.JS_GetException(engine.context);
        var actual_owned = true; defer if (actual_owned) engine.freeValue(actual);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, actual, if (fatal_first) cleanup_original else cleanup_fatal));
        try std.testing.expect(c.JS_IsUncatchableError(actual));
        try std.testing.expect(original_marked == fatal_first);
        try std.testing.expectEqual(@as(usize, 1), cleanup_counts[0]);
        try std.testing.expectEqual(@as(usize, if (fatal_first) 0 else 1), cleanup_counts[1]);
        try std.testing.expectEqual(@as(usize, 1), cleanup_counts[2]);
        engine.freeValue(actual); actual_owned = false;
        try std.testing.expectEqual(@as(usize, 1), cleanup_counts[1]);
        try std.testing.expect(c.JS_IsUndefined(cleanup_slot) and !c.JS_HasException(engine.context));
    }
}

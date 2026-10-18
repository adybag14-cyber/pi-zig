//! Actual c268 PKCE caller and genuine native WebCrypto/encoding controls.
const std = @import("std");
const x = @import("extensions/native_ai_auth_helper_values.zig");
const c = x.c;
fn publish(engine: *x.em.Engine, name: [*:0]const u8, value: c.JSValue) !void {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try @import("extensions/native_js_values.zig").define(engine, global, name, c.JS_DupValue(engine.context, value));
}
fn prepare(engine: *x.em.Engine) !void {
    engine.native_io = std.testing.io;
    try @import("extensions/text_encoding.zig").install(engine);
    try @import("extensions/native_web_crypto.zig").install(engine);
    const base64 = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(base64);
    try @import("extensions/node_base64.zig").install(engine, base64);
    const native = try @import("extensions/native_ai_oauth_pkce.zig").create(engine);
    defer engine.freeValue(native);
    try publish(engine, "pkceNative", native);
    // Exact accepted runtime JavaScript; its source-map content equals c268 TS.
    const source = try engine.evalModule(@embedFile("extensions/fixtures/oauth-pkce-c268-source.mjs"), "actual-source-pkce-c268.mjs");
    defer engine.freeValue(source);
    try publish(engine, "pkceSource", source);
}
fn run(engine: *x.em.Engine, source: []const u8) !void {
    const namespace = try engine.evalModule(source, "actual-pkce-caller.mjs");
    engine.freeValue(namespace);
}
fn observer(engine: *x.em.Engine, tail: []const u8) !void {
    const source = try std.mem.concat(engine.gpa, u8, &.{ @embedFile("extensions/fixtures/oauth-pkce-genuine-af-observer.mjs"), "\n", tail });
    defer engine.gpa.free(source);
    try run(engine, source);
}
test "native OAuth PKCE actual export is a genuine nonconstructible async declaration" {
    const engine = try x.em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try prepare(engine);
    var scope: x.Scope = .{ .engine = engine };
    defer scope.deinit();
    const function = try scope.get(try scope.global("pkceNative"), "generatePKCE");
    try std.testing.expect(c.JS_IsAsyncFunction(function));
    try std.testing.expect(!c.JS_IsConstructor(engine.context, function));
    try std.testing.expect(scope.equal(try scope.get(function, "name"), try scope.text("generatePKCE")));
    try std.testing.expect(scope.equal(try scope.get(function, "length"), c.JS_NewInt32(engine.context, 0)));
}
test "native OAuth PKCE exact Source crypto digest Await thenable rejection iterator and lookup traces" {
    const engine = try x.em.Engine.init(std.testing.allocator, .{ .interrupt_budget = 1_000_000 });
    defer engine.deinit();
    try prepare(engine);
    try observer(engine,
        \\export const rows=await comparePKCE(pkceNative.generatePKCE,pkceSource.generatePKCE,["real-digest","thenable","reject","iterator-close","iterator-close-primitive","replace-getter","intrinsic-promise"]);
        \\if(rows.length!==7||rows[0].result.verifier!=="A".repeat(43))throw Error("all PKCE Source routes required");
    );
}
test "native OAuth PKCE real secure randomness and native SHA256 produce valid independent challenges" {
    const engine = try x.em.Engine.init(std.testing.allocator, .{ .interrupt_budget = 1_000_000 });
    defer engine.deinit();
    try prepare(engine);
    try run(engine,
        \\const first=await pkceNative.generatePKCE(),second=await pkceNative.generatePKCE();
        \\for(const value of [first,second]){
        \\ if(!/^[A-Za-z0-9_-]{43}$/.test(value.verifier)||!/^[A-Za-z0-9_-]{43}$/.test(value.challenge))throw Error("PKCE encoding");
        \\ const bytes=new Uint8Array(await crypto.subtle.digest("SHA-256",new TextEncoder().encode(value.verifier)));
        \\ const digest=btoa(String.fromCharCode(...bytes)).replace(/\+/g,"-").replace(/\//g,"_").replace(/=/g,"");
        \\ if(digest!==value.challenge)throw Error("PKCE SHA256");
        \\}
        \\if(first.verifier===second.verifier)throw Error("Secure nonces repeated");
    );
}
fn privateData(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    _ = x.em.Engine.fromContext(context.?).throwNativeOutOfMemory();
    return c.JS_GetException(context);
}
fn actualFatal(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = x.em.Engine.fromContext(context.?);
    _ = engine.checked(engine.throwNativeOutOfMemoryFatal()) catch {};
    const global = c.JS_GetGlobalObject(context);
    defer engine.freeValue(global);
    _ = c.JS_DefinePropertyValueStr(context, global, "pkceObservedB", c.JS_DupValue(context, engine.captured_exception.?), c.JS_PROP_C_W_E);
    return c.pi_js_undefined();
}
fn read(engine: *x.em.Engine, name: [*:0]const u8) !c.JSValue {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    return engine.checked(c.JS_GetPropertyStr(engine.context, global, name));
}
test "native OAuth PKCE same-operation private DATA getter call and constructor throws stay ordinary" {
    inline for (.{ "getter", "call", "constructor" }) |mode| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try prepare(engine);
        try engine.bindFunction("pkcePrivateData", privateData, 0);
        const tail: []const u8 = if (std.mem.eql(u8, mode, "getter"))
            "Object.defineProperty(crypto,'getRandomValues',{get(){pkceA=pkcePrivateData();throw pkceA}});"
        else if (std.mem.eql(u8, mode, "call"))
            "Object.defineProperty(crypto,'getRandomValues',{value(){pkceA=pkcePrivateData();throw pkceA}});"
        else
            "globalThis.Uint8Array=function(){pkceA=pkcePrivateData();throw pkceA};";
        const source = try std.mem.concat(engine.gpa, u8, &.{
            "globalThis.pkceA=undefined;globalThis.pkceCaught=undefined;", tail,
            "try{await pkceNative.generatePKCE()}catch(error){pkceCaught=error}if(pkceCaught!==pkceA||!pkceA)throw Error('PKCE DATA identity');",
        });
        defer engine.gpa.free(source);
        try run(engine, source);
        const reason = try read(engine, "pkceA");
        defer engine.freeValue(reason);
        try std.testing.expect(c.pi_js_native_allocation_error_generation(reason) != 0);
        try std.testing.expect(!c.JS_IsUncatchableError(reason));
        try std.testing.expect(engine.native_fatal_invocation == null);
    }
}
test "native OAuth PKCE actual captured fatal B survives later ordinary DATA A in crypto getter" {
    const engine = try x.em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try prepare(engine);
    try engine.bindFunction("pkcePrivateData", privateData, 0);
    try engine.bindFunction("pkceActualFatal", actualFatal, 0);
    const outcome = engine.evalModule(
        \\globalThis.pkceA=undefined;globalThis.pkceCaught=undefined;
        \\Object.defineProperty(crypto,"getRandomValues",{get(){pkceA=pkcePrivateData();pkceActualFatal();throw pkceA}});
        \\try{await pkceNative.generatePKCE()}catch(error){pkceCaught=error}
    , "actual-pkce-fatal-priority.mjs");
    if (outcome) |value| {
        engine.freeValue(value);
        return error.ActualPkceFatalWasSwallowed;
    } else |err| try std.testing.expect(err == error.JavaScriptException);
    const selected = engine.captured_exception orelse return error.RequiredPkceFatal;
    const reason = try read(engine, "pkceObservedB");
    defer engine.freeValue(reason);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, selected, reason));
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expect(engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
}
fn gc(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    c.JS_RunGC(x.em.Engine.fromContext(context.?).runtime);
    return c.pi_js_undefined();
}
test "native OAuth PKCE declared bytes encoder and data survive the actual digest suspension" {
    inline for (.{ false, true }) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{ .interrupt_budget = 1_000_000 });
        defer engine.deinit();
        try prepare(engine);
        const setup =
            \\globalThis.pkceWeak=[];
            \\const actualArray=Uint8Array;
            \\Object.defineProperty(crypto,"getRandomValues",{value(bytes){pkceWeak.push(new WeakRef(bytes));return bytes.fill(0)}});
            \\globalThis.TextEncoder=class {constructor(){pkceWeak.push(new WeakRef(this))}encode(){const bytes=new actualArray(43);pkceWeak.push(new WeakRef(bytes));return bytes}};
            \\Object.defineProperty(crypto.subtle,"digest",{value(){return new Promise(resolve=>{globalThis.pkceRelease=()=>resolve(new actualArray(32).buffer)})}});
        ;
        const source = try std.mem.concat(engine.gpa, u8, &.{ setup, if (native) "\nglobalThis.pkcePending=pkceNative.generatePKCE();" else "\nglobalThis.pkcePending=pkceSource.generatePKCE();" });
        defer engine.gpa.free(source);
        try run(engine, source);
        try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
        c.JS_RunGC(engine.runtime);
        try run(engine,
            \\if(pkceWeak.length!==3||pkceWeak.some(value=>value.deref()===undefined))throw Error("Declared PKCE local retired before Await completion");
            \\pkceRelease();await pkcePending;delete globalThis.pkcePending;delete globalThis.pkceRelease;
        );
    }
}
test "native OAuth PKCE constructor temporary retires before next global crypto getter" {
    inline for (.{ false, true }) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{ .interrupt_budget = 1_000_000 });
        defer engine.deinit();
        try prepare(engine);
        try engine.bindFunction("pkceGc", gc, 0);
        try run(engine,
            \\const actualArray=Uint8Array,actualCrypto=crypto;
            \\let constructor=function(size){return new actualArray(size)};
            \\globalThis.pkceConstructorWeak=new WeakRef(constructor);
            \\Object.defineProperty(globalThis,"Uint8Array",{configurable:true,get(){if(constructor){const value=constructor;constructor=undefined;return value}return actualArray}});
            \\Object.defineProperty(globalThis,"crypto",{configurable:true,get(){pkceGc();if(pkceConstructorWeak.deref()!==undefined)throw Error("Constructor retained into crypto getter");return actualCrypto}});
        );
        try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
        try run(engine, if (native) "await pkceNative.generatePKCE();" else "await pkceSource.generatePKCE();");
    }
}


test "native OAuth PKCE iterator method retires before iterator next getter" {
    inline for (.{ false, true }) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{ .interrupt_budget = 1_000_000 });
        defer engine.deinit();
        try prepare(engine);
        try engine.bindFunction("pkceGc", gc, 0);
        try run(engine,
            \\const actualArray=Uint8Array;
            \\let method=function(){return {get next(){pkceGc();if(pkceIteratorMethodWeak.deref()!==undefined)throw Error("Iterator method retained into next getter");return function(){return {done:true}}}}};
            \\globalThis.pkceIteratorMethodWeak=new WeakRef(method);
            \\let first=true;
            \\globalThis.Uint8Array=function(value){if(first){first=false;return {get [Symbol.iterator](){const selected=method;method=undefined;return selected}}}return new actualArray(value)};
            \\Object.defineProperty(crypto,"getRandomValues",{value(value){return value}});
        );
        try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
        try run(engine, if (native) "await pkceNative.generatePKCE();" else "await pkceSource.generatePKCE();");
    }
}
test "native OAuth PKCE String method and receiver retire before addition coercion" {
    inline for (.{ false, true }) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{ .interrupt_budget = 1_000_000 });
        defer engine.deinit();
        try prepare(engine);
        try engine.bindFunction("pkceGc", gc, 0);
        try run(engine,
            \\const actualString=String;
            \\let receiver={fromCharCode(){return {[Symbol.toPrimitive](){pkceGc();if(pkceStringWeak.deref()!==undefined||pkceCharMethodWeak.deref()!==undefined)throw Error("String call temporaries retained into coercion");return "\0"}}}};
            \\globalThis.pkceStringWeak=new WeakRef(receiver);globalThis.pkceCharMethodWeak=new WeakRef(receiver.fromCharCode);
            \\Object.defineProperty(globalThis,"String",{configurable:true,get(){if(receiver){const selected=receiver;receiver=undefined;return selected}return actualString}});
            \\Object.defineProperty(crypto,"getRandomValues",{value(value){return value.fill(0)}});
        );
        try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
        try run(engine, if (native) "await pkceNative.generatePKCE();" else "await pkceSource.generatePKCE();");
    }
}
test "native OAuth PKCE literal RegExp arguments ignore global constructor replacement" {
    inline for (.{ false, true }) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{ .interrupt_budget = 1_000_000 });
        defer engine.deinit();
        try prepare(engine);
        try run(engine,
            \\const actualBtoa=btoa,prototype=RegExp.prototype,replace=String.prototype.replace;
            \\globalThis.pkceRegexArguments=[];
            \\globalThis.RegExp=function(){throw Error("Global RegExp constructor observed")};
            \\globalThis.btoa=function(binary){let current=actualBtoa(binary),index=0;return {replace(pattern,replacement){
            \\ if(Object.getPrototypeOf(pattern)!==prototype||pattern.flags!=="g"||pattern.lastIndex!==0||pattern.source!==["\\+","\\/","="][index])throw Error("PKCE literal metadata");
            \\ pkceRegexArguments.push(pattern);current=Reflect.apply(replace,current,[pattern,replacement]);return ++index===3?current:this;
            \\}}};
        );
        try run(engine, if (native) "await pkceNative.generatePKCE();" else "await pkceSource.generatePKCE();");
        try run(engine, "if(pkceRegexArguments.length!==6||new Set(pkceRegexArguments).size!==6)throw Error('Fresh literal objects required');");
    }
}

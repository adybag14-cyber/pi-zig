//! Actual External/GetExternal controls; source-only, not executed.
//! Uses real VM native classes, concrete FileHandle and independent native refs.
const std = @import("std");
const support = @import("native_node_file_handle_owner_test_support.zig");
const a = support.a;
const c = a.c;
const external = @import("extensions/native_node_external_value.zig");
const dispatch = @import("extensions/native_node_stream_js_dispatch.zig");

fn make(f: *support.Fixture, pointer: *anyopaque) !c.JSValue {
    return a.expression(f.engine, struct {
        fn body(s: *a.Scope, raw: *anyopaque) !c.JSValue {
            return a.duplicate(s.engine, try external.create(s, raw));
        }
    }.body, .{pointer});
}
fn get(f: *support.Fixture, receiver: c.JSValue) !c.JSValue {
    return a.expression(f.engine, struct {
        fn body(s: *a.Scope, fx: *support.Fixture, object: c.JSValue) !c.JSValue {
            return dispatch.getExternal(s, fx.registry(), object);
        }
    }.body, .{f, receiver});
}
fn closed(f: *support.Fixture) !*support.Handle {
    const handle = try f.create(-1, null, null);
    try std.testing.expectEqual(@as(c_int,-1),try f.releaseDescriptor());
    return handle;
}

test "native Stream external actual VM class stores a borrowed nonnull address" {
    var f: support.Fixture=undefined; try f.init(); defer f.deinit();
    var marker: u64=0x12345678;
    const value=try make(&f,@ptrCast(&marker)); defer f.engine.freeValue(value);
    try std.testing.expect(external.isExternal(value));
    try std.testing.expect(c.JS_IsObject(value));
    try std.testing.expect(!c.JS_IsFunction(f.engine.context,value));
    try std.testing.expect(!c.JS_IsConstructor(f.engine.context,value));
    try std.testing.expect(external.value(value)==@as(*anyopaque,@ptrCast(&marker)));
    try std.testing.expectEqual(@as(u64,0x12345678),marker);
}

test "native Stream external null prototype nonextensibility and native object shape match original" {
    var f: support.Fixture=undefined; try f.init(); defer f.deinit();
    var marker: u8=1;
    const value=try make(&f,@ptrCast(&marker)); defer f.engine.freeValue(value);
    try f.expose("actualExternal",value);
    try f.expect("typeof actualExternal==='object' && Object.getPrototypeOf(actualExternal)===null" ++
        " && Reflect.ownKeys(actualExternal).length===0 && !Object.isExtensible(actualExternal)" ++
        " && Object.isSealed(actualExternal) && Object.isFrozen(actualExternal)" ++
        " && Object.prototype.toString.call(actualExternal)==='[object Object]' && JSON.stringify(actualExternal)==='{}'");
    try f.expect("Reflect.set(actualExternal,'added',1)===false" ++
        " && Reflect.defineProperty(actualExternal,'added',{value:1})===false" ++
        " && Reflect.setPrototypeOf(actualExternal,Object.prototype)===false" ++
        " && Reflect.setPrototypeOf(actualExternal,null)===true" ++
        " && (()=>{try{String(actualExternal);return false;}catch(e){return e instanceof TypeError;}})()");
}

test "native Stream external fresh getter identities carry the same actual live StreamBase address" {
    var file:support.File=undefined; try file.init(); defer file.deinit();
    var f:support.Fixture=undefined; try f.init(); defer f.deinit();
    const handle=try f.create(file.take(),null,null);
    const first=try get(&f,f.primary_wrapper.?); defer f.engine.freeValue(first);
    const second=try get(&f,f.primary_wrapper.?); defer f.engine.freeValue(second);
    try std.testing.expect(external.isExternal(first) and external.isExternal(second));
    try std.testing.expect(!c.JS_IsStrictEqual(f.engine.context,first,second));
    const pointer:*anyopaque=@ptrCast(&handle.stream);
    try std.testing.expect(external.value(first)==pointer and external.value(second)==pointer);
    file.descriptor=try f.releaseDescriptor();
}

test "native Stream external closed streams still expose the native address without IsAlive filtering" {
    var f:support.Fixture=undefined; try f.init(); defer f.deinit();
    const handle=try closed(&f);
    try std.testing.expect(!handle.isAlive());
    const value=try get(&f,f.primary_wrapper.?); defer f.engine.freeValue(value);
    try std.testing.expect(external.isExternal(value));
    try std.testing.expect(external.value(value)==@as(*anyopaque,@ptrCast(&handle.stream)));
}

test "native Stream external getter does not acquire native or registry references or trigger scope" {
    var f:support.Fixture=undefined; try f.init(); defer f.deinit();
    const handle=try closed(&f);
    const native_before=handle.wrap.native_references;
    const registry_before=f.registry().references;
    f.env().uidField(.default_trigger).*=811;
    const value=try get(&f,f.primary_wrapper.?); defer f.engine.freeValue(value);
    try std.testing.expectEqual(native_before,handle.wrap.native_references);
    try std.testing.expectEqual(registry_before,f.registry().references);
    try std.testing.expectEqual(@as(f64,811),f.env().uidField(.default_trigger).*);
}

test "native Stream external missing and foreign receiver bodies return undefined without user traps" {
    var f:support.Fixture=undefined; try f.init(); defer f.deinit(); _=try closed(&f);
    try f.expose("externalHandle",f.primary_wrapper.?);
    try f.evaluate("globalThis.externalTraps=0;");
    inline for (.{
        "({})", "Object.create(Object.getPrototypeOf(externalHandle))",
        "new Proxy(externalHandle,{get(){externalTraps++;throw 1;}})",
    }) |source| {
        const receiver=try f.value(source); defer f.engine.freeValue(receiver);
        const value=try get(&f,receiver); defer f.engine.freeValue(value);
        try std.testing.expect(c.JS_IsUndefined(value));
    }
    try f.expect("externalTraps===0");
}

test "native Stream external authentic recognition rejects structural copies and proxies without coercion" {
    var f:support.Fixture=undefined; try f.init(); defer f.deinit();
    var marker:u8=1;
    const value=try make(&f,@ptrCast(&marker)); defer f.engine.freeValue(value);
    try f.expose("authenticExternal",value);
    try f.evaluate("globalThis.externalTraps=0;");
    inline for (.{
        "Object.preventExtensions(Object.create(null))",
        "new Proxy(authenticExternal,{get(){externalTraps++;throw 1;}})",
        "({[Symbol.toPrimitive](){externalTraps++;throw 1;}})", "null", "Symbol('external')",
    }) |source| {
        const wrong=try f.value(source); defer f.engine.freeValue(wrong);
        try std.testing.expect(!external.isExternal(wrong));
        try std.testing.expect(external.value(wrong)==null);
        try std.testing.expect(!c.JS_HasException(f.engine.context));
    }
    try f.expect("externalTraps===0");
}

test "native Stream external public native opaque setter cannot overwrite its private class slot" {
    var f:support.Fixture=undefined; try f.init(); defer f.deinit();
    var first:u8=1; var other:u8=2;
    const value=try make(&f,@ptrCast(&first)); defer f.engine.freeValue(value);
    try std.testing.expectEqual(@as(c_int,-1),c.JS_SetOpaque(value,@ptrCast(&other)));
    try std.testing.expect(external.value(value)==@as(*anyopaque,@ptrCast(&first)));
    try std.testing.expect(!c.JS_HasException(f.engine.context));
}

test "native Stream external freeing the value does not dispose or close its independently owned stream" {
    var file:support.File=undefined; try file.init(); defer file.deinit();
    var f:support.Fixture=undefined; try f.init(); defer f.deinit();
    const fd=file.take(); const handle=try f.create(fd,null,null);
    const value=try get(&f,f.primary_wrapper.?);
    f.engine.freeValue(value); c.JS_RunGC(f.engine.runtime);
    try std.testing.expect(handle.isAlive() and support.File.status(fd)==0);
    try std.testing.expect(f.registry().unwrap(f.primary_wrapper.?)==&handle.wrap);
    file.descriptor=try f.releaseDescriptor();
}

test "native Stream external value survives target retirement as a borrowed address with no keepalive" {
    var f:support.Fixture=undefined; try f.init(); defer f.deinit();
    const handle=try closed(&f);
    const pointer:*anyopaque=@ptrCast(&handle.stream);
    const value=try get(&f,f.primary_wrapper.?); defer f.engine.freeValue(value);
    try std.testing.expectEqual(@as(usize,0),handle.wrap.native_references);
    try handle.wrap.retire(false);
    // The address is now stale, exactly like the original External. Recognition
    // and extraction must not dereference it or resurrect/retain the old owner.
    try std.testing.expect(f.registry().unwrap(f.primary_wrapper.?)==null);
    c.JS_RunGC(f.engine.runtime);
    try std.testing.expect(external.isExternal(value));
    try std.testing.expect(external.value(value)==pointer);
    const after=try get(&f,f.primary_wrapper.?); defer f.engine.freeValue(after);
    try std.testing.expect(c.JS_IsUndefined(after));
}

//! Runtime key operations commit asynchronously and synchronize cached status.
const std = @import("std");
const sdk = @import("native_sdk.zig");
const engine_mod = @import("engine.zig");
const c = engine_mod.c;
const Stage = enum(c_int) { commit, complete, failed, ignored, started };
const error_module = "native-sdk-credential-sync-error";
fn function(engine: *engine_mod.Engine, job: c.JSValue, stage: Stage) !c.JSValue {
    var captured = [_]c.JSValue{job};
    return engine.checked(c.JS_NewCFunctionData2(engine.context, callback, "runtimeCredentialOperation", 1, @intFromEnum(stage), 1, &captured));
}
fn callback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, stage: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return advance(engine, data[0], @enumFromInt(stage), if (argc > 0) args[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
pub fn enqueue(engine: *engine_mod.Engine, runtime: c.JSValue, id: c.JSValue, key: c.JSValue, options: c.JSValue, remove: bool) !c.JSValue {
    const owner = try sdk.state(engine, runtime);
    var chains = try sdk.get(engine, owner.data, "credentialOperations");
    defer engine.freeValue(chains);
    if (!c.JS_IsObject(chains)) {
        engine.freeValue(chains);
        chains = try @import("native_sdk_auth_snapshot.zig").collection(engine, "Map");
        try sdk.put(engine, owner.data, "credentialOperations", c.JS_DupValue(engine.context, chains));
    }
    const job = try sdk.object(engine);
    defer engine.freeValue(job);
    inline for (.{ .{ "runtime", runtime }, .{ "id", id }, .{ "key", key } }) |entry| try sdk.put(engine, job, entry[0], c.JS_DupValue(engine.context, entry[1]));
    const copied = try sdk.object(engine);
    defer engine.freeValue(copied);
    try @import("native_sdk_models.zig").copy(engine, copied, options);
    const supplied_signal = try sdk.get(engine, copied, "signal");
    defer engine.freeValue(supplied_signal);
    const signal = if (c.JS_IsObject(supplied_signal)) c.JS_DupValue(engine.context, supplied_signal) else try @import("abort_signal.zig").create(engine);
    defer engine.freeValue(signal);
    try sdk.put(engine, copied, "signal", c.JS_DupValue(engine.context, signal));
    try sdk.put(engine, job, "options", c.JS_DupValue(engine.context, copied));
    try sdk.put(engine, job, "remove", c.pi_js_bool(engine.context, @intFromBool(remove)));
    var caps: [2]c.JSValue = undefined;
    const started = try engine.checked(c.JS_NewPromiseCapability(engine.context, &caps));
    defer engine.freeValue(started);
    defer for (caps) |cap| engine.freeValue(cap);
    try sdk.put(engine, job, "startedResolve", c.JS_DupValue(engine.context, caps[0]));
    const previous = try sdk.invoke(engine, chains, "get", &.{id});
    defer engine.freeValue(previous);
    const adopted = try sdk.promise(engine, previous);
    defer engine.freeValue(adopted);
    const ignored = try function(engine, job, .ignored);
    defer engine.freeValue(ignored);
    const observed = try sdk.invoke(engine, adopted, "catch", &.{ignored});
    defer engine.freeValue(observed);
    const commit = try function(engine, job, .commit);
    defer engine.freeValue(commit);
    const result = try sdk.invoke(engine, observed, "then", &.{commit});
    errdefer engine.freeValue(result);
    const tail = try sdk.invoke(engine, result, "catch", &.{ignored});
    defer engine.freeValue(tail);
    const stored = try sdk.invoke(engine, chains, "set", &.{ id, tail });
    engine.freeValue(stored);
    try sdk.put(engine, job, "operation", c.JS_DupValue(engine.context, result));
    const raced = try @import("native_models_refresh.zig").race(engine, started, signal, c.pi_js_undefined());
    defer engine.freeValue(raced);
    const ready = try function(engine, job, .started);
    defer engine.freeValue(ready);
    const returned = try sdk.invoke(engine, raced, "then", &.{ready});
    engine.freeValue(result);
    return returned;
}
fn advance(engine: *engine_mod.Engine, job: c.JSValue, stage: Stage, value: c.JSValue) !c.JSValue {
    if (stage == .ignored) return c.pi_js_undefined();
    if (stage == .started) return sdk.get(engine, job, "operation");
    const runtime = try sdk.get(engine, job, "runtime");
    defer engine.freeValue(runtime);
    const owner = try sdk.state(engine, runtime);
    const id = try sdk.get(engine, job, "id");
    defer engine.freeValue(id);
    const remove = try sdk.get(engine, job, "remove");
    defer engine.freeValue(remove);
    const removed = c.JS_ToBool(engine.context, remove) == 1;
    const options = try sdk.get(engine, job, "options");
    defer engine.freeValue(options);
    if (stage == .complete) {
        const signal = try sdk.get(engine, options, "signal");
        defer engine.freeValue(signal);
        const checked = sdk.invoke(engine, signal, "throwIfAborted", &.{}) catch |err| {
            if (err != error.JavaScriptException) return err;
            return advance(engine, job, .failed, engine.captured_exception.?);
        };
        engine.freeValue(checked);
        const errors = try sdk.get(engine, value, "errors");
        defer engine.freeValue(errors);
        const failure = try sdk.invoke(engine, errors, "get", &.{id});
        defer engine.freeValue(failure);
        if (!c.JS_IsUndefined(failure)) return advance(engine, job, .failed, failure);
        return c.pi_js_undefined();
    }
    if (stage == .failed) {
        const operation = if (removed) "removeRuntimeApiKey" else "setRuntimeApiKey";
        const credential = if (removed) c.pi_js_undefined() else try sdk.object(engine);
        defer engine.freeValue(credential);
        if (!removed) {
            try sdk.put(engine, credential, "type", try sdk.text(engine, "api_key"));
            try sdk.put(engine, credential, "key", try sdk.get(engine, job, "key"));
        }
        const private = engine.native_module_values.get(error_module) orelse return error.NativeSDKCredentialErrorUnavailable;
        const prototype = try sdk.get(engine, private, "prototype");
        defer engine.freeValue(prototype);
        const operation_value = try sdk.text(engine, operation);
        defer engine.freeValue(operation_value);
        const error_options = try sdk.object(engine);
        defer engine.freeValue(error_options);
        try sdk.put(engine, error_options, "cause", c.JS_DupValue(engine.context, value));
        return c.JS_Throw(engine.context, try errorValue(engine, prototype, id, operation_value, credential, error_options));
    }
    const signal = try sdk.get(engine, options, "signal");
    defer engine.freeValue(signal);
    if (c.JS_IsObject(signal)) {
        const checked = try sdk.invoke(engine, signal, "throwIfAborted", &.{});
        engine.freeValue(checked);
    }
    const notify = try sdk.get(engine, job, "startedResolve");
    defer engine.freeValue(notify);
    const notified = try engine.checked(c.JS_Call(engine.context, notify, c.pi_js_undefined(), 0, null));
    engine.freeValue(notified);
    const keys = try sdk.get(engine, owner.data, "keys");
    defer engine.freeValue(keys);
    const provider = try engine.toString(id);
    defer engine.gpa.free(provider);
    const field = try engine.gpa.dupeZ(u8, provider);
    defer engine.gpa.free(field);
    try sdk.put(engine, keys, field, if (removed) c.pi_js_undefined() else try sdk.get(engine, job, "key"));
    const refresh_options = try sdk.object(engine);
    defer engine.freeValue(refresh_options);
    try sdk.put(engine, refresh_options, "allowNetwork", c.pi_js_bool(engine.context, 0));
    const providers = try sdk.array(engine);
    defer engine.freeValue(providers);
    try sdk.append(engine, providers, c.JS_DupValue(engine.context, id));
    try sdk.put(engine, refresh_options, "providers", c.JS_DupValue(engine.context, providers));
    try sdk.put(engine, refresh_options, "signal", c.JS_DupValue(engine.context, signal));
    const pending = try @import("native_sdk_refresh.zig").start(engine, runtime, refresh_options);
    defer engine.freeValue(pending);
    const complete = try function(engine, job, .complete);
    defer engine.freeValue(complete);
    const failed = try function(engine, job, .failed);
    defer engine.freeValue(failed);
    return sdk.invoke(engine, pending, "then", &.{ complete, failed });
}
fn errorValue(engine: *engine_mod.Engine, prototype: c.JSValue, id: c.JSValue, operation: c.JSValue, credential: c.JSValue, options: c.JSValue) !c.JSValue {
    const error_value = try engine.checked(c.JS_NewError(engine.context));
    errdefer engine.freeValue(error_value);
    if (c.JS_SetPrototype(engine.context, error_value, prototype) < 0) return error.JavaScriptException;
    const provider = try engine.toString(id);
    defer engine.gpa.free(provider);
    const name = try engine.toString(operation);
    defer engine.gpa.free(name);
    const message = try std.fmt.allocPrint(engine.gpa, "Credential {s} committed for {s}, but local synchronization failed", .{ name, provider });
    defer engine.gpa.free(message);
    try sdk.put(engine, error_value, "name", try sdk.text(engine, "CredentialSynchronizationError"));
    if (c.JS_DefinePropertyValueStr(engine.context, error_value, "message", try sdk.text(engine, message), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return error.JavaScriptException;
    try sdk.put(engine, error_value, "providerId", c.JS_DupValue(engine.context, id));
    try sdk.put(engine, error_value, "operation", c.JS_DupValue(engine.context, operation));
    try sdk.put(engine, error_value, "credential", c.JS_DupValue(engine.context, credential));
    if (c.JS_IsObject(options)) {
        const atom = c.JS_NewAtom(engine.context, "cause");
        defer c.JS_FreeAtom(engine.context, atom);
        const has = c.JS_HasProperty(engine.context, options, atom);
        if (has < 0) return error.JavaScriptException;
        if (has == 1 and c.JS_DefinePropertyValueStr(engine.context, error_value, "cause", try sdk.get(engine, options, "cause"), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return error.JavaScriptException;
    }
    return error_value;
}
fn errorConstructor(context: ?*c.JSContext, target: c.JSValue, argc: c_int, args: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    const prototype = sdk.get(engine, target, "prototype") catch |err| return sdk.fail(engine, err);
    defer engine.freeValue(prototype);
    return errorValue(engine, prototype, if (argc > 0) args[0] else c.pi_js_undefined(), if (argc > 1) args[1] else c.pi_js_undefined(), if (argc > 2) args[2] else c.pi_js_undefined(), if (argc > 3) args[3] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
pub fn install(engine: *engine_mod.Engine, exports: c.JSValue) !void {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const error_class = try sdk.get(engine, global, "Error");
    defer engine.freeValue(error_class);
    const base = try sdk.get(engine, error_class, "prototype");
    defer engine.freeValue(base);
    const prototype = try engine.checked(c.JS_NewObjectProto(engine.context, base));
    defer engine.freeValue(prototype);
    const constructor = try engine.checked(c.JS_NewCFunction2(engine.context, errorConstructor, "CredentialSynchronizationError", 4, c.JS_CFUNC_constructor, 0));
    defer engine.freeValue(constructor);
    _ = c.JS_SetConstructorBit(engine.context, constructor, true);
    if (c.JS_SetConstructor(engine.context, constructor, prototype) < 0) return error.JavaScriptException;
    try sdk.put(engine, exports, "CredentialSynchronizationError", c.JS_DupValue(engine.context, constructor));
    const private = try sdk.object(engine);
    defer engine.freeValue(private);
    try sdk.put(engine, private, "prototype", c.JS_DupValue(engine.context, prototype));
    try engine.registerValueModule(error_module, private);
}

test "SDK auth snapshot key synchronization roots and errors survive failed host allocations" {
    const Probe = struct {
        fn exercise(gpa: std.mem.Allocator) !void {
            const engine = try engine_mod.Engine.init(gpa, .{});
            defer engine.deinit();
            try @import("native_stream.zig").install(engine);
            const exports = try sdk.object(engine);
            defer engine.freeValue(exports);
            try sdk.install(engine, exports);
            try engine.registerValueModule("sdk-auth-allocations", exports);
            const evaluated = try engine.evalModule(
                "import {ModelRuntime,CredentialSynchronizationError} from 'sdk-auth-allocations';const r=await ModelRuntime.create({modelsPath:null,refreshOnCreate:false,credentials:{read:async()=>undefined,list:async()=>[]}});let failure;const rows=[{id:'m',provider:'p',type:'chat'}];r.registerNativeProvider({id:'p',auth:{apiKey:{check:async()=>{if(failure)throw failure;return {type:'api_key',source:'fixture'}},resolve:async()=>({auth:{apiKey:'key'}})}},getModels:()=>rows});await r.getAvailable();await r.getAvailable();if(!r.hasConfiguredAuth('p'))throw Error('cached');await r.setRuntimeApiKey('p','fixture');if(r.getProviderAuthStatus('p').source!=='runtime')throw Error('runtime');failure=new RangeError('failed');try{await r.setRuntimeApiKey('p','committed');throw Error('not failed')}catch(e){if(!(e instanceof CredentialSynchronizationError)||e.credential.key!=='committed')throw e}failure=undefined;await r.removeRuntimeApiKey('p');if(r.getError()!==undefined)throw Error('not cleared');globalThis.authAllocationRuntime=r;",
                "sdk-auth-allocations.mjs",
            );
            defer engine.freeValue(evaluated);
            const settled = try engine.awaitValue(evaluated);
            defer engine.freeValue(settled);
            const global = c.JS_GetGlobalObject(engine.context);
            defer engine.freeValue(global);
            const runtime = try sdk.get(engine, global, "authAllocationRuntime");
            defer engine.freeValue(runtime);
            var copied = (try @import("native_sdk_availability.zig").copySnapshot(engine, runtime, gpa)).?;
            defer copied.deinit();
            try std.testing.expect(copied.auth_known);
            try std.testing.expectEqualStrings("p", copied.configured_providers[0]);
            c.JS_RunGC(engine.runtime);
        }
        fn run(gpa: std.mem.Allocator) !void {
            exercise(gpa) catch |err| {
                const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
                if (failing.has_induced_failure and (err == error.OutOfMemory or err == error.JavaScriptException)) return error.OutOfMemory;
                std.debug.print("SDK auth allocation failure {s}; induced={any}; index={d}\n", .{ @errorName(err), failing.has_induced_failure, failing.alloc_index });
                return err;
            };
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}

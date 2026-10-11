//! Private resize API candidate. Arguments stay on the owner; codec work runs
//! in an independently owned VM. Public export waits for Source qualification.
const js = @import("native_js_values.zig");
const c = js.c;
const graph = @import("native_image_resize_options.zig");
const worker = @import("native_image_vm_worker.zig");
const promises = @import("native_image_worker_promise.zig");
const strategy = @import("native_image_resize_strategy.zig");
const function = @import("native_node_function.zig");
fn rejected(engine: *js.Engine, err: anyerror) !c.JSValue {
    const reason = if (err == error.JavaScriptException) blk: {
        _ = engine.throwCaptured();
        break :blk c.JS_GetException(engine.context);
    } else blk: {
        _ = engine.throwNativeOutOfMemory();
        break :blk c.JS_GetException(engine.context);
    };
    defer engine.freeValue(reason);
    var handlers: [2]c.JSValue = undefined;
    const promise = try engine.checked(c.JS_NewPromiseCapability(engine.context, &handlers));
    errdefer engine.freeValue(promise);
    defer for (handlers) |handler| engine.freeValue(handler);
    const ignored = try js.call(engine, handlers[1], c.pi_js_undefined(), &.{reason});
    engine.freeValue(ignored);
    return promise;
}
const BufferView = struct { backing: c.JSValue, bytes: []const u8 };
fn bytes(engine: *js.Engine, value: c.JSValue) !BufferView {
    var offset: usize = 0;
    var length: usize = 0;
    var element: usize = 0;
    const backing = try engine.checked(c.JS_GetTypedArrayBuffer(engine.context, value, &offset, &length, &element));
    errdefer engine.freeValue(backing);
    var total: usize = 0;
    const pointer = c.JS_GetArrayBuffer(engine.context, &total, backing);
    if (c.JS_HasException(engine.context)) return js.capture(engine);
    if (offset > total or length > total - offset or (pointer == null and length != 0)) return js.typeError(engine, "Invalid image byte buffer");
    return .{ .backing = backing, .bytes = if (length == 0) &.{} else pointer[offset .. offset + length] };
}
fn fallback(engine: *js.Engine, _: c.JSValue, _: []const c.JSValue, retained: []const c.JSValue) !c.JSValue {
    const input = try bytes(engine, retained[0]);
    defer engine.freeValue(input.backing);
    return strategy.resize(engine, input.bytes, retained[1], retained[2]);
}
fn invoke(engine: *js.Engine, _: c.JSValue, arguments: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return invokeAsync(engine, arguments) catch |err| rejected(engine, err);
}
fn invokeAsync(engine: *js.Engine, arguments: []const c.JSValue) !c.JSValue {
    const input = if (arguments.len > 0) arguments[0] else c.pi_js_undefined();
    const mime = if (arguments.len > 1) arguments[1] else c.pi_js_undefined();
    const options = if (arguments.len > 2) arguments[2] else c.pi_js_undefined();
    const on_failure = try function.create(engine, "", 1, fallback, &.{ input, mime, options });
    defer engine.freeValue(on_failure);
    const request = start(engine, input, mime, options) catch |err| {
        // Source attempts the original options again when clone/worker setup
        // fails. Discard that first error, preserving the fallback's exception.
        if (err == error.JavaScriptException) {
            _ = engine.throwCaptured();
            const ignored = c.JS_GetException(engine.context);
            engine.freeValue(ignored);
        }
        const result = fallback(engine, c.pi_js_undefined(), &.{}, &.{ input, mime, options }) catch |fallback_error| return rejected(engine, fallback_error);
        defer engine.freeValue(result);
        var handlers: [2]c.JSValue = undefined;
        const promise = try engine.checked(c.JS_NewPromiseCapability(engine.context, &handlers));
        errdefer engine.freeValue(promise);
        defer for (handlers) |handler| engine.freeValue(handler);
        const ignored = try js.call(engine, handlers[0], c.pi_js_undefined(), &.{result});
        engine.freeValue(ignored);
        return promise;
    };
    defer engine.freeValue(request);
    return js.invoke(engine, request, "then", &.{ c.pi_js_undefined(), on_failure });
}
fn start(engine: *js.Engine, input: c.JSValue, mime: c.JSValue, options: c.JSValue) !c.JSValue {
    const constructor = try js.global(engine, "Uint8Array");
    defer engine.freeValue(constructor);
    var constructor_arguments = [_]c.JSValue{input};
    const copied_value = try engine.checked(c.JS_CallConstructor(engine.context, constructor, 1, &constructor_arguments));
    defer engine.freeValue(copied_value);
    const view = try bytes(engine, copied_value);
    defer engine.freeValue(view.backing);
    // Source copies caller bytes before postMessage invokes option getters.
    // A getter may mutate the caller's original buffer during structured clone.
    const copied_input = try engine.gpa.dupe(u8, view.bytes);
    defer engine.gpa.free(copied_input);
    var encoded_mime = try graph.serializeForWorker(engine, mime);
    defer encoded_mime.deinit(engine.gpa);
    var encoded_options = try graph.serializeForWorker(engine, options);
    defer encoded_options.deinit(engine.gpa);
    const task = try worker.Worker.start(engine.gpa, copied_input, encoded_mime, encoded_options);
    return promises.create(engine, task) catch |err| {
        task.deinit();
        return err;
    };
}
pub fn create(engine: *js.Engine) !c.JSValue {
    return function.create(engine, "resizeImage", 3, invoke, &.{});
}

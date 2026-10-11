//! JavaScript-valued Photon strategy for an independently owned worker VM.
//! Promise transport and public installation are separate lifecycle steps.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
const p = @import("../ai/photon_session.zig");
const codec = p.operations;
const arithmetic = @import("native_image_arithmetic.zig");
const output = @import("native_image_codec_result.zig");
const defaults = @import("native_image_resize_options.zig");
const orientation = @import("../ai/photon_session_orientation.zig");
const exif = @import("../ai/photon_exif.zig");
const values = @import("native_select_list.zig");
const Context = struct {
    engine: *js.Engine,
    session: *p.Session,
    original: ?u32 = null,
    scaled: ?u32 = null,
    fn call(self: *Context, operation: p.Operation, handle: u32, input: ?[]const u8, width: u32, height: u32, quality: u32) !p.Reply {
        return self.session.checked(self.session.call(operation, handle, input, width, height, quality));
    }
};
fn runtimeError(engine: *js.Engine, message: []const u8) !c.JSValue {
    const failure = try engine.checked(c.JS_NewError(engine.context));
    errdefer engine.freeValue(failure);
    try js.define(engine, failure, "message", try values.text(engine, message));
    return failure;
}
pub fn resize(engine: *js.Engine, input: []const u8, mime: c.JSValue, options: c.JSValue) !c.JSValue {
    const opts = try defaults.spreadDefaults(engine, options);
    defer engine.freeValue(opts);
    const session = p.Session.init(engine.gpa) catch |err| return if (err == error.OutOfMemory) err else c.pi_js_null();
    defer session.deinit();
    var context: Context = .{ .engine = engine, .session = session };
    var cause: ?anyerror = null;
    const result = attempt(&context, input, mime, opts) catch |err| blk: {
        cause = err;
        if (err == error.JavaScriptException) {
            const failure = engine.throwCaptured();
            _ = failure;
            const captured = c.JS_GetException(engine.context);
            engine.freeValue(captured);
        }
        break :blk c.pi_js_null();
    };
    errdefer engine.freeValue(result);
    if (context.scaled) |handle| {
        const cleanup = try session.invoke(codec.PI_SESSION_FREE, handle, null, 0, 0, 0);
        switch (cleanup) {
            .value => |reply| session.freeReply(reply),
            .failure => |failure| {
                var owned = failure;
                owned.deinit(engine.gpa);
            },
        }
    }
    if (context.original) |handle| {
        const cleanup = try session.invoke(codec.PI_SESSION_FREE, handle, null, 0, 0, 0);
        switch (cleanup) {
            .value => |reply| session.freeReply(reply),
            .failure => |failure| {
                var owned = failure;
                defer owned.deinit(engine.gpa);
                const exception = try runtimeError(engine, owned.message orelse "Image codec failure");
                _ = try engine.checked(c.JS_Throw(engine.context, exception));
                unreachable;
            },
        }
    }
    if (cause) |err| if (err == error.OutOfMemory) return err;
    return result;
}
fn attempt(ctx: *Context, input: []const u8, mime: c.JSValue, opts: c.JSValue) !c.JSValue {
    const engine = ctx.engine;
    const raw = try ctx.call(codec.PI_SESSION_DECODE, 0, input, 0, 0, 0);
    const chosen = try orientation.apply(ctx.session, raw.image, exif.read(input));
    ctx.original = chosen;
    if (chosen != raw.image) _ = try ctx.call(codec.PI_SESSION_FREE, raw.image, null, 0, 0, 0);
    const dimensions = try ctx.call(codec.PI_SESSION_PIXELS, chosen, null, 0, 0, 0);
    defer ctx.session.freeReply(dimensions);
    const ow = c.JS_NewInt64(engine.context, dimensions.width);
    defer engine.freeValue(ow);
    const oh = c.JS_NewInt64(engine.context, dimensions.height);
    defer engine.freeValue(oh);
    const separator = try values.text(engine, "/");
    defer engine.freeValue(separator);
    const split = try js.invoke(engine, mime, "split", &.{separator});
    defer engine.freeValue(split);
    const format_value = try engine.checked(c.JS_GetPropertyUint32(engine.context, split, 1));
    defer engine.freeValue(format_value);
    const max_width = try js.get(engine, opts, "maxWidth");
    defer engine.freeValue(max_width);
    if (try arithmetic.compare(engine, .less_equal, ow, max_width)) {
        const max_height = try js.get(engine, opts, "maxHeight");
        defer engine.freeValue(max_height);
        if (try arithmetic.compare(engine, .less_equal, oh, max_height) and try arithmetic.fitsEncodedSize(engine, std.base64.standard.Encoder.calcSize(input.len), opts)) {
            var selected_mime = c.JS_DupValue(engine.context, mime);
            defer engine.freeValue(selected_mime);
            if (!values.truthy(engine, selected_mime)) {
                engine.freeValue(selected_mime);
                const prefix = try values.text(engine, "image/");
                defer engine.freeValue(prefix);
                const selected_format = if (c.JS_IsNull(format_value) or c.JS_IsUndefined(format_value)) try values.text(engine, "png") else c.JS_DupValue(engine.context, format_value);
                defer engine.freeValue(selected_format);
                selected_mime = try values.concat(engine, &.{ prefix, selected_format });
            }
            return output.create(engine, input, selected_mime, ow, oh, ow, oh, false);
        }
    }
    var size = try arithmetic.initialDimensions(engine, ow, oh, opts);
    defer size.deinit(engine);
    const qualities = try arithmetic.qualitySteps(engine, opts);
    defer engine.freeValue(qualities);
    while (true) {
        const scaled = try ctx.call(codec.PI_SESSION_RESIZE, chosen, null, try arithmetic.wasmDimension(engine, size.width), try arithmetic.wasmDimension(engine, size.height), 0);
        ctx.scaled = scaled.image;
        var candidates: std.ArrayList(p.Reply) = .empty;
        defer {
            for (candidates.items) |candidate| ctx.session.freeReply(candidate);
            candidates.deinit(engine.gpa);
        }
        const png = try ctx.call(codec.PI_SESSION_PNG, scaled.image, null, 0, 0, 0);
        candidates.append(engine.gpa, png) catch |err| {
            ctx.session.freeReply(png);
            return err;
        };
        const symbol = try engine.checked(c.JS_GetIteratorSymbol(engine.context));
        defer engine.freeValue(symbol);
        const quality_values = try js.collect(engine, qualities, symbol);
        defer engine.freeValue(quality_values);
        const length = try js.get(engine, quality_values, "length");
        defer engine.freeValue(length);
        const count = try arithmetic.wasmDimension(engine, length);
        for (0..count) |index| {
            const quality = try engine.checked(c.JS_GetPropertyUint32(engine.context, quality_values, @intCast(index)));
            defer engine.freeValue(quality);
            const candidate = try ctx.call(codec.PI_SESSION_JPEG, scaled.image, null, 0, 0, try arithmetic.wasmDimension(engine, quality));
            candidates.append(engine.gpa, candidate) catch |err| {
                ctx.session.freeReply(candidate);
                return err;
            };
        }
        var selected: ?c.JSValue = null;
        for (candidates.items, 0..) |candidate, index| if (try arithmetic.fitsEncodedSize(engine, std.base64.standard.Encoder.calcSize(candidate.length), opts)) {
            const format = try values.text(engine, if (index == 0) "image/png" else "image/jpeg");
            defer engine.freeValue(format);
            selected = try output.create(engine, candidate.bytes[0..candidate.length], format, ow, oh, size.width, size.height, true);
            break;
        };
        errdefer if (selected) |value| engine.freeValue(value);
        ctx.scaled = null;
        _ = try ctx.call(codec.PI_SESSION_FREE, scaled.image, null, 0, 0, 0);
        if (selected) |value| return value;
        const one = c.JS_NewInt32(engine.context, 1);
        if (c.JS_IsStrictEqual(engine.context, size.width, one) and c.JS_IsStrictEqual(engine.context, size.height, one)) return c.pi_js_null();
        const next_width = try arithmetic.nextDimension(engine, size.width);
        errdefer engine.freeValue(next_width);
        const next_height = try arithmetic.nextDimension(engine, size.height);
        if (c.JS_IsStrictEqual(engine.context, next_width, size.width) and c.JS_IsStrictEqual(engine.context, next_height, size.height)) {
            engine.freeValue(next_width);
            engine.freeValue(next_height);
            return c.pi_js_null();
        }
        engine.freeValue(size.width);
        engine.freeValue(size.height);
        size = .{ .width = next_width, .height = next_height };
    }
}

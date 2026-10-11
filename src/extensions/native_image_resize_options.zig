//! Source default spread and worker-clone boundary. Keep own undefined values.
const js = @import("native_js_values.zig");
const c = js.c;
const values = @import("native_select_list.zig");
const std = @import("std");
pub const Serialized = struct {
    bytes: []u8,
    pub fn deinit(self: *Serialized, allocator: std.mem.Allocator) void {
        allocator.free(self.bytes);
        self.* = undefined;
    }
    pub fn read(self: Serialized, engine: *js.Engine) !c.JSValue {
        return engine.checked(c.JS_ReadObject(engine.context, self.bytes.ptr, self.bytes.len, c.JS_READ_OBJ_REFERENCE));
    }
};
/// Clone getters run on the owner, while worker option arithmetic uses the
/// independent receiver graph. Serialized data cannot contain bytecode.
pub fn serializeForWorker(engine: *js.Engine, options: c.JSValue) !Serialized {
    const cloned = try cloneForWorker(engine, options);
    defer engine.freeValue(cloned);
    var size: usize = 0;
    const bytes = c.JS_WriteObject(engine.context, &size, cloned, c.JS_WRITE_OBJ_REFERENCE);
    if (bytes == null) return js.capture(engine);
    defer c.js_free(engine.context, bytes);
    return .{ .bytes = try engine.gpa.dupe(u8, bytes[0..size]) };
}
pub fn spreadDefaults(engine: *js.Engine, options: c.JSValue) !c.JSValue {
    const result = try js.object(engine);
    errdefer engine.freeValue(result);
    inline for (.{ .{ "maxWidth", 2000.0 }, .{ "maxHeight", 2000.0 }, .{ "maxBytes", 4718592.0 }, .{ "jpegQuality", 80.0 } }) |field|
        try js.define(engine, result, field[0], values.numeric(engine, field[1]));
    try js.spreadInto(engine, result, options);
    return result;
}
pub fn cloneForWorker(engine: *js.Engine, options: c.JSValue) !c.JSValue {
    return @import("native_structured_clone.zig").clone(engine, options);
}

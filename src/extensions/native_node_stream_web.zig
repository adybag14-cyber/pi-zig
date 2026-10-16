//! Full node:stream/web builtin object with seventeen actual native classes.
//! registerDefaultModule supplies the separate eighteenth ESM default binding.
const em = @import("engine.zig");
const Scope = @import("native_models_stream_scope.zig").Scope;
const c = em.c;
pub fn install(engine: *em.Engine) !void {
    if (engine.native_module_values.contains("node:stream/web")) return;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try scope.object();
    const readable = try scope.own(try @import("native_readable_stream.zig").exports(engine));
    const writable = try scope.own(try @import("native_writable_stream.zig").exports(engine));
    const transform = try scope.own(try @import("native_transform_stream.zig").exports(engine));
    const queuing = try scope.own(try @import("native_queuing_strategy.zig").exports(engine));
    const text = try scope.own(try @import("native_text_stream.zig").exports(engine));
    const compression = try scope.own(try @import("native_compression_stream.zig").exports(engine));
    // Actual bundled Node object's insertion order. Every value comes from its
    // native owner's captured constructor, never a mutable public global.
    inline for (.{ "ReadableStream", "ReadableStreamDefaultReader", "ReadableStreamBYOBReader", "ReadableStreamBYOBRequest", "ReadableByteStreamController", "ReadableStreamDefaultController" }) |name| try scope.put(result, name, try scope.get(readable, name));
    inline for (.{ "TransformStream", "TransformStreamDefaultController" }) |name| try scope.put(result, name, try scope.get(transform, name));
    inline for (.{ "WritableStream", "WritableStreamDefaultWriter", "WritableStreamDefaultController" }) |name| try scope.put(result, name, try scope.get(writable, name));
    inline for (.{ "ByteLengthQueuingStrategy", "CountQueuingStrategy" }) |name| try scope.put(result, name, try scope.get(queuing, name));
    inline for (.{ "TextEncoderStream", "TextDecoderStream" }) |name| try scope.put(result, name, try scope.get(text, name));
    inline for (.{ "CompressionStream", "DecompressionStream" }) |name| try scope.put(result, name, try scope.get(compression, name));
    try engine.registerDefaultModule("node:stream/web", result);
}

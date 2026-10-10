const std = @import("std");
const sdk = @import("extensions/native_sdk.zig");
const engine_mod = @import("extensions/engine.zig");
const config = @import("extensions/native_sdk_model_config.zig");
const c = engine_mod.c;
test "SDK immutable model configuration schema parse and roots survive host allocation failures" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const io = std.testing.io;
    try temporary.dir.writeFile(io, .{ .sub_path = "valid.json", .data = "\xef\xbb\xbf{// source\n\"providers\":{\"p\":{\"api\":\"openai-completions\",\"apiKey\":\"fixture\",\"baseUrl\":\"https://fixture.invalid\",\"models\":[{\"id\":\"m\",\"compat\":{\"supportsStore\":false},\"samplingParams\":{\"nested\":{\"safe\":true}},},],},},}" });
    try temporary.dir.writeFile(io, .{ .sub_path = "invalid.json", .data = "{\"providers\":{\"p\":{\"models\":[{\"id\":3,\"input\":[\"audio\"],\"inputLimits\":{\"maxRequestBytes\":0}}]}}}" });
    try temporary.dir.writeFile(io, .{ .sub_path = "parse.json", .data = "{broken" });
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const count = try temporary.dir.realPath(io, &buffer);
    const root = buffer[0..count];
    const Probe = struct {
        fn exercise(gpa: std.mem.Allocator, directory: []const u8) !void {
            const engine = try engine_mod.Engine.init(gpa, .{});
            defer engine.deinit();
            engine.native_io = std.testing.io;
            const options = try sdk.object(engine);
            defer engine.freeValue(options);
            inline for (.{ "valid.json", "invalid.json", "parse.json" }) |name| {
                const path = try std.fs.path.join(gpa, &.{ directory, name });
                defer gpa.free(path);
                try sdk.put(engine, options, "modelsPath", try sdk.text(engine, path));
                const loaded = try config.load(engine, options);
                defer engine.freeValue(loaded);
                const error_value = try sdk.get(engine, loaded, "error");
                defer engine.freeValue(error_value);
                if (comptime std.mem.eql(u8, name, "valid.json")) {
                    try std.testing.expect(c.JS_IsUndefined(error_value));
                    const providers = try sdk.get(engine, loaded, "providers");
                    defer engine.freeValue(providers);
                    const provider = try sdk.get(engine, providers, "p");
                    defer engine.freeValue(provider);
                    const global = c.JS_GetGlobalObject(engine.context);
                    defer engine.freeValue(global);
                    const object = try sdk.get(engine, global, "Object");
                    defer engine.freeValue(object);
                    const frozen = try sdk.invoke(engine, object, "isFrozen", &.{provider});
                    defer engine.freeValue(frozen);
                    try std.testing.expectEqual(@as(c_int, 1), c.JS_ToBool(engine.context, frozen));
                } else try std.testing.expect(c.JS_IsString(error_value));
                c.JS_RunGC(engine.runtime);
            }
        }
        fn run(gpa: std.mem.Allocator, directory: []const u8) !void {
            exercise(gpa, directory) catch |err| {
                const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
                if (failing.has_induced_failure and (err == error.OutOfMemory or err == error.JavaScriptException)) return error.OutOfMemory;
                std.debug.print("SDK model config allocation failure {s}, induced={any}, index={d}\n", .{ @errorName(err), failing.has_induced_failure, failing.alloc_index });
                return err;
            };
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{root});
}
test "SDK config template references preserve source escaping duplicates and unusual identifiers" {
    const values = @import("extensions/native_sdk_config_value.zig");
    const actual = try values.names(std.testing.allocator, "$A-${B}-$A-$$C-$!D-${not.valid}-$9-$left_right");
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqual(@as(usize, 3), actual.len);
    try std.testing.expectEqualStrings("A", actual[0]);
    try std.testing.expectEqualStrings("B", actual[1]);
    try std.testing.expectEqualStrings("left_right", actual[2]);
}

//! Owned worker VM. Only serialized data crosses its thread boundary.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
const options = @import("native_image_resize_options.zig");
const strategy = @import("native_image_resize_strategy.zig");
pub const Worker = struct {
    allocator: std.mem.Allocator,
    input: []u8,
    mime: options.Serialized,
    options: options.Serialized,
    output: ?[]u8 = null,
    message: ?[]u8 = null,
    failure: ?anyerror = null,
    done: std.atomic.Value(bool) = .init(false),
    thread: ?std.Thread = null,
    pub fn start(allocator: std.mem.Allocator, input: []const u8, mime: options.Serialized, request_options: options.Serialized) !*Worker {
        const self = try allocator.create(Worker);
        errdefer allocator.destroy(self);
        const bytes = try allocator.dupe(u8, input);
        errdefer allocator.free(bytes);
        const mime_copy = try allocator.dupe(u8, mime.bytes);
        errdefer allocator.free(mime_copy);
        const option_copy = try allocator.dupe(u8, request_options.bytes);
        errdefer allocator.free(option_copy);
        self.* = .{ .allocator = allocator, .input = bytes, .mime = .{ .bytes = mime_copy }, .options = .{ .bytes = option_copy } };
        self.thread = try std.Thread.spawn(.{}, run, .{self});
        return self;
    }
    fn run(self: *Worker) void {
        self.execute() catch |err| {
            self.failure = err;
        };
        self.done.store(true, .release);
    }
    fn execute(self: *Worker) !void {
        const engine = try js.Engine.init(self.allocator, .{});
        defer engine.deinit();
        const mime = try self.mime.read(engine);
        defer engine.freeValue(mime);
        const request_options = try self.options.read(engine);
        defer engine.freeValue(request_options);
        const result = strategy.resize(engine, self.input, mime, request_options) catch |err| {
            if (engine.last_error) |message| self.message = try self.allocator.dupe(u8, message);
            return err;
        };
        defer engine.freeValue(result);
        var length: usize = 0;
        const encoded = c.JS_WriteObject(engine.context, &length, result, c.JS_WRITE_OBJ_REFERENCE);
        if (encoded == null) return js.capture(engine);
        defer c.js_free(engine.context, encoded);
        self.output = try self.allocator.dupe(u8, encoded[0..length]);
    }
    pub fn isDone(self: *Worker) bool {
        return self.done.load(.acquire);
    }
    pub fn join(self: *Worker) void {
        if (self.thread) |thread| {
            thread.join();
            self.thread = null;
        }
    }
    pub fn result(self: *Worker, engine: *js.Engine) !c.JSValue {
        self.join();
        if (self.failure) |err| return err;
        const bytes = self.output orelse return error.ImageWorkerMissingResult;
        return engine.checked(c.JS_ReadObject(engine.context, bytes.ptr, bytes.len, c.JS_READ_OBJ_REFERENCE));
    }
    pub fn deinit(self: *Worker) void {
        self.join();
        if (self.output) |bytes| self.allocator.free(bytes);
        if (self.message) |bytes| self.allocator.free(bytes);
        self.mime.deinit(self.allocator);
        self.options.deinit(self.allocator);
        self.allocator.free(self.input);
        self.allocator.destroy(self);
    }
};

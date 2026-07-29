//! print / json event stream / rpc JSONL modes.
const std = @import("std");
const Io = std.Io;
const agent_loop = @import("../agent/loop.zig");
const tui_render = @import("../tui/render.zig");

pub const JsonEmitter = struct {
    io: Io,

    pub fn emit(self: JsonEmitter, kind: []const u8, fields: anytype) !void {
        var aw: std.Io.Writer.Allocating = .init(std.heap.page_allocator);
        defer aw.deinit();
        try aw.writer.writeAll("{\"type\":");
        try std.json.Stringify.value(kind, .{}, &aw.writer);
        // fields is a struct of optional slices
        inline for (std.meta.fields(@TypeOf(fields))) |f| {
            const val = @field(fields, f.name);
            if (@TypeOf(val) == []const u8) {
                try aw.writer.writeAll(",\"");
                try aw.writer.writeAll(f.name);
                try aw.writer.writeAll("\":");
                try std.json.Stringify.value(val, .{}, &aw.writer);
            } else if (@TypeOf(val) == bool) {
                try aw.writer.writeAll(",\"");
                try aw.writer.writeAll(f.name);
                try aw.writer.writeAll("\":");
                try aw.writer.writeAll(if (val) "true" else "false");
            } else if (@TypeOf(val) == usize or @TypeOf(val) == i32 or @TypeOf(val) == u64) {
                try aw.writer.writeAll(",\"");
                try aw.writer.writeAll(f.name);
                try aw.writer.writeAll("\":");
                try aw.writer.print("{d}", .{val});
            }
        }
        try aw.writer.writeAll("}\n");
        try tui_render.writeAll(self.io, aw.written());
    }

    pub fn onEvent(ctx: ?*anyopaque, event: agent_loop.AgentEvent) void {
        const self: *JsonEmitter = @ptrCast(@alignCast(ctx.?));
        const kind = switch (event.kind) {
            .user => "user",
            .assistant => "assistant",
            .tool_call => "tool_call",
            .tool_result => "tool_result",
            .done => "done",
            .turn_limit => "turn_limit",
        };
        self.emit(kind, .{
            .text = event.text,
            .name = event.name,
            .id = event.id,
        }) catch {};
    }
};

pub const PrintEmitter = struct {
    io: Io,
    verbose: bool = false,

    pub fn onEvent(ctx: ?*anyopaque, event: agent_loop.AgentEvent) void {
        const self: *PrintEmitter = @ptrCast(@alignCast(ctx.?));
        switch (event.kind) {
            .assistant => {
                // Intermediate assistant turns only when verbose; final text is printed by caller.
                if (self.verbose) tui_render.renderAssistant(self.io, event.text) catch {};
            },
            .tool_call => {
                if (self.verbose) tui_render.renderToolCall(self.io, event.name, event.text) catch {};
            },
            .tool_result => {
                if (self.verbose) tui_render.renderToolResult(self.io, event.name, event.text, false) catch {};
            },
            else => {},
        }
    }
};

pub const RpcRequest = struct {
    id: []const u8,
    method: []const u8,
    params_prompt: ?[]const u8 = null,
};

/// Parse one JSONL RPC line: {id, method, params}
pub fn parseRpcLine(gpa: std.mem.Allocator, line: []const u8) !RpcRequest {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, line, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidRpc;
    const id_v = parsed.value.object.get("id") orelse return error.InvalidRpc;
    const method_v = parsed.value.object.get("method") orelse return error.InvalidRpc;
    const id = switch (id_v) {
        .string => |s| try gpa.dupe(u8, s),
        .integer => |i| try std.fmt.allocPrint(gpa, "{d}", .{i}),
        else => return error.InvalidRpc,
    };
    errdefer gpa.free(id);
    if (method_v != .string) return error.InvalidRpc;
    var prompt: ?[]const u8 = null;
    if (parsed.value.object.get("params")) |params| {
        if (params == .object) {
            if (params.object.get("prompt") orelse params.object.get("text")) |p| {
                if (p == .string) prompt = try gpa.dupe(u8, p.string);
            }
        } else if (params == .string) {
            prompt = try gpa.dupe(u8, params.string);
        }
    }
    return .{
        .id = id,
        .method = try gpa.dupe(u8, method_v.string),
        .params_prompt = prompt,
    };
}

pub fn freeRpcRequest(gpa: std.mem.Allocator, req: *RpcRequest) void {
    gpa.free(req.id);
    gpa.free(req.method);
    if (req.params_prompt) |p| gpa.free(p);
    req.* = undefined;
}

pub fn writeRpcResult(io: Io, id: []const u8, result_text: []const u8) !void {
    var aw: std.Io.Writer.Allocating = .init(std.heap.page_allocator);
    defer aw.deinit();
    try aw.writer.writeAll("{\"id\":");
    try std.json.Stringify.value(id, .{}, &aw.writer);
    try aw.writer.writeAll(",\"result\":");
    try std.json.Stringify.value(result_text, .{}, &aw.writer);
    try aw.writer.writeAll("}\n");
    try tui_render.writeAll(io, aw.written());
}

pub fn writeRpcError(io: Io, id: []const u8, message: []const u8) !void {
    var aw: std.Io.Writer.Allocating = .init(std.heap.page_allocator);
    defer aw.deinit();
    try aw.writer.writeAll("{\"id\":");
    try std.json.Stringify.value(id, .{}, &aw.writer);
    try aw.writer.writeAll(",\"error\":");
    try std.json.Stringify.value(message, .{}, &aw.writer);
    try aw.writer.writeAll("}\n");
    try tui_render.writeAll(io, aw.written());
}

test "parse rpc prompt" {
    const gpa = std.testing.allocator;
    var req = try parseRpcLine(gpa,
        \\{"id":"1","method":"prompt","params":{"prompt":"hi"}}
    );
    defer freeRpcRequest(gpa, &req);
    try std.testing.expectEqualStrings("1", req.id);
    try std.testing.expectEqualStrings("prompt", req.method);
    try std.testing.expectEqualStrings("hi", req.params_prompt.?);
}

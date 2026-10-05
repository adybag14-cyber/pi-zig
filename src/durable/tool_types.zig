//! Owned structured results. Native errors retain their original typed cause.
const std = @import("std");
const types = @import("types.zig");
const shell = @import("shell.zig");
const truncate = @import("truncate.zig");
pub const Severity = enum { info, warn, err };
pub const Diagnostic = struct { severity: Severity, code: ?[]const u8 = null, message: []u8 };
pub const EditDetails = struct { diff: []u8, patch: []u8, firstChangedLine: ?u64 = null };
pub const Details = union(enum) { truncation: truncate.Details, edit: EditDetails };
pub const ToolResult = struct {
    /// null and the empty string both serialize to an empty content array.
    text: ?[]u8 = null,
    isError: bool = false,
    diagnostics: std.ArrayList(Diagnostic) = .empty,
    details: ?Details = null,
    pub fn deinit(self: *ToolResult, gpa: std.mem.Allocator) void {
        if (self.text) |text| gpa.free(text);
        for (self.diagnostics.items) |item| gpa.free(item.message);
        self.diagnostics.deinit(gpa);
        if (self.details) |details| switch (details) {
            .edit => |edit| {
                gpa.free(edit.diff);
                gpa.free(edit.patch);
            },
            .truncation => {},
        };
        self.* = undefined;
    }
    pub fn diagnostic(self: *ToolResult, gpa: std.mem.Allocator, severity: Severity, code: ?[]const u8, message: []u8) !void {
        errdefer gpa.free(message);
        try self.diagnostics.append(gpa, .{ .severity = severity, .code = code, .message = message });
    }
};
pub const Failure = struct {
    message: []u8,
    cause: ?anyerror = null,
    file: ?types.FileError = null,
    execution: ?shell.ExecutionError = null,
    diagnostics: std.ArrayList(Diagnostic) = .empty,
    pub fn deinit(self: *Failure, gpa: std.mem.Allocator) void {
        gpa.free(self.message);
        if (self.file) |*file| file.deinit(gpa);
        if (self.execution) |*execution| execution.deinit(gpa);
        for (self.diagnostics.items) |item| gpa.free(item.message);
        self.diagnostics.deinit(gpa);
        self.* = undefined;
    }
};
pub const Result = union(enum) {
    value: ToolResult,
    failure: Failure,
    pub fn deinit(self: *Result, gpa: std.mem.Allocator) void {
        switch (self.*) {
            .value => |*value| value.deinit(gpa),
            .failure => |*value| value.deinit(gpa),
        }
    }
};
pub fn fileFailure(gpa: std.mem.Allocator, file: types.FileError) !Result {
    var owned = file;
    errdefer owned.deinit(gpa);
    return .{ .failure = .{ .message = try gpa.dupe(u8, file.message), .cause = file.cause, .file = file } };
}
pub fn messageFailure(gpa: std.mem.Allocator, message: []const u8, cause: ?anyerror) !Result {
    return .{ .failure = .{ .message = try gpa.dupe(u8, message), .cause = cause } };
}

//! Prepared actual host-allocation control, not a result or replacement owner.
//! Root supplies a fresh real composition and admits the eventual test target.
const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const c = v.c;
pub const Observation = struct { fail_after: usize, admitted_public_names: usize, immutable_partial: bool };
fn published(engine: *v.em.Engine) usize {
    var count: usize = 0;
    inline for (.{ "node:net", "net", "node:util", "util", "node:readline", "readline", "node:tty", "tty" }) |name| {
        if (engine.native_module_names.contains(name) or engine.native_builtin_aliases.contains(name)) count += 1;
    }
    return count;
}
/// Call on a fresh Engine. fail_after=0 exercises the first actual public
/// registration allocation, with an older captured sentinel deliberately live.
/// Later fail indices can observe immutable partial publication; the controller
/// must record that observation rather than invent its allocation position.
pub fn run(comptime ActualAssembly: type, engine: *v.em.Engine, actual: ActualAssembly.Inputs, fail_after: usize) !Observation {
    const first = try ActualAssembly.create(engine, actual); defer first.deinit(engine);
    try std.testing.expectEqual(@as(usize, 0), published(engine));
    const sentinel = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(sentinel);
    const prior = engine.captured_exception; engine.captured_exception = c.JS_DupValue(engine.context, sentinel);
    defer {
        if (engine.captured_exception) |reason| engine.freeValue(reason);
        engine.captured_exception = prior;
    }
    const actual_gpa = engine.gpa;
    var failing = std.testing.FailingAllocator.init(actual_gpa, .{ .fail_index = fail_after, .resize_fail_index = 0 });
    engine.gpa = failing.allocator(); defer engine.gpa = actual_gpa;
    const unexpected = ActualAssembly.install(engine, actual) catch |err| {
        engine.gpa = actual_gpa;
        try std.testing.expect(failing.has_induced_failure);
        // The finite first-allocation profile is host OOM with no new VM
        // event. Old captured history must not become the sticky JS reason.
        if (fail_after == 0) {
            try std.testing.expect(err == error.OutOfMemory);
            try std.testing.expect(!c.JS_HasException(engine.context));
            try std.testing.expect(c.JS_IsStrictEqual(engine.context, sentinel, engine.captured_exception.?));
        }
        const names_after_failure = published(engine);
        const first_reason: ?c.JSValue = if (engine.captured_exception) |reason| c.JS_DupValue(engine.context, reason) else null;
        defer if (first_reason) |reason| engine.freeValue(reason);
        const retried = ActualAssembly.install(engine, actual) catch |again| {
            try std.testing.expect(again == err);
            try std.testing.expectEqual(names_after_failure, published(engine));
            if (first_reason) |reason| try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, engine.captured_exception orelse return error.MissingActualPublicationReason));
            const same = try ActualAssembly.create(engine, actual); defer same.deinit(engine);
            inline for (std.meta.fields(ActualAssembly.Exports)) |field| try std.testing.expect(c.JS_IsStrictEqual(engine.context, @field(first, field.name), @field(same, field.name)));
            return .{ .fail_after = fail_after, .admitted_public_names = names_after_failure, .immutable_partial = names_after_failure != 0 };
        };
        retried.deinit(engine); return error.ExpectedStickyActualPublicationFailure;
    };
    unexpected.deinit(engine); return error.ExpectedActualPublicationAllocationFailure;
}

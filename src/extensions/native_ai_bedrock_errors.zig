//! Exact owner-thread Bedrock SDK HTTP error adaptation.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const flow = @import("native_agent_async.zig");
const wire = @import("native_ai_bedrock_wire.zig");
pub fn http(s: *Scope, response: c.JSValue, request_id: c.JSValue, body: c.JSValue) !c.JSValue {
    var guard = @import("native_ai_json_scope.zig").Guard.enter(s.engine);
    defer guard.deinit();
    var parse_failure = false;
    const parsed = s.invoke(try s.global("JSON"), "parse", &.{body}) catch |err| blk: {
        parse_failure = true;
        const reason = try s.own(flow.reason(s.engine, err));
        if (s.engine.captured_exception) |captured| {
            s.engine.captured_exception = null;
            s.engine.freeValue(captured);
        }
        const message = try s.get(reason, "message");
        try s.set(reason, "message", try s.concat(message, try s.text("\n  Deserialization error: to see the raw response, inspect the hidden field {error}.$response on this object.")));
        break :blk reason;
    };
    const error_value = if (parse_failure) parsed else blk: {
        var code = try v.optional(s, parsed, "code");
        if (!s.truthy(code)) code = try v.optional(s, parsed, "__type");
        if (!s.truthy(code)) code = try s.text("Unknown");
        const raw = try s.engine.toString(code);
        defer s.engine.gpa.free(raw);
        const name = if (std.mem.lastIndexOfScalar(u8, raw, '#')) |i| raw[i + 1 ..] else raw;
        break :blk try wire.serviceError(s, name, parsed);
    };
    const metadata = try s.object();
    try s.put(metadata, "httpStatusCode", try s.get(response, "status"));
    try s.put(metadata, "requestId", request_id);
    try s.put(error_value, "$metadata", metadata);
    return error_value;
}

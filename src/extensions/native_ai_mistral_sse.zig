//! Mistral's actual UTF-8/event-boundary/data-line parser over owned byte frames.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
pub fn init(scope: *Scope, owner: c.JSValue) !void {
    try scope.put(owner, "mistralBuffer", try scope.text(""));
    try scope.put(owner, "mistralEof", c.pi_js_bool(scope.engine.context, 0));
    try scope.put(owner, "mistralDecoder", try scope.own(try v.js.builtin(scope.engine, "TextDecoder", &.{})));
    try scope.put(owner, "mistralBoundary", try scope.own(try v.js.builtin(scope.engine, "RegExp", &.{try scope.text("\\r\\n\\r\\n|\\r\\n\\r|\\r\\n\\n|\\r\\r\\n|\\n\\r\\n|\\r\\r|\\n\\r|\\n\\n")})));
    try scope.put(owner, "mistralLine", try scope.own(try v.js.builtin(scope.engine, "RegExp", &.{try scope.text("\\r\\n|\\r|\\n")})));
}
pub fn feed(scope: *Scope, owner: c.JSValue, bytes: c.JSValue, eof: bool) !void {
    const options = try scope.object();
    try scope.put(options, "stream", c.pi_js_bool(scope.engine.context, @intFromBool(!eof)));
    const decoded = if (eof) try scope.invoke(try scope.get(owner, "mistralDecoder"), "decode", &.{}) else try scope.invoke(try scope.get(owner, "mistralDecoder"), "decode", &.{ bytes, options });
    const combined = try scope.concat(try scope.get(owner, "mistralBuffer"), decoded);
    if (try v.length(scope, combined) > @import("native_ai_http_worker.zig").maximum_frame_bytes) return error.NativeMistralEventLimit;
    try scope.put(owner, "mistralBuffer", combined);
    if (eof) try scope.put(owner, "mistralEof", c.pi_js_bool(scope.engine.context, 1));
}
pub const Event = union(enum) { need_bytes, eof, done, data: c.JSValue };
pub fn pop(scope: *Scope, owner: c.JSValue) !Event {
    var steps: usize = 0;
    while (true) {
        try @import("native_ai_budget.zig").step(scope.engine, &steps);
        const buffer = try scope.get(owner, "mistralBuffer");
        const boundary = try scope.invoke(try scope.get(owner, "mistralBoundary"), "exec", &.{buffer});
        var event = c.pi_js_undefined();
        if (scope.truthy(boundary)) {
            const index = try scope.get(boundary, "index");
            event = try scope.invoke(buffer, "slice", &.{ c.JS_NewInt32(scope.engine.context, 0), index });
            const length = try scope.get(try v.at(scope, boundary, 0), "length");
            const after = try scope.own(try @import("native_image_arithmetic.zig").binary(scope.engine, .add, index, length));
            try scope.put(owner, "mistralBuffer", try scope.invoke(buffer, "slice", &.{after}));
        } else if (scope.truthy(try scope.get(owner, "mistralEof"))) {
            if (try v.length(scope, try scope.invoke(buffer, "trim", &.{})) == 0) return .eof;
            event = buffer;
            try scope.put(owner, "mistralBuffer", try scope.text(""));
        } else return .need_bytes;
        const lines = try scope.invoke(event, "split", &.{try scope.get(owner, "mistralLine")});
        const fields = try scope.array();
        var rows = try v.iterator(scope, lines);
        defer rows.deinit();
        errdefer rows.closePreserving();
        while (try rows.next()) |line| {
            defer scope.engine.freeValue(line);
            if (!scope.truthy(try scope.invoke(line, "startsWith", &.{try scope.text("data:")}))) continue;
            const value = try scope.invoke(try scope.invoke(line, "slice", &.{c.JS_NewInt32(scope.engine.context, 5)}), "trimStart", &.{});
            _ = try scope.invoke(fields, "push", &.{value});
        }
        const data = try scope.invoke(try scope.invoke(fields, "join", &.{try scope.text("\n")}), "trim", &.{});
        if (!scope.truthy(data)) continue;
        if (try v.eq(scope, data, "[DONE]")) return .done;
        const parsed = try scope.invoke(try scope.global("JSON"), "parse", &.{data});
        if (!c.JS_IsObject(parsed) or c.JS_IsNull(parsed) or try v.array(scope, parsed) or !try v.array(scope, try scope.get(parsed, "choices"))) return v.errorText(scope, try scope.text("Invalid Mistral streaming event"));
        return .{ .data = parsed };
    }
}

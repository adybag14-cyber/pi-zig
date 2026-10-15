//! Exact pinned SDK processStreamResponse framing, distinct from Mistral/SSE.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
pub fn init(scope: *Scope, owner: c.JSValue) !void {
    try scope.put(owner, "buffer", try scope.text(""));
    try scope.put(owner, "decoder", try scope.own(try v.js.builtin(scope.engine, "TextDecoder", &.{try scope.text("utf-8")})));
    const delimiters = try scope.array();
    try scope.index(delimiters, 0, try scope.text("\n\n"));
    try scope.index(delimiters, 1, try scope.text("\r\r"));
    try scope.index(delimiters, 2, try scope.text("\r\n\r\n"));
    try scope.put(owner, "delimiters", delimiters);
}
fn streamedError(scope: *Scope, chunk: c.JSValue) !void {
    const json = try scope.global("JSON");
    const parsed = try scope.invoke(json, "parse", &.{chunk});
    if (!c.JS_IsObject(parsed)) return v.js.typeError(scope.engine, "right operand of 'in' is not an object");
    if (!try v.js.hasKey(scope.engine, parsed, try scope.text("error"))) return;
    const error_json = try scope.invoke(json, "parse", &.{try scope.invoke(json, "stringify", &.{try scope.get(parsed, "error")})});
    const status = try scope.get(error_json, "status");
    const code = try scope.get(error_json, "code");
    const arithmetic = @import("native_image_arithmetic.zig");
    if (try arithmetic.compare(scope.engine, .greater_equal, code, c.JS_NewInt32(scope.engine.context, 400)) and try arithmetic.compare(scope.engine, .less, code, c.JS_NewInt32(scope.engine.context, 600))) {
        const message = try scope.concat(try scope.concat(try scope.concat(try scope.text("got status: "), try scope.stringify(status)), try scope.text(". ")), try scope.invoke(json, "stringify", &.{parsed}));
        const reason = try scope.own(try v.js.builtin(scope.engine, "Error", &.{message}));
        try scope.set(reason, "name", try scope.text("ApiError"));
        try scope.set(reason, "status", code);
        _ = try scope.engine.checked(c.JS_Throw(scope.engine.context, c.JS_DupValue(scope.engine.context, reason)));
        unreachable;
    }
}
pub fn feed(scope: *Scope, owner: c.JSValue, bytes: c.JSValue) !void {
    const options = try scope.object();
    try scope.put(options, "stream", c.pi_js_bool(scope.engine.context, 1));
    const chunk = try scope.invoke(try scope.get(owner, "decoder"), "decode", &.{ bytes, options });
    const generation = scope.engine.native_allocation_generation;
    streamedError(scope, chunk) catch |err| {
        if (err != error.JavaScriptException or scope.engine.native_allocation_generation != generation) return err;
        const reason = try scope.own(@import("native_agent_async.zig").reason(scope.engine, err));
        if (try v.eq(scope, try scope.get(reason, "name"), "ApiError")) return err;
        try @import("native_ai_partial_json.zig").discard(scope.engine, err, generation);
    };
    const combined = try scope.concat(try scope.get(owner, "buffer"), chunk);
    if (try v.length(scope, combined) > @import("native_ai_http_worker.zig").maximum_frame_bytes) return error.NativeGoogleEventLimit;
    try scope.put(owner, "buffer", combined);
}
pub fn eof(scope: *Scope, owner: c.JSValue) !void {
    // Source deliberately does not flush TextDecoder at EOF.
    if (try v.length(scope, try scope.invoke(try scope.get(owner, "buffer"), "trim", &.{})) > 0) return v.errorText(scope, try scope.text("Incomplete JSON segment at the end"));
}
pub fn pop(scope: *Scope, owner: c.JSValue) !?c.JSValue {
    var steps: usize = 0;
    while (true) {
        try @import("native_ai_budget.zig").step(scope.engine, &steps);
        const buffer = try scope.get(owner, "buffer");
        var selected: i32 = -1;
        var delimiter_length: c.JSValue = c.JS_NewInt32(scope.engine.context, 0);
        var delimiters = try v.iterator(scope, try scope.get(owner, "delimiters"));
        defer delimiters.deinit();
        errdefer delimiters.closePreserving();
        while (try delimiters.next()) |delimiter| {
            defer scope.engine.freeValue(delimiter);
            var index: i32 = 0;
            if (c.JS_ToInt32(scope.engine.context, &index, try scope.invoke(buffer, "indexOf", &.{delimiter})) < 0) return v.js.capture(scope.engine);
            if (index != -1 and (selected == -1 or index < selected)) {
                selected = index;
                delimiter_length = try scope.get(delimiter, "length");
            }
        }
        if (selected == -1) return null;
        const event = try scope.invoke(buffer, "substring", &.{ c.JS_NewInt32(scope.engine.context, 0), c.JS_NewInt32(scope.engine.context, selected) });
        const after = try scope.own(try @import("native_image_arithmetic.zig").binary(scope.engine, .add, c.JS_NewInt32(scope.engine.context, selected), delimiter_length));
        try scope.put(owner, "buffer", try scope.invoke(buffer, "substring", &.{after}));
        const trimmed = try scope.invoke(event, "trim", &.{});
        if (!scope.truthy(try scope.invoke(trimmed, "startsWith", &.{try scope.text("data:")}))) continue;
        return try scope.invoke(try scope.invoke(trimmed, "substring", &.{c.JS_NewInt32(scope.engine.context, 5)}), "trim", &.{});
    }
}

//! Real typed reducer bodies over the supplied public runner and handler graph.
//! Eight actual bodies: cache/message/toolResult/toolCall/request/headers/resources/input.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const dispatch = @import("native_sdk_public_runner_emit.zig");
const State = dispatch.State;
const Root = dispatch.Root;
const c = em.c;
extern "c" fn JS_GetIteratorSymbol(context: ?*c.JSContext) c.JSValue;
fn assign(engine: *em.Engine, receiver: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    if (c.JS_SetPropertyStr(engine.context, receiver, name, value) < 0) return js.capture(engine);
}
fn nullish(value: c.JSValue) bool {
    return c.JS_IsNull(value) or c.JS_IsUndefined(value);
}
fn optional(engine: *em.Engine, value: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return if (nullish(value)) c.pi_js_undefined() else sdk.get(engine, value, name);
}
pub fn initialize(engine: *em.Engine, retained: *State) !void {
    const original = retained.get(.parameter0);
    switch (retained.kind) {
        .context => try @import("native_sdk_public_runner_context_reducer.zig").initialize(engine, retained),
        .cache => retained.replace(engine, .current, try sdk.get(engine, original, "action")),
        .message => retained.replace(engine, .current, try sdk.get(engine, original, "message")),
        .tool_result => retained.replace(engine, .current, try js.spread(engine, original)),
        .request, .headers, .input => retained.replace(engine, .current, c.JS_DupValue(engine.context, original)),
        .resources => retained.replace(engine, .current, try sdk.array(engine)),
        .boundary => {
            retained.replace(engine, .current, try sdk.array(engine));
            retained.replace(engine, .aux, c.pi_js_bool(engine.context, 0));
        },
        .tool_call, .user_bash => {},
        .generic, .agent_start => unreachable,
    }
    if (retained.kind == .input) retained.replace(engine, .aux, c.JS_DupValue(engine.context, retained.get(.parameter1)));
    if (retained.kind == .resources) {
        retained.replace(engine, .aux, try sdk.array(engine));
        retained.replace(engine, .aux2, try sdk.array(engine));
    }
}
pub fn typeName(kind: dispatch.Kind) [*:0]const u8 {
    return switch (kind) {
        .message => "message_end",
        .tool_result => "tool_result",
        .tool_call => "tool_call",
        .request => "before_provider_request",
        .headers => "before_provider_headers",
        .resources => "resources_discover",
        .input => "input",
        .agent_start => "before_agent_start",
        .user_bash => "user_bash",
        .cache, .boundary, .context, .generic => unreachable,
    };
}
pub fn eventType(engine: *em.Engine, retained: *State) !c.JSValue {
    if (retained.kind == .context) return sdk.text(engine, if (retained.context_system) "context_with_system" else "context");
    return if (retained.kind == .cache or retained.kind == .boundary) sdk.get(engine, retained.get(.parameter0), "type") else sdk.text(engine, std.mem.span(typeName(retained.kind)));
}
pub fn prepare(engine: *em.Engine, retained: *State) !void {
    if (retained.kind == .agent_start) return @import("native_sdk_public_runner_agent_start.zig").prepare(engine, retained);
    if (retained.kind == .context) return @import("native_sdk_public_runner_context_reducer.zig").prepare(engine, retained);
    if (retained.kind == .boundary) {
        const event = try js.spread(engine, retained.get(.parameter0));
        errdefer engine.freeValue(event);
        try sdk.put(engine, event, "entries", c.JS_DupValue(engine.context, retained.get(.current)));
        try sdk.put(engine, event, "continue", c.JS_DupValue(engine.context, retained.get(.aux)));
        try sdk.put(engine, event, "context", c.JS_DupValue(engine.context, retained.get(.aux2)));
        retained.replace(engine, .event, event);
        return;
    }
    if (retained.kind == .cache or retained.kind == .tool_call or retained.kind == .user_bash) {
        retained.replace(engine, .event, c.JS_DupValue(engine.context, retained.get(.parameter0)));
        return;
    }
    if (retained.kind == .tool_result) {
        retained.replace(engine, .event, c.JS_DupValue(engine.context, retained.get(.current)));
        return;
    }
    const event = if (retained.kind == .message) try js.spread(engine, retained.get(.parameter0)) else try sdk.object(engine);
    errdefer engine.freeValue(event);
    if (retained.kind != .message) try sdk.put(engine, event, "type", try sdk.text(engine, std.mem.span(typeName(retained.kind))));
    switch (retained.kind) {
        .message => try sdk.put(engine, event, "message", c.JS_DupValue(engine.context, retained.get(.current))),
        .request => try sdk.put(engine, event, "payload", c.JS_DupValue(engine.context, retained.get(.current))),
        .headers => try sdk.put(engine, event, "headers", c.JS_DupValue(engine.context, retained.get(.parameter0))),
        .resources => {
            try sdk.put(engine, event, "cwd", c.JS_DupValue(engine.context, retained.get(.parameter0)));
            try sdk.put(engine, event, "reason", c.JS_DupValue(engine.context, retained.get(.parameter1)));
        },
        .input => {
            try sdk.put(engine, event, "text", c.JS_DupValue(engine.context, retained.get(.current)));
            try sdk.put(engine, event, "images", c.JS_DupValue(engine.context, retained.get(.aux)));
            try sdk.put(engine, event, "source", c.JS_DupValue(engine.context, retained.get(.parameter2)));
            try sdk.put(engine, event, "streamingBehavior", c.JS_DupValue(engine.context, retained.get(.parameter3)));
        },
        else => unreachable,
    }
    retained.replace(engine, .event, event);
}
pub fn accept(engine: *em.Engine, retained: *State, result: c.JSValue) !bool {
    switch (retained.kind) {
        .agent_start => try @import("native_sdk_public_runner_agent_start.zig").accept(engine, retained, result),
        .context => try @import("native_sdk_public_runner_context_reducer.zig").accept(engine, retained, result),
        .boundary => {
            const entries = try optional(engine, result, "entries");
            defer engine.freeValue(entries);
            if (!c.JS_IsUndefined(entries)) retained.replace(engine, .current, try sdk.get(engine, result, "entries"));
            const should_continue = try optional(engine, result, "continue");
            defer engine.freeValue(should_continue);
            if (!c.JS_IsUndefined(should_continue)) retained.replace(engine, .aux, try sdk.get(engine, result, "continue"));
        },
        .cache => {
            const action = try optional(engine, result, "action");
            defer engine.freeValue(action);
            if (!c.JS_IsUndefined(action)) retained.replace(engine, .current, try sdk.get(engine, result, "action"));
        },
        .message => {
            const message = try optional(engine, result, "message");
            defer engine.freeValue(message);
            if (c.JS_ToBool(engine.context, message) != 1) return false;
            const next = try sdk.get(engine, result, "message");
            defer engine.freeValue(next);
            const role = try sdk.get(engine, next, "role");
            defer engine.freeValue(role);
            const previous_role = try sdk.get(engine, retained.get(.current), "role");
            defer engine.freeValue(previous_role);
            if (!c.JS_IsStrictEqual(engine.context, role, previous_role)) {
                try reportRole(engine, retained);
                return false;
            }
            retained.replace(engine, .current, try sdk.get(engine, result, "message"));
            retained.modified = true;
        },
        .tool_result => {
            if (c.JS_ToBool(engine.context, result) != 1) return false;
            const content = try sdk.get(engine, result, "content");
            defer engine.freeValue(content);
            if (!c.JS_IsUndefined(content)) {
                try assign(engine, retained.get(.current), "content", try sdk.get(engine, result, "content"));
                const structured = try sdk.get(engine, result, "structuredContent");
                defer engine.freeValue(structured);
                if (c.JS_IsUndefined(structured)) {
                    const atom = c.JS_NewAtom(engine.context, "structuredContent");
                    defer c.JS_FreeAtom(engine.context, atom);
                    if (c.JS_DeleteProperty(engine.context, retained.get(.current), atom, c.JS_PROP_THROW) < 0) return js.capture(engine);
                }
                retained.modified = true;
            }
            inline for (.{ "details", "structuredContent", "isError", "usage" }) |name| {
                const first = try sdk.get(engine, result, name);
                defer engine.freeValue(first);
                if (!c.JS_IsUndefined(first)) {
                    try assign(engine, retained.get(.current), name, try sdk.get(engine, result, name));
                    retained.modified = true;
                }
            }
        },
        .user_bash => {
            if (c.JS_IsUndefined(result)) return false;
            if (!try @import("native_sdk_public_runner_user_bash.zig").valid(engine, result)) {
                const message = try sdk.text(engine, "Invalid user_bash handler result: return undefined for local execution or exactly one valid { operations } or { result } object");
                defer engine.freeValue(message);
                const reason = try js.builtin(engine, "Error", &.{message});
                _ = c.JS_Throw(engine.context, reason);
                return js.capture(engine);
            }
            retained.replace(engine, .result, c.JS_DupValue(engine.context, result));
            return true;
        },
        .tool_call => {
            if (c.JS_ToBool(engine.context, result) != 1) return false;
            retained.replace(engine, .result, c.JS_DupValue(engine.context, result));
            const blocked = try sdk.get(engine, result, "block");
            defer engine.freeValue(blocked);
            return c.JS_ToBool(engine.context, blocked) == 1;
        },
        .request => if (!c.JS_IsUndefined(result)) retained.replace(engine, .current, c.JS_DupValue(engine.context, result)),
        .headers => {},
        .resources => {
            try collectPaths(engine, retained, result, "skillPaths", .current);
            try collectPaths(engine, retained, result, "promptPaths", .aux);
            try collectPaths(engine, retained, result, "themePaths", .aux2);
        },
        .input => {
            const first_action = try optional(engine, result, "action");
            defer engine.freeValue(first_action);
            const handled = try sdk.text(engine, "handled");
            defer engine.freeValue(handled);
            if (c.JS_IsStrictEqual(engine.context, first_action, handled)) {
                retained.replace(engine, .result, c.JS_DupValue(engine.context, result));
                retained.early_return = true;
                return true;
            }
            const second_action = try optional(engine, result, "action");
            defer engine.freeValue(second_action);
            const transform = try sdk.text(engine, "transform");
            defer engine.freeValue(transform);
            if (c.JS_IsStrictEqual(engine.context, second_action, transform)) {
                retained.replace(engine, .current, try sdk.get(engine, result, "text"));
                const images = try sdk.get(engine, result, "images");
                defer engine.freeValue(images);
                if (!nullish(images)) retained.replace(engine, .aux, c.JS_DupValue(engine.context, images));
            }
        },
        .generic => unreachable,
    }
    return false;
}
fn reportRole(engine: *em.Engine, retained: *State) !void {
    const emit = try sdk.get(engine, retained.get(.runner), "emitError");
    defer engine.freeValue(emit);
    const report = try sdk.object(engine);
    defer engine.freeValue(report);
    try sdk.put(engine, report, "extensionPath", try sdk.get(engine, retained.get(.extension), "path"));
    try sdk.put(engine, report, "event", try sdk.text(engine, "message_end"));
    try sdk.put(engine, report, "error", try sdk.text(engine, "message_end handlers must return a message with the same role"));
    const ignored = try js.call(engine, emit, retained.get(.runner), &.{report});
    engine.freeValue(ignored);
}
fn pathMapper(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return mapPath(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), roots[0]) catch |err| sdk.fail(engine, err);
}
fn mapPath(engine: *em.Engine, path: c.JSValue, extension: c.JSValue) !c.JSValue {
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    try sdk.put(engine, result, "path", c.JS_DupValue(engine.context, path));
    try sdk.put(engine, result, "extensionPath", try sdk.get(engine, extension, "path"));
    return result;
}
fn collectPaths(engine: *em.Engine, retained: *State, result: c.JSValue, name: [*:0]const u8, target: Root) !void {
    const paths = try optional(engine, result, name);
    defer engine.freeValue(paths);
    const length = try optional(engine, paths, "length");
    defer engine.freeValue(length);
    if (c.JS_ToBool(engine.context, length) != 1) return;
    const push = try sdk.get(engine, retained.get(target), "push");
    defer engine.freeValue(push);
    const repeated = try sdk.get(engine, result, name);
    defer engine.freeValue(repeated);
    const map = try sdk.get(engine, repeated, "map");
    defer engine.freeValue(map);
    var roots = [_]c.JSValue{retained.get(.extension)};
    const mapper = try engine.checked(c.JS_NewCFunctionData2(engine.context, pathMapper, "", 1, 0, roots.len, &roots));
    defer engine.freeValue(mapper);
    const mapped = try js.call(engine, map, repeated, &.{mapper});
    defer engine.freeValue(mapped);
    const symbol = try engine.checked(JS_GetIteratorSymbol(engine.context));
    defer engine.freeValue(symbol);
    var iterator = try js.Iterator.init(engine, mapped, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    var arguments: std.ArrayList(c.JSValue) = .empty;
    defer {
        for (arguments.items) |argument| engine.freeValue(argument);
        arguments.deinit(engine.gpa);
    }
    while (try iterator.next()) |value| {
        arguments.append(engine.gpa, value) catch |err| {
            engine.freeValue(value);
            return err;
        };
    }
    const ignored = try js.call(engine, push, retained.get(target), arguments.items);
    engine.freeValue(ignored);
}
pub fn output(engine: *em.Engine, retained: *State) !c.JSValue {
    switch (retained.kind) {
        .agent_start => return @import("native_sdk_public_runner_agent_start.zig").output(engine, retained),
        .context => return c.JS_DupValue(engine.context, retained.get(.current)),
        .boundary => {
            const result = try sdk.object(engine);
            errdefer engine.freeValue(result);
            try sdk.put(engine, result, "entries", if (retained.boundary_valid) c.JS_DupValue(engine.context, retained.get(.current)) else try sdk.array(engine));
            try sdk.put(engine, result, "continue", if (retained.boundary_valid) c.JS_DupValue(engine.context, retained.get(.aux)) else c.pi_js_bool(engine.context, 0));
            try sdk.put(engine, result, "context", c.JS_DupValue(engine.context, retained.get(.aux2)));
            try sdk.put(engine, result, "valid", c.pi_js_bool(engine.context, @intFromBool(retained.boundary_valid)));
            return result;
        },
        .cache, .request => return c.JS_DupValue(engine.context, retained.get(.current)),
        .message => return if (retained.modified) c.JS_DupValue(engine.context, retained.get(.current)) else c.pi_js_undefined(),
        .tool_call, .user_bash => return c.JS_DupValue(engine.context, retained.get(.result)),
        .headers => return c.JS_DupValue(engine.context, retained.get(.parameter0)),
        .tool_result => {
            if (!retained.modified) return c.pi_js_undefined();
            const result = try sdk.object(engine);
            errdefer engine.freeValue(result);
            inline for (.{ "content", "details", "structuredContent", "isError", "usage" }) |name| try sdk.put(engine, result, name, try sdk.get(engine, retained.get(.current), name));
            return result;
        },
        .resources => {
            const result = try sdk.object(engine);
            errdefer engine.freeValue(result);
            try sdk.put(engine, result, "skillPaths", c.JS_DupValue(engine.context, retained.get(.current)));
            try sdk.put(engine, result, "promptPaths", c.JS_DupValue(engine.context, retained.get(.aux)));
            try sdk.put(engine, result, "themePaths", c.JS_DupValue(engine.context, retained.get(.aux2)));
            return result;
        },
        .input => {
            if (retained.early_return) return c.JS_DupValue(engine.context, retained.get(.result));
            const result = try sdk.object(engine);
            errdefer engine.freeValue(result);
            const changed = !c.JS_IsStrictEqual(engine.context, retained.get(.current), retained.get(.parameter0)) or !c.JS_IsStrictEqual(engine.context, retained.get(.aux), retained.get(.parameter1));
            try sdk.put(engine, result, "action", try sdk.text(engine, if (changed) "transform" else "continue"));
            if (changed) {
                try sdk.put(engine, result, "text", c.JS_DupValue(engine.context, retained.get(.current)));
                try sdk.put(engine, result, "images", c.JS_DupValue(engine.context, retained.get(.aux)));
            }
            return result;
        },
        .generic => unreachable,
    }
}

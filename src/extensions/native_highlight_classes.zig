//! Complete Source Response, TokenTree, TokenTreeEmitter and HTMLRenderer bodies.
//! Source-only observable classes; independent Original class differential pending.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const class = @import("native_class.zig");
const Scope = @import("native_highlight_scope.zig").Scope;
const c = em.c;
const Kind = enum(c_int) { response_ignore, top, root, add, open, close, close_all, json, walk, walk_static, collapse, walk_child, collapse_child, is_string, keyword, text, sublanguage, html, finalize, html_text, html_open, html_close, html_value, html_span };
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn callback(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return invoke(engine, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, @enumFromInt(magic), roots[0]) catch |err| sdk.fail(engine, err);
}
fn function(scope: *Scope, name: [*:0]const u8, arity: c_int, kind: Kind, captured: c.JSValue) !c.JSValue {
    var roots = [_]c.JSValue{captured};
    return scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, callback, name, arity, @intFromEnum(kind), roots.len, &roots)));
}
fn method(scope: *Scope, prototype: c.JSValue, name: [*:0]const u8, arity: c_int, kind: Kind, captured: c.JSValue) !void {
    if (c.JS_DefinePropertyValueStr(scope.engine.context, prototype, name, c.JS_DupValue(scope.engine.context, try function(scope, name, arity, kind, captured)), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(scope.engine);
}
fn getter(scope: *Scope, prototype: c.JSValue, name: [*:0]const u8, function_name: [*:0]const u8, kind: Kind) !void {
    const atom = c.JS_NewAtom(scope.engine.context, name);
    if (atom == c.JS_ATOM_NULL) return error.OutOfMemory;
    defer c.JS_FreeAtom(scope.engine.context, atom);
    if (c.JS_DefinePropertyGetSet(scope.engine.context, prototype, atom, c.JS_DupValue(scope.engine.context, try function(scope, function_name, 0, kind, c.pi_js_undefined())), c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(scope.engine);
}
fn expression(scope: *Scope, pattern: []const u8) !c.JSValue {
    var args = [_]c.JSValue{ try scope.text(pattern), try scope.text("g") };
    return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, scope.engine.intrinsic_regexp_constructor, args.len, &args)));
}
pub fn escapeHtml(scope: *Scope, value: c.JSValue) !c.JSValue {
    var result = value;
    inline for (.{ .{ "&", "&amp;" }, .{ "<", "&lt;" }, .{ ">", "&gt;" }, .{ "\"", "&quot;" }, .{ "'", "&#x27;" } }) |rule| result = try scope.invoke(result, "replace", &.{ try expression(scope, rule[0]), try scope.text(rule[1]) });
    return result;
}
fn invoke(engine: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, kind: Kind, captured: c.JSValue) !c.JSValue {
    return switch (kind) {
        inline else => |selected| invokeKind(engine, receiver, args, selected, captured),
    };
}
fn invokeKind(engine: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, comptime kind: Kind, captured: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const first = arg(args, 0);
    const second = arg(args, 1);
    switch (kind) {
        .response_ignore => try scope.set(receiver, "isMatchIgnored", c.pi_js_bool(engine.context, 1)),
        .top => {
            const stack = try scope.get(receiver, "stack");
            const index = try scope.own(try engine.checked(c.JS_PiBinaryOperator(engine.context, 1, try scope.get(stack, "length"), c.JS_NewInt32(engine.context, 1))));
            return js.getKey(engine, stack, index);
        },
        .root => return sdk.get(engine, receiver, "rootNode"),
        .add => {
            _ = try scope.invoke(try scope.get(try scope.get(receiver, "top"), "children"), "push", &.{first});
        },
        .open => {
            const node = try scope.object();
            try scope.put(node, "kind", first);
            try scope.put(node, "children", try scope.array());
            _ = try scope.invoke(receiver, "add", &.{node});
            _ = try scope.invoke(try scope.get(receiver, "stack"), "push", &.{node});
        },
        .close => {
            const stack = try scope.get(receiver, "stack");
            if (scope.truthy(try scope.own(try engine.checked(c.JS_PiBinaryOperator(engine.context, 6, try scope.get(stack, "length"), c.JS_NewInt32(engine.context, 1)))))) return c.JS_DupValue(engine.context, try scope.invoke(stack, "pop", &.{}));
        },
        .close_all => {
            while (scope.truthy(try scope.invoke(receiver, "closeNode", &.{}))) try tick(engine);
        },
        .json => return c.JS_DupValue(engine.context, try scope.invoke(try scope.global("JSON"), "stringify", &.{ try scope.get(receiver, "rootNode"), c.pi_js_null(), c.JS_NewInt32(engine.context, 4) })),
        .walk => {
            const constructor = try scope.get(receiver, "constructor");
            const walk = try scope.get(constructor, "_walk");
            return c.JS_DupValue(engine.context, try scope.call(walk, constructor, &.{ first, try scope.get(receiver, "rootNode") }));
        },
        .walk_static => {
            try tick(engine);
            if (c.JS_IsString(second)) {
                _ = try scope.invoke(first, "addText", &.{second});
            } else if (scope.truthy(try scope.get(second, "children"))) {
                _ = try scope.invoke(first, "openNode", &.{second});
                const state = try scope.object();
                try scope.put(state, "owner", receiver);
                try scope.put(state, "builder", first);
                _ = try scope.invoke(try scope.get(second, "children"), "forEach", &.{try function(&scope, "", 1, .walk_child, state)});
                _ = try scope.invoke(first, "closeNode", &.{second});
            }
            return c.JS_DupValue(engine.context, first);
        },
        .walk_child => {
            const owner = try scope.get(captured, "owner");
            _ = try scope.invoke(owner, "_walk", &.{ try scope.get(captured, "builder"), first });
        },
        .collapse => {
            try tick(engine);
            if (c.JS_IsString(first)) return c.pi_js_undefined();
            if (!scope.truthy(try scope.get(first, "children"))) return c.pi_js_undefined();
            if (scope.truthy(try scope.invoke(try scope.get(first, "children"), "every", &.{try function(&scope, "", 1, .is_string, c.pi_js_undefined())}))) {
                const children = try scope.array();
                try scope.index(children, 0, try scope.invoke(try scope.get(first, "children"), "join", &.{try scope.text("")}));
                try scope.set(first, "children", children);
            } else {
                _ = try scope.invoke(try scope.get(first, "children"), "forEach", &.{try function(&scope, "", 1, .collapse_child, captured)});
            }
        },
        .collapse_child => {
            _ = try scope.invoke(captured, "_collapse", &.{first});
        },
        .is_string => return c.pi_js_bool(engine.context, @intFromBool(c.JS_IsString(first))),
        .keyword => {
            if (scope.equal(first, try scope.text(""))) return c.pi_js_undefined();
            _ = try scope.invoke(receiver, "openNode", &.{second});
            _ = try scope.invoke(receiver, "addText", &.{first});
            _ = try scope.invoke(receiver, "closeNode", &.{});
        },
        .text => {
            if (!scope.equal(first, try scope.text(""))) _ = try scope.invoke(receiver, "add", &.{first});
        },
        .sublanguage => {
            const node = try scope.get(first, "root");
            try scope.set(node, "kind", second);
            try scope.set(node, "sublanguage", c.pi_js_bool(engine.context, 1));
            _ = try scope.invoke(receiver, "add", &.{node});
        },
        .html => {
            var args2 = [_]c.JSValue{ receiver, try scope.get(receiver, "options") };
            const renderer = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, captured, args2.len, &args2)));
            return c.JS_DupValue(engine.context, try scope.invoke(renderer, "value", &.{}));
        },
        .finalize => return c.pi_js_bool(engine.context, 1),
        .html_text => {
            const prior = try scope.get(receiver, "buffer");
            try scope.set(receiver, "buffer", try scope.concat(prior, try escapeHtml(&scope, first)));
        },
        .html_open => {
            if (!scope.truthy(try scope.get(first, "kind"))) return c.pi_js_undefined();
            var name = try scope.get(first, "kind");
            if (!scope.truthy(try scope.get(first, "sublanguage"))) name = try scope.concat(try scope.stringify(try scope.get(receiver, "classPrefix")), try scope.stringify(name));
            _ = try scope.invoke(receiver, "span", &.{name});
        },
        .html_close => {
            if (scope.truthy(try scope.get(first, "kind"))) {
                const prior = try scope.get(receiver, "buffer");
                try scope.set(receiver, "buffer", try scope.concat(prior, try scope.text("</span>")));
            }
        },
        .html_value => return sdk.get(engine, receiver, "buffer"),
        .html_span => {
            const prior = try scope.get(receiver, "buffer");
            const span = try scope.concat(try scope.concat(try scope.text("<span class=\""), try scope.stringify(first)), try scope.text("\">"));
            try scope.set(receiver, "buffer", try scope.concat(prior, span));
        },
    }
    return c.pi_js_undefined();
}
fn tick(engine: *em.Engine) !void {
    engine.interrupts +|= 1;
    if (engine.cancelled.load(.acquire) or engine.interrupts > engine.options.interrupt_budget) {
        _ = try engine.checked(c.JS_ThrowInternalError(engine.context, "interrupted"));
        unreachable;
    }
}
fn responseConstruct(engine: *em.Engine, target: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) anyerror!c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const mode = arg(args, 0);
    const result = try scope.own(try class.object(engine, target));
    if (c.JS_IsUndefined(try scope.get(mode, "data"))) try scope.set(mode, "data", try scope.object());
    try scope.set(result, "data", try scope.get(mode, "data"));
    try scope.set(result, "isMatchIgnored", c.pi_js_bool(engine.context, 0));
    return c.JS_DupValue(engine.context, result);
}
fn treeConstruct(engine: *em.Engine, target: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) anyerror!c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try scope.own(try class.object(engine, target));
    const root = try scope.object();
    try scope.put(root, "children", try scope.array());
    try scope.set(result, "rootNode", root);
    const stack = try scope.array();
    try scope.index(stack, 0, try scope.get(result, "rootNode"));
    try scope.set(result, "stack", stack);
    return c.JS_DupValue(engine.context, result);
}
fn emitterConstruct(engine: *em.Engine, target: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) anyerror!c.JSValue {
    const result = try treeConstruct(engine, target, &.{}, &.{});
    errdefer engine.freeValue(result);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.set(result, "options", arg(args, 0));
    return result;
}
fn htmlConstruct(engine: *em.Engine, target: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) anyerror!c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try scope.own(try class.object(engine, target));
    try scope.set(result, "buffer", try scope.text(""));
    try scope.set(result, "classPrefix", try scope.get(arg(args, 1), "classPrefix"));
    _ = try scope.invoke(arg(args, 0), "walk", &.{result});
    return c.JS_DupValue(engine.context, result);
}
pub fn create(engine: *em.Engine) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const response_proto = try scope.object();
    const response = try scope.own(try class.constructor(engine, "Response", 1, response_proto, responseConstruct, &.{}));
    try method(&scope, response_proto, "ignoreMatch", 0, .response_ignore, c.pi_js_undefined());
    const tree_proto = try scope.object();
    const tree = try scope.own(try class.constructor(engine, "TokenTree", 0, tree_proto, treeConstruct, &.{}));
    try getter(&scope, tree_proto, "top", "get top", .top);
    try getter(&scope, tree_proto, "root", "get root", .root);
    inline for (.{ .{ "add", 1, Kind.add }, .{ "openNode", 1, Kind.open }, .{ "closeNode", 0, Kind.close }, .{ "closeAllNodes", 0, Kind.close_all }, .{ "toJSON", 0, Kind.json }, .{ "walk", 1, Kind.walk } }) |entry| try method(&scope, tree_proto, entry[0], entry[1], entry[2], c.pi_js_undefined());
    try method(&scope, tree, "_walk", 2, .walk_static, c.pi_js_undefined());
    try method(&scope, tree, "_collapse", 1, .collapse, tree);
    const html_proto = try scope.object();
    const html = try scope.own(try class.constructor(engine, "HTMLRenderer", 2, html_proto, htmlConstruct, &.{}));
    inline for (.{ .{ "addText", 1, Kind.html_text }, .{ "openNode", 1, Kind.html_open }, .{ "closeNode", 1, Kind.html_close }, .{ "value", 0, Kind.html_value }, .{ "span", 1, Kind.html_span } }) |entry| try method(&scope, html_proto, entry[0], entry[1], entry[2], c.pi_js_undefined());
    const emitter_proto = try scope.own(try engine.checked(c.JS_NewObjectProto(engine.context, tree_proto)));
    const emitter = try scope.own(try class.constructor(engine, "TokenTreeEmitter", 1, emitter_proto, emitterConstruct, &.{}));
    if (c.JS_SetPrototype(engine.context, emitter, tree) < 0) return js.capture(engine);
    inline for (.{ .{ "addKeyword", 2, Kind.keyword }, .{ "addText", 1, Kind.text }, .{ "addSublanguage", 2, Kind.sublanguage }, .{ "toHTML", 0, Kind.html }, .{ "finalize", 0, Kind.finalize } }) |entry| try method(&scope, emitter_proto, entry[0], entry[1], entry[2], html);
    const exports = try scope.object();
    try scope.put(exports, "Response", response);
    try scope.put(exports, "TokenTree", tree);
    try scope.put(exports, "TokenTreeEmitter", emitter);
    try scope.put(exports, "HTMLRenderer", html);
    return c.JS_DupValue(engine.context, exports);
}

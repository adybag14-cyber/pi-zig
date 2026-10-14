//! Private highlight.js10.7.3 TokenTreeEmitter/HTMLRenderer algorithm bodies.
//! Internal parse-tree owner for the unfinished full native grammar engine.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const c = em.c;

pub const Emitter = struct {
    engine: *em.Engine,
    root: c.JSValue,
    stack: c.JSValue,
    options: c.JSValue,

    pub fn init(engine: *em.Engine, options: c.JSValue) !Emitter {
        var scope: Scope = .{ .engine = engine };
        defer scope.deinit();
        const root = try scope.object();
        try scope.put(root, "children", try scope.array());
        const stack = try scope.array();
        try scope.index(stack, 0, root);
        return .{ .engine = engine, .root = c.JS_DupValue(engine.context, root), .stack = c.JS_DupValue(engine.context, stack), .options = c.JS_DupValue(engine.context, options) };
    }
    pub fn deinit(self: *Emitter) void {
        self.engine.freeValue(self.root);
        self.engine.freeValue(self.stack);
        self.engine.freeValue(self.options);
    }
    fn top(self: *Emitter, scope: *Scope) !c.JSValue {
        const last = try scope.own(try self.engine.checked(c.JS_PiBinaryOperator(self.engine.context, 1, try scope.get(self.stack, "length"), c.JS_NewInt32(self.engine.context, 1))));
        return scope.own(try js.getKey(self.engine, self.stack, last));
    }
    pub fn add(self: *Emitter, node: c.JSValue) !void {
        var scope: Scope = .{ .engine = self.engine };
        defer scope.deinit();
        _ = try scope.invoke(try scope.get(try self.top(&scope), "children"), "push", &.{node});
    }
    pub fn openNode(self: *Emitter, kind: c.JSValue) !void {
        var scope: Scope = .{ .engine = self.engine };
        defer scope.deinit();
        const node = try scope.object();
        try scope.put(node, "kind", kind);
        try scope.put(node, "children", try scope.array());
        try self.add(node);
        _ = try scope.invoke(self.stack, "push", &.{node});
    }
    pub fn closeNode(self: *Emitter) !c.JSValue {
        var scope: Scope = .{ .engine = self.engine };
        defer scope.deinit();
        const more = try scope.own(try self.engine.checked(c.JS_PiBinaryOperator(self.engine.context, 6, try scope.get(self.stack, "length"), c.JS_NewInt32(self.engine.context, 1))));
        if (!scope.truthy(more)) return c.pi_js_undefined();
        return c.JS_DupValue(self.engine.context, try scope.invoke(self.stack, "pop", &.{}));
    }
    pub fn closeAllNodes(self: *Emitter) !void {
        while (true) {
            const closed = try self.closeNode();
            defer self.engine.freeValue(closed);
            if (c.JS_ToBool(self.engine.context, closed) != 1) break;
        }
    }
    pub fn addText(self: *Emitter, text: c.JSValue) !void {
        var scope: Scope = .{ .engine = self.engine };
        defer scope.deinit();
        if (scope.equal(text, try scope.text(""))) return;
        try self.add(text);
    }
    pub fn addKeyword(self: *Emitter, text: c.JSValue, kind: c.JSValue) !void {
        var scope: Scope = .{ .engine = self.engine };
        defer scope.deinit();
        if (scope.equal(text, try scope.text(""))) return;
        try self.openNode(kind);
        try self.addText(text);
        const closed = try self.closeNode();
        self.engine.freeValue(closed);
    }
    pub fn addSublanguage(self: *Emitter, emitter: *const Emitter, name: c.JSValue) !void {
        var scope: Scope = .{ .engine = self.engine };
        defer scope.deinit();
        try scope.set(emitter.root, "kind", name);
        try scope.set(emitter.root, "sublanguage", c.pi_js_bool(self.engine.context, 1));
        try self.add(emitter.root);
    }
    pub fn finalize(_: *Emitter) bool {
        return true;
    }
    pub fn toJson(self: *Emitter) !c.JSValue {
        var scope: Scope = .{ .engine = self.engine };
        defer scope.deinit();
        const result = try scope.invoke(try scope.global("JSON"), "stringify", &.{ self.root, c.pi_js_null(), c.JS_NewInt32(self.engine.context, 4) });
        return c.JS_DupValue(self.engine.context, result);
    }
    pub fn toHtml(self: *Emitter) !c.JSValue {
        var scope: Scope = .{ .engine = self.engine };
        defer scope.deinit();
        const owner = try scope.object();
        try scope.put(owner, "buffer", try scope.text(""));
        try scope.put(owner, "classPrefix", try scope.get(self.options, "classPrefix"));
        var renderer: Renderer = .{ .engine = self.engine, .owner = owner };
        try renderer.walk(self.root, 0);
        return c.JS_DupValue(self.engine.context, try scope.get(owner, "buffer"));
    }
};

const Renderer = struct {
    engine: *em.Engine,
    owner: c.JSValue,
    fn append(self: *Renderer, value: c.JSValue) !void {
        var scope: Scope = .{ .engine = self.engine };
        defer scope.deinit();
        const result = try scope.concat(try scope.get(self.owner, "buffer"), value);
        try scope.set(self.owner, "buffer", result);
    }
    fn escape(scope: *Scope, text: c.JSValue) !c.JSValue {
        var result = text;
        inline for (.{ .{ "&", "&amp;" }, .{ "<", "&lt;" }, .{ ">", "&gt;" }, .{ "\"", "&quot;" }, .{ "'", "&#x27;" } }) |entry| {
            const replace = try scope.get(result, "replace");
            var arguments = [_]c.JSValue{ try scope.text(entry[0]), try scope.text("g") };
            const expression = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, scope.engine.intrinsic_regexp_constructor, arguments.len, &arguments)));
            result = try scope.call(replace, result, &.{ expression, try scope.text(entry[1]) });
        }
        return result;
    }
    fn open(self: *Renderer, scope: *Scope, node: c.JSValue) !void {
        if (!scope.truthy(try scope.get(node, "kind"))) return;
        var name = try scope.get(node, "kind");
        if (!scope.truthy(try scope.get(node, "sublanguage"))) name = try scope.concat(try scope.stringify(try scope.get(self.owner, "classPrefix")), try scope.stringify(name));
        try self.append(try scope.concat(try scope.concat(try scope.text("<span class=\""), try scope.stringify(name)), try scope.text("\">")));
    }
    fn walk(self: *Renderer, node: c.JSValue, depth: usize) anyerror!void {
        var scope: Scope = .{ .engine = self.engine };
        defer scope.deinit();
        if (self.engine.cancelled.load(.acquire) or depth > 512) {
            _ = try self.engine.checked(c.JS_ThrowInternalError(self.engine.context, if (depth > 512) "stack overflow" else "interrupted"));
            unreachable;
        }
        if (c.JS_IsString(node)) {
            try self.append(try escape(&scope, node));
            return;
        }
        if (!scope.truthy(try scope.get(node, "children"))) return;
        try self.open(&scope, node);
        const children = try scope.get(node, "children");
        const for_each = try scope.get(children, "forEach");
        // forEach performs the actual live Array/proxy iteration and skips holes.
        // A caller can retain a callback through a replaced Array.forEach.
        // Capture VM-owned renderer state, never an ephemeral native pointer.
        var roots = [_]c.JSValue{ self.owner, c.JS_NewFloat64(self.engine.context, @floatFromInt(depth)) };
        const callback = try scope.own(try self.engine.checked(c.JS_NewCFunctionData2(self.engine.context, childCallback, "", 1, 0, roots.len, &roots)));
        _ = try scope.call(for_each, children, &.{callback});
        if (scope.truthy(try scope.get(node, "kind"))) try self.append(try scope.text("</span>"));
    }
    fn childCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
        const engine = em.Engine.fromContext(context.?);
        return child(engine, roots[0], roots[1], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
    }
    fn child(engine: *em.Engine, owner: c.JSValue, depth_value: c.JSValue, node: c.JSValue) !c.JSValue {
        var depth: i64 = undefined;
        if (c.JS_ToInt64(engine.context, &depth, depth_value) < 0) return js.capture(engine);
        var renderer: Renderer = .{ .engine = engine, .owner = owner };
        try renderer.walk(node, @intCast(depth + 1));
        return c.pi_js_undefined();
    }
};

//! Native port of partial-json 0.1.7's default Allow.ALL parser.
//! Retains the dependency's permissive collection prefixes, substring recovery,
//! ordinary object assignment and live JSON.parse calls. Not a final parser.
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_models_stream_scope.zig");
const Scope = temp.Scope;
const c = em.c;

// JavaScript catch blocks suppress guest failures, but trusted host allocation
// failure must reach the owner. Never retain a discarded captured exception.
pub fn discard(engine: *em.Engine, err: anyerror, generation: u64) !void {
    if (engine.nativeAllocationError(err, generation) == error.OutOfMemory) return error.OutOfMemory;
    if (engine.cancelled.load(.acquire) or engine.interrupts > engine.options.interrupt_budget) return err;
    if (engine.captured_exception) |value| {
        engine.captured_exception = null;
        engine.freeValue(value);
    }
}
pub fn parse(engine: *em.Engine, input: c.JSValue) !c.JSValue {
    if (!c.JS_IsString(input)) return error.PartialJSONNotString;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const text = try scope.invoke(input, "trim", &.{});
    var size: i64 = 0;
    if (c.JS_ToInt64(engine.context, &size, try scope.get(text, "length")) < 0) return js.capture(engine);
    if (size == 0) return error.PartialJSONEmpty;
    const owner = try scope.object();
    try scope.put(owner, "text", text);
    try scope.put(owner, "length", c.JS_NewFloat64(engine.context, @floatFromInt(size)));
    try scope.put(owner, "index", c.JS_NewInt32(engine.context, 0));
    try scope.put(owner, "steps", c.JS_NewInt32(engine.context, 0));
    var roots = [_]c.JSValue{owner};
    // Deliberately declare one argument and call with zero. QuickJS's native
    // C-function-data call path checks its configured stack guard when padding
    // missing arguments. Every recursive value therefore crosses that real VM
    // guard, rather than imposing an unrelated fixed depth on the JSON tree.
    const function = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, recurse, "", 1, 0, roots.len, &roots)));
    try scope.put(owner, "parse", function);
    return js.call(engine, function, c.pi_js_undefined(), &.{});
}
fn recurse(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return recurseBody(engine, roots[0]) catch |err| @import("native_sdk.zig").fail(engine, err);
}
fn integer(scope: *Scope, owner: c.JSValue, key: [*:0]const u8) !usize {
    var result: i64 = 0;
    if (c.JS_ToInt64(scope.engine.context, &result, try scope.get(owner, key)) < 0) return js.capture(scope.engine);
    return @intCast(result);
}
fn recurseBody(engine: *em.Engine, owner: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var parser: Parser = .{ .engine = engine, .owner = owner, .function = try scope.get(owner, "parse"), .text = try scope.get(owner, "text"), .length = try integer(&scope, owner, "length"), .index = try integer(&scope, owner, "index"), .steps = try integer(&scope, owner, "steps") };
    const result = parser.any() catch |err| {
        const saved = engine.captured_exception;
        engine.captured_exception = null;
        parser.save() catch |save_error| {
            if (saved) |value| engine.freeValue(value);
            return save_error;
        };
        engine.captured_exception = saved;
        return err;
    };
    errdefer engine.freeValue(result);
    try parser.save();
    return result;
}
const Parser = struct {
    engine: *em.Engine,
    owner: c.JSValue,
    function: c.JSValue,
    text: c.JSValue,
    length: usize,
    index: usize = 0,
    steps: usize = 0,
    fn save(self: *Parser) !void {
        if (c.JS_SetPropertyStr(self.engine.context, self.owner, "index", self.number(self.index)) < 0) return js.capture(self.engine);
        if (c.JS_SetPropertyStr(self.engine.context, self.owner, "steps", self.number(self.steps)) < 0) return js.capture(self.engine);
    }
    fn nested(self: *Parser) !c.JSValue {
        try self.save();
        var scope: Scope = .{ .engine = self.engine };
        defer scope.deinit();
        const result = js.call(self.engine, self.function, c.pi_js_undefined(), &.{}) catch |err| {
            self.index = try integer(&scope, self.owner, "index");
            self.steps = try integer(&scope, self.owner, "steps");
            return err;
        };
        errdefer self.engine.freeValue(result);
        self.index = try integer(&scope, self.owner, "index");
        self.steps = try integer(&scope, self.owner, "steps");
        return result;
    }
    fn number(self: *Parser, value: usize) c.JSValue {
        return c.JS_NewFloat64(self.engine.context, @floatFromInt(value));
    }
    fn char(self: *Parser, index: usize, expected: []const u8) !bool {
        var scope: Scope = .{ .engine = self.engine };
        defer scope.deinit();
        const value = try scope.own(try js.getKey(self.engine, self.text, self.number(index)));
        return scope.equal(value, try scope.text(expected));
    }
    fn blank(self: *Parser) !void {
        while (self.index < self.length) {
            try @import("native_ai_budget.zig").step(self.engine, &self.steps);
            if (!(try self.char(self.index, " ") or try self.char(self.index, "\n") or try self.char(self.index, "\r") or try self.char(self.index, "\t"))) break;
            self.index += 1;
        }
    }
    fn substring(self: *Parser, scope: *Scope, start: usize, end: c.JSValue) !c.JSValue {
        return scope.invoke(self.text, "substring", &.{ self.number(start), end });
    }
    fn json(scope: *Scope, value: c.JSValue) !c.JSValue {
        return js.invoke(scope.engine, try scope.global("JSON"), "parse", &.{value});
    }
    fn malformed(self: *Parser, err: anyerror, generation: u64) !c.JSValue {
        if (self.engine.nativeAllocationError(err, generation) == error.OutOfMemory) return error.OutOfMemory;
        if (self.engine.cancelled.load(.acquire) or self.engine.interrupts > self.engine.options.interrupt_budget) return err;
        if (self.engine.captured_exception) |reason| {
            self.engine.captured_exception = null;
            defer self.engine.freeValue(reason);
            var scope: Scope = .{ .engine = self.engine };
            defer scope.deinit();
            // The dependency evaluates String(e) before constructing its local
            // MalformedJSON. Preserve coercion callbacks even though Pi catches it.
            _ = try scope.call(try scope.global("String"), c.pi_js_undefined(), &.{reason});
        }
        return error.PartialJSONMalformed;
    }
    fn any(self: *Parser) anyerror!c.JSValue {
        try @import("native_ai_budget.zig").step(self.engine, &self.steps);
        try self.blank();
        if (self.index >= self.length) return error.PartialJSONUnexpectedEnd;
        if (try self.char(self.index, "\"")) return self.string();
        if (try self.char(self.index, "{")) return self.object();
        if (try self.char(self.index, "[")) return self.array();
        var scope: Scope = .{ .engine = self.engine };
        defer scope.deinit();
        inline for (.{ "null", "true", "false", "Infinity", "-Infinity", "NaN" }) |literal| {
            const remaining = try self.substring(&scope, self.index, self.number(self.length));
            const head = try self.substring(&scope, self.index, self.number(self.index + literal.len));
            if (scope.equal(head, try scope.text(literal)) or
                (self.length - self.index < literal.len and (literal[0] != '-' or self.length - self.index > 1) and
                    scope.truthy(try scope.invoke(try scope.text(literal), "startsWith", &.{remaining}))))
            {
                self.index += literal.len;
                return if (comptime @import("std").mem.eql(u8, literal, "null")) c.pi_js_null() else if (comptime @import("std").mem.eql(u8, literal, "true")) c.pi_js_bool(self.engine.context, 1) else if (comptime @import("std").mem.eql(u8, literal, "false")) c.pi_js_bool(self.engine.context, 0) else c.JS_NewFloat64(self.engine.context, if (comptime @import("std").mem.eql(u8, literal, "NaN")) @import("std").math.nan(f64) else if (literal[0] == '-') -@import("std").math.inf(f64) else @import("std").math.inf(f64));
            }
        }
        return self.numeric();
    }
    fn string(self: *Parser) !c.JSValue {
        const start = self.index;
        var escape = false;
        self.index += 1;
        while (self.index < self.length and (!(try self.char(self.index, "\"")) or (escape and try self.char(self.index - 1, "\\")))) : (self.index += 1) {
            try @import("native_ai_budget.zig").step(self.engine, &self.steps);
            escape = if (try self.char(self.index, "\\")) !escape else false;
        }
        var scope: Scope = .{ .engine = self.engine };
        defer scope.deinit();
        if (try self.char(self.index, "\"")) {
            self.index += 1;
            const generation = self.engine.native_allocation_generation;
            return json(&scope, try self.substring(&scope, start, self.number(self.index - @intFromBool(escape)))) catch |err| self.malformed(err, generation);
        }
        const generation = self.engine.native_allocation_generation;
        const candidate = try scope.concat(try self.substring(&scope, start, self.number(self.index - @intFromBool(escape))), try scope.text("\""));
        return json(&scope, candidate) catch |err| {
            try discard(self.engine, err, generation);
            const last = try scope.invoke(self.text, "lastIndexOf", &.{try scope.text("\\")});
            return json(&scope, try scope.concat(try self.substring(&scope, start, last), try scope.text("\"")));
        };
    }
    fn numeric(self: *Parser) !c.JSValue {
        var scope: Scope = .{ .engine = self.engine };
        defer scope.deinit();
        const start = self.index;
        if (start != 0) {
            if (try self.char(self.index, "-")) self.index += 1;
            while (self.index < self.length and !(try self.char(self.index, ",") or try self.char(self.index, "]") or try self.char(self.index, "}"))) : (self.index += 1) try @import("native_ai_budget.zig").step(self.engine, &self.steps);
        }
        const text = if (start == 0) self.text else try self.substring(&scope, start, self.number(self.index));
        if (scope.equal(text, try scope.text("-"))) return error.PartialJSONNumber;
        const generation = self.engine.native_allocation_generation;
        return json(&scope, text) catch |err| {
            const root_reason = if (start == 0 and self.engine.captured_exception != null) try scope.own(c.JS_DupValue(self.engine.context, self.engine.captured_exception.?)) else c.pi_js_undefined();
            try discard(self.engine, err, generation);
            const last = try scope.invoke(self.text, "lastIndexOf", &.{try scope.text("e")});
            return json(&scope, try self.substring(&scope, start, last)) catch |last_error| {
                if (start != 0) return self.malformed(last_error, generation);
                try discard(self.engine, last_error, generation);
                _ = try scope.call(try scope.global("String"), c.pi_js_undefined(), &.{root_reason});
                return error.PartialJSONMalformed;
            };
        };
    }
    fn object(self: *Parser) !c.JSValue {
        var scope: Scope = .{ .engine = self.engine };
        defer scope.deinit();
        const output = try scope.object();
        self.index += 1;
        try self.blank();
        const generation = self.engine.native_allocation_generation;
        self.objectItems(output) catch |err| try discard(self.engine, err, generation);
        return c.JS_DupValue(self.engine.context, output);
    }
    fn objectItems(self: *Parser, output: c.JSValue) !void {
        while (!(try self.char(self.index, "}"))) {
            var scope: Scope = .{ .engine = self.engine };
            defer scope.deinit();
            try self.blank();
            if (self.index >= self.length) return;
            const key = try scope.own(try self.string());
            try self.blank();
            self.index += 1; // Dependency intentionally does not validate colon.
            const value = try scope.own(try self.nested());
            try js.setKey(self.engine, output, key, value);
            try self.blank();
            if (try self.char(self.index, ",")) self.index += 1;
        }
        self.index += 1;
    }
    fn array(self: *Parser) !c.JSValue {
        var scope: Scope = .{ .engine = self.engine };
        defer scope.deinit();
        const output = try scope.array();
        self.index += 1;
        const generation = self.engine.native_allocation_generation;
        self.arrayItems(output) catch |err| try discard(self.engine, err, generation);
        return c.JS_DupValue(self.engine.context, output);
    }
    fn arrayItems(self: *Parser, output: c.JSValue) !void {
        while (!(try self.char(self.index, "]"))) {
            const value = try self.nested();
            defer self.engine.freeValue(value);
            try js.push(self.engine, output, value);
            try self.blank();
            if (try self.char(self.index, ",")) self.index += 1;
        }
        self.index += 1;
    }
};

// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Node v24.14 loader lookup declarations over the actual Module and its
//! retained lexical paths. Every selected guest expression has a Node boundary.
const a = @import("native_node_argument_values.zig");
const v = a.v;
const c = a.c;
const Scope = a.Scope;
const LegacyScope = v.Scope;
const LookupFrame = a.frames.Frame(enum { paths, main_paths, parent_dir });
pub const Inputs = struct {
    module_constructor: c.JSValue,
    path: c.JSValue,
    /// The same private owner whose modulePaths binding _initPaths replaces.
    state: c.JSValue,
    /// Genuine normalizeRequirableId, including its original coercion. This is
    /// not public isBuiltin (which has a different non-string short circuit).
    is_builtin: c.JSValue,
    array_slice: c.JSValue,
    array_unshift: c.JSValue,
    array_push: c.JSValue,
    array_includes: c.JSValue,
    array_is_array: c.JSValue,
    reflect_apply: c.JSValue,
    invalid_arg_value: c.JSValue,
    string_char_at: c.JSValue,
    string_starts_with: c.JSValue,
    string_char_code_at: c.JSValue,
    windows: bool,
};
const root_count = 15;
pub const captured_root_count = root_count;
pub fn captureRoots(engine: *v.em.Engine, inputs: Inputs) [root_count]c.JSValue { return roots(engine, inputs); }
pub fn restoreRoots(engine: *v.em.Engine, values: []const c.JSValue) Inputs { return fromRoots(engine, values); }
fn roots(engine: *v.em.Engine, inputs: Inputs) [root_count]c.JSValue {
    return .{ inputs.module_constructor, inputs.path, inputs.state, inputs.is_builtin,
        inputs.array_slice, inputs.array_unshift, inputs.array_push, inputs.array_includes,
        inputs.array_is_array, inputs.reflect_apply, inputs.invalid_arg_value,
        inputs.string_char_at, inputs.string_starts_with, inputs.string_char_code_at,
        c.pi_js_bool(engine.context, @intFromBool(inputs.windows)) };
}
fn fromRoots(engine: *v.em.Engine, values: []const c.JSValue) Inputs {
    return .{ .module_constructor = values[0], .path = values[1], .state = values[2], .is_builtin = values[3],
        .array_slice = values[4], .array_unshift = values[5], .array_push = values[6], .array_includes = values[7],
        .array_is_array = values[8], .reflect_apply = values[9], .invalid_arg_value = values[10],
        .string_char_at = values[11], .string_starts_with = values[12], .string_char_code_at = values[13],
        .windows = c.JS_ToBool(engine.context, values[14]) == 1 };
}
pub fn createLookupPaths(engine: *v.em.Engine, inputs: Inputs) !c.JSValue {
    const values = roots(engine, inputs);
    return @import("native_node_module_callable.zig").create(engine, "", 2, true, lookupCallback, &values);
}
fn lookupCallback(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, values: []const c.JSValue) !c.JSValue {
    return lookupPaths(engine, fromRoots(engine, values), a.arg(args, 0), a.arg(args, 1));
}
fn statement(engine: *v.em.Engine, comptime body: anytype, args: anytype) !void {
    var s = Scope.init(engine);
    var failure: ?anyerror = null;
    @call(.auto, body, .{&s} ++ args) catch |err| { failure = err; };
    _ = try s.finish(if (failure) |err| @as(anyerror!c.JSValue, err) else c.pi_js_undefined());
}
fn callTruthy(s: *Scope, function: c.JSValue, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue {
    return a.boolean(s, s.truthy(try s.call(function, receiver, args)));
}
fn charEqual(s: *Scope, function: c.JSValue, text: c.JSValue, position: i32, expected: []const u8) !c.JSValue {
    const value = try s.call(function, text, &.{c.JS_NewInt32(s.engine.context, position)});
    return a.boolean(s, s.equal(value, try s.text(expected)));
}
fn firstCodeIsDot(s: *Scope, inputs: Inputs, text: c.JSValue) !c.JSValue {
    return a.boolean(s, s.equal(try s.call(inputs.string_char_code_at, text,
        &.{c.JS_NewInt32(s.engine.context, 0)}), c.JS_NewInt32(s.engine.context, 46)));
}
fn lengthEqualOne(s: *Scope, text: c.JSValue) !c.JSValue {
    return a.boolean(s, s.equal(try s.get(text, "length"), c.JS_NewInt32(s.engine.context, 1)));
}
fn startsWith(s: *Scope, inputs: Inputs, text: c.JSValue, prefix: []const u8) !c.JSValue {
    return a.boolean(s, s.truthy(try s.call(inputs.string_starts_with, text, &.{try s.text(prefix)})));
}
/// Actual loader isRelative uses CharCodeAt for its first test. Every operand
/// consumed by a short-circuit predicate retires before the following read.
pub fn isRelative(engine: *v.em.Engine, inputs: Inputs, text: c.JSValue) !bool {
    return a.condition(engine, relativeBody, .{inputs, text});
}
fn relativeBody(s: *Scope, inputs: Inputs, text: c.JSValue) !c.JSValue {
    if (!try a.condition(s.engine, firstCodeIsDot, .{inputs, text})) return a.boolean(s, false);
    if (try a.condition(s.engine, lengthEqualOne, .{text}) or s.equal(text, try s.text(".."))) return a.boolean(s, true);
    inline for (.{ "./", "../" }) |prefix|
        if (try a.condition(s.engine, startsWith, .{inputs, text, @as([]const u8, prefix)})) return a.boolean(s, true);
    if (inputs.windows and try a.condition(s.engine, startsWith, .{inputs, text, @as([]const u8, ".\\")})) return a.boolean(s, true);
    return a.boolean(s, try a.condition(s.engine, startsWith, .{inputs, text, @as([]const u8, "..\\")}));
}
fn lengthAbove(s: *Scope, receiver: c.JSValue, bound: i32) !c.JSValue {
    return a.boolean(s, s.truthy(try s.binary(6, try s.get(receiver, "length"), c.JS_NewInt32(s.engine.context, bound))));
}
fn parentPathsLength(s: *Scope, parent: c.JSValue) !c.JSValue {
    if (v.nullish(parent)) return c.pi_js_undefined();
    const paths = try s.get(parent, "paths");
    if (v.nullish(paths)) return c.pi_js_undefined();
    return a.duplicate(s.engine, try s.get(paths, "length"));
}
fn hasParentPaths(s: *Scope, parent: c.JSValue) !c.JSValue {
    // Complete the optional chain before consuming its final predicate.
    const length = try s.own(try a.expression(s.engine, parentPathsLength, .{parent}));
    return a.boolean(s, s.truthy(length));
}
fn slicePaths(s: *Scope, inputs: Inputs) !c.JSValue {
    return a.duplicate(s.engine, try s.call(inputs.array_slice, try s.get(inputs.state, "modulePaths"), &.{}));
}
fn unshiftParent(s: *Scope, inputs: Inputs, paths: c.JSValue, parent: c.JSValue) !void {
    // Primordials UnshiftApply uses actual array-like argument-list handling.
    const actual = try s.get(parent, "paths");
    _ = try s.call(inputs.reflect_apply, c.pi_js_undefined(), &.{inputs.array_unshift, paths, actual});
}
fn dotArray(s: *Scope) !c.JSValue {
    const paths = try a.array(s);
    try a.index(s, paths, 0, try s.text("."));
    return a.duplicate(s.engine, paths);
}
fn dirname(s: *Scope, inputs: Inputs, parent: c.JSValue) !c.JSValue {
    const method = try s.get(inputs.path, "dirname");
    return a.duplicate(s.engine, try s.call(method, inputs.path, &.{try s.get(parent, "filename")}));
}
fn directoryArray(s: *Scope, inputs: Inputs, parent: c.JSValue) !c.JSValue {
    // Source allocates the literal Array before evaluating its one element.
    const paths = try a.array(s);
    const directory = try s.own(try a.expression(s.engine, dirname, .{inputs, parent}));
    try a.index(s, paths, 0, directory);
    return a.duplicate(s.engine, paths);
}
pub fn lookupPaths(engine: *v.em.Engine, inputs: Inputs, request: c.JSValue, parent: c.JSValue) !c.JSValue {
    var s = Scope.init(engine);
    const frame = LookupFrame.create(&s.values) catch |err| return s.finish(@as(anyerror!c.JSValue, err));
    return a.finishFrame(&s, frame, lookupBody(&s, frame, inputs, request, parent));
}
fn lookupBody(s: *Scope, frame: *LookupFrame, inputs: Inputs, request: c.JSValue, parent: c.JSValue) !c.JSValue {
    if (try a.condition(s.engine, callTruthy, .{inputs.is_builtin, c.pi_js_undefined(), @as([]const c.JSValue, &.{request})})) return c.pi_js_null();
    const first_dot = try a.condition(s.engine, charEqual, .{inputs.string_char_at, request, @as(i32, 0), @as([]const u8, ".")});
    const bare = !first_dot or
        (try a.condition(s.engine, lengthAbove, .{request, @as(i32, 1)}) and
        !try a.condition(s.engine, charEqual, .{inputs.string_char_at, request, @as(i32, 1), @as([]const u8, ".")}) and
        !try a.condition(s.engine, charEqual, .{inputs.string_char_at, request, @as(i32, 1), @as([]const u8, "/")}) and
        (!inputs.windows or !try a.condition(s.engine, charEqual, .{inputs.string_char_at, request, @as(i32, 1), @as([]const u8, "\\")})));
    if (bare) {
        if (try a.condition(s.engine, hasParentPaths, .{parent})) {
            try frame.take(.paths, a.expression(s.engine, slicePaths, .{inputs}));
            try statement(s.engine, unshiftParent, .{inputs, frame.get(.paths), parent});
        } else try frame.take(.paths, a.field(s.engine, inputs.state, "modulePaths"));
        return if (try a.condition(s.engine, lengthAbove, .{frame.get(.paths), @as(i32, 0)}))
            a.duplicate(s.engine, frame.get(.paths)) else c.pi_js_null();
    }
    if (!s.truthy(parent) or !try a.condition(s.engine, a.fieldTruthy, .{parent, @as([*:0]const u8, "id")}) or
        !try a.condition(s.engine, a.fieldTruthy, .{parent, @as([*:0]const u8, "filename")}))
    {
        try frame.take(.main_paths, a.expression(s.engine, dotArray, .{}));
        return a.duplicate(s.engine, frame.get(.main_paths));
    }
    // The disabled module debug call still evaluates its parent.id argument.
    // Keep that read even before the full loader's diagnostic import is wired.
    var debug_parent = try a.field(s.engine, parent, "id");
    s.boundary.release(&debug_parent);
    try s.pending();
    try frame.take(.parent_dir, a.expression(s.engine, directoryArray, .{inputs, parent}));
    return a.duplicate(s.engine, frame.get(.parent_dir));
}
// The following options.paths branch belongs to _resolveFilename's function
// activation. Its migration will retain fakeParent and body locals through the
// remainder of that actual caller, rather than closing them at this helper.
fn append(s: *LegacyScope, inputs: Inputs, target: c.JSValue, value: c.JSValue) !void {
    _ = try s.call(inputs.array_push, target, &.{value});
}
/// _resolveFilename's actual options.paths branch. Caller performs builtin
/// short-circuit and captures options?.conditions BEFORE entering this body.
/// For nonrelative requests new Module('', null) and its observable public
/// lookup methods are real; no lexical surrogate or guessed path array is used.
pub fn resolveSearchPaths(engine: *v.em.Engine, inputs: Inputs, request: c.JSValue, parent: c.JSValue, options: c.JSValue) !c.JSValue {
    var s: LegacyScope = .{ .engine = engine }; defer s.deinit();
    if (c.JS_IsObject(options) and !c.JS_IsFunction(engine.context, options)) {
        const first_paths = try s.get(options, "paths");
        if (s.truthy(try s.call(inputs.array_is_array, c.pi_js_undefined(), &.{first_paths}))) {
            if (try isRelative(engine, inputs, request)) return v.js.get(engine, options, "paths");
            var arguments = [_]c.JSValue{ try s.text(""), c.pi_js_null() };
            const fake_parent = try s.own(try engine.checked(c.JS_CallConstructor(engine.context, inputs.module_constructor, arguments.len, &arguments)));
            const paths = try s.array();
            var index = c.JS_NewInt32(engine.context, 0); defer engine.freeValue(index);
            var steps: usize = 0;
            while (true) {
                var frame: LegacyScope = .{ .engine = engine }; defer frame.deinit();
                const condition_paths = try frame.get(options, "paths");
                if (!frame.truthy(try frame.own(try engine.checked(c.JS_PiBinaryOperator(engine.context, 4, index, try frame.get(condition_paths, "length")))))) break;
                try @import("native_node_commonjs_interrupt.zig").step(engine, &steps);
                const path = try frame.own(try v.js.getKey(engine, try frame.get(options, "paths"), index));
                const node_paths = try frame.get(inputs.module_constructor, "_nodeModulePaths");
                try frame.set(fake_parent, "paths", try frame.call(node_paths, inputs.module_constructor, &.{path}));
                const lookup = try frame.get(inputs.module_constructor, "_resolveLookupPaths");
                const lookup_paths = try frame.call(lookup, inputs.module_constructor, &.{ request, fake_parent });
                var inner = c.JS_NewInt32(engine.context, 0); defer engine.freeValue(inner);
                while (true) {
                    var inner_frame: LegacyScope = .{ .engine = engine }; defer inner_frame.deinit();
                    if (!inner_frame.truthy(try inner_frame.own(try engine.checked(c.JS_PiBinaryOperator(engine.context, 4, inner, try inner_frame.get(lookup_paths, "length")))))) break;
                    try @import("native_node_commonjs_interrupt.zig").step(engine, &steps);
                    const item = try inner_frame.own(try v.js.getKey(engine, lookup_paths, inner));
                    if (!inner_frame.truthy(try inner_frame.call(inputs.array_includes, paths, &.{item}))) {
                        // Source re-reads lookupPaths[j] for Push, after Includes.
                        const inserted = try inner_frame.own(try v.js.getKey(engine, lookup_paths, inner));
                        try append(&inner_frame, inputs, paths, inserted);
                    }
                    const next = try engine.checked(c.JS_PiIncrement(engine.context, inner));
                    engine.freeValue(inner); inner = next;
                }
                const next = try engine.checked(c.JS_PiIncrement(engine.context, index));
                engine.freeValue(index); index = next;
            }
            return c.JS_DupValue(engine.context, paths);
        }
        if (!c.JS_IsUndefined(try s.get(options, "paths"))) {
            const name = try s.text("options.paths");
            const value = try s.get(options, "paths");
            var arguments = [_]c.JSValue{ name, value };
            const reason = try s.own(try engine.checked(c.JS_CallConstructor(engine.context, inputs.invalid_arg_value, arguments.len, &arguments)));
            _ = try engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason)));
            unreachable;
        }
    }
    const lookup = try s.get(inputs.module_constructor, "_resolveLookupPaths");
    return v.js.call(engine, lookup, inputs.module_constructor, &.{ request, parent });
}

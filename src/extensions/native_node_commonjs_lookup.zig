// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Node24.14.0 loader.js lookup/resolve-options bodies. Ordinary raw completion.
//! Source f657bb8ed86365ff3fdbe32e27563e778b41486a; Node MIT LICENSE retained.
//! The private global paths and builtin predicate must be genuine initialized
//! Node policy. This leaf does not alias SourceLoader.normalizeRequire.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = v.Scope;
pub const Inputs = struct {
    module_constructor: c.JSValue,
    path: c.JSValue,
    /// Private VM-traced lexical state; modulePaths is replaced by _initPaths.
    state: c.JSValue,
    is_builtin: c.JSValue,
    array_slice: c.JSValue,
    array_unshift: c.JSValue,
    array_push: c.JSValue,
    array_includes: c.JSValue,
    array_is_array: c.JSValue,
    reflect_apply: c.JSValue,
    /// Genuine Node ERR_INVALID_ARG_VALUE constructor/factory; returns owned
    /// actual error. It is never substituted by a generic host TypeError.
    invalid_arg_value: c.JSValue,
    string_char_at: c.JSValue,
    string_starts_with: c.JSValue,
    windows: bool,
};
const root_count = 14;
pub const captured_root_count = root_count;
pub fn captureRoots(engine: *v.em.Engine, inputs: Inputs) [root_count]c.JSValue { return roots(engine, inputs); }
pub fn restoreRoots(engine: *v.em.Engine, values: []const c.JSValue) Inputs { return fromRoots(engine, values); }
fn roots(engine: *v.em.Engine, inputs: Inputs) [root_count]c.JSValue {
    return .{ inputs.module_constructor, inputs.path, inputs.state, inputs.is_builtin,
        inputs.array_slice, inputs.array_unshift, inputs.array_push, inputs.array_includes,
        inputs.array_is_array, inputs.reflect_apply, inputs.invalid_arg_value,
        inputs.string_char_at, inputs.string_starts_with, c.pi_js_bool(engine.context, @intFromBool(inputs.windows)) };
}
fn fromRoots(engine: *v.em.Engine, values: []const c.JSValue) Inputs {
    return .{ .module_constructor = values[0], .path = values[1], .state = values[2], .is_builtin = values[3],
        .array_slice = values[4], .array_unshift = values[5], .array_push = values[6], .array_includes = values[7],
        .array_is_array = values[8], .reflect_apply = values[9], .invalid_arg_value = values[10],
        .string_char_at = values[11], .string_starts_with = values[12], .windows = c.JS_ToBool(engine.context, values[13]) == 1 };
}
fn arg(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
/// Real ordinary _resolveLookupPaths declaration. The assembler installs it on
/// the same actual Module used by constructor/cache/require, never a stand-in.
pub fn createLookupPaths(engine: *v.em.Engine, inputs: Inputs) !c.JSValue {
    const values = roots(engine, inputs);
    return @import("native_node_module_callable.zig").create(engine, "", 2, true, lookupCallback, &values);
}
fn lookupCallback(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, values: []const c.JSValue) !c.JSValue {
    return lookupPaths(engine, fromRoots(engine, values), arg(args, 0), arg(args, 1));
}
fn append(s: *Scope, inputs: Inputs, target: c.JSValue, value: c.JSValue) !void {
    _ = try s.call(inputs.array_push, target, &.{value});
}
fn char(s: *Scope, inputs: Inputs, text: c.JSValue, index: i32) !c.JSValue {
    return s.call(inputs.string_char_at, text, &.{c.JS_NewInt32(s.engine.context, index)});
}
/// Actual Node isRelative rule. In particular .name and absolute paths are not
/// relative, while the final '..\\' branch is accepted on either platform.
pub fn isRelative(engine: *v.em.Engine, inputs: Inputs, text: c.JSValue) !bool {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    if (!s.equal(try char(&s, inputs, text, 0), try s.text("."))) return false;
    if (s.equal(try s.get(text, "length"), c.JS_NewInt32(engine.context, 1)) or s.equal(text, try s.text(".."))) return true;
    inline for (.{ "./", "../" }) |prefix|
        if (s.truthy(try s.call(inputs.string_starts_with, text, &.{try s.text(prefix)}))) return true;
    if (inputs.windows and s.truthy(try s.call(inputs.string_starts_with, text, &.{try s.text(".\\")}))) return true;
    return s.truthy(try s.call(inputs.string_starts_with, text, &.{try s.text("..\\")}));
}
/// Exact _resolveLookupPaths control flow. Values returned by the builtin path
/// are null, and the private module_paths array may be returned by identity.
pub fn lookupPaths(engine: *v.em.Engine, inputs: Inputs, request: c.JSValue, parent: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    if (s.truthy(try s.call(inputs.is_builtin, c.pi_js_undefined(), &.{request}))) return c.pi_js_null();
    const first = try char(&s, inputs, request, 0);
    const is_dot = s.equal(first, try s.text("."));
    const second_branch = if (is_dot and s.truthy(try s.own(try engine.checked(c.JS_PiBinaryOperator(engine.context, 6, try s.get(request, "length"), c.JS_NewInt32(engine.context, 1)))))) branch: {
        if (s.equal(try char(&s, inputs, request, 1), try s.text("."))) break :branch false;
        if (s.equal(try char(&s, inputs, request, 1), try s.text("/"))) break :branch false;
        if (inputs.windows and s.equal(try char(&s, inputs, request, 1), try s.text("\\"))) break :branch false;
        break :branch true;
    } else false;
    if (!is_dot or second_branch) {
        var paths = c.pi_js_undefined();
        const parent_paths = try v.optional(&s, parent, "paths");
        const parent_length = try v.optional(&s, parent_paths, "length");
        if (s.truthy(parent_length)) {
            paths = try s.call(inputs.array_slice, try s.get(inputs.state, "modulePaths"), &.{});
            // Source re-reads parent.paths after slicing, then UnshiftApply
            // consumes array-like values, not an iterator or string list.
            const actual = try s.get(parent, "paths");
            const ignored = try v.js.call(engine, inputs.reflect_apply, c.pi_js_undefined(), &.{ inputs.array_unshift, paths, actual });
            engine.freeValue(ignored);
        } else paths = try s.get(inputs.state, "modulePaths");
        const positive = try s.own(try engine.checked(c.JS_PiBinaryOperator(engine.context, 6, try s.get(paths, "length"), c.JS_NewInt32(engine.context, 0))));
        return if (s.truthy(positive)) c.JS_DupValue(engine.context, paths) else c.pi_js_null();
    }
    if (!s.truthy(parent) or !s.truthy(try s.get(parent, "id")) or !s.truthy(try s.get(parent, "filename"))) {
        const paths = try s.array(); try s.index(paths, 0, try s.text("."));
        return c.JS_DupValue(engine.context, paths);
    }
    const path_dirname = try s.get(inputs.path, "dirname");
    const directory = try s.call(path_dirname, inputs.path, &.{try s.get(parent, "filename")});
    const paths = try s.array(); try s.index(paths, 0, directory);
    return c.JS_DupValue(engine.context, paths);
}
/// _resolveFilename's actual options.paths branch. Caller performs builtin
/// short-circuit and captures options?.conditions BEFORE entering this body.
/// For nonrelative requests new Module('', null) and its observable public
/// lookup methods are real; no lexical surrogate or guessed path array is used.
pub fn resolveSearchPaths(engine: *v.em.Engine, inputs: Inputs, request: c.JSValue, parent: c.JSValue, options: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
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
                var frame: Scope = .{ .engine = engine }; defer frame.deinit();
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
                    var inner_frame: Scope = .{ .engine = engine }; defer inner_frame.deinit();
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

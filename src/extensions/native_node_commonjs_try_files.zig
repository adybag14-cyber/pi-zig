// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Actual Node24 loader.js tryFile/tryExtensions/tryPackage source bodies.
//! Private stat/realpath/readPackage are actual filesystem bindings, not mocks.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = v.Scope;
pub const Inputs = struct {
    state: c.JSValue,
    path: c.JSValue,
    process: c.JSValue,
    to_real_path: c.JSValue,
    read_package: c.JSValue,
    error_constructor: c.JSValue,
    preserve_symlinks: bool,
    preserve_symlinks_main: bool,
};
pub fn file(engine: *v.em.Engine, inputs: Inputs, request_path: c.JSValue, is_main: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const stat = try s.get(inputs.state, "stat");
    const rc = try s.call(stat, c.pi_js_undefined(), &.{request_path});
    if (!s.equal(rc, c.JS_NewInt32(engine.context, 0))) return c.pi_js_undefined();
    if (if (s.truthy(is_main)) inputs.preserve_symlinks_main else inputs.preserve_symlinks) {
        const resolve = try s.get(inputs.path, "resolve");
        return v.js.call(engine, resolve, inputs.path, &.{request_path});
    }
    return v.js.call(engine, inputs.to_real_path, c.pi_js_undefined(), &.{request_path});
}
pub fn extensions(engine: *v.em.Engine, inputs: Inputs, base: c.JSValue, exts: c.JSValue, is_main: c.JSValue) !c.JSValue {
    var index = c.JS_NewInt32(engine.context, 0); defer engine.freeValue(index);
    var steps: usize = 0;
    while (true) {
        var s: Scope = .{ .engine = engine }; defer s.deinit();
        if (!s.truthy(try s.own(try engine.checked(c.JS_PiBinaryOperator(engine.context, 4, index, try s.get(exts, "length")))))) break;
        try @import("native_node_commonjs_interrupt.zig").step(engine, &steps);
        const ext = try s.own(try v.js.getKey(engine, exts, index));
        const filename = try s.own(try file(engine, inputs, try s.concat(base, ext), is_main));
        if (s.truthy(filename)) return c.JS_DupValue(engine.context, filename);
        const next = try engine.checked(c.JS_PiIncrement(engine.context, index));
        engine.freeValue(index); index = next;
    }
    return c.pi_js_bool(engine.context, 0);
}
pub fn package(engine: *v.em.Engine, inputs: Inputs, request_path: c.JSValue, exts: c.JSValue, is_main: c.JSValue, original_path: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const record = try s.call(inputs.read_package, c.pi_js_undefined(), &.{request_path});
    const main = try s.get(record, "main");
    const json_path = try s.get(record, "pjsonPath");
    if (!s.truthy(main)) {
        const resolve = try s.get(inputs.path, "resolve");
        const base = try s.call(resolve, inputs.path, &.{ request_path, try s.text("index") });
        return extensions(engine, inputs, base, exts, is_main);
    }
    const resolve = try s.get(inputs.path, "resolve");
    const filename = try s.call(resolve, inputs.path, &.{ request_path, main });
    var actual = try s.own(try file(engine, inputs, filename, is_main));
    if (!s.truthy(actual)) actual = try s.own(try extensions(engine, inputs, filename, exts, is_main));
    if (!s.truthy(actual)) {
        const index_resolve = try s.get(inputs.path, "resolve");
        const base = try s.call(index_resolve, inputs.path, &.{ filename, try s.text("index") });
        actual = try s.own(try extensions(engine, inputs, base, exts, is_main));
    }
    if (s.equal(actual, c.pi_js_bool(engine.context, 0))) {
        const fallback_resolve = try s.get(inputs.path, "resolve");
        const base = try s.call(fallback_resolve, inputs.path, &.{ request_path, try s.text("index") });
        actual = try s.own(try extensions(engine, inputs, base, exts, is_main));
        if (!s.truthy(actual)) {
            const message = try s.concat(try s.concat(try s.text("Cannot find module '"), try s.stringify(filename)),
                try s.text("'. Please verify that the package.json has a valid \"main\" entry"));
            var args = [_]c.JSValue{message};
            const reason = try s.own(try engine.checked(c.JS_CallConstructor(engine.context, inputs.error_constructor, args.len, &args)));
            try s.set(reason, "code", try s.text("MODULE_NOT_FOUND"));
            try s.set(reason, "path", json_path);
            try s.set(reason, "requestPath", original_path);
            _ = try engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason)));
            unreachable;
        }
        const warning = try s.get(inputs.process, "emitWarning");
        const message = try s.concat(try s.concat(try s.concat(try s.concat(try s.text("Invalid 'main' field in '"), try s.stringify(json_path)), try s.text("' of '")), try s.stringify(main)),
            try s.text("'. Please either fix that or report it to the module author"));
        _ = try s.call(warning, inputs.process, &.{ message, try s.text("DeprecationWarning"), try s.text("DEP0128") });
    }
    return c.JS_DupValue(engine.context, actual);
}

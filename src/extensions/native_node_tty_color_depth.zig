// Copyright Sindre Sorhus and Node contributors. MIT; retained authority/license.
//! Complete internal/tty.getColorDepth and its original private lexical state.
//! The actual builtin assembler supplies process/require and an early-bootstrapped
//! genuine SafeMap. No terminal capability, OS release or environment is guessed.
const a = @import("native_node_argument_values.zig");
const functions = @import("native_node_module_callable.zig");
const sync = @import("native_sync_arguments.zig");
const public = @import("native_public_values.zig");
const arithmetic = @import("native_image_arithmetic.zig");
const c = a.c;
const Scope = a.Scope;
const Frame = a.frames.Frame(enum { release, build_number, env_name, colors, term_env });

pub const Inputs = struct {
    process: c.JSValue,
    require: c.JSValue,
    /// Exact class retained by native_node_fs_collections.acquireSafeMap during
    /// genuine primordial bootstrap. Late global recapture is not performed.
    safe_map: c.JSValue,
};
fn intrinsic(s: *Scope, name: [*:0]const u8) !c.JSValue {
    return s.get(s.engine.intrinsic_clone_operations, name);
}
fn numberValue(s: *Scope, number: i32) c.JSValue { return c.JS_NewInt32(s.engine.context, number); }
fn sameText(s: *Scope, value: c.JSValue, bytes: []const u8) !bool {
    return c.JS_IsString(value) and s.equal(value, try s.text(bytes));
}
fn regexp(s: *Scope, pattern: []const u8) !c.JSValue {
    return s.construct(try intrinsic(s, "RegExp"), &.{try s.text(pattern)});
}
fn state(s: *Scope, owner: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return s.get(owner, name);
}
/// Return the actual constructible getColorDepth callable, length zero. The
/// genuine module assembler retains one result for its module evaluation.
/// hasColors/validateInteger and public TTY publication are separate suppliers.
pub fn create(engine: *a.v.em.Engine, inputs: Inputs) !c.JSValue {
    return a.expression(engine, createBody, .{inputs});
}
fn createBody(s: *Scope, inputs: Inputs) !c.JSValue {
    try s.pending();
    const expected = s.engine.native_module_values.get("\x00native.fs.SafeMap") orelse
        return error.RequiredBootstrappedActualTtySafeMap;
    if (!s.equal(expected, inputs.safe_map)) return error.ActualTtySafeMapIdentityChanged;
    if (!c.JS_IsObject(inputs.process) or !c.JS_IsFunction(s.engine.context, inputs.require))
        return error.RequiredActualTtyBuiltinInputs;
    const safe_map = try s.own(a.duplicate(s.engine, inputs.safe_map));
    const owner = try s.objectProto(c.pi_js_null());
    try s.define(owner, "process", inputs.process, 0);
    try s.define(owner, "require", inputs.require, 0);
    try s.define(owner, "OSRelease", c.pi_js_undefined(), c.JS_PROP_WRITABLE);
    try s.define(owner, "warned", a.boolean(s, false), c.JS_PROP_WRITABLE);
    const terms = try s.object();
    // Original ordinary object: inherited keys remain observable.
    inline for (.{
        .{ "eterm", 4 }, .{ "cons25", 4 }, .{ "console", 4 }, .{ "cygwin", 4 },
        .{ "dtterm", 4 }, .{ "gnome", 4 }, .{ "hurd", 4 }, .{ "jfbterm", 4 },
        .{ "konsole", 4 }, .{ "kterm", 4 }, .{ "mlterm", 4 }, .{ "mosh", 24 },
        .{ "putty", 4 }, .{ "st", 4 }, .{ "rxvt-unicode-24bit", 24 },
        .{ "terminator", 24 }, .{ "xterm-kitty", 24 },
    }) |entry| try s.define(terms, entry[0], numberValue(s, entry[1]), c.JS_PROP_C_W_E);
    try s.define(owner, "terms", terms, 0);
    const ci_object = try s.object();
    inline for (.{
        .{ "APPVEYOR", 8 }, .{ "BUILDKITE", 8 }, .{ "CIRCLECI", 24 }, .{ "DRONE", 8 },
        .{ "GITEA_ACTIONS", 24 }, .{ "GITHUB_ACTIONS", 24 }, .{ "GITLAB_CI", 8 }, .{ "TRAVIS", 8 },
    }) |entry| try s.define(ci_object, entry[0], numberValue(s, entry[1]), c.JS_PROP_C_W_E);
    const entries = try s.call(try intrinsic(s, "Object.entries"), c.pi_js_undefined(), &.{ci_object});
    const ci_map = try s.construct(safe_map, &.{entries});
    try s.define(owner, "ci_map", ci_map, 0);
    const regexes = try a.array(s);
    inline for (.{ "ansi", "color", "linux", "direct", "^con[0-9]*x[0-9]",
        "^rxvt", "^screen", "^xterm", "^vt100", "^vt220" }, 0..) |pattern, index|
        try a.index(s, regexes, @intCast(index), try regexp(s, pattern));
    try s.define(owner, "regexes", regexes, 0);
    return functions.createWithArguments(s.engine, "getColorDepth", 0, true,
        .{ .formal_count = 1, .callback = depthCallback, .hooks = sync.frameHooks(Frame) }, &.{owner});
}
fn defaultEnvironment(s: *Scope, owner: c.JSValue) !c.JSValue {
    return a.duplicate(s.engine, try s.get(try state(s, owner, "process"), "env"));
}
fn fieldDefined(s: *Scope, object: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return a.boolean(s, !c.JS_IsUndefined(try s.get(object, name)));
}
fn fieldEquals(s: *Scope, object: c.JSValue, name: [*:0]const u8, text: []const u8) !c.JSValue {
    return a.boolean(s, try sameText(s, try s.get(object, name), text));
}
fn disabled(engine: *a.v.em.Engine, environment: c.JSValue, name: [*:0]const u8) !bool {
    // Each discarded comparison operand retires before the next Get.
    return try a.condition(engine, fieldDefined, .{ environment, name }) and
        !try a.condition(engine, fieldEquals, .{ environment, name, @as([]const u8, "") });
}
fn forceLevel(s: *Scope, environment: c.JSValue) !c.JSValue {
    const force = try s.get(environment, "FORCE_COLOR");
    return numberValue(s, if (try sameText(s, force, "") or try sameText(s, force, "1") or
        try sameText(s, force, "true")) 4 else if (try sameText(s, force, "2")) 8 else
        if (try sameText(s, force, "3")) 24 else 1);
}
fn emitWarning(s: *Scope, owner: c.JSValue, node: bool, no_color: bool) !c.JSValue {
    const process = try state(s, owner, "process");
    const emit = try s.get(process, "emitWarning");
    const message = if (node and no_color)
        "The 'NODE_DISABLE_COLORS' and 'NO_COLOR' env is ignored due to the 'FORCE_COLOR' env being set."
    else if (node)
        "The 'NODE_DISABLE_COLORS' env is ignored due to the 'FORCE_COLOR' env being set."
    else "The 'NO_COLOR' env is ignored due to the 'FORCE_COLOR' env being set.";
    _ = try s.call(emit, process, &.{ try s.text(message), try s.text("Warning") });
    return c.pi_js_undefined();
}
fn markWarned(s: *Scope, owner: c.JSValue) !c.JSValue {
    try s.put(owner, "warned", a.boolean(s, true));
    return c.pi_js_undefined();
}
fn warning(s: *Scope, owner: c.JSValue, environment: c.JSValue) !c.JSValue {
    if (try a.condition(s.engine, a.fieldTruthy, .{ owner, @as([*:0]const u8, "warned") }))
        return c.pi_js_undefined();
    const node = try disabled(s.engine, environment, "NODE_DISABLE_COLORS");
    const no_color = try disabled(s.engine, environment, "NO_COLOR");
    if (node or no_color) {
        // The call/reference/ignored result retire before the assignment.
        _ = try a.expression(s.engine, emitWarning, .{ owner, node, no_color });
        _ = try a.expression(s.engine, markWarned, .{owner});
    }
    return c.pi_js_undefined();
}
fn windowsPlatform(s: *Scope, owner: c.JSValue) !c.JSValue {
    return fieldEquals(s, try state(s, owner, "process"), "platform", "win32");
}
fn releaseMissing(s: *Scope, owner: c.JSValue) !c.JSValue {
    return a.boolean(s, c.JS_IsUndefined(try state(s, owner, "OSRelease")));
}
fn releaseFunction(s: *Scope, owner: c.JSValue) !c.JSValue {
    const require = try state(s, owner, "require");
    const os = try s.call(require, c.pi_js_undefined(), &.{try s.text("os")});
    return a.duplicate(s.engine, try s.get(os, "release"));
}
fn assignRelease(s: *Scope, owner: c.JSValue, release: c.JSValue) !c.JSValue {
    const split = try intrinsic(s, "String.split");
    const raw = try s.call(release, c.pi_js_undefined(), &.{});
    const parts = try s.call(split, raw, &.{ try s.text("."), numberValue(s, 3) });
    // A nested require/release/split may initialize the cache. The outer
    // successful assignment still wins, exactly as the original Source.
    try s.put(owner, "OSRelease", parts);
    return c.pi_js_undefined();
}
fn releaseNumber(s: *Scope, owner: c.JSValue, name: [*:0]const u8) !c.JSValue {
    const item = try s.get(try state(s, owner, "OSRelease"), name);
    try s.pending();
    return a.duplicate(s.engine, try s.checked(c.JS_ToNumber(s.engine.context, item)));
}
fn majorAtLeastTen(s: *Scope, owner: c.JSValue) !c.JSValue {
    const major = try s.own(try a.expression(s.engine, releaseNumber, .{ owner, @as([*:0]const u8, "0") }));
    return a.duplicate(s.engine, try s.binary(@intFromEnum(arithmetic.Operation.greater_equal), major, numberValue(s, 10)));
}
fn atLeast(s: *Scope, value: c.JSValue, minimum: i32) !c.JSValue {
    return a.duplicate(s.engine, try s.binary(@intFromEnum(arithmetic.Operation.greater_equal), value, numberValue(s, minimum)));
}
fn windowsDepth(s: *Scope, owner: c.JSValue, frame: *Frame) !c.JSValue {
    if (try a.condition(s.engine, releaseMissing, .{owner})) {
        try frame.take(.release, a.expression(s.engine, releaseFunction, .{owner}));
        _ = try a.expression(s.engine, assignRelease, .{ owner, frame.get(.release) });
    }
    if (try a.condition(s.engine, majorAtLeastTen, .{owner})) {
        try frame.take(.build_number, a.expression(s.engine, releaseNumber, .{ owner, @as([*:0]const u8, "2") }));
        if (try a.condition(s.engine, atLeast, .{ frame.get(.build_number), @as(i32, 14931) })) return numberValue(s, 24);
        if (try a.condition(s.engine, atLeast, .{ frame.get(.build_number), @as(i32, 10586) })) return numberValue(s, 8);
    }
    return numberValue(s, 4);
}
fn hasOwn(s: *Scope, environment: c.JSValue, key: c.JSValue) !c.JSValue {
    return a.duplicate(s.engine, try s.call(try intrinsic(s, "Object.hasOwnProperty"), environment, &.{key}));
}
fn hasOwnText(s: *Scope, environment: c.JSValue, name: []const u8) !c.JSValue {
    return hasOwn(s, environment, try s.text(name));
}
fn unpackCI(s: *Scope, incoming: c.JSValue, frame: *Frame) !c.JSValue {
    const entry = try s.own(incoming);
    try frame.take(.env_name, a.field(s.engine, entry, "0"));
    try frame.take(.colors, a.field(s.engine, entry, "1"));
    return c.pi_js_undefined();
}
fn ciLoop(s: *Scope, environment: c.JSValue, frame: *Frame, iterator: *public.Iterator) !c.JSValue {
    while (try iterator.next()) |entry| {
        _ = try a.expression(s.engine, unpackCI, .{ entry, frame });
        if (try a.condition(s.engine, hasOwn, .{ environment, frame.get(.env_name) }))
            return a.duplicate(s.engine, frame.get(.colors));
    }
    return numberValue(s, if (try a.condition(s.engine, fieldEquals,
        .{ environment, @as([*:0]const u8, "CI_NAME"), @as([]const u8, "codeship") })) 8 else 1);
}
fn normalIteratorClose(s: *Scope, iterator: *public.Iterator) !c.JSValue {
    if (iterator.closed) return c.pi_js_undefined();
    iterator.closed = true;
    const close = try s.get(iterator.receiver, "return");
    if (!c.JS_IsNull(close) and !c.JS_IsUndefined(close)) {
        const result = try s.call(close, iterator.receiver, &.{});
        if (!c.JS_IsObject(result)) {
            const generation = try s.beforeAllocation();
            return s.checkedAllocation(c.JS_ThrowTypeError(s.engine.context, "iterator must return an object"), generation);
        }
    }
    return c.pi_js_undefined();
}
fn finishCI(engine: *a.v.em.Engine, iterator: *public.Iterator, result: anyerror!c.JSValue) !c.JSValue {
    const value = result catch |err| { try iterator.finish(err); unreachable; };
    _ = a.expression(engine, normalIteratorClose, .{iterator}) catch |err| {
        var failed = a.owned.Completion.initVoid(engine, err);
        failed.release(value);
        try iterator.finish(failed.finishVoid());
        unreachable;
    };
    iterator.finish({}) catch |err| {
        var failed = a.owned.Completion.initVoid(engine, err);
        failed.release(value);
        try failed.finishVoid();
        unreachable;
    };
    return value;
}
fn ciDepth(s: *Scope, owner: c.JSValue, environment: c.JSValue, frame: *Frame) !c.JSValue {
    var iterator = try public.Iterator.init(s.engine, try state(s, owner, "ci_map"));
    return finishCI(s.engine, &iterator, ciLoop(s, environment, frame, &iterator));
}
fn teamcityPresent(s: *Scope, environment: c.JSValue) !c.JSValue {
    // Native HasProperty alone is not the 'in' operator on a primitive RHS.
    if (!c.JS_IsObject(environment)) {
        const generation = try s.beforeAllocation();
        return s.checkedAllocation(c.JS_ThrowTypeError(s.engine.context, "invalid 'in' operand"), generation);
    }
    return a.boolean(s, try s.hasKey(environment, try s.text("TEAMCITY_VERSION")));
}
fn matchesField(s: *Scope, environment: c.JSValue, name: [*:0]const u8, pattern: []const u8) !c.JSValue {
    const exec = try intrinsic(s, "RegExp.exec");
    // Each Source regexp literal in the function is freshly instantiated
    // before the environment argument Get, not shared across calls.
    const expression = try regexp(s, pattern);
    return a.boolean(s, !c.JS_IsNull(try s.call(exec, expression, &.{try s.get(environment, name)})));
}
fn terminalProgram(s: *Scope, environment: c.JSValue) !c.JSValue {
    const program = try s.get(environment, "TERM_PROGRAM");
    return numberValue(s, if (try sameText(s, program, "iTerm.app")) 1 else
        if (try sameText(s, program, "HyperTerm") or try sameText(s, program, "MacTerm")) 24 else
        if (try sameText(s, program, "Apple_Terminal")) 8 else 0);
}
fn lowerTerm(s: *Scope, environment: c.JSValue) !c.JSValue {
    const lower = try intrinsic(s, "String.toLowerCase");
    return a.duplicate(s.engine, try s.call(lower, try s.get(environment, "TERM"), &.{}));
}
fn mappedTerm(s: *Scope, owner: c.JSValue, term: c.JSValue) !c.JSValue {
    return a.duplicate(s.engine, try s.getKey(try state(s, owner, "terms"), term));
}
fn mappedTruthy(s: *Scope, owner: c.JSValue, term: c.JSValue) !c.JSValue {
    return a.boolean(s, s.truthy(try s.getKey(try state(s, owner, "terms"), term)));
}
fn regexpTermBody(s: *Scope, term: c.JSValue, term_env: c.JSValue) !c.JSValue {
    return a.boolean(s, !c.JS_IsNull(try s.call(try intrinsic(s, "RegExp.exec"), term, &.{term_env})));
}
fn regexpTermCallback(engine: *a.v.em.Engine, _: c.JSValue, args: *sync.Arguments, roots: []const c.JSValue) !c.JSValue {
    return a.expression(engine, regexpTermBody, .{ args.get(0), roots[0] });
}
fn someTerm(s: *Scope, owner: c.JSValue, term_env: c.JSValue) !c.JSValue {
    const some = try intrinsic(s, "Array.some");
    const regexes = try state(s, owner, "regexes");
    const predicate = try s.own(try functions.createWithArguments(s.engine, "", 1, false,
        .{ .formal_count = 1, .callback = regexpTermCallback }, &.{term_env}));
    return a.duplicate(s.engine, try s.call(some, regexes, &.{predicate}));
}
fn depthBody(s: *Scope, owner: c.JSValue, environment: c.JSValue, frame: *Frame) !c.JSValue {
    const engine = s.engine;
    if (try a.condition(engine, fieldDefined, .{ environment, @as([*:0]const u8, "FORCE_COLOR") })) {
        const level = try s.own(try a.expression(engine, forceLevel, .{environment}));
        if (!s.equal(level, numberValue(s, 1))) _ = try a.expression(engine, warning, .{ owner, environment });
        return a.duplicate(engine, level);
    }
    if (try disabled(engine, environment, "NODE_DISABLE_COLORS") or try disabled(engine, environment, "NO_COLOR") or
        try a.condition(engine, fieldEquals, .{ environment, @as([*:0]const u8, "TERM"), @as([]const u8, "dumb") }))
        return numberValue(s, 1);
    if (try a.condition(engine, windowsPlatform, .{owner})) return windowsDepth(s, owner, frame);
    if (try a.condition(engine, a.fieldTruthy, .{ environment, @as([*:0]const u8, "TMUX") })) return numberValue(s, 24);
    if (try a.condition(engine, hasOwnText, .{ environment, @as([]const u8, "TF_BUILD") }) and
        try a.condition(engine, hasOwnText, .{ environment, @as([]const u8, "AGENT_NAME") })) return numberValue(s, 4);
    if (try a.condition(engine, hasOwnText, .{ environment, @as([]const u8, "CI") }))
        return ciDepth(s, owner, environment, frame);
    if (try a.condition(engine, teamcityPresent, .{environment}))
        return numberValue(s, if (try a.condition(engine, matchesField, .{ environment,
            @as([*:0]const u8, "TEAMCITY_VERSION"), @as([]const u8, "^(9\\.(0*[1-9]\\d*)\\.|\\d{2,}\\.)") })) 4 else 1);
    const program = try s.own(try a.expression(engine, terminalProgram, .{environment}));
    if (s.equal(program, numberValue(s, 1))) {
        if (!try a.condition(engine, a.fieldTruthy, .{ environment, @as([*:0]const u8, "TERM_PROGRAM_VERSION") }) or
            try a.condition(engine, matchesField, .{ environment, @as([*:0]const u8, "TERM_PROGRAM_VERSION"), @as([]const u8, "^[0-2]\\.") }))
            return numberValue(s, 8);
        return numberValue(s, 24);
    }
    if (!s.equal(program, numberValue(s, 0))) return a.duplicate(engine, program);
    if (try a.condition(engine, fieldEquals, .{ environment, @as([*:0]const u8, "COLORTERM"), @as([]const u8, "truecolor") }) or
        try a.condition(engine, fieldEquals, .{ environment, @as([*:0]const u8, "COLORTERM"), @as([]const u8, "24bit") }))
        return numberValue(s, 24);
    if (try a.condition(engine, a.fieldTruthy, .{ environment, @as([*:0]const u8, "TERM") })) {
        if (try a.condition(engine, matchesField, .{ environment, @as([*:0]const u8, "TERM"), @as([]const u8, "truecolor") })) return numberValue(s, 24);
        if (try a.condition(engine, matchesField, .{ environment, @as([*:0]const u8, "TERM"), @as([]const u8, "^xterm-256") })) return numberValue(s, 8);
        try frame.take(.term_env, a.expression(engine, lowerTerm, .{environment}));
        if (try a.condition(engine, mappedTruthy, .{ owner, frame.get(.term_env) }))
            return a.expression(engine, mappedTerm, .{ owner, frame.get(.term_env) });
        if (try a.condition(engine, someTerm, .{ owner, frame.get(.term_env) })) return numberValue(s, 4);
    }
    return numberValue(s, if (try a.condition(engine, a.fieldTruthy,
        .{ environment, @as([*:0]const u8, "COLORTERM") })) 4 else 1);
}
fn depthCallback(engine: *a.v.em.Engine, _: c.JSValue, args: *sync.Arguments, roots: []const c.JSValue) !c.JSValue {
    var s = Scope.init(engine);
    const owner = roots[0];
    if (c.JS_IsUndefined(args.get(0))) {
        args.take(0, a.expression(engine, defaultEnvironment, .{owner})) catch |err|
            return s.finish(@as(anyerror!c.JSValue, err));
    }
    const frame = args.createFrame(&s.values, Frame) catch |err| return s.finish(@as(anyerror!c.JSValue, err));
    return s.finish(depthBody(&s, owner, args.get(0), frame));
}

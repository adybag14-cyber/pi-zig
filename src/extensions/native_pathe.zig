//! Actual pathe2.0.3 operations consumed by jiti2.7. Module constants are
//! GC-visible captures; string methods remain live VM operations, not node:path.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = v.Scope;
// Actual owned call/construction adapter already used by the consumed MLLY
// bindings. Sharing its synchronous provenance also covers Pathe/MLLY reentry;
// an independently copied stack would re-promote an ordinary cross-leaf reason.
const functions = @import("native_mlly_function.zig");
const body = @import("native_async_body.zig");
fn arg(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
fn number(s: *Scope, value: i64) c.JSValue { return c.JS_NewInt64(s.engine.context, value); }
fn binary(s: *Scope, op: c_int, a: c.JSValue, b: c.JSValue) !c.JSValue { return s.own(try s.engine.checked(c.JS_PiBinaryOperator(s.engine.context, op, a, b))); }
fn key(s: *Scope, value: c.JSValue, at: c.JSValue) !c.JSValue { return s.own(try v.js.getKey(s.engine, value, at)); }
fn same(s: *Scope, value: c.JSValue, text: []const u8) !bool { return s.equal(value, try s.text(text)); }
fn assign(engine: *v.em.Engine, slot: *c.JSValue, value: c.JSValue) void { const retained = c.JS_DupValue(engine.context, value); engine.freeValue(slot.*); slot.* = retained; }
fn define(s: *Scope, value: c.JSValue, name: [*:0]const u8, item: c.JSValue) !void { try v.js.define(s.engine, value, name, c.JS_DupValue(s.engine.context, item)); }
fn regex(s: *Scope, pattern: []const u8, flags: []const u8) !c.JSValue {
    const args = [_]c.JSValue{ try s.text(pattern), try s.text(flags) };
    return s.own(try s.engine.checked(c.JS_CallConstructor(s.engine.context, s.engine.intrinsic_regexp_constructor, args.len, @constCast(&args))));
}
fn checkedBoundary(engine: *v.em.Engine, err: anyerror, generation: u64) anyerror {
    if (err == error.JavaScriptException) if (engine.captured_exception) |reason| body.rethrowRecognizedAllocation(engine, reason, functions.trustedGeneration(engine, generation)) catch |fatal| return fatal;
    return err;
}
fn restore(engine: *v.em.Engine, reason: ?c.JSValue) void {
    const previous = engine.captured_exception; engine.captured_exception = null;
    if (previous) |value| engine.freeValue(value);
    engine.captured_exception = if (reason) |value| c.JS_DupValue(engine.context, value) else null;
}
fn closeAbrupt(engine: *v.em.Engine, iterator: *v.js.Iterator, failure: anyerror, generation: u64) anyerror {
    const primary_error = checkedBoundary(engine, failure, generation);
    const primary = if (primary_error == error.JavaScriptException) if (engine.captured_exception) |value| c.JS_DupValue(engine.context, value) else null else null;
    defer if (primary) |value| engine.freeValue(value);
    const fatal = primary_error == error.OutOfMemory or (if (primary) |value| c.JS_IsUncatchableError(value) else false);
    abruptReturn(engine, iterator) catch |err| {
        // abruptReturn already classified its actual getter/call boundary. The
        // loop-start generation must not promote older cleanup data a second time.
        const cleanup_error = err;
        if (!fatal and (cleanup_error == error.OutOfMemory or (cleanup_error == error.JavaScriptException and if (engine.captured_exception) |reason| c.JS_IsUncatchableError(reason) else false))) return cleanup_error;
    };
    // IteratorClose suppresses an ordinary cleanup throw for a throw completion.
    // A trusted primary keeps its exact owned reason through attempted cleanup.
    restore(engine, primary);
    return primary_error;
}
fn abruptReturn(engine: *v.em.Engine, iterator: *v.js.Iterator) !void {
    if (iterator.closed) return;
    iterator.closed = true;
    const getter_generation = engine.native_allocation_generation;
    const method = v.js.get(engine, iterator.iterator, "return") catch |err| return checkedBoundary(engine, err, getter_generation); defer engine.freeValue(method);
    if (v.nullish(method)) return;
    const call_generation = engine.native_allocation_generation;
    const result = v.js.call(engine, method, iterator.iterator, &.{}) catch |err| return checkedBoundary(engine, err, call_generation); defer engine.freeValue(result);
    // IteratorClose with a throw completion returns the primary BEFORE the
    // normal-return object check. Do not manufacture a suppressed TypeError.
}
fn normalCloseFailure(engine: *v.em.Engine, err: anyerror, generation: u64) anyerror {
    const classified = checkedBoundary(engine, err, generation);
    if (classified == error.JavaScriptException) if (engine.captured_exception) |reason| {
        if (!c.JS_IsUncatchableError(reason)) functions.ordinaryBoundary(engine);
    };
    return classified;
}
fn closeNormal(engine: *v.em.Engine, iterator: *v.js.Iterator) !void {
    if (iterator.closed) return; iterator.closed = true;
    const getter_generation = engine.native_allocation_generation;
    const method = v.js.get(engine, iterator.iterator, "return") catch |err| return normalCloseFailure(engine, err, getter_generation); defer engine.freeValue(method);
    if (v.nullish(method)) return;
    const call_generation = engine.native_allocation_generation;
    const result = v.js.call(engine, method, iterator.iterator, &.{}) catch |err| return normalCloseFailure(engine, err, call_generation); defer engine.freeValue(result);
    if (!c.JS_IsObject(result)) return v.js.typeError(engine, "Iterator return result is not an object");
}
fn advance(engine: *v.em.Engine, iterator: *v.js.Iterator) !?c.JSValue {
    try budget(engine, &iterator.native_steps);
    errdefer iterator.closed = true;
    const step = try v.js.call(engine, iterator.next_function, iterator.iterator, &.{}); defer engine.freeValue(step);
    if (!c.JS_IsObject(step)) return v.js.typeError(engine, "Iterator result is not an object");
    const done = try v.js.get(engine, step, "done"); defer engine.freeValue(done);
    if (c.JS_ToBool(engine.context, done) != 0) { iterator.closed = true; return null; }
    return v.js.get(engine, step, "value");
}
fn Boundary(comptime callback: functions.Callback) type { return struct {
    fn call(engine: *v.em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
        const generation = engine.native_allocation_generation;
        return callback(engine, receiver, args, roots) catch |err| return checkedBoundary(engine, err, generation);
    }
}; }
fn budget(engine: *v.em.Engine, steps: *usize) !void {
    steps.* +|= 1;
    if (engine.cancelled.load(.acquire) or (steps.* % 256 == 0 and blk: { engine.interrupts +|= 1; break :blk engine.interrupts > engine.options.interrupt_budget; })) {
        _ = c.JS_ThrowInternalError(engine.context, "interrupted");
        const reason = c.JS_GetException(engine.context);
        c.JS_SetUncatchableError(engine.context, reason);
        _ = try engine.checked(c.JS_Throw(engine.context, reason)); unreachable;
    }
}
fn upper(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue { return v.js.invoke(engine, arg(args, 0), "toUpperCase", &.{}); }
fn windows(s: *Scope, state: c.JSValue, input: c.JSValue) !c.JSValue {
    const value = if (c.JS_IsUndefined(input)) try s.text("") else input;
    if (!s.truthy(value)) return value;
    const slash_replace = try s.get(value, "replace");
    const backslash = try regex(s, "\\\\", "g");
    const slashed = try s.call(slash_replace, value, &.{ backslash, try s.text("/") });
    const replace = try s.get(slashed, "replace");
    const drive = try s.get(state, "driveStart");
    const uppercase = try s.own(try functions.createArrow(s.engine, "", 1, Boundary(upper).call, &.{}));
    return s.call(replace, slashed, &.{ drive, uppercase });
}
fn absolute(s: *Scope, state: c.JSValue, input: c.JSValue) !bool { return s.truthy(try s.invoke(try s.get(state, "absolute"), "test", &.{input})); }
fn normalString(engine: *v.em.Engine, path: c.JSValue, above_root: bool) !c.JSValue {
    var res = try engine.checked(c.JS_NewString(engine.context, "")); defer engine.freeValue(res);
    var last_length = c.JS_NewInt32(engine.context, 0); defer engine.freeValue(last_length);
    var last_slash: i64 = -1;
    var dots: i32 = 0;
    var char = c.pi_js_null(); defer engine.freeValue(char);
    var index: i64 = 0; var steps: usize = 0;
    while (true) : (index += 1) {
        var s: Scope = .{ .engine = engine }; defer s.deinit();
        try budget(engine, &steps);
        if (!s.truthy(try binary(&s, 5, number(&s, index), try s.get(path, "length")))) break;
        if (s.truthy(try binary(&s, 4, number(&s, index), try s.get(path, "length")))) assign(engine, &char, try key(&s, path, number(&s, index)))
        else if (try same(&s, char, "/")) break
        else assign(engine, &char, try s.text("/"));
        if (try same(&s, char, "/")) {
            if (last_slash == index - 1 or dots == 1) {
                // Source NOOP.
            } else if (dots == 2) {
                const short = s.truthy(try binary(&s, 4, try s.get(res, "length"), number(&s, 2)));
                const previous_dots = s.equal(last_length, number(&s, 2));
                if (short or !previous_dots or !try same(&s, try key(&s, res, try binary(&s, 1, try s.get(res, "length"), number(&s, 1))), ".") or !try same(&s, try key(&s, res, try binary(&s, 1, try s.get(res, "length"), number(&s, 2))), ".")) {
                    if (s.truthy(try binary(&s, 6, try s.get(res, "length"), number(&s, 2)))) {
                        const at = try s.invoke(res, "lastIndexOf", &.{try s.text("/")});
                        if (s.equal(at, number(&s, -1))) { assign(engine, &res, try s.text("")); assign(engine, &last_length, number(&s, 0)); }
                        else {
                            assign(engine, &res, try s.invoke(res, "slice", &.{ number(&s, 0), at }));
                            const less = try binary(&s, 1, try s.get(res, "length"), number(&s, 1));
                            assign(engine, &last_length, try binary(&s, 1, less, try s.invoke(res, "lastIndexOf", &.{try s.text("/")})));
                        }
                        last_slash = index; dots = 0; continue;
                    } else if (s.truthy(try binary(&s, 6, try s.get(res, "length"), number(&s, 0)))) {
                        assign(engine, &res, try s.text("")); assign(engine, &last_length, number(&s, 0)); last_slash = index; dots = 0; continue;
                    }
                }
                if (above_root) {
                    assign(engine, &res, try s.concat(res, try s.text(if (s.truthy(try binary(&s, 6, try s.get(res, "length"), number(&s, 0)))) "/.." else "..")));
                    assign(engine, &last_length, number(&s, 2));
                }
            } else {
                if (s.truthy(try binary(&s, 6, try s.get(res, "length"), number(&s, 0)))) {
                    const left = try s.own(c.JS_DupValue(engine.context, res));
                    const right = try s.invoke(path, "slice", &.{ number(&s, last_slash + 1), number(&s, index) });
                    const suffix = try s.concat(try s.text("/"), try s.stringify(right));
                    assign(engine, &res, try s.concat(left, suffix));
                } else assign(engine, &res, try s.invoke(path, "slice", &.{ number(&s, last_slash + 1), number(&s, index) }));
                assign(engine, &last_length, number(&s, index - last_slash - 1));
            }
            last_slash = index; dots = 0;
        } else if (try same(&s, char, ".") and dots != -1) dots += 1 else dots = -1;
    }
    return c.JS_DupValue(engine.context, res);
}
fn normal(s: *Scope, state: c.JSValue, input: c.JSValue) !c.JSValue {
    if (s.equal(try s.get(input, "length"), number(s, 0))) return s.text(".");
    var path = try windows(s, state, input);
    const unc = try s.invoke(path, "match", &.{try s.get(state, "unc")});
    const is_absolute = try absolute(s, state, path);
    const trailing = try same(s, try key(s, path, try binary(s, 1, try s.get(path, "length"), number(s, 1))), "/");
    path = try s.own(try normalString(s.engine, path, !is_absolute));
    if (s.equal(try s.get(path, "length"), number(s, 0))) return s.text(if (is_absolute) "/" else if (trailing) "./" else ".");
    if (trailing) path = try s.concat(path, try s.text("/"));
    if (s.truthy(try s.invoke(try s.get(state, "driveOnly"), "test", &.{path}))) path = try s.concat(path, try s.text("/"));
    if (s.truthy(unc)) return s.concat(try s.text(if (is_absolute) "//" else "//./"), try s.stringify(path));
    return if (is_absolute and !try absolute(s, state, path)) s.concat(try s.text("/"), try s.stringify(path)) else path;
}
fn normalizeCall(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); return c.JS_DupValue(engine.context, try normal(&s, roots[0], arg(args, 0)));
}
fn absoluteCall(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); return v.js.invoke(engine, try s.get(roots[0], "absolute"), "test", &.{arg(args, 0)});
}
fn extnameCall(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    if (try same(&s, arg(args, 0), "..")) return engine.checked(c.JS_NewString(engine.context, ""));
    const exec = try s.get(try s.get(roots[0], "extension"), "exec");
    const normalized = try windows(&s, roots[0], arg(args, 0));
    const match = try s.call(exec, try s.get(roots[0], "extension"), &.{normalized});
    const value = if (s.truthy(match)) try v.at(&s, match, 1) else match;
    return c.JS_DupValue(engine.context, if (s.truthy(value)) value else try s.text(""));
}
fn dirnameCall(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const normalized = try windows(&s, roots[0], arg(args, 0));
    const replace = try s.get(normalized, "replace");
    const trailing = try regex(&s, "/$", "");
    const stripped = try s.call(replace, normalized, &.{ trailing, try s.text("") });
    const split = try s.invoke(stripped, "split", &.{try s.text("/")});
    const segments = try s.invoke(split, "slice", &.{ number(&s, 0), number(&s, -1) });
    if (s.equal(try s.get(segments, "length"), number(&s, 1)) and s.truthy(try s.invoke(try s.get(roots[0], "driveOnly"), "test", &.{try v.at(&s, segments, 0)}))) {
        try v.js.setKey(engine, segments, number(&s, 0), try s.concat(try v.at(&s, segments, 0), try s.text("/")));
    }
    const joined = try s.invoke(segments, "join", &.{try s.text("/")});
    return c.JS_DupValue(engine.context, if (s.truthy(joined)) joined else try s.text(if (try absolute(&s, roots[0], arg(args, 0))) "/" else "."));
}
fn basenameCall(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const segments = try s.invoke(try windows(&s, roots[0], arg(args, 0)), "split", &.{try s.text("/")});
    var last = try s.text("");
    var index = try engine.checked(c.JS_PiBinaryOperator(engine.context, 1, try s.get(segments, "length"), number(&s, 1))); defer engine.freeValue(index);
    var steps: usize = 0;
    while (true) {
        var f: Scope = .{ .engine = engine }; defer f.deinit(); try budget(engine, &steps);
        if (!f.truthy(try binary(&f, 7, index, number(&f, 0)))) break;
        const value = try key(&f, segments, index);
        if (f.truthy(value)) { last = try s.own(c.JS_DupValue(engine.context, value)); break; }
        const next = try engine.checked(c.JS_PiDecrement(engine.context, index)); engine.freeValue(index); index = next;
    }
    const extension = arg(args, 1);
    if (s.truthy(extension) and s.truthy(try s.invoke(last, "endsWith", &.{extension}))) {
        const slice = try s.get(last, "slice");
        const negative = try binary(&s, 1, c.JS_NewFloat64(engine.context, -0.0), try s.get(extension, "length"));
        return v.js.call(engine, slice, last, &.{ number(&s, 0), negative });
    }
    return c.JS_DupValue(engine.context, last);
}
fn rest(s: *Scope, args: []const c.JSValue) !c.JSValue {
    const array = try s.array();
    for (args, 0..) |value, index| if (c.JS_DefinePropertyValueUint32(s.engine.context, array, @intCast(index), c.JS_DupValue(s.engine.context, value), c.JS_PROP_C_W_E) < 0) return v.js.capture(s.engine);
    return array;
}
fn joined(engine: *v.em.Engine, state: c.JSValue, args: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    var iterator = try v.iterator(&s, try rest(&s, args)); defer iterator.deinit();
    const generation = engine.native_allocation_generation;
    return joinLoop(engine, state, &iterator) catch |err| return closeAbrupt(engine, &iterator, err, generation);
}
fn joinLoop(engine: *v.em.Engine, state: c.JSValue, iterator: *v.js.Iterator) !c.JSValue {
    var path = try engine.checked(c.JS_NewString(engine.context, "")); defer engine.freeValue(path);
    while (try advance(engine, iterator)) |segment| {
        defer engine.freeValue(segment);
        var s: Scope = .{ .engine = engine }; defer s.deinit();
        if (!s.truthy(segment)) continue;
        if (s.truthy(try binary(&s, 6, try s.get(path, "length"), number(&s, 0)))) {
            const trailing = try same(&s, try key(&s, path, try binary(&s, 1, try s.get(path, "length"), number(&s, 1))), "/");
            const leading = try same(&s, try v.at(&s, segment, 0), "/");
            const suffix = if (trailing and leading) try s.invoke(segment, "slice", &.{number(&s, 1)}) else if (trailing or leading) segment else try s.concat(try s.text("/"), try s.stringify(segment));
            assign(engine, &path, try s.concat(path, suffix));
        } else assign(engine, &path, try s.concat(path, segment));
    }
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    return c.JS_DupValue(engine.context, try normal(&s, state, path));
}
fn joinCall(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue { return joined(engine, roots[0], args); }
fn resolveArgument(engine:*v.em.Engine,_:c.JSValue,args:[]const c.JSValue,roots:[]const c.JSValue)!c.JSValue {
    var s:Scope=.{.engine=engine};defer s.deinit();
    return c.JS_DupValue(engine.context,try windows(&s,roots[0],arg(args,0)));
}
fn cwd(s:*Scope)!c.JSValue {
    // Source performs three independent global process reads, and reads cwd
    // once for typeof and again for the call. Do not snapshot these getters.
    if(!c.JS_IsUndefined(try s.global("process"))){
        const checked_process=try s.global("process");const function=try s.get(checked_process,"cwd");
        if(c.JS_IsFunction(s.engine.context,function)){
            const process=try s.global("process");const value=try s.invoke(process,"cwd",&.{});
            const replace=try s.get(value,"replace");const backslash=try regex(s,"\\\\","g");
            return s.call(replace,value,&.{backslash,try s.text("/")});
        }
    }
    return s.text("/");
}
fn resolveCall(engine:*v.em.Engine,_:c.JSValue,args:[]const c.JSValue,roots:[]const c.JSValue)!c.JSValue {
    var s:Scope=.{.engine=engine};defer s.deinit();const state=roots[0];
    const arguments=try rest(&s,args);const map=try s.get(arguments,"map");
    const callback=try s.own(try functions.createArrow(engine,"",1,Boundary(resolveArgument).call,&.{state}));
    const mapped=try s.call(map,arguments,&.{callback});
    var resolved=try engine.checked(c.JS_NewString(engine.context,""));defer engine.freeValue(resolved);var resolved_absolute=false;
    var index=c.JS_DupValue(engine.context,try binary(&s,1,try s.get(mapped,"length"),number(&s,1)));defer engine.freeValue(index);var steps:usize=0;
    while(true){
        var step:Scope=.{.engine=engine};defer step.deinit();
        if(!step.truthy(try binary(&step,7,index,number(&step,-1))) or resolved_absolute)break;
        try budget(engine,&steps);
        const path=if(step.truthy(try binary(&step,7,index,number(&step,0))))try key(&step,mapped,index) else try cwd(&step);
        if(step.truthy(path) and !step.equal(try step.get(path,"length"),number(&step,0))){
            const prefix=try step.concat(try step.stringify(path),try step.text("/"));
            const next=try step.concat(prefix,try step.stringify(resolved));
            assign(engine,&resolved,next);
            resolved_absolute=try absolute(&step,state,path);
        }
        // Source -- is numeric coercion, unlike binary- on a BigInt returned by
        // a hostile replacement length getter.
        const next_index=try engine.checked(c.JS_PiDecrement(engine.context,index));engine.freeValue(index);index=next_index;
    }
    const normalized=try s.own(try normalString(engine,resolved,!resolved_absolute));
    if(resolved_absolute and !try absolute(&s,state,normalized))return c.JS_DupValue(engine.context,try s.concat(try s.text("/"),try s.stringify(normalized)));
    return c.JS_DupValue(engine.context,if(s.truthy(try binary(&s,6,try s.get(normalized,"length"),number(&s,0))))normalized else try s.text("."));
}
fn filenameCall(engine:*v.em.Engine,_:c.JSValue,args:[]const c.JSValue,roots:[]const c.JSValue)!c.JSValue {
    var s:Scope=.{.engine=engine};defer s.deinit();const path=arg(args,0);
    const split=try s.get(path,"split");const segments=try s.call(split,path,&.{try s.get(roots[0],"filenameSlash")});
    const base=try s.invoke(segments,"pop",&.{});if(!s.truthy(base))return c.pi_js_undefined();
    const separator=try s.invoke(base,"lastIndexOf",&.{try s.text(".")});
    if(s.truthy(try binary(&s,5,separator,number(&s,0))))return c.JS_DupValue(engine.context,base);
    return c.JS_DupValue(engine.context,try s.invoke(base,"slice",&.{number(&s,0),separator}));
}

fn first(s: *Scope, pair: c.JSValue) !c.JSValue {
    var iterator = try v.iterator(s, pair); defer iterator.deinit();
    const generation = s.engine.native_allocation_generation;
    const value = advance(s.engine, &iterator) catch |err| return closeAbrupt(s.engine, &iterator, err, generation);
    const result = s.own(value orelse c.pi_js_undefined()) catch |err| return closeAbrupt(s.engine, &iterator, err, generation);
    try closeNormal(s.engine, &iterator); return result;
}
fn compareAliases(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const a = try first(&s, arg(args, 0)); const b = try first(&s, arg(args, 1));
    const b_parts = try s.invoke(b, "split", &.{try s.text("/")}); const b_length = try s.get(b_parts, "length");
    const a_parts = try s.invoke(a, "split", &.{try s.text("/")});
    return engine.checked(c.JS_PiBinaryOperator(engine.context, 1, b_length, try s.get(a_parts, "length")));
}
fn forIn(s: *Scope, object: c.JSValue) !c.JSValue {
    const result = try s.array();
    var seen: std.ArrayList(c.JSAtom) = .empty;
    defer { for (seen.items) |atom| c.JS_FreeAtom(s.engine.context, atom); seen.deinit(s.engine.gpa); }
    var current = c.JS_DupValue(s.engine.context, object); defer s.engine.freeValue(current);
    var at: u32 = 0; var steps: usize = 0;
    while (c.JS_IsObject(current)) {
        try budget(s.engine, &steps);
        var names: [*c]c.JSPropertyEnum = null; var count: u32 = 0;
        if (c.JS_GetOwnPropertyNames(s.engine.context, &names, &count, current, c.JS_GPN_STRING_MASK) < 0) return v.js.capture(s.engine);
        defer c.JS_FreePropertyEnum(s.engine.context, names, count);
        for (names[0..count]) |entry| {
            try budget(s.engine, &steps);
            if (std.mem.indexOfScalar(c.JSAtom, seen.items, entry.atom) != null) continue;
            const retained = c.JS_DupAtom(s.engine.context, entry.atom);
            seen.append(s.engine.gpa, retained) catch |err| { c.JS_FreeAtom(s.engine.context, retained); return err; };
            var descriptor: c.JSPropertyDescriptor = undefined;
            const present = c.JS_GetOwnProperty(s.engine.context, &descriptor, current, entry.atom);
            if (present < 0) return v.js.capture(s.engine);
            if (present == 0) continue;
            defer { s.engine.freeValue(descriptor.value); s.engine.freeValue(descriptor.getter); s.engine.freeValue(descriptor.setter); }
            if (descriptor.flags & c.JS_PROP_ENUMERABLE == 0) continue;
            const name = try s.engine.checked(c.JS_AtomToValue(s.engine.context, entry.atom));
            if (c.JS_DefinePropertyValueUint32(s.engine.context, result, at, name, c.JS_PROP_C_W_E) < 0) return v.js.capture(s.engine);
            at += 1;
        }
        const next = try s.engine.checked(c.JS_GetPrototype(s.engine.context, current)); s.engine.freeValue(current); current = next;
    }
    return result;
}
fn aliases(s: *Scope, state: c.JSValue, input: c.JSValue) !c.JSValue {
    const symbol = try s.get(state, "normalizedAliasSymbol");
    if (s.truthy(try key(s, input, symbol))) return input;
    // Source resolves Object.fromEntries before evaluating its entries argument.
    const from_object = try s.global("Object");
    const from = try s.get(from_object, "fromEntries");
    const entries = try s.invoke(try s.global("Object"), "entries", &.{input});
    const sort = try s.get(entries, "sort");
    const compare = try s.own(try functions.createArrow(s.engine, "", 2, Boundary(compareAliases).call, &.{}));
    const sorted = try s.call(sort, entries, &.{compare});
    const value = try s.call(from, from_object, &.{sorted});
    const keys = try forIn(s, value);
    const length = try v.length(s, keys);
    for (0..length) |index| {
        var outer: Scope = .{ .engine = s.engine }; defer outer.deinit();
        const current = try v.at(&outer, keys, @intCast(index));
        if (!try v.js.hasKey(s.engine, value, current)) continue;
        const inner_keys = try forIn(&outer, value);
        const inner_length = try v.length(&outer, inner_keys);
        for (0..inner_length) |inner| {
            var f: Scope = .{ .engine = s.engine }; defer f.deinit();
            const alias = try v.at(&f, inner_keys, @intCast(inner));
            if (!try v.js.hasKey(s.engine, value, alias)) continue;
            if (f.equal(alias, current) or f.truthy(try f.invoke(current, "startsWith", &.{alias}))) continue;
            const target = try key(&f, value, current);
            if (v.nullish(target) or !f.truthy(try f.invoke(target, "startsWith", &.{alias}))) continue;
            const has = try f.get(try f.get(state, "pathSeparators"), "has");
            const boundary = try key(&f, try key(&f, value, current), try f.get(alias, "length"));
            if (!f.truthy(try f.call(has, try f.get(state, "pathSeparators"), &.{boundary}))) continue;
            const left = try key(&f, value, alias);
            const suffix = try f.invoke(try key(&f, value, current), "slice", &.{try f.get(alias, "length")});
            try v.js.setKey(s.engine, value, current, try f.concat(left, suffix));
        }
    }
    const descriptor = try s.object(); try define(s, descriptor, "value", c.pi_js_bool(s.engine.context, 1)); try define(s, descriptor, "enumerable", c.pi_js_bool(s.engine.context, 0));
    _ = try s.invoke(try s.global("Object"), "defineProperty", &.{ value, symbol, descriptor });
    return value;
}
fn normalizeAliasesCall(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); return c.JS_DupValue(engine.context, try aliases(&s, roots[0], arg(args, 0)));
}
fn trailingSlash(s: *Scope, input: c.JSValue) !bool {
    const path = if (c.JS_IsUndefined(input)) try s.text("/") else input;
    const last = try key(s, path, try binary(s, 1, try s.get(path, "length"), number(s, 1)));
    return try same(s, last, "/") or try same(s, last, "\\");
}
fn resolveAliasCall(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const path = try windows(&s, roots[0], arg(args, 0));
    const normalized = try aliases(&s, roots[0], arg(args, 1));
    const entries = try s.invoke(try s.global("Object"), "entries", &.{normalized});
    var iterator = try v.iterator(&s, entries); defer iterator.deinit();
    const generation = engine.native_allocation_generation;
    return resolveAliasLoop(engine, roots[0], path, &iterator) catch |err| return closeAbrupt(engine, &iterator, err, generation);
}
fn resolveAliasLoop(engine: *v.em.Engine, state: c.JSValue, path: c.JSValue, iterator: *v.js.Iterator) !c.JSValue {
    while (try advance(engine, iterator)) |entry| {
        defer engine.freeValue(entry);
        var s: Scope = .{ .engine = engine }; defer s.deinit();
        const pair = try pairExact(engine, entry);
        defer { engine.freeValue(pair[0]); engine.freeValue(pair[1]); }
        const alias = pair[0]; const to = pair[1];
        if (!s.truthy(try s.invoke(path, "startsWith", &.{alias}))) continue;
        const check = if (try trailingSlash(&s, alias)) try s.invoke(alias, "slice", &.{ number(&s, 0), number(&s, -1) }) else alias;
        if (try trailingSlash(&s, try key(&s, path, try s.get(check, "length")))) {
            const suffix = try s.invoke(path, "slice", &.{try s.get(alias, "length")});
            const result = try joined(engine, state, &.{ to, suffix });
            errdefer engine.freeValue(result);
            try closeNormal(engine, &iterator); return result;
        }
    }
    return c.JS_DupValue(engine.context, path);
}
fn pairExact(engine: *v.em.Engine, entry: c.JSValue) ![2]c.JSValue {
    const symbol = try engine.checked(c.JS_GetIteratorSymbol(engine.context)); defer engine.freeValue(symbol);
    var iterator = try v.js.Iterator.init(engine, entry, symbol); defer iterator.deinit();
    const generation = engine.native_allocation_generation;
    const first_value = (advance(engine, &iterator) catch |err| return closeAbrupt(engine, &iterator, err, generation)) orelse c.pi_js_undefined();
    errdefer engine.freeValue(first_value);
    const second_value = if (iterator.closed) c.pi_js_undefined() else (advance(engine, &iterator) catch |err| return closeAbrupt(engine, &iterator, err, generation)) orelse c.pi_js_undefined();
    errdefer engine.freeValue(second_value);
    try closeNormal(engine, &iterator);
    return .{ first_value, second_value };
}

/// Namespace factory only: callers retain one actual instance for imported
/// binding identity. Registration/default selection belongs to composition.
pub fn create(engine: *v.em.Engine) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const state = try s.object();
    inline for (.{ .{ "driveStart", "^[A-Za-z]:/", "" }, .{ "unc", "^[/\\\\]{2}", "" }, .{ "absolute", "^[/\\\\](?![/\\\\])|^[/\\\\]{2}(?!\\.)|^[A-Za-z]:[/\\\\]", "" }, .{ "driveOnly", "^[A-Za-z]:$", "" }, .{ "extension", ".(\\.[^./]+|\\.)$", "" } }) |spec| try define(&s, state, spec[0], try regex(&s, spec[1], spec[2]));
    const result = try s.object();
    const separators = try rest(&s, &.{ try s.text("/"), try s.text("\\"), c.pi_js_undefined() });
    try define(&s, state, "pathSeparators", try s.own(try v.js.builtin(engine, "Set", &.{separators})));
    try define(&s, state, "normalizedAliasSymbol", try s.invoke(try s.global("Symbol"), "for", &.{try s.text("pathe:normalizedAlias")}));
    try define(&s,state,"filenameSlash",try regex(&s,"[/\\\\]",""));
    inline for (.{ .{ "normalize", 1, normalizeCall }, .{ "dirname", 1, dirnameCall }, .{ "basename", 2, basenameCall }, .{ "extname", 1, extnameCall }, .{ "isAbsolute", 1, absoluteCall }, .{ "join", 0, joinCall }, .{ "normalizeAliases", 1, normalizeAliasesCall }, .{ "resolveAlias", 2, resolveAliasCall } }) |spec| try define(&s, result, spec[0], try s.own(try functions.create(engine, spec[0], spec[1], Boundary(spec[2]).call, &.{state})));
    try define(&s,result,"resolve",try s.own(try functions.create(engine,"resolve",0,Boundary(resolveCall).call,&.{state})));
    try define(&s,result,"filename",try s.own(try functions.create(engine,"filename",1,Boundary(filenameCall).call,&.{state})));
    return c.JS_DupValue(engine.context, result);
}

fn returnPrimitive(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue { return c.JS_NewInt32(context, 1); }
test "native jiti pathe abrupt primitive return adds no TypeError allocation" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const engine = try v.em.Engine.init(failing.allocator(), .{}); defer engine.deinit();
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const object = try s.object();
    const method = try s.own(try engine.checked(c.JS_NewCFunction(engine.context, returnPrimitive, "return", 0)));
    try define(&s, object, "return", method);
    const primary = try s.object(); restore(engine, primary);
    var iterator: v.js.Iterator = .{ .engine = engine, .iterator = c.JS_DupValue(engine.context, object), .next_function = c.JS_DupValue(engine.context, method) }; defer iterator.deinit();
    failing.fail_index = failing.alloc_index; failing.resize_fail_index = failing.resize_index;
    const result = closeAbrupt(engine, &iterator, error.JavaScriptException, engine.native_allocation_generation);
    failing.fail_index = std.math.maxInt(usize); failing.resize_fail_index = std.math.maxInt(usize);
    try std.testing.expect(result == error.JavaScriptException);
    try std.testing.expect(!failing.has_induced_failure); try std.testing.expect(iterator.closed);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, primary, engine.captured_exception orelse return error.MissingPathePrimary));
}
test "native jiti pathe local iterator cancellation is uncatchable before advance" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const object = try s.object(); const method = try s.own(try engine.checked(c.JS_NewCFunction(engine.context, returnPrimitive, "next", 0)));
    var iterator: v.js.Iterator = .{ .engine = engine, .iterator = c.JS_DupValue(engine.context, object), .next_function = c.JS_DupValue(engine.context, method) }; defer iterator.deinit();
    engine.cancelled.store(true, .release);
    try std.testing.expectError(error.JavaScriptException, advance(engine, &iterator));
    engine.cancelled.store(false, .release);
    try std.testing.expectEqual(@as(usize, 1), iterator.native_steps); try std.testing.expect(!iterator.closed);
    try std.testing.expect(c.JS_IsUncatchableError(engine.captured_exception orelse return error.MissingPatheCancellation));
}
test "native jiti pathe key enumeration quota is uncatchable and guest lookalikes stay ordinary" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const object = try s.object();
    for (0..300) |index| if (c.JS_DefinePropertyValueUint32(engine.context, object, @intCast(index), c.JS_NewInt32(engine.context, 1), c.JS_PROP_C_W_E) < 0) return v.js.capture(engine);
    const old_budget = engine.options.interrupt_budget; const old_interrupts = engine.interrupts;
    engine.options.interrupt_budget = 0; engine.interrupts = 0;
    try std.testing.expectError(error.JavaScriptException, forIn(&s, object));
    engine.options.interrupt_budget = old_budget; engine.interrupts = old_interrupts;
    try std.testing.expect(c.JS_IsUncatchableError(engine.captured_exception orelse return error.MissingPatheQuota)); restore(engine, null);
    const ordinary = try engine.evalModule("let caught=false;try{const error=Error('interrupted');error.name='InternalError';throw error}catch{caught=true}if(!caught)throw Error('ordinary guest lookalike lost');", "native-jiti-pathe-lookalike.mjs"); engine.freeValue(ordinary);
}

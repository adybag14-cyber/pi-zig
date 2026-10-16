//! Actual generic runWithConcurrency<T>: shared cursor, genuine async workers,
//! live Array.from/Promise.all and ordered sparse results. A failing worker
//! rejects the outer await without replacing or cancelling the other workers.
const data = @import("native_sdk_package_data.zig");
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const body = @import("native_async_body.zig");
const af = body.native;
const f = @import("native_node_function.zig");
const arithmetic = @import("native_image_arithmetic.zig");
pub fn install(engine: *v.em.Engine, prototype: c.JSValue) !void {
    const function = try af.createResumable(engine, "runWithConcurrency", 2, run, &.{});
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "runWithConcurrency", function, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return v.js.capture(engine);
}
fn arg(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
fn run(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) return .{ .thrown = c.JS_DupValue(engine.context, input) };
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    if (completion == .fulfilled) return .{ .returned = c.JS_DupValue(engine.context, try s.get(state.*, "results")) };
    const tasks = arg(args, 0);
    if (s.equal(try s.get(tasks, "length"), c.JS_NewInt32(engine.context, 0))) return .{ .returned = c.JS_DupValue(engine.context, try s.array()) };
    const shared = try body.init(&s, state);
    try data.put(s.engine, shared, "tasks", tasks);
    const array_constructor = try s.global("Array");
    var array_args = [_]c.JSValue{try s.get(tasks, "length")};
    const results = try s.own(try engine.checked(c.JS_CallConstructor(engine.context, array_constructor, 1, &array_args)));
    try data.put(s.engine, shared, "results", results); try data.put(s.engine, shared, "nextIndex", c.JS_NewInt32(engine.context, 0));
    const max_math = try s.global("Math"); const max = try s.get(max_math, "max");
    const min_math = try s.global("Math"); const min = try s.get(min_math, "min");
    const minimum = try s.call(min, min_math, &.{ arg(args, 1), try s.get(tasks, "length") });
    const worker_count = try s.call(max, max_math, &.{ c.JS_NewInt32(engine.context, 1), minimum });
    const worker = try s.own(try af.createResumableArrow(engine, "worker", 0, work, &.{shared}, c.pi_js_undefined()));
    const promise = try s.global("Promise"); const all = try s.get(promise, "all");
    const array = try s.global("Array"); const from = try s.get(array, "from");
    const shape = try s.object(); try data.put(s.engine, shape, "length", worker_count);
    const start = try s.own(try f.createArrow(engine, "", 0, startWorker, &.{worker}));
    const workers = try s.call(from, array, &.{ shape, start });
    return .{ .awaited = c.JS_DupValue(engine.context, try s.call(all, promise, &.{workers})) };
}
fn startWorker(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue { return v.js.call(engine, roots[0], c.pi_js_undefined(), &.{}); }
fn work(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) return .{ .thrown = c.JS_DupValue(engine.context, input) };
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const shared = roots[0];
    const local = if (completion == .start) try body.init(&s, state) else state.*;
    if (completion == .fulfilled) {
        const results = try s.get(shared, "results"); const index = try s.get(local, "index");
        try v.js.setKey(engine, results, index, input);
    }
    const index = try s.get(shared, "nextIndex");
    try s.set(shared, "nextIndex", try s.concat(index, c.JS_NewInt32(engine.context, 1)));
    const tasks = try s.get(shared, "tasks");
    if (try arithmetic.compare(engine, .greater_equal, index, try s.get(tasks, "length"))) return .{ .returned = c.pi_js_undefined() };
    try data.put(s.engine, local, "index", index);
    const callback = try s.own(try v.js.getKey(engine, tasks, index));
    // tasks[index]() is a property call: its receiver is the tasks array.
    return .{ .awaited = c.JS_DupValue(engine.context, try s.call(callback, tasks, &.{})) };
}

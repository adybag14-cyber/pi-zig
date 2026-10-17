//! c268154 portable atomic migrations. Genuine AF/Await and real SQL adapter.
const v = @import("native_ai_provider_values.zig");
const q = @import("native_chord_sqlite_values.zig");
const c = v.c;
const af = q.af;
pub fn create(engine: *v.em.Engine, actual_validate: c.JSValue) !c.JSValue {
    try q.pending(engine);
    return af.createResumable(engine, "applySqliteMigrations", 3, applyBody, &.{actual_validate});
}
fn applyBody(engine: *v.em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var captures = try q.Captures.enter(engine); defer captures.deinit();
    try q.pending(engine);
    const generation = engine.native_allocation_generation;
    return applyInner(engine, receiver, args, roots, state, completion, input) catch |err| q.failure(engine, err, generation);
}
fn applyInner(engine: *v.em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    if (completion != .start) {
        if (completion == .rejected) {
            // Await rejection is DATA: preserve its exact object and hidden
            // flags. Only the outer actual pending/captured event guards act.
            return .{ .thrown = c.JS_DupValue(engine.context, input) };
        }
        return .{ .returned = c.pi_js_undefined() };
    }
    const job = try q.body.init(&s, state);
    const database = q.arg(args, 0);
    const migrations = q.arg(args, 1);
    const table = try q.get(&s, q.arg(args, 2), "table");
    const ignored = try q.success(engine, try v.js.call(engine, roots[0], c.pi_js_undefined(), &.{table}));
    engine.freeValue(ignored);
    var index: f64 = 0;
    var steps: usize = 0;
    while (true) : (index += 1) {
        var iteration: v.Scope = .{ .engine = engine }; defer iteration.deinit();
        if (!iteration.truthy(try q.binary(&iteration, 4, c.JS_NewFloat64(engine.context, index), try q.get(&iteration, migrations, "length")))) break;
        steps +|= 1; try @import("native_jiti_budget.zig").check(engine, steps);
        const migration = try q.key(&iteration, migrations, c.JS_NewFloat64(engine.context, index));
        const version = if (v.nullish(migration)) c.pi_js_undefined() else try q.get(&iteration, migration, "version");
        if (!c.JS_IsStrictEqual(engine.context, version, c.JS_NewFloat64(engine.context, index + 1))) return q.errorText(&iteration, try iteration.text("SQLite migrations must have contiguous versions starting at 1"));
    }
    // Resolve transaction BEFORE creating the Source async arrow argument.
    const transaction = try q.get(&s, database, "transaction");
    const callback = try s.own(try af.createResumableArrow(engine, "", 1, transactionBody, &.{ migrations, table }, receiver));
    const result = try q.call(&s, transaction, database, &.{callback});
    return q.wait(&s, job, 1, result);
}
fn openIterator(s: *v.Scope, job: c.JSValue, comptime name: []const u8, iterable: c.JSValue) !void {
    // Do not leave extra iterator/next roots in the caller Scope. In particular
    // an empty statements iterator retires before UPDATE in this SAME body.
    var step: v.Scope = .{ .engine = s.engine }; defer step.deinit();
    const symbol = try step.own(try s.engine.checked(c.JS_GetIteratorSymbol(s.engine.context)));
    const function = try q.key(&step, iterable, symbol);
    const iterator = try q.call(&step, function, iterable, &.{});
    if (!c.JS_IsObject(iterator)) return v.js.typeError(s.engine, "Iterator is not an object");
    const next_function = try q.get(&step, iterator, "next");
    try q.put(s.engine, job, name ++ "Iterator", iterator);
    try q.put(s.engine, job, name ++ "Next", next_function);
    try q.put(s.engine, job, name ++ "Open", c.pi_js_bool(s.engine.context, 1));
    try q.put(s.engine, job, name ++ "Steps", c.JS_NewInt32(s.engine.context, 0));
}
fn next(s: *v.Scope, job: c.JSValue, comptime name: []const u8) !?c.JSValue {
    // IteratorRecord, step and done/value temporaries retire BEFORE a later
    // SQL callback. Only the yielded value enters the caller's lexical scope.
    var step: v.Scope = .{ .engine = s.engine }; defer step.deinit();
    var steps: u64 = 0;
    if (c.JS_ToIndex(s.engine.context, &steps, try q.get(&step, job, name ++ "Steps")) < 0) return v.js.capture(s.engine);
    steps +|= 1; try @import("native_jiti_budget.zig").check(s.engine, @intCast(steps));
    try q.put(s.engine, job, name ++ "Steps", c.JS_NewFloat64(s.engine.context, @floatFromInt(steps)));
    // IteratorStep/value failures do not gain an invented IteratorClose call.
    try q.put(s.engine, job, name ++ "Open", c.pi_js_bool(s.engine.context, 0));
    const iterator = try q.get(&step, job, name ++ "Iterator");
    const result = try q.call(&step, try q.get(&step, job, name ++ "Next"), iterator, &.{});
    if (!c.JS_IsObject(result)) return v.js.typeError(s.engine, "Iterator result is not an object");
    if (step.truthy(try q.get(&step, result, "done"))) {
        try retire(s.engine, job, name);
        return null;
    }
    const value = try q.get(&step, result, "value");
    try q.put(s.engine, job, name ++ "Open", c.pi_js_bool(s.engine.context, 1));
    return s.own(c.JS_DupValue(s.engine.context, value));
}
fn retire(engine: *v.em.Engine, job: c.JSValue, comptime name: []const u8) !void {
    try q.put(engine, job, name ++ "Open", c.pi_js_bool(engine.context, 0));
    try q.put(engine, job, name ++ "Iterator", c.pi_js_undefined());
    try q.put(engine, job, name ++ "Next", c.pi_js_undefined());
}
fn closeOne(s: *v.Scope, job: c.JSValue, comptime name: []const u8) !void {
    var step: v.Scope = .{ .engine = s.engine }; defer step.deinit();
    if (!step.truthy(try q.get(&step, job, name ++ "Open"))) return retire(s.engine, job, name);
    try q.put(s.engine, job, name ++ "Open", c.pi_js_bool(s.engine.context, 0));
    const iterator = try q.get(&step, job, name ++ "Iterator");
    const function = try q.get(&step, iterator, "return");
    if (v.nullish(function)) return retire(s.engine, job, name);
    const result = try q.call(&step, function, iterator, &.{});
    if (!c.JS_IsObject(result)) return v.js.typeError(s.engine, "Iterator return result is not an object");
    try retire(s.engine, job, name);
}
fn closeAbrupt(s: *v.Scope, job: c.JSValue) !void {
    if (!c.JS_IsObject(job)) return;
    inline for (.{ "statement", "migration" }) |name| {
        const generation = s.engine.native_allocation_generation;
        closeOne(s, job, name) catch |err| {
            const ordinary = try q.take(s.engine, err, generation);
            defer s.engine.freeValue(ordinary); // Source throw completion wins ordinary close error.
            try retire(s.engine, job, name);
        };
    }
}
fn transactionBody(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var captures = try q.Captures.enter(engine); defer captures.deinit();
    try q.pending(engine);
    const generation = engine.native_allocation_generation;
    return transactionInner(engine, args, roots, state, completion, input) catch |err| {
        const ordinary = try q.take(engine, err, generation);
        defer engine.freeValue(ordinary);
        var s: v.Scope = .{ .engine = engine }; defer s.deinit();
        try closeAbrupt(&s, state.*);
        return .{ .thrown = c.JS_DupValue(engine.context, ordinary) };
    };
}
fn sql(s: *v.Scope, before: []const u8, table: c.JSValue, after: []const u8) !c.JSValue {
    const head = try q.binary(s, 0, try s.text(before), try q.text(s, table));
    return q.binary(s, 0, head, try s.text(after));
}
fn execute(s: *v.Scope, job: c.JSValue, name: [*:0]const u8, before: []const u8, after: []const u8, next_stage: i32) !af.Action {
    const transaction = try q.get(s, job, "transaction");
    const function = try q.get(s, transaction, name);
    const statement = try sql(s, before, try q.get(s, job, "table"), after);
    return q.wait(s, job, next_stage, try q.call(s, function, transaction, &.{statement}));
}
fn transactionInner(engine: *v.em.Engine, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    if (completion == .start) {
        const job = try q.body.init(&s, state);
        try q.put(engine, job, "transaction", q.arg(args, 0));
        try q.put(engine, job, "migrations", roots[0]);
        try q.put(engine, job, "table", roots[1]);
        return execute(&s, job, "exec", "CREATE TABLE IF NOT EXISTS ", " (\n\t\t\tsingleton INTEGER PRIMARY KEY CHECK (singleton = 1),\n\t\t\tversion INTEGER NOT NULL CHECK (version >= 0)\n\t\t) STRICT", 1);
    }
    const job = state.*;
    if (completion == .rejected) {
        // Preserve rejected DATA unchanged, including any historical bit/tag.
        try closeAbrupt(&s, job);
        return .{ .thrown = c.JS_DupValue(engine.context, input) };
    }
    switch (try q.stage(&s, job)) {
        1 => return execute(&s, job, "run", "INSERT OR IGNORE INTO ", " (singleton, version) VALUES (1, 0)", 2),
        2 => return execute(&s, job, "get", "SELECT version FROM ", " WHERE singleton = 1", 3),
        3 => {
            if (c.JS_IsUndefined(input)) return q.errorText(&s, try s.text("SQLite schema metadata is missing"));
            try q.put(engine, job, "row", input);
            const migrations = try q.get(&s, job, "migrations");
            const last = try q.invoke(&s, migrations, "at", &.{c.JS_NewInt32(engine.context, -1)});
            const last_version = if (v.nullish(last)) c.pi_js_undefined() else try q.get(&s, last, "version");
            const current = if (v.nullish(last_version)) c.JS_NewInt32(engine.context, 0) else last_version;
            if (s.truthy(try q.binary(&s, 6, try q.get(&s, input, "version"), current))) {
                // Error constructor is resolved before template argument getters.
                const constructor = try s.own(try q.success(engine, try v.js.global(engine, "Error")));
                const head = try q.binary(&s, 0, try s.text("SQLite schema version "), try q.text(&s, try q.get(&s, input, "version")));
                const middle = try q.binary(&s, 0, head, try s.text(" is newer than supported version "));
                const message = try q.binary(&s, 0, middle, try q.text(&s, current));
                var error_args = [_]c.JSValue{message};
                const reason = try s.own(try q.success(engine, try engine.checked(c.JS_CallConstructor(engine.context, constructor, 1, &error_args))));
                _ = try engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason)));
                unreachable;
            }
            try openIterator(&s, job, "migration", migrations);
            return nextMigration(&s, job);
        },
        4 => return nextStatement(&s, job),
        5 => return nextMigration(&s, job),
        else => return error.InvalidPortableMigrationStage,
    }
}
fn nextMigration(s: *v.Scope, job: c.JSValue) !af.Action {
    try q.put(s.engine, job, "migration", c.pi_js_undefined());
    while (true) {
        var iteration: v.Scope = .{ .engine = s.engine }; defer iteration.deinit();
        const migration = (try next(&iteration, job, "migration")) orelse break;
        const version = try q.get(&iteration, migration, "version");
        if (iteration.truthy(try q.binary(&iteration, 5, version, try q.get(&iteration, try q.get(&iteration, job, "row"), "version")))) continue;
        try q.put(s.engine, job, "migration", migration);
        try openIterator(s, job, "statement", try q.get(s, migration, "statements"));
        return nextStatement(s, job);
    }
    return .{ .returned = c.pi_js_undefined() };
}
fn nextStatement(s: *v.Scope, job: c.JSValue) !af.Action {
    const transaction = try q.get(s, job, "transaction");
    if (try next(s, job, "statement")) |statement| {
        const function = try q.get(s, transaction, "exec");
        return q.wait(s, job, 4, try q.call(s, function, transaction, &.{statement}));
    }
    const function = try q.get(s, transaction, "run");
    const statement = try sql(s, "UPDATE ", try q.get(s, job, "table"), " SET version = ? WHERE singleton = 1");
    const version = try q.get(s, try q.get(s, job, "migration"), "version");
    return q.wait(s, job, 5, try q.call(s, function, transaction, &.{ statement, version }));
}

//! Complete private ProjectTrustStore from pinned trust-manager.ts.
//! Required inputs are genuine imported owners. This class preserves ordinary
//! fields/methods, live Error/JSON/Object/Date operations, and Source lock/finally
//! ordering. The supplier does not publish an incomplete trust module or policy.
const h = @import("native_sdk_session_locals.zig");
const v = h.v;
const c = h.c;
const Engine = h.Engine;
const Scope = h.Scope;
const caught = @import("native_agent_af_values.zig").caught;
const native_class = @import("native_class.zig");

pub const Inputs = struct {
    filesystem: c.JSValue,
    paths: c.JSValue,
    path_utilities: c.JSValue,
    text_utilities: c.JSValue,
    lockfile: c.JSValue,
};
const input_names = .{ "filesystem", "paths", "path_utilities", "text_utilities", "lockfile" };
const cache_key = "pi-private:actual-sdk-project-trust-store";
const Creating = struct { engine: *Engine, previous: ?*Creating };
threadlocal var creating: ?*Creating = null;

pub fn create(engine: *Engine, inputs: Inputs) anyerror!c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(cache_key)) |cached|
        return h.expression(engine, cachedBody, .{ cached, inputs });
    var cursor = creating;
    while (cursor) |current| : (cursor = current.previous)
        if (current.engine == engine) return error.ActualProjectTrustStoreCreationReentry;
    var entry: Creating = .{ .engine = engine, .previous = creating };
    creating = &entry;
    defer creating = entry.previous;
    var invocation: Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&invocation);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const result = createOwned(engine, inputs) catch |err|
        return engine.checked(engine.leaveNativeInvocation(&invocation,
            @import("native_sdk.zig").fail(engine, err)));
    return engine.checked(engine.leaveNativeInvocation(&invocation, result));
}
fn cachedBody(s: *Scope, cached: c.JSValue, inputs: Inputs) anyerror!c.JSValue {
    inline for (input_names) |name|
        if (!v.equal(s, try v.get(s, cached, name), @field(inputs, name)))
            return error.ActualProjectTrustStoreImportsChanged;
    return v.duplicate(s, try v.get(s, cached, "constructor"));
}
fn createOwned(engine: *Engine, inputs: Inputs) anyerror!c.JSValue {
    const graph = try h.expression(engine, createBody, .{inputs});
    const constructor_value = h.get(engine, graph, "constructor") catch |err| {
        var failure = v.owned.Completion.initValue(engine, err);
        failure.release(graph);
        return failure.finishValue();
    };
    engine.native_module_values.ensureUnusedCapacity(engine.gpa, 1) catch |err| {
        var failure = v.owned.Completion.initValue(engine, err);
        failure.release(constructor_value);
        failure.release(graph);
        return failure.finishValue();
    };
    engine.native_module_values.putAssumeCapacity(cache_key, graph);
    return constructor_value;
}
fn required(s: *Scope, owner: c.JSValue, name: [*:0]const u8) anyerror!c.JSValue {
    const value = try v.get(s, owner, name);
    if (!c.JS_IsFunction(s.engine.context, value)) return error.ActualProjectTrustStoreImportRequired;
    return value;
}
fn createBody(s: *Scope, inputs: Inputs) anyerror!c.JSValue {
    // Every module borrow is rooted before the first potentially reentrant Get.
    inline for (input_names) |name| _ = try v.own(s, v.duplicate(s, @field(inputs, name)));
    const exists_sync = try required(s, inputs.filesystem, "existsSync");
    const mkdir_sync = try required(s, inputs.filesystem, "mkdirSync");
    const read_sync = try required(s, inputs.filesystem, "readFileSync");
    const write_sync = try required(s, inputs.filesystem, "writeFileSync");
    const dirname = try required(s, inputs.paths, "dirname");
    const join = try required(s, inputs.paths, "join");
    const canonicalize = try required(s, inputs.path_utilities, "canonicalizePath");
    const resolve_path = try required(s, inputs.path_utilities, "resolvePath");
    const strip_bom = try required(s, inputs.text_utilities, "stripBom");
    // A default-import object stays live: lockSync itself is read per attempt.
    const normalize = try v.ordinary(s, "normalizeCwd", 1, normalizeCall, &.{ canonicalize, resolve_path });
    const constructor_value = try fromCaptures(s, .{
        .exists_sync = exists_sync, .mkdir_sync = mkdir_sync, .read_sync = read_sync,
        .write_sync = write_sync, .dirname = dirname, .join = join,
        .resolve_path = resolve_path, .strip_bom = strip_bom,
        .lockfile = inputs.lockfile, .normalize = normalize,
    });
    const graph = try v.stateObject(s);
    inline for (input_names) |name| try v.put(s, graph, name, @field(inputs, name));
    try v.put(s, graph, "constructor", constructor_value);
    return v.duplicate(s, graph);
}
/// Actual captured imports and the one shared normalizeCwd closure supplied
/// by the complete trust-manager evaluation. Every value is already rooted in s.
pub const Captures = struct {
    exists_sync: c.JSValue, mkdir_sync: c.JSValue, read_sync: c.JSValue,
    write_sync: c.JSValue, dirname: c.JSValue, join: c.JSValue,
    resolve_path: c.JSValue, strip_bom: c.JSValue,
    lockfile: c.JSValue, normalize: c.JSValue,
};
/// Returns a borrowed complete ordinary class constructor rooted in s.
pub fn fromCaptures(s: *Scope, imports: Captures) anyerror!c.JSValue {
    try s.engine.checkNativeEntry();
    const exists_sync = imports.exists_sync;
    const mkdir_sync = imports.mkdir_sync;
    const read_sync = imports.read_sync;
    const write_sync = imports.write_sync;
    const dirname = imports.dirname;
    const join = imports.join;
    const resolve_path = imports.resolve_path;
    const strip_bom = imports.strip_bom;
    const normalize = imports.normalize;
    const nearest = try v.ordinary(s, "findNearestTrustEntry", 2, nearestCall, &.{ normalize, dirname });
    const read_file = try v.ordinary(s, "readTrustFile", 1, readCall, &.{ exists_sync, read_sync, strip_bom });
    const write_file = try v.ordinary(s, "writeTrustFile", 2, writeCall, &.{ dirname, mkdir_sync, write_sync });
    const acquire = try v.ordinary(s, "acquireTrustLockSync", 1, acquireCall, &.{ dirname, mkdir_sync, imports.lockfile });
    const with_lock = try v.ordinary(s, "withTrustFileLock", 2, withLockCall, &.{acquire});
    const prototype = try v.object(s);
    var constructor_boundary: v.guest.Boundary = .{ .engine = s.engine };
    try constructor_boundary.begin();
    const constructor_value = try constructor_boundary.finishValue(s,
        native_class.constructor(s.engine, "ProjectTrustStore", 1, prototype,
            constructCall, &.{ join, resolve_path }));
    try defineMethod(s, prototype, "get", 1, getCall, &.{});
    try defineMethod(s, prototype, "getEntry", 1, getEntryCall, &.{ with_lock, read_file, nearest });
    try defineMethod(s, prototype, "set", 2, setCall, &.{});
    try defineMethod(s, prototype, "setMany", 1, setManyCall, &.{ with_lock, read_file, normalize, write_file });
    return constructor_value;
}
fn defineMethod(s: *Scope, prototype: c.JSValue, name: [:0]const u8, length: c_int,
    callback: v.function.Callback, roots: []const c.JSValue) anyerror!void
{
    const method = try v.method(s, name.ptr, length, callback, roots);
    var boundary: v.guest.Boundary = .{ .engine = s.engine };
    try boundary.begin();
    return boundary.finishStatus(c.JS_DefinePropertyValueStr(s.engine.context, prototype,
        name.ptr, v.duplicate(s, method), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE));
}
fn callOwned(engine: *Engine, function_value: c.JSValue, args: []const c.JSValue) anyerror!c.JSValue {
    return h.expression(engine, callBody, .{ function_value, args });
}
fn callBody(s: *Scope, function_value: c.JSValue, args: []const c.JSValue) anyerror!c.JSValue {
    return v.duplicate(s, try v.call(s, function_value, c.pi_js_undefined(), args));
}
fn callStatement(s: *Scope, function_value: c.JSValue, args: []const c.JSValue) anyerror!void {
    _ = try v.call(s, function_value, c.pi_js_undefined(), args);
}
fn raise(s: *Scope, reason: c.JSValue) anyerror {
    _ = s.engine.checked(c.JS_Throw(s.engine.context, v.duplicate(s, reason))) catch |err| return err;
    unreachable;
}
fn typeofObject(value: c.JSValue, engine: *Engine) bool {
    return c.JS_IsObject(value) and !c.JS_IsFunction(engine.context, value);
}
fn decision(value: c.JSValue) bool { return c.JS_IsBool(value) or c.JS_IsNull(value); }
fn keyAtom(s: *Scope, property: c.JSValue) anyerror!c.JSAtom {
    var boundary: v.guest.Boundary = .{ .engine = s.engine };
    try boundary.begin();
    const atom = c.JS_ValueToAtom(s.engine.context, property);
    boundary.finishStatus(if (atom == c.JS_ATOM_NULL) -1 else 0) catch |err| {
        if (atom != c.JS_ATOM_NULL) c.JS_FreeAtom(s.engine.context, atom);
        return err;
    };
    return atom;
}
fn assignKey(s: *Scope, target: c.JSValue, property: c.JSValue, value: c.JSValue) anyerror!void {
    const atom = try keyAtom(s, property);
    defer c.JS_FreeAtom(s.engine.context, atom);
    var boundary: v.guest.Boundary = .{ .engine = s.engine };
    try boundary.begin();
    return boundary.finishStatus(c.JS_SetProperty(s.engine.context, target, atom, v.duplicate(s, value)));
}
fn deleteKey(s: *Scope, target: c.JSValue, property: c.JSValue) anyerror!void {
    const atom = try keyAtom(s, property);
    defer c.JS_FreeAtom(s.engine.context, atom);
    var boundary: v.guest.Boundary = .{ .engine = s.engine };
    try boundary.begin();
    return boundary.finishStatus(c.JS_DeleteProperty(s.engine.context, target, atom, c.JS_PROP_THROW));
}
fn isError(s: *Scope, reason: c.JSValue) anyerror!bool {
    const constructor_value = try v.global(s, "Error");
    var boundary: v.guest.Boundary = .{ .engine = s.engine };
    try boundary.begin();
    const result = c.JS_IsInstanceOf(s.engine.context, reason, constructor_value);
    try boundary.finishStatus(result);
    return result != 0;
}
fn messageBody(s: *Scope, reason: c.JSValue) anyerror!c.JSValue {
    if (try isError(s, reason)) return v.duplicate(s, try v.get(s, reason, "message"));
    return v.duplicate(s, try v.call(s, try v.global(s, "String"), c.pi_js_undefined(), &.{reason}));
}
fn append(s: *Scope, left: c.JSValue, right: c.JSValue) anyerror!c.JSValue {
    return v.binary(s, 0, left, right);
}
fn pathPrefix(s: *Scope, prefix: []const u8, path_value: c.JSValue) anyerror!c.JSValue {
    return append(s, try v.text(s, prefix), try v.stringify(s, path_value));
}
const ErrorKind = enum { read, object, value, acquire };
fn errorBody(s: *Scope, path_value: c.JSValue, detail: c.JSValue, kind: ErrorKind) anyerror!c.JSValue {
    // Source evaluates the live Error callee before any template substitution.
    const constructor_value = try v.global(s, "Error");
    var text_value = if (kind == .acquire) try v.text(s, "Failed to acquire trust store lock")
        else try pathPrefix(s, if (kind == .read) "Failed to read trust store " else "Invalid trust store ", path_value);
    switch (kind) {
        .read => {
            text_value = try append(s, text_value, try v.text(s, ": "));
            text_value = try append(s, text_value, try v.stringify(s, detail));
        },
        .object => text_value = try append(s, text_value, try v.text(s, ": expected an object")),
        .value => {
            text_value = try append(s, text_value, try v.text(s, ": value for "));
            const json = try v.global(s, "JSON");
            const rendered = try v.invoke(s, json, "stringify", &.{detail});
            text_value = try append(s, text_value, try v.stringify(s, rendered));
            text_value = try append(s, text_value, try v.text(s, " must be true, false, or null"));
        },
        .acquire => {},
    }
    return raise(s, try v.construct(s, constructor_value, &.{text_value}));
}

fn constructCall(engine: *Engine, target: c.JSValue, args: []const c.JSValue,
    roots: []const c.JSValue) anyerror!c.JSValue
{
    return h.expression(engine, constructBody, .{ target, v.arg(args, 0), roots });
}
fn constructBody(s: *Scope, target: c.JSValue, agent_dir: c.JSValue,
    roots: []const c.JSValue) anyerror!c.JSValue
{
    var boundary: v.guest.Boundary = .{ .engine = s.engine };
    try boundary.begin();
    const receiver = try boundary.finishValue(s, native_class.object(s.engine, target));
    // TypeScript's ordinary class field declaration precedes its assignment.
    try v.put(s, receiver, "trustPath", c.pi_js_undefined());
    const resolved = try v.call(s, roots[1], c.pi_js_undefined(), &.{agent_dir});
    const path_value = try v.call(s, roots[0], c.pi_js_undefined(), &.{ resolved, try v.text(s, "trust.json") });
    try v.set(s, receiver, "trustPath", path_value);
    return v.duplicate(s, receiver);
}
fn normalizeCall(engine: *Engine, _: c.JSValue, args: []const c.JSValue,
    roots: []const c.JSValue) anyerror!c.JSValue
{
    return h.expression(engine, normalizeBody, .{ v.arg(args, 0), roots });
}
fn normalizeBody(s: *Scope, cwd: c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    const path_value = try v.call(s, roots[1], c.pi_js_undefined(), &.{cwd});
    return v.duplicate(s, try v.call(s, roots[0], c.pi_js_undefined(), &.{path_value}));
}
const NearestFrame = h.Frame(enum { current_dir, value, parent_dir });
fn nearestCall(engine: *Engine, _: c.JSValue, args: []const c.JSValue,
    roots: []const c.JSValue) anyerror!c.JSValue
{
    var frame = NearestFrame.init(engine);
    return frame.finish(nearestBody(&frame, v.arg(args, 0), v.arg(args, 1), roots));
}
fn nearestBody(frame: *NearestFrame, data: c.JSValue, cwd: c.JSValue,
    roots: []const c.JSValue) anyerror!c.JSValue
{
    try frame.set(.current_dir, callOwned(frame.engine, roots[0], &.{cwd}));
    var steps: usize = 0;
    while (true) {
        try v.poll(frame.engine, &steps);
        try frame.clear(.value);
        try frame.clear(.parent_dir);
        try frame.set(.value, h.key(frame.engine, data, frame.get(.current_dir)));
        if (c.JS_IsBool(frame.get(.value)))
            return h.expression(frame.engine, entryBody, .{ frame.get(.current_dir), frame.get(.value) });
        try frame.set(.parent_dir, callOwned(frame.engine, roots[1], &.{frame.get(.current_dir)}));
        if (c.JS_IsStrictEqual(frame.engine.context, frame.get(.parent_dir), frame.get(.current_dir)))
            return c.pi_js_null();
        try frame.set(.current_dir, h.duplicate(frame.engine, frame.get(.parent_dir)));
    }
}
fn entryBody(s: *Scope, path_value: c.JSValue, value: c.JSValue) anyerror!c.JSValue {
    const row = try v.object(s);
    try v.put(s, row, "path", path_value);
    try v.put(s, row, "decision", value);
    return v.duplicate(s, row);
}

const ReadFrame = h.Frame(enum { parsed, data, key, value });
const ReadCatchFrame = h.Frame(enum { reason, message });
fn readCall(engine: *Engine, _: c.JSValue, args: []const c.JSValue,
    roots: []const c.JSValue) anyerror!c.JSValue
{
    var frame = ReadFrame.init(engine);
    return frame.finish(readBody(&frame, v.arg(args, 0), roots));
}
fn callTruthyBody(s: *Scope, function_value: c.JSValue, args: []const c.JSValue) anyerror!c.JSValue {
    return v.boolean(s, v.truthy(s, try v.call(s, function_value, c.pi_js_undefined(), args)));
}
fn emptyObjectBody(s: *Scope) anyerror!c.JSValue { return v.duplicate(s, try v.object(s)); }
fn parseBody(s: *Scope, path_value: c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    // Callee evaluation JSON.parse precedes stripBom(readFileSync(...)).
    const json = try v.global(s, "JSON");
    const parse_function = try v.get(s, json, "parse");
    const text_value = try v.call(s, roots[1], c.pi_js_undefined(), &.{ path_value, try v.text(s, "utf-8") });
    const stripped = try v.call(s, roots[2], c.pi_js_undefined(), &.{text_value});
    return v.duplicate(s, try v.call(s, parse_function, json, &.{stripped}));
}
fn readCaught(engine: *Engine, path_value: c.JSValue, err: anyerror) anyerror!c.JSValue {
    var frame = ReadCatchFrame.init(engine);
    return frame.finish(readCaughtBody(&frame, path_value, err));
}
fn readCaughtBody(frame: *ReadCatchFrame, path_value: c.JSValue, err: anyerror) anyerror!c.JSValue {
    try frame.set(.reason, caught(frame.engine, err));
    try frame.set(.message, h.expression(frame.engine, messageBody, .{frame.get(.reason)}));
    return h.expression(frame.engine, errorBody, .{ path_value, frame.get(.message), ErrorKind.read });
}
fn isArrayBody(s: *Scope, value: c.JSValue) anyerror!c.JSValue {
    return v.boolean(s, v.truthy(s, try v.invoke(s, try v.global(s, "Array"), "isArray", &.{value})));
}
fn entriesBody(s: *Scope, value: c.JSValue) anyerror!c.JSValue {
    return v.duplicate(s, try v.invoke(s, try v.global(s, "Object"), "entries", &.{value}));
}
fn readBody(frame: *ReadFrame, path_value: c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    const engine = frame.engine;
    if (!h.truthy(engine, try h.expression(engine, callTruthyBody, .{ roots[0], @as([]const c.JSValue, &.{path_value}) })))
        return h.expression(engine, emptyObjectBody, .{});
    // Only parse/strip/read belongs to the original catch. exists, validation,
    // enumeration and assignments retain their own ordinary abrupt completions.
    const parsed = h.expression(engine, parseBody, .{ path_value, roots }) catch |err|
        return readCaught(engine, path_value, err);
    try frame.set(.parsed, parsed);
    if (!typeofObject(frame.get(.parsed), engine) or
        h.truthy(engine, try h.expression(engine, isArrayBody, .{frame.get(.parsed)})))
        return h.expression(engine, errorBody, .{ path_value, c.pi_js_undefined(), ErrorKind.object });
    try frame.set(.data, h.expression(engine, emptyObjectBody, .{}));
    var iterator = try v.Iterator.initOwned(engine, try h.expression(engine, entriesBody, .{frame.get(.parsed)}));
    try iterator.finish(readEntries(frame, &iterator, path_value));
    return h.duplicate(engine, frame.get(.data));
}
fn readEntries(frame: *ReadFrame, iterator: *v.Iterator, path_value: c.JSValue) anyerror!void {
    while (try iterator.next()) |row| {
        // Array binding uses its actual iterator, including early normal close.
        var pair = try v.Iterator.initOwned(frame.engine, row);
        try pair.finish(bindPair(frame, &pair));
        try h.statement(frame.engine, validateEntryBody,
            .{ path_value, frame.get(.data), frame.get(.key), frame.get(.value) });
    }
}
fn bindPair(frame: *ReadFrame, pair: *v.Iterator) anyerror!void {
    try frame.set(.key, (try pair.next()) orelse c.pi_js_undefined());
    try frame.set(.value, if (pair.closed) c.pi_js_undefined() else
        (try pair.next()) orelse c.pi_js_undefined());
    return closeNormal(pair);
}
fn closeNormal(iterator: *v.Iterator) anyerror!void {
    if (iterator.closed) return;
    iterator.closed = true;
    // As in bytecode IteratorClose, retire the cached next before return lookup.
    const next_function = iterator.next_function;
    iterator.next_function = c.pi_js_undefined();
    var completion = v.owned.Completion.initVoid(iterator.engine, {});
    completion.release(next_function);
    try completion.finishVoid();
    return h.statement(iterator.engine, closeNormalBody, .{iterator.receiver});
}
fn closeNormalBody(s: *Scope, receiver: c.JSValue) anyerror!void {
    const method = try v.get(s, receiver, "return");
    if (v.nullish(method)) return;
    const result = try v.call(s, method, receiver, &.{});
    if (!c.JS_IsObject(result)) return v.typeError(s, "iterator must return an object");
}
fn validateEntryBody(s: *Scope, path_value: c.JSValue, data: c.JSValue,
    key: c.JSValue, value: c.JSValue) anyerror!void
{
    if (!decision(value)) {
        _ = try errorBody(s, path_value, key, .value);
        unreachable;
    }
    // Source assignment deliberately preserves inherited __proto__ semantics.
    return assignKey(s, data, key, value);
}

const WriteFrame = h.Frame(enum { sorted, key, value });
fn writeCall(engine: *Engine, _: c.JSValue, args: []const c.JSValue,
    roots: []const c.JSValue) anyerror!c.JSValue
{
    var frame = WriteFrame.init(engine);
    return frame.finish(writeBody(&frame, v.arg(args, 0), v.arg(args, 1), roots));
}
fn keysBody(s: *Scope, data: c.JSValue) anyerror!c.JSValue {
    const keys = try v.invoke(s, try v.global(s, "Object"), "keys", &.{data});
    return v.duplicate(s, try v.invoke(s, keys, "sort", &.{}));
}
fn writeBody(frame: *WriteFrame, path_value: c.JSValue, data: c.JSValue,
    roots: []const c.JSValue) anyerror!c.JSValue
{
    try frame.set(.sorted, h.expression(frame.engine, emptyObjectBody, .{}));
    var iterator = try v.Iterator.initOwned(frame.engine, try h.expression(frame.engine, keysBody, .{data}));
    try iterator.finish(writeEntries(frame, &iterator, data));
    try h.statement(frame.engine, mkdirPathBody, .{ path_value, roots[0], roots[1] });
    try h.statement(frame.engine, persistBody, .{ path_value, frame.get(.sorted), roots[2] });
    return c.pi_js_undefined();
}
fn writeEntries(frame: *WriteFrame, iterator: *v.Iterator, data: c.JSValue) anyerror!void {
    while (try iterator.next()) |key| {
        try frame.set(.key, key);
        // The new for-of head is assigned before resetting its body local.
        try frame.clear(.value);
        try frame.set(.value, h.key(frame.engine, data, frame.get(.key)));
        if (decision(frame.get(.value)))
            try h.statement(frame.engine, assignKey, .{ frame.get(.sorted), frame.get(.key), frame.get(.value) });
    }
}
fn mkdirBody(s: *Scope, dir: c.JSValue, mkdir_sync: c.JSValue) anyerror!void {
    const options = try v.object(s);
    try v.put(s, options, "recursive", v.boolean(s, true));
    _ = try v.call(s, mkdir_sync, c.pi_js_undefined(), &.{ dir, options });
}
fn mkdirPathBody(s: *Scope, path_value: c.JSValue, dirname: c.JSValue,
    mkdir_sync: c.JSValue) anyerror!void
{
    const dir = try v.call(s, dirname, c.pi_js_undefined(), &.{path_value});
    return mkdirBody(s, dir, mkdir_sync);
}
fn persistBody(s: *Scope, path_value: c.JSValue, sorted: c.JSValue,
    write_sync: c.JSValue) anyerror!void
{
    const json = try v.global(s, "JSON");
    const rendered = try v.invoke(s, json, "stringify", &.{ sorted, c.pi_js_null(), v.number(s, 2) });
    const text_value = try append(s, try v.stringify(s, rendered), try v.text(s, "\n"));
    _ = try v.call(s, write_sync, c.pi_js_undefined(), &.{ path_value, text_value, try v.text(s, "utf-8") });
}

const AcquireFrame = h.Frame(enum { trust_dir, last_error, reason, code, start });
fn acquireCall(engine: *Engine, _: c.JSValue, args: []const c.JSValue,
    roots: []const c.JSValue) anyerror!c.JSValue
{
    var frame = AcquireFrame.init(engine);
    return frame.finish(acquireBody(&frame, v.arg(args, 0), roots));
}
fn acquireBody(frame: *AcquireFrame, path_value: c.JSValue,
    roots: []const c.JSValue) anyerror!c.JSValue
{
    const engine = frame.engine;
    try frame.set(.trust_dir, callOwned(engine, roots[0], &.{path_value}));
    try h.statement(engine, mkdirBody, .{ frame.get(.trust_dir), roots[1] });
    var attempt: usize = 1;
    var steps: usize = 0;
    while (attempt <= 10) : (attempt += 1) {
        try v.poll(engine, &steps);
        const result = h.expression(engine, lockAttemptBody,
            .{ path_value, frame.get(.trust_dir), roots[2] }) catch |err|
        {
            // An actual fatal event bypasses catch and all subsequent guest work.
            try frame.set(.reason, caught(engine, err));
            try frame.clear(.code);
            try frame.clear(.start);
            try frame.set(.code, h.expression(engine, retryCodeBody, .{frame.get(.reason)}));
            if (!(try codeLocked(engine, frame.get(.code))) or attempt == 10)
                return h.expression(engine, throwBody, .{frame.get(.reason)});
            try frame.set(.last_error, h.duplicate(engine, frame.get(.reason)));
            try frame.set(.start, h.expression(engine, dateNowBody, .{}));
            while (h.truthy(engine, try h.expression(engine, waitBody, .{frame.get(.start)})))
                try v.poll(engine, &steps);
            continue;
        };
        return result;
    }
    if (h.truthy(engine, try h.expression(engine, isErrorBody, .{frame.get(.last_error)})))
        return h.expression(engine, throwBody, .{frame.get(.last_error)});
    return h.expression(engine, errorBody, .{ path_value, c.pi_js_undefined(), ErrorKind.acquire });
}
fn lockAttemptBody(s: *Scope, path_value: c.JSValue, trust_dir: c.JSValue,
    lockfile: c.JSValue) anyerror!c.JSValue
{
    const lock_sync = try v.get(s, lockfile, "lockSync");
    const options = try v.object(s);
    try v.put(s, options, "realpath", v.boolean(s, false));
    const lock_path = try append(s, try v.stringify(s, path_value), try v.text(s, ".lock"));
    try v.put(s, options, "lockfilePath", lock_path);
    return v.duplicate(s, try v.call(s, lock_sync, lockfile, &.{ trust_dir, options }));
}
fn retryCodeBody(s: *Scope, reason: c.JSValue) anyerror!c.JSValue {
    if (!typeofObject(reason, s.engine)) return c.pi_js_undefined();
    const atom = try keyAtom(s, try v.text(s, "code"));
    defer c.JS_FreeAtom(s.engine.context, atom);
    var boundary: v.guest.Boundary = .{ .engine = s.engine };
    try boundary.begin();
    const present = c.JS_HasProperty(s.engine.context, reason, atom);
    try boundary.finishStatus(present);
    if (present == 0) return c.pi_js_undefined();
    // Source resolves the String callee BEFORE reading error.code.
    const string_function = try v.global(s, "String");
    return v.duplicate(s, try v.call(s, string_function, c.pi_js_undefined(), &.{try v.get(s, reason, "code")}));
}
fn codeLocked(engine: *Engine, code: c.JSValue) anyerror!bool {
    return h.truthy(engine, try h.expression(engine, codeLockedBody, .{code}));
}
fn codeLockedBody(s: *Scope, code: c.JSValue) anyerror!c.JSValue {
    return v.boolean(s, try v.eq(s, code, "ELOCKED"));
}
fn isErrorBody(s: *Scope, reason: c.JSValue) anyerror!c.JSValue {
    return v.boolean(s, try isError(s, reason));
}
fn throwBody(s: *Scope, reason: c.JSValue) anyerror!c.JSValue { return raise(s, reason); }
fn dateNowBody(s: *Scope) anyerror!c.JSValue {
    return v.duplicate(s, try v.invoke(s, try v.global(s, "Date"), "now", &.{}));
}
fn waitBody(s: *Scope, start: c.JSValue) anyerror!c.JSValue {
    const now = try v.invoke(s, try v.global(s, "Date"), "now", &.{});
    const elapsed = try h.binary(s, .subtract, now, start);
    return v.boolean(s, v.truthy(s, try h.binary(s, .less, elapsed, v.number(s, 20))));
}

const LockFrame = h.Frame(enum { release });
fn withLockCall(engine: *Engine, _: c.JSValue, args: []const c.JSValue,
    roots: []const c.JSValue) anyerror!c.JSValue
{
    var frame = LockFrame.init(engine);
    return frame.finish(withLockBody(&frame, v.arg(args, 0), v.arg(args, 1), roots[0]));
}
fn withLockBody(frame: *LockFrame, path_value: c.JSValue, function_value: c.JSValue,
    acquire: c.JSValue) anyerror!c.JSValue
{
    const engine = frame.engine;
    try frame.set(.release, callOwned(engine, acquire, &.{path_value}));
    var completion = v.owned.Completion.initValue(engine, callOwned(engine, function_value, &.{}));
    const selected = try completion.finishAction();
    // Ordinary throw/return is held as owned DATA across finally. A failing
    // release supersedes it; actual fatal producers retain the shared boundary.
    h.statement(engine, callStatement, .{ frame.get(.release), @as([]const c.JSValue, &.{}) }) catch |err| {
        var displaced = v.owned.Completion.initValue(engine, err);
        switch (selected) {
            .returned, .thrown => |value| displaced.release(value),
            .awaited => unreachable,
        }
        return displaced.finishValue();
    };
    return switch (selected) {
        .returned => |value| value,
        .thrown => |reason| engine.checked(c.JS_Throw(engine.context, reason)),
        .awaited => unreachable,
    };
}

fn getCall(engine: *Engine, receiver: c.JSValue, args: []const c.JSValue,
    _: []const c.JSValue) anyerror!c.JSValue
{
    return h.expression(engine, getBody, .{ receiver, v.arg(args, 0) });
}
fn getBody(s: *Scope, receiver: c.JSValue, cwd: c.JSValue) anyerror!c.JSValue {
    const row = try v.invoke(s, receiver, "getEntry", &.{cwd});
    if (v.nullish(row)) return c.pi_js_null();
    const value = try v.get(s, row, "decision");
    return if (v.nullish(value)) c.pi_js_null() else v.duplicate(s, value);
}
fn getEntryCall(engine: *Engine, receiver: c.JSValue, args: []const c.JSValue,
    roots: []const c.JSValue) anyerror!c.JSValue
{
    return h.expression(engine, getEntryBody, .{ receiver, v.arg(args, 0), roots });
}
fn getEntryBody(s: *Scope, receiver: c.JSValue, cwd: c.JSValue,
    roots: []const c.JSValue) anyerror!c.JSValue
{
    const path_value = try v.get(s, receiver, "trustPath");
    const callback = try v.arrow(s, "", 0, readEntryCall, &.{ receiver, cwd, roots[1], roots[2] });
    return v.duplicate(s, try v.call(s, roots[0], c.pi_js_undefined(), &.{ path_value, callback }));
}
const EntryFrame = h.Frame(enum { data });
fn readEntryCall(engine: *Engine, _: c.JSValue, _: []const c.JSValue,
    roots: []const c.JSValue) anyerror!c.JSValue
{
    var frame = EntryFrame.init(engine);
    return frame.finish(readEntryBody(&frame, roots));
}
fn readThisBody(s: *Scope, receiver: c.JSValue, read_file: c.JSValue) anyerror!c.JSValue {
    return v.duplicate(s, try v.call(s, read_file, c.pi_js_undefined(), &.{try v.get(s, receiver, "trustPath")}));
}
fn readEntryBody(frame: *EntryFrame, roots: []const c.JSValue) anyerror!c.JSValue {
    try frame.set(.data, h.expression(frame.engine, readThisBody, .{ roots[0], roots[2] }));
    return callOwned(frame.engine, roots[3], &.{ frame.get(.data), roots[1] });
}
fn setCall(engine: *Engine, receiver: c.JSValue, args: []const c.JSValue,
    _: []const c.JSValue) anyerror!c.JSValue
{
    return h.expression(engine, setBody, .{ receiver, v.arg(args, 0), v.arg(args, 1) });
}
fn setBody(s: *Scope, receiver: c.JSValue, cwd: c.JSValue, value: c.JSValue) anyerror!c.JSValue {
    const method = try v.get(s, receiver, "setMany");
    const updates = try v.array(s);
    const row = try v.object(s);
    try v.put(s, row, "path", cwd);
    try v.put(s, row, "decision", value);
    try v.index(s, updates, 0, row);
    _ = try v.call(s, method, receiver, &.{updates});
    return c.pi_js_undefined();
}
fn setManyCall(engine: *Engine, receiver: c.JSValue, args: []const c.JSValue,
    roots: []const c.JSValue) anyerror!c.JSValue
{
    return h.expression(engine, setManyBody, .{ receiver, v.arg(args, 0), roots });
}
fn setManyBody(s: *Scope, receiver: c.JSValue, decisions: c.JSValue,
    roots: []const c.JSValue) anyerror!c.JSValue
{
    const path_value = try v.get(s, receiver, "trustPath");
    const callback = try v.arrow(s, "", 0, updateCall,
        &.{ receiver, decisions, roots[1], roots[2], roots[3] });
    _ = try v.call(s, roots[0], c.pi_js_undefined(), &.{ path_value, callback });
    return c.pi_js_undefined();
}
const UpdateFrame = h.Frame(enum { data, path, value, key });
fn updateCall(engine: *Engine, _: c.JSValue, _: []const c.JSValue,
    roots: []const c.JSValue) anyerror!c.JSValue
{
    var frame = UpdateFrame.init(engine);
    return frame.finish(updateBody(&frame, roots));
}
fn updateBody(frame: *UpdateFrame, roots: []const c.JSValue) anyerror!c.JSValue {
    try frame.set(.data, h.expression(frame.engine, readThisBody, .{ roots[0], roots[2] }));
    var iterator = try v.Iterator.init(frame.engine, roots[1]);
    try iterator.finish(updateEntries(frame, &iterator, roots[3]));
    try h.statement(frame.engine, writeThisBody, .{ roots[0], frame.get(.data), roots[4] });
    return c.pi_js_undefined();
}
fn updateEntries(frame: *UpdateFrame, iterator: *v.Iterator, normalize: c.JSValue) anyerror!void {
    while (try iterator.next()) |row| {
        try h.statement(frame.engine, bindUpdateBody, .{ frame, row });
        try frame.clear(.key);
        try frame.set(.key, callOwned(frame.engine, normalize, &.{frame.get(.path)}));
        if (c.JS_IsNull(frame.get(.value)))
            try h.statement(frame.engine, deleteKey, .{ frame.get(.data), frame.get(.key) })
        else
            try h.statement(frame.engine, assignKey, .{ frame.get(.data), frame.get(.key), frame.get(.value) });
    }
}
fn bindUpdateBody(s: *Scope, frame: *UpdateFrame, incoming: c.JSValue) anyerror!void {
    const input = try v.own(s, incoming);
    // Object binding boxes once: both strict getters see the same wrapper.
    const row = try v.guest.toObject(s, input);
    try frame.set(.path, h.get(s.engine, row, "path"));
    try frame.set(.value, h.get(s.engine, row, "decision"));
}
fn writeThisBody(s: *Scope, receiver: c.JSValue, data: c.JSValue,
    write_file: c.JSValue) anyerror!void
{
    _ = try v.call(s, write_file, c.pi_js_undefined(), &.{ try v.get(s, receiver, "trustPath"), data });
}

//! Actual original/candidate comparison helper; reference and owned path required.
const std = @import("std");
const em = @import("extensions/engine.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const c = em.c;
pub fn compareActualSource(engine: *em.Engine, actual_adapter: c.JSValue, actual_sqlite: c.JSValue, owned_file: c.JSValue, original_json: []const u8) !void {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const observer = try s.own(try engine.evalModule(@embedFile("../verification/chord-node-sqlite-c268-sourceonly-20261017/observer.mjs"), "actual-chord-node-sqlite-observer.mjs"));
    const pending = try s.call(try s.get(observer, "observeNodeSqlite"), c.pi_js_undefined(), &.{ actual_adapter, actual_sqlite, owned_file });
    const actual = try s.own(try engine.awaitValue(pending));
    const terminated = try engine.gpa.dupeZ(u8, original_json); defer engine.gpa.free(terminated);
    const original = try s.own(try engine.checked(c.JS_ParseJSON(engine.context, terminated.ptr, original_json.len, "actual-original-chord-node-sqlite.json")));
    try std.testing.expect(s.equal(try s.get(original, "authority"), try s.text("actual-c268-Chord-node-SQLite-Node24.14")));
    try std.testing.expect(s.equal(try s.get(try s.get(original, "rows"), "length"), c.JS_NewInt32(engine.context, 25)));
    const json = try s.global("JSON"); const stringify = try s.get(json, "stringify");
    try std.testing.expect(s.equal(try s.call(stringify, json, &.{original}), try s.call(stringify, json, &.{actual})));
    try std.testing.expect(c.JS_IsAsyncFunction(try s.get(actual_adapter, "openNodeSqliteDatabase")));
    try std.testing.expect(!c.JS_IsConstructor(engine.context, try s.get(actual_adapter, "openNodeSqliteDatabase")));
}

fn unexpectedFs(_: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return error.MemoryDatabaseMustNotCallFilesystem;
}
fn installMemoryControl(engine: *em.Engine) !void {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const sqlite = try s.own(try @import("extensions/native_node_sqlite.zig").create(engine));
    // A causal branch sentinel, never a product/default filesystem provider.
    // Real file observations require the genuine separately owned mkdir input.
    const sentinel = try s.own(try @import("extensions/native_node_function.zig").createArrow(engine, "mustNotCallFilesystemForMemory", 0, unexpectedFs, &.{}));
    const adapter = try s.own(try @import("extensions/native_chord_sqlite_node.zig").create(engine, .{ .database_sync = try s.get(sqlite, "DatabaseSync"), .mkdir = sentinel, .dirname = sentinel }));
    const global = try s.own(c.JS_GetGlobalObject(engine.context));
    try s.put(global, "ownedSqlite", sqlite); try s.put(global, "ownedAdapter", adapter);
}
fn actualControl(allocator: std.mem.Allocator, text: []const u8) !void {
    const engine = try em.Engine.init(allocator, .{}); defer engine.deinit();
    try installMemoryControl(engine);
    const pending = try engine.eval(text, "actual-chord-node-sqlite-native-control.js", c.JS_EVAL_TYPE_GLOBAL); defer engine.freeValue(pending);
    const completed = try engine.awaitValue(pending); defer engine.freeValue(completed);
}
test "native Chord SQLite real C values retained rows reset and finalized statement" {
    try actualControl(std.testing.allocator,
        "(async()=>{const db=new ownedSqlite.DatabaseSync(':memory:');try{" ++
        "db.exec('CREATE TABLE owned(i INTEGER,s TEXT,b BLOB)');" ++
        "const insert=db.prepare('INSERT INTO owned VALUES(?,?,?)');insert.run(3n,'text',new Uint8Array([0,255]));" ++
        "const q=db.prepare('SELECT * FROM owned');const first=q.get();const second=q.get();" ++
        "if(Object.getPrototypeOf(first)!==null||first.i!==3||first.s!=='text'||!(first.b instanceof Uint8Array)||first.b[1]!==255||first.b===second.b)throw Error('Actual SQLite value/ownership mismatch');" ++
        "db.close();try{q.get();throw Error('Finalized statement accepted')}catch(error){if(error.code!=='ERR_INVALID_STATE')throw error}" ++
        "}finally{try{db.close()}catch{}}})()"
    );
}
test "native Chord SQLite real transaction serializes outside work and expires handle" {
    try actualControl(std.testing.allocator,
        "(async()=>{const db=await ownedAdapter.openNodeSqliteDatabase(':memory:');try{" ++
        "await db.exec('CREATE TABLE owned(i INTEGER)');const entered=Promise.withResolvers(),release=Promise.withResolvers();let saved;" ++
        "const tx=db.transaction(async handle=>{saved=handle;await handle.run('INSERT INTO owned VALUES(?)',1);entered.resolve();await release.promise;return 4});" ++
        "await entered.promise;const queued=db.run('INSERT INTO owned VALUES(?)',2);if(db.access.pending!==2)throw Error('Actual queue barrier was not published');release.resolve();" ++
        "if(await tx!==4)throw Error('Transaction return identity changed');await queued;const rows=await db.all('SELECT i FROM owned ORDER BY i');" ++
        "if(rows.length!==2||rows[0].i!==1||rows[1].i!==2||saved.scope.active||db.access.pending!==0)throw Error('Actual transaction ordering mismatch');" ++
        "try{await saved.exec('SELECT 1');throw Error('Expired handle accepted')}catch(error){if(error.message!=='SQLite transaction handle is no longer active')throw error}" ++
        "}finally{await db.close()}})()"
    );
}
test "native Chord SQLite genuine rollback preserves raw rejection and close is idempotent" {
    try actualControl(std.testing.allocator,
        "(async()=>{const db=await ownedAdapter.openNodeSqliteDatabase(':memory:');const reason={owned:true};" ++
        "await db.exec('CREATE TABLE owned(i INTEGER)');try{await db.transaction(async tx=>{await tx.run('INSERT INTO owned VALUES(?)',1);throw reason});throw Error('Rejection lost')}catch(error){if(error!==reason)throw error}" ++
        "const row=await db.get('SELECT count(*) AS n FROM owned');if(row.n!==0)throw Error('Actual rollback did not finish');await db.close();await db.close();" ++
        "if(!db.closed||db.statements.size!==0)throw Error('Actual close lifecycle mismatch')})()"
    );
}
test "native Chord SQLite host allocation failures retain actual C connection ownership" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, actualControl, .{
        "(async()=>{const db=await ownedAdapter.openNodeSqliteDatabase(':memory:');try{await db.exec('CREATE TABLE owned(i INTEGER)');await db.run('INSERT INTO owned VALUES(?)',7);await db.get('SELECT i FROM owned')}finally{await db.close()}})()",
    });
}

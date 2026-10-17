//! Prepared causal controls only; requires real module/database composition.
//! No fake SQL provider, substitute factory or WeakRef same-job proof.
const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const q = @import("extensions/native_chord_sqlite_values.zig");
const c = v.c;
pub fn verifyPreexistingCapturedFatal(engine: *v.em.Engine) !void {
    try std.testing.expect(engine.captured_exception == null);
    try std.testing.expect(!c.JS_HasException(engine.context));
    const portable = engine.native_module_values.get("@earendil-works/chord/sqlite") orelse return error.RequiredActualPortableModule;
    const validate = try v.js.get(engine, portable, "validateSqliteSchemaPrefix"); defer engine.freeValue(validate);
    const setup = try engine.evalModule(
        \\globalThis.sqliteFatalPrefixReads=0;globalThis.sqliteFatalPrefix={toString(){sqliteFatalPrefixReads++;return 'metadata'}};
    , "sqlite-captured-fatal-setup.mjs"); engine.freeValue(setup);
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    const prefix = try v.js.get(engine, global, "sqliteFatalPrefix"); defer engine.freeValue(prefix);
    const diagnostics = engine.native_exception_diagnostics_suppressed;
    engine.native_exception_diagnostics_suppressed += 1;
    _ = engine.throwNativeOutOfMemory();
    const captured_error = v.js.capture(engine);
    engine.native_exception_diagnostics_suppressed -= 1;
    try std.testing.expect(captured_error == error.JavaScriptException);
    const reason = c.JS_DupValue(engine.context, engine.captured_exception orelse return error.MissingActualCapturedFatal);
    defer engine.freeValue(reason);
    var args = [_]c.JSValue{prefix};
    const result = c.JS_Call(engine.context, validate, c.pi_js_undefined(), 1, &args);
    defer engine.freeValue(result); // Own even unexpected success on assertion failure.
    try std.testing.expect(c.JS_IsException(result));
    const actual = c.JS_GetException(engine.context); defer engine.freeValue(actual);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, actual));
    try std.testing.expect(c.JS_IsUncatchableError(actual));
    try std.testing.expect(engine.captured_exception == null);
    try std.testing.expectEqual(diagnostics, engine.native_exception_diagnostics_suppressed);
    const checked = try engine.evalModule(
        \\if(sqliteFatalPrefixReads!==0)throw Error('captured fatal bypassed');delete globalThis.sqliteFatalPrefixReads;delete globalThis.sqliteFatalPrefix;
    , "sqlite-captured-fatal-check.mjs"); engine.freeValue(checked);
}
/// Fresh real opened NodeSqliteDatabase required. The observer delegates its
/// actual transaction/run operations; a gate pauses only the real UPDATE's
/// completion. Both weak targets were created in a PRIOR completed job before
/// the driver clears kept objects and runs the actual VM GC.
pub fn verifyPriorJobIteratorRetirement(engine: *v.em.Engine, actual_database: c.JSValue, empty_statements: bool) !void {
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    try q.put(engine, global, "actualSqliteLifetimeDatabase", actual_database);
    try q.put(engine, global, "actualSqliteEmptyStatements", c.pi_js_bool(engine.context, @intFromBool(empty_statements)));
    const started = try engine.evalModule(
        \\import{applySqliteMigrations as migrate}from'@earendil-works/chord/sqlite';
        \\globalThis.sqliteLifetimeProbe={atUpdate:false,finished:false};const p=sqliteLifetimeProbe,db=actualSqliteLifetimeDatabase,empty=actualSqliteEmptyStatements,gate=Promise.withResolvers();p.release=gate.resolve;
        \\const migration={version:1,statements:{[Symbol.iterator](){let i=0;const iterator={next(){return empty||i++?{done:true}:{done:false,value:'CREATE TABLE retired_iterator_probe(id INTEGER)'}}};p.inner=new WeakRef(iterator);return iterator}}};
        \\const migrations=[migration];migrations[Symbol.iterator]=function(){let i=0;const iterator={next(){return i++?{done:true}:{done:false,value:migration}}};p.outer=new WeakRef(iterator);return iterator};
        \\const observed=new Proxy(db,{get(target,key,receiver){if(key!=='transaction')return Reflect.get(target,key,receiver);const original=Reflect.get(target,key,target);return function(callback){return Reflect.apply(original,target,[transaction=>callback(new Proxy(transaction,{get(tx,name,txReceiver){if(name!=='run')return Reflect.get(tx,name,txReceiver);const run=Reflect.get(tx,name,tx);return function(...args){const actual=Reflect.apply(run,tx,args);if(String(args[0]).startsWith('UPDATE ')){p.atUpdate=true;return actual.then(()=>gate.promise)}return actual}}}))])}}});
        \\p.promise=migrate(observed,migrations,{table:'retired_iterator_metadata'}).then(()=>{p.finished=true});
    , "sqlite-iterator-lifetime-start.mjs"); engine.freeValue(started);
    // Drain the real queue to the actual UPDATE gate; no polling sleeps/jobs.
    _ = try engine.runReadyJobs(engine.options.job_budget);
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
    const first = try engine.evalModule(
        \\const p=sqliteLifetimeProbe;if(!p.atUpdate||p.finished)throw Error('real SQL gate not reached');if(p.inner.deref()!==undefined)throw Error('completed inner IteratorRecord retained');if(p.outer.deref()===undefined)throw Error('active outer IteratorRecord lost');p.release();
    , "sqlite-iterator-lifetime-at-update.mjs"); engine.freeValue(first);
    _ = try engine.runReadyJobs(engine.options.job_budget);
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
    const finished = try engine.evalModule(
        \\const p=sqliteLifetimeProbe;if(!p.finished)throw Error('real migration not finished');if(p.outer.deref()!==undefined)throw Error('completed outer IteratorRecord retained');delete globalThis.sqliteLifetimeProbe;delete globalThis.actualSqliteLifetimeDatabase;delete globalThis.actualSqliteEmptyStatements;
    , "sqlite-iterator-lifetime-finished.mjs"); engine.freeValue(finished);
}

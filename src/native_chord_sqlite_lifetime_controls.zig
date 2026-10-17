//! Prepared causal controls only; requires real module/database composition.
//! No fake SQL provider, substitute factory or WeakRef same-job proof.
const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const q = @import("extensions/native_chord_sqlite_values.zig");
const c = v.c;
fn prefixReads(engine: *v.em.Engine, global: c.JSValue, expected: i32) !void {
    const atom = c.JS_NewAtom(engine.context, "sqliteFatalPrefixReads");
    if (atom == c.JS_ATOM_NULL) return error.OutOfMemory;
    defer c.JS_FreeAtom(engine.context, atom);
    var descriptor: c.JSPropertyDescriptor = undefined;
    try std.testing.expectEqual(@as(c_int, 1), c.JS_GetOwnProperty(engine.context, &descriptor, global, atom));
    defer engine.freeValue(descriptor.value); defer engine.freeValue(descriptor.getter); defer engine.freeValue(descriptor.setter);
    try std.testing.expect(c.JS_IsUndefined(descriptor.getter) and c.JS_IsUndefined(descriptor.setter));
    try std.testing.expect(c.JS_IsNumber(descriptor.value));
    var reads: i32 = -1;
    try std.testing.expectEqual(@as(c_int, 0), c.JS_ToInt32(engine.context, &reads, descriptor.value));
    try std.testing.expectEqual(expected, reads);
}
fn captureMarkedOom(engine: *v.em.Engine) !void {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    _ = engine.throwNativeOutOfMemory();
    const reason = c.JS_GetException(engine.context);
    // Mark this ACTUAL pending native Error, before capture. This is the
    // normal fatal-delivery event policy, not mutation of rejected DATA.
    c.JS_SetUncatchableError(engine.context, reason);
    _ = c.JS_Throw(engine.context, reason);
    try std.testing.expect(v.js.capture(engine) == error.JavaScriptException);
    try std.testing.expect(c.JS_IsUncatchableError(engine.captured_exception orelse return error.MissingMarkedNativeOom));
}
/// Earlier completed producer's captured diagnostic is HISTORY at a new call.
/// Its private bit remains unchanged and must not suppress the actual body.
pub fn verifyHistoricalCapturedDataBodyRuns(engine: *v.em.Engine) !void {
    try std.testing.expect(engine.captured_exception == null);
    try std.testing.expect(!c.JS_HasException(engine.context));
    const portable = engine.native_module_values.get("@earendil-works/chord/sqlite") orelse return error.RequiredActualPortableModule;
    const validate = try v.js.get(engine, portable, "validateSqliteSchemaPrefix"); defer engine.freeValue(validate);
    const setup = try engine.evalModule(
        \\globalThis.sqliteFatalPrefixReads=0;globalThis.sqliteFatalPrefix={toString(){sqliteFatalPrefixReads++;return 'metadata'},toLowerCase(){sqliteFatalPrefixReads++;return 'metadata'}};
    , "sqlite-captured-fatal-setup.mjs"); engine.freeValue(setup);
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    const prefix = try v.js.get(engine, global, "sqliteFatalPrefix"); defer engine.freeValue(prefix);
    const diagnostics = engine.native_exception_diagnostics_suppressed;
    try captureMarkedOom(engine);
    const reason = c.JS_DupValue(engine.context, engine.captured_exception orelse return error.MissingActualCapturedFatal);
    defer engine.freeValue(reason);
    var args = [_]c.JSValue{prefix};
    const result = c.JS_Call(engine.context, validate, c.pi_js_undefined(), 1, &args);
    defer engine.freeValue(result); // Own even unexpected success on assertion failure.
    try std.testing.expect(c.JS_IsUndefined(result));
    try std.testing.expect(!c.JS_HasException(engine.context));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, engine.captured_exception orelse return error.HistoricalCaptureLost));
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expectEqual(diagnostics, engine.native_exception_diagnostics_suppressed);
    try prefixReads(engine, global, 2);
}
/// Distinct ACTUAL pending VM Error takes precedence over an older captured
/// native fatal. No input flag is used as a substitute for the event slot.
pub fn verifyCurrentPendingWins(engine: *v.em.Engine) !void {
    try std.testing.expect(engine.captured_exception == null);
    try std.testing.expect(!c.JS_HasException(engine.context));
    const portable = engine.native_module_values.get("@earendil-works/chord/sqlite") orelse return error.RequiredActualPortableModule;
    const validate = try v.js.get(engine, portable, "validateSqliteSchemaPrefix"); defer engine.freeValue(validate);
    const setup = try engine.evalModule(
        \\globalThis.sqliteFatalPrefixReads=0;globalThis.sqliteFatalPrefix={toString(){sqliteFatalPrefixReads++;return 'metadata'}};
    , "sqlite-current-pending-setup.mjs"); engine.freeValue(setup);
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    const prefix = try v.js.get(engine, global, "sqliteFatalPrefix"); defer engine.freeValue(prefix);
    const diagnostics = engine.native_exception_diagnostics_suppressed;
    try captureMarkedOom(engine);
    const older = c.JS_DupValue(engine.context, engine.captured_exception.?); defer engine.freeValue(older);
    _ = c.JS_ThrowInternalError(engine.context, "Actual current SQLite VM event");
    const current = c.JS_GetException(engine.context); defer engine.freeValue(current);
    try std.testing.expect(!c.JS_IsStrictEqual(engine.context, older, current));
    _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, current));
    var args = [_]c.JSValue{prefix};
    const result = c.JS_Call(engine.context, validate, c.pi_js_undefined(), 1, &args);
    defer engine.freeValue(result);
    try std.testing.expect(c.JS_IsException(result));
    const actual = c.JS_GetException(engine.context); defer engine.freeValue(actual);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, current, actual));
    try std.testing.expect(engine.captured_exception == null);
    try std.testing.expectEqual(diagnostics, engine.native_exception_diagnostics_suppressed);
    try std.testing.expect(c.JS_IsUncatchableError(older));
    try prefixReads(engine, global, 0);
}
fn currentProducer(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = v.em.Engine.fromContext(context.?);
    const global = c.JS_GetGlobalObject(context); defer engine.freeValue(global);
    // This control owns the real global data property. No getter/coercion is
    // substituted for the actual native allocation producer below.
    if (c.JS_SetPropertyStr(context, global, "sqliteFatalPrefixReads", c.JS_NewInt32(context, 1)) < 0) return c.JS_Throw(context, c.JS_GetException(context));
    _ = engine.throwNativeOutOfMemory();
    const reason = c.JS_GetException(context);
    c.JS_SetUncatchableError(context, reason);
    return c.JS_Throw(context, reason);
}
/// Real new native producer during the actual validator's coercion must win
/// over old captured DATA. No historical-object flag is cleared or reclassified.
pub fn verifyCurrentProducerWins(engine: *v.em.Engine) !void {
    try std.testing.expect(engine.captured_exception == null);
    try std.testing.expect(!c.JS_HasException(engine.context));
    const portable = engine.native_module_values.get("@earendil-works/chord/sqlite") orelse return error.RequiredActualPortableModule;
    const validate = try v.js.get(engine, portable, "validateSqliteSchemaPrefix"); defer engine.freeValue(validate);
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    try q.put(engine, global, "sqliteFatalPrefixReads", c.JS_NewInt32(engine.context, 0));
    const prefix = try v.js.object(engine); defer engine.freeValue(prefix);
    const producer = try engine.checked(c.JS_NewCFunction(engine.context, currentProducer, "actualSqliteNativeProducer", 0)); defer engine.freeValue(producer);
    try q.put(engine, prefix, "toString", producer);
    const diagnostics = engine.native_exception_diagnostics_suppressed;
    try captureMarkedOom(engine);
    const older = c.JS_DupValue(engine.context, engine.captured_exception.?); defer engine.freeValue(older);
    const generation = engine.native_allocation_generation;
    var args = [_]c.JSValue{prefix};
    const result = c.JS_Call(engine.context, validate, c.pi_js_undefined(), 1, &args);
    defer engine.freeValue(result);
    try std.testing.expect(c.JS_IsException(result));
    const actual = c.JS_GetException(engine.context); defer engine.freeValue(actual);
    try std.testing.expect(!c.JS_IsStrictEqual(engine.context, older, actual));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, actual, engine.native_allocation_exception orelse return error.MissingCurrentProducerReason));
    try std.testing.expect(c.JS_IsUncatchableError(actual));
    try std.testing.expect(c.JS_IsUncatchableError(older));
    try std.testing.expect(engine.native_allocation_generation != generation);
    try std.testing.expect(engine.captured_exception == null);
    try std.testing.expectEqual(diagnostics, engine.native_exception_diagnostics_suppressed);
    try prefixReads(engine, global, 1);
}
fn collectActual(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = v.em.Engine.fromContext(context.?);
    c.JS_RunGC(engine.runtime);
    return c.pi_js_undefined();
}
/// Fresh real opened NodeSqliteDatabase required. The observer delegates its
/// actual transaction/run operations; a gate pauses only the real UPDATE's
/// completion. Both weak targets were created in a PRIOR completed job before
/// the driver clears kept objects and runs the actual VM GC.
pub fn verifyPriorJobIteratorRetirement(engine: *v.em.Engine, actual_database: c.JSValue, empty_statements: bool) !void {
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    const collect = try engine.checked(c.JS_NewCFunction(engine.context, collectActual, "collectActualSqliteLifetime", 0)); defer engine.freeValue(collect);
    try q.put(engine, global, "collectActualSqliteLifetime", collect);
    try q.put(engine, global, "actualSqliteLifetimeDatabase", actual_database);
    try q.put(engine, global, "actualSqliteEmptyStatements", c.pi_js_bool(engine.context, @intFromBool(empty_statements)));
    const started = try engine.evalModule(
        \\import{applySqliteMigrations as migrate}from'@earendil-works/chord/sqlite';
        \\globalThis.sqliteLifetimeProbe={atUpdate:false,finished:false};const p=sqliteLifetimeProbe,db=actualSqliteLifetimeDatabase,empty=actualSqliteEmptyStatements,gate=Promise.withResolvers();p.release=gate.resolve;
        \\let innerIndex=0,pendingInner={next(){return empty||innerIndex++?{done:true}:{done:false,value:'CREATE TABLE retired_iterator_probe(id INTEGER)'}}};p.inner=new WeakRef(pendingInner);
        \\const migration={version:1,statements:{[Symbol.iterator](){const iterator=pendingInner;pendingInner=undefined;return iterator}}};
        \\let outerIndex=0,pendingOuter={next(){return outerIndex++?{done:true}:{done:false,value:migration}}};p.outer=new WeakRef(pendingOuter);const migrations=[migration];migrations[Symbol.iterator]=function(){const iterator=pendingOuter;pendingOuter=undefined;return iterator};
        \\const observed=new Proxy(db,{get(target,key,receiver){if(key!=='transaction')return Reflect.get(target,key,receiver);const original=Reflect.get(target,key,target);return function(callback){return Reflect.apply(original,target,[transaction=>callback(new Proxy(transaction,{get(tx,name,txReceiver){if(name!=='run')return Reflect.get(tx,name,txReceiver);const run=Reflect.get(tx,name,tx);return function(...args){const actual=Reflect.apply(run,tx,args);if(String(args[0]).startsWith('UPDATE ')){collectActualSqliteLifetime();p.innerRetiredInsideUpdate=p.inner.deref()===undefined;p.atUpdate=true;return actual.then(()=>gate.promise)}return actual}}}))])}}});
        \\p.start=()=>{p.promise=migrate(observed,migrations,{table:'retired_iterator_metadata'}).then(()=>{p.finished=true})};
    , "sqlite-iterator-lifetime-start.mjs"); engine.freeValue(started);
    // End the setup checkpoint BEFORE invoking the genuine migration. WeakRef
    // targets are still strongly held by the actual input's factory until used.
    _ = try engine.runReadyJobs(engine.options.job_budget);
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
    const invoked = try engine.evalModule(
        \\sqliteLifetimeProbe.start();delete sqliteLifetimeProbe.start;
    , "sqlite-iterator-lifetime-invoke.mjs"); engine.freeValue(invoked);
    // Drain the real queue to the actual UPDATE gate; no polling sleeps/jobs.
    _ = try engine.runReadyJobs(engine.options.job_budget);
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
    const first = try engine.evalModule(
        \\const p=sqliteLifetimeProbe;if(!p.atUpdate||p.finished)throw Error('real SQL gate not reached');if(!p.innerRetiredInsideUpdate)throw Error('inner IteratorRecord or temporary root survived into real UPDATE callback');if(p.inner.deref()!==undefined)throw Error('completed inner IteratorRecord retained');if(p.outer.deref()===undefined)throw Error('active outer IteratorRecord lost');p.release();
    , "sqlite-iterator-lifetime-at-update.mjs"); engine.freeValue(first);
    _ = try engine.runReadyJobs(engine.options.job_budget);
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
    const finished = try engine.evalModule(
        \\const p=sqliteLifetimeProbe;if(!p.finished)throw Error('real migration not finished');if(p.outer.deref()!==undefined)throw Error('completed outer IteratorRecord retained');delete globalThis.sqliteLifetimeProbe;delete globalThis.actualSqliteLifetimeDatabase;delete globalThis.actualSqliteEmptyStatements;delete globalThis.collectActualSqliteLifetime;
    , "sqlite-iterator-lifetime-finished.mjs"); engine.freeValue(finished);
}

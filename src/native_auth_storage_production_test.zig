//! Integration replay entrypoints require genuine assembler dependencies and
//! real owned filesystem fixtures. No fabricated default resolver/backend is
//! used to make the production AuthStorage constructor appear qualified.
const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const c = v.c;
const production = @import("extensions/native_auth_storage_production.zig");

pub fn replay(engine: *v.em.Engine, actual_imports: c.JSValue, actual_fixture: c.JSValue, source_expected: c.JSValue) !void {
    var scope: v.Scope = .{ .engine = engine };
    defer scope.deinit();
    const exports = try scope.own(try production.create(engine, actual_imports));
    try engine.registerValueModule("native-auth-storage-production", exports);
    try engine.registerModule("auth-storage-production-cases", @embedFile("extensions/fixtures/auth-storage-production-4954-cases.input.txt"));
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(global, "authStorageActualFixture", actual_fixture);
    try scope.put(global, "authStorageSourceExpected", source_expected);
    const module = engine.evalModule(
        \\import{AuthStorage,InMemoryAuthStorageBackend,FileAuthStorageBackend}from'native-auth-storage-production';
        \\import{runAuthStorageCases,authStorageCaseIds}from'auth-storage-production-cases';
        \\const result=await runAuthStorageCases({AuthStorage,InMemoryAuthStorageBackend,FileAuthStorageBackend},authStorageActualFixture);
        \\if(result.rows.length!==47||authStorageCaseIds.length!==47||authStorageSourceExpected.length!==47)throw Error('actual Source47 inventory required');
        \\for(let index=0;index<47;index++)if(JSON.stringify(result.rows[index])!==JSON.stringify(authStorageSourceExpected[index]))throw Error(JSON.stringify({index,actual:result.rows[index],expected:authStorageSourceExpected[index]}));
        \\export const proof=true;
    , "actual-auth-storage-production-source47") catch |err| {
        std.debug.print("AuthStorage production Source47 {s}: {s}\n", .{ @errorName(err), engine.last_error orelse "no diagnostic" });
        return err;
    };
    defer engine.freeValue(module);
    c.JS_RunGC(engine.runtime);
}

/// The caller invokes this with the same genuine module bindings, forces GC,
/// then calls the returned namespace's finish() and awaits work. Both the
/// ordinary instance and its actual in-memory backend must remain reachable.
pub fn prepareRetained(engine: *v.em.Engine, actual_imports: c.JSValue) !c.JSValue {
    var scope: v.Scope = .{ .engine = engine };
    defer scope.deinit();
    const exports = try scope.own(try production.create(engine, actual_imports));
    try engine.registerValueModule("native-auth-storage-retained", exports);
    return engine.evalModule(
        \\import{AuthStorage,InMemoryAuthStorageBackend}from'native-auth-storage-retained';
        \\const store=AuthStorage.inMemory({p:{type:'oauth',access:'before',unknown:{value:1}}});let release,enter;
        \\const entered=new Promise(resolve=>enter=resolve),gate=new Promise(resolve=>release=resolve),next={type:'oauth',access:'after',unknown:{identity:true}};
        \\export const work=store.modify('p',async current=>{if(current.access!=='before')throw Error('current');enter();await gate;return next}).then(result=>{if(result!==next||store.readState.data.p!==next||!(store instanceof AuthStorage)||!(store.storage instanceof InMemoryAuthStorageBackend)||Object.hasOwn(store,'read'))throw Error('retained ordinary AuthStorage graph');return true});
        \\export function finish(){release()}await entered;
    , "actual-auth-storage-production-retained");
}

test "native ordinary AuthStorage production refuses missing actual default dependencies" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var scope: v.Scope = .{ .engine = engine };
    defer scope.deinit();
    try std.testing.expectError(error.RequiredActualAuthStorageDependency, production.create(engine, try scope.object()));
    try std.testing.expectError(error.RequiredActualConfigValueResolver, production.createDefault(engine, c.pi_js_undefined()));
}

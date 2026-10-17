//! Prepared tests only. No expected Source capture exists for this new unit.
const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const q = @import("extensions/native_chord_sqlite_values.zig");
const c = v.c;
fn setup() !*v.em.Engine {
    const engine = try v.em.Engine.init(std.testing.allocator, .{});
    errdefer engine.deinit();
    const exports = try v.js.object(engine); defer engine.freeValue(exports);
    const validate = try @import("extensions/native_chord_sqlite_schema.zig").create(engine); defer engine.freeValue(validate);
    try q.put(engine, exports, "validateSqliteSchemaPrefix", validate);
    const migrate = try @import("extensions/native_chord_sqlite_migrations.zig").create(engine, validate); defer engine.freeValue(migrate);
    try q.put(engine, exports, "applySqliteMigrations", migrate);
    try engine.registerValueModule("@earendil-works/chord/sqlite", exports);
    return engine;
}
test "Chord portable SQLite actual identifier validation and function metadata" {
    const engine = try setup(); defer engine.deinit();
    const result = try engine.evalModule(
        \\import{validateSqliteSchemaPrefix as validate,applySqliteMigrations as migrate}from'@earendil-works/chord/sqlite';
        \\if(validate.length!==1||validate.name!=='validateSqliteSchemaPrefix'||migrate.length!==3||migrate.constructor.name!=='AsyncFunction')throw Error('actual export metadata');
        \\for(const value of ['x','_','A_09','prefix_','not_sqlite'])if(validate(value)!==undefined)throw Error('valid identifier');
        \\for(const value of ['', '1x','a-b','a.b','quote"','é','sqlite_x','SQLITE_']){let error;try{validate(value)}catch(e){error=e}if(!error||!error.message.includes('SQLite schema prefix'))throw Error('invalid identifier admitted')}
        \\if(Object.getOwnPropertyDescriptor(validate,'prototype')===undefined||Object.getOwnPropertyDescriptor(migrate,'prototype')!==undefined)throw Error('declaration kind');
    , "chord-sqlite-validation.mjs");
    engine.freeValue(result);
}
test "Chord portable SQLite validation retains live test coercion and Error argument order" {
    const engine = try setup(); defer engine.deinit();
    const result = try engine.evalModule(
        \\import{validateSqliteSchemaPrefix as validate}from'@earendil-works/chord/sqlite';
        \\const log=[],prefix={toString(){log.push('test-coerce');return 'hello'},toLowerCase(){log.push('lower');return{startsWith(value){log.push('starts:'+value);return false}}}};validate(prefix);
        \\if(log.join('|')!=='test-coerce|lower|starts:sqlite_')throw Error('coercion order');
        \\const original=Object.getOwnPropertyDescriptor(globalThis,'Error'),json=JSON.stringify;try{Object.defineProperty(globalThis,'Error',{configurable:true,get(){log.push('Error');return original.value}});JSON.stringify=function(value){log.push('json');return Reflect.apply(json,this,[value])};try{validate('!')}catch{}if(log.slice(-2).join('|')!=='Error|json')throw new original.value('Error evaluated after argument')}finally{Object.defineProperty(globalThis,'Error',original);JSON.stringify=json}
    , "chord-sqlite-validation-order.mjs");
    engine.freeValue(result);
}
test "Chord portable SQLite async validation rejects before database transaction lookup" {
    const engine = try setup(); defer engine.deinit();
    const result = try engine.evalModule(
        \\import{applySqliteMigrations as migrate}from'@earendil-works/chord/sqlite';
        \\let looked=0;const database=new Proxy({}, {get(){looked++;throw Error('transaction must not be read')}});let rejected;
        \\const promise=migrate(database,[{version:2,statements:[]}],{table:'meta'});if(!(promise instanceof Promise))throw Error('not actual outer promise');try{await promise}catch(error){rejected=error}if(rejected?.message!=='SQLite migrations must have contiguous versions starting at 1'||looked!==0)throw Error('invalid migrations reached database');
        \\const reason={toString(){throw Error('diagnostic coercion')}};let got;try{await migrate(database,[],{get table(){throw reason}})}catch(error){got=error}if(got!==reason||looked!==0)throw Error('getter identity/early boundary');
    , "chord-sqlite-validation-before-transaction.mjs");
    engine.freeValue(result);
}
/// Requires a REAL opened native NodeSqliteDatabase. This is not a fabricated
/// callback database. Root's actual adapter gate calls it only after composition.
pub fn verifyActualMigrations(engine: *v.em.Engine, actual_database: c.JSValue) !void {
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    try q.put(engine, global, "actualChordSqliteDatabase", actual_database);
    defer { const atom = c.JS_NewAtom(engine.context, "actualChordSqliteDatabase"); defer c.JS_FreeAtom(engine.context, atom); _ = c.JS_DeleteProperty(engine.context, global, atom, 0); }
    const result = try engine.evalModule(
        \\import{applySqliteMigrations as migrate}from'@earendil-works/chord/sqlite';const db=actualChordSqliteDatabase;
        \\const migrations=[{version:1,statements:['CREATE TABLE items(id INTEGER PRIMARY KEY,value TEXT)','INSERT INTO items VALUES(1,\'one\')']},{version:2,statements:['INSERT INTO items VALUES(2,\'two\')']}];
        \\await migrate(db,migrations,{table:'metadata'});await migrate(db,migrations,{table:'metadata'});const rows=await db.all('SELECT * FROM items ORDER BY id');if(rows.length!==2||rows[1].value!=='two'||(await db.get('SELECT version FROM metadata')).version!==2)throw Error('migration apply/idempotency');
        \\let failed=false;try{await migrate(db,[...migrations,{version:3,statements:['INSERT INTO items VALUES(3,\'three\')','THIS IS INVALID SQL']}],{table:'metadata'})}catch{failed=true}if(!failed||(await db.all('SELECT * FROM items')).length!==2||(await db.get('SELECT version FROM metadata')).version!==2)throw Error('atomic migration rollback');
        \\let newer;try{await migrate(db,migrations.slice(0,1),{table:'metadata'})}catch(error){newer=error}if(newer?.message!=='SQLite schema version 2 is newer than supported version 1')throw Error('newer schema message');
    , "chord-sqlite-actual-native-migrations.mjs");
    engine.freeValue(result);
}

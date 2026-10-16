//! Replay requires the actual assembled Type/Memory/operator graph, no doubles.
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
const c = em.c;
pub fn replay(engine: *em.Engine, actual_type: c.JSValue, actual_system: c.JSValue, actual_schemas: c.JSValue, actual_compiler: c.JSValue, expected_source: c.JSValue) !void {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    inline for (.{ "actualSchemaType", "actualSchemaSystem", "actualModelSchemas", "actualSchemaCompiler", "modelSchemasPartialSource" }, .{ actual_type, actual_system, actual_schemas, actual_compiler, expected_source }) |name, value| try js.define(engine, global, name, c.JS_DupValue(engine.context, value));
    const pending = try engine.evalModule(@embedFile("extensions/fixtures/ai-model-schemas-partial-4954.input.mjs") ++
        \\
        \\if(modelSchemasPartialSource.sourceHead!=='4954d760504c11df9b2cbdc040346107b6a8153d'||modelSchemasPartialSource.rows.length!==modelSchemasPartialObservation.rows.length)throw Error('real schema/Partial Source scope');for(let i=0;i<modelSchemasPartialSource.rows.length;i++){const expected=modelSchemasPartialSource.rows[i],actual=modelSchemasPartialObservation.rows[i];if(JSON.stringify(expected)!==JSON.stringify(actual))throw Error(JSON.stringify({case:i,expected,actual}))}export const pass=true;
    , "actual-model-schemas-partial-4954.mjs");
    defer engine.freeValue(pending);
    const settled = try engine.awaitValue(pending);
    engine.freeValue(settled);
}

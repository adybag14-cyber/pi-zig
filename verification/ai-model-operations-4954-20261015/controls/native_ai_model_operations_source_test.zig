//! Authored comparison entry. Native compilation/replay has not been granted.
const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const c = em.c;

fn install(engine: *em.Engine) !void {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    // The actual shared class factory is mandatory; no positive mock class.
    const models_error = try @import("extensions/native_ai_models_error.zig").create(engine);
    defer engine.freeValue(models_error);
    const operations = try @import("extensions/native_ai_model_operations.zig").create(engine, models_error);
    defer engine.freeValue(operations);
    try sdk.put(engine, global, "modelOperationNamespace", c.JS_DupValue(engine.context, operations));
    try sdk.put(engine, global, "CanonicalModelsError", c.JS_DupValue(engine.context, models_error));
}

test "native model operations compare all genuine4954 observations with actual shared ModelsError" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const expected = @embedFile("extensions/fixtures/ai-model-operations-4954.json");
    try sdk.put(engine, global, "modelOperationExpected", try engine.checked(c.JS_ParseJSON(engine.context, expected.ptr, expected.len, "original4954-model-operations.json")));
    const checked = engine.evalModule(@embedFile("extensions/fixtures/ai-model-operations-4954.input.txt") ++
        "\nif(!modelOperationCaptureComplete||modelOperationExpected.sourceHead!=='4954d760504c11df9b2cbdc040346107b6a8153d'||!modelOperationExpected.canonicalModelsErrorIdentity||modelOperationRows.length!==modelOperationExpected.cases)throw Error('all actual Source rows required');for(let i=0;i<modelOperationRows.length;i++)if(JSON.stringify(modelOperationRows[i])!==JSON.stringify(modelOperationExpected.rows[i]))throw Error(JSON.stringify({case:i,actual:modelOperationRows[i],expected:modelOperationExpected.rows[i]}));globalThis.nativeModelOperationRawDiagnostics=JSON.stringify(modelOperationRawDiagnostics);", "native-model-operations4954-comparison.mjs") catch |err| {
        std.debug.print("Model operations comparison: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(checked);
    const diagnostics = try engine.eval("globalThis.nativeModelOperationRawDiagnostics", "native-model-operations-raw-diagnostics.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(diagnostics);
    const text = try engine.valueToZigString(diagnostics);
    defer engine.gpa.free(text);
    std.debug.print("NATIVE_MODEL_OPERATION_RAW_DIAGNOSTICS {s}\n", .{text});
    c.JS_RunGC(engine.runtime);
}

test "native model-operation functions retain the actual shared ModelsError through collection" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    const prepare = try engine.evalModule("globalThis.keptAssertion=modelOperationNamespace.assertImageModel;globalThis.keptModelsError=CanonicalModelsError;delete globalThis.modelOperationNamespace;delete globalThis.CanonicalModelsError;", "model-operation-retention-prepare.mjs");
    engine.freeValue(prepare);
    c.JS_RunGC(engine.runtime);
    const replay = try engine.evalModule("let observed=false;try{keptAssertion({type:'chat',provider:'p',id:'id'})}catch(error){observed=error instanceof keptModelsError&&error.code==='provider'&&error.message==='Model p/id is not an image model'}if(!observed)throw Error('actual retained shared class required');delete globalThis.keptAssertion;delete globalThis.keptModelsError;", "model-operation-retention-replay.mjs");
    engine.freeValue(replay);
    c.JS_RunGC(engine.runtime);
}

const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const c = v.c;

test "native actual Models class preserves ordinary receivers and intrinsic request promises" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    const exports = try @import("extensions/native_ai_models_namespace.zig").create(engine);
    defer engine.freeValue(exports);
    try engine.registerValueModule("native:actual-models-class", exports);
    var source: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer source.deinit();
    try source.writer.writeAll(@embedFile("extensions/native_ai_models_class_fixture.mjs"));
    try source.writer.writeAll(
        \\import * as api from 'native:actual-models-class';
        \\const rows=await run(api),byCase=Object.fromEntries(rows.map(row=>[row.case,row]));
        \\for(const row of rows)if(row.error)throw Error(JSON.stringify(row));
        \\const shape=byCase['ordinary class and shared prototype'].value;
        \\if(shape.fields.join(',')!=='providers,credentials,modelsStore,authContext,refreshGenerations,refreshControllers,publicationChains'||shape.prototype.length!==39||!shape.sharedPrototype||!shape.sharedMethods||shape.ownMethod||!shape.ordinaryPrototype||!shape.fieldsIndependent)throw Error('Actual ModelsImpl class surface');
        \\if(!byCase['constructor live getters and raw failure'].value.same||byCase['constructor live getters and raw failure'].value.trace.join(',')!=='credentials,modelsStore')throw Error('Constructor raw failure ordering');
        \\if(!Object.values(byCase['query fields remain live'].value).every(Boolean))throw Error('Hidden bound registry');
        \\const absent=byCase['requireProvider missing error shared family no cause'].value;
        \\if(!absent.family||absent.cause||absent.code!=='provider'||absent.message!=='Unknown provider: owned')throw Error('Canonical ModelsError family');
        \\for(const method of ['complete','completeSimple','fetchDeferred'])if(!byCase[method+' fresh intrinsic promise and live receiver'].value.fresh)throw Error('Async request must return fresh promise');
        \\const raw=byCase['complete raw getter failure is asynchronous'].value;if(raw.sync||!raw.same)throw Error('Lost raw async exception');
        \\const cancel=byCase['cancel deferred live getter order and awaited result'].value;
        \\if(!cancel.undefinedResult||JSON.stringify(cancel.trace)!==JSON.stringify([['require',true],'cancel getter','apply getter',['apply call',true,true,true],'requestModel','requestOptions','cancel getter',['cancel call',true,true,true,true]]))throw Error('Deferred request evaluation order');
        \\const known=byCase['createProvider lexical known type coercion and hasOwn'].value;
        \\if(known.ids.join(',')!=='coerced'||JSON.stringify(known.trace)!==JSON.stringify(['hasOwn',['type','string'],'hasOwn']))throw Error('Known type property-key coercion');
        \\const m=api.createModels({credentials:{async read(){return undefined}},modelsStore:{},authContext:{}});
        \\globalThis.retainedActualModels=m;globalThis.retainedActualPrototype=Object.getPrototypeOf(m);
    );
    const namespace = engine.evalModule(source.written(), "native-actual-models-class-owned.mjs") catch |err| {
        std.debug.print("Actual Models class: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(namespace);
    c.JS_RunGC(engine.runtime);
    const after = try engine.evalModule(
        \\if(Object.getPrototypeOf(retainedActualModels)!==retainedActualPrototype)throw Error('Prototype retention');
        \\const provider={id:'owned-retained',getModels(){return[{id:'owned-retained-model'}]}};
        \\retainedActualModels.setProvider(provider);
        \\if(retainedActualModels.getProvider('owned-retained')!==provider||retainedActualModels.getModel('owned-retained','owned-retained-model').id!=='owned-retained-model')throw Error('Class roots after GC');
        \\delete globalThis.retainedActualModels;delete globalThis.retainedActualPrototype;
    , "native-actual-models-class-after-gc.mjs");
    engine.freeValue(after);
    c.JS_RunGC(engine.runtime);
}

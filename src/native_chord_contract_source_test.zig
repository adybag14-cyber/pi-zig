const std = @import("std");
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
const c = em.c;
fn setup(gpa: std.mem.Allocator) !*em.Engine {
    const engine = try em.Engine.init(gpa, .{});
    errdefer engine.deinit();
    engine.native_io = std.testing.io;
    const api = try @import("extensions/native_chord_errors.zig").exports(engine);
    defer engine.freeValue(api);
    const error_class = try js.get(engine, api, "ChordError");
    defer engine.freeValue(error_class);
    const contracts = try @import("extensions/native_chord_contracts.zig").exports(engine, error_class);
    defer engine.freeValue(contracts);
    try js.spreadInto(engine, api, contracts);
    const schema = try @import("extensions/native_chord_schema_api.zig").exports(engine);
    defer engine.freeValue(schema);
    try js.spreadInto(engine, api, schema);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    try js.define(engine, root, "nativeChordContractApi", c.JS_DupValue(engine.context, api));
    return engine;
}
test "native Chord contracts actual19cb identities fingerprints structural compatibility and version binding" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const original = @embedFile("extensions/fixtures/chord-contract-original-19cb.json");
    try js.define(engine, root, "contractSource", try engine.checked(c.JS_ParseJSON(engine.context, original.ptr, original.len, "chord-contract-original-19cb.json")));
    const result = engine.evalModule("const api=nativeChordContractApi;\n" ++ @embedFile("extensions/fixtures/chord-contract-original-19cb.input.txt") ++
        "\nif(chordContractCases.length!==contractSource.cases.length)throw Error('Chord contract Source case count');for(let i=0;i<chordContractCases.length;i++)if(JSON.stringify(chordContractCases[i])!==JSON.stringify(contractSource.cases[i]))throw Error(JSON.stringify({case:i,actual:chordContractCases[i],expected:contractSource.cases[i]}));", "chord-contract-source.mjs") catch |err| {
        std.debug.print("Native Chord contract Source: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
}
test "native Chord contracts token symbols callbacks and schema identities survive owner collection" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    const prepared = try engine.evalModule(
        \\const{local,method,opaque}=nativeChordContractApi;const args={type:'number'},result={type:'string'},token=local('retained',{version:1,input:{},members:{call:method(args,result),owner:opaque('owner@1')}});globalThis.contractRetained={token,args,result};
    , "chord-contract-gc-start.mjs");
    engine.freeValue(prepared);
    c.JS_RunGC(engine.runtime);
    const checked = try engine.evalModule(
        \\const r=contractRetained;if(r.token.description.variants[''].call.args!==r.args||r.token.description.variants[''].call.result!==r.result||nativeChordContractApi.bind(r.token,undefined,r.token)!==undefined)throw Error('contract private symbols or aliases lost');delete globalThis.contractRetained;
    , "chord-contract-gc-end.mjs");
    engine.freeValue(checked);
    c.JS_RunGC(engine.runtime);
}
test "native Chord contracts canonical callbacks and all native owners unwind every allocator failure" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try setup(gpa);
            defer engine.deinit();
            const generation = engine.native_allocation_generation;
            const result = engine.evalModule(
                \\const{local,method,opaque,canonicalIdentity,fits,bind}=nativeChordContractApi;const token=local('owned',{version:1,input:{type:'object'},members:{call:method({type:'number'},{type:'string'}),owner:opaque('owner@1')}});if(bind(token,undefined,token)!==undefined||!fits({type:'integer'},{type:'number'})||canonicalIdentity({properties:{x:{default:1}}},{x:1,y:2})!=='{"y":2}')throw Error('contract result changed');
            , "chord-contract-allocation.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(result);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}

const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const c = v.c;

test "native Anthropic SDK errors preserve genuine class Headers and constructor coercion semantics" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("extensions/native_headers.zig").install(engine);
    var scope: v.Scope = .{ .engine = engine };
    defer scope.deinit();
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(global, "sdkErrors", try scope.own(try @import("extensions/native_ai_anthropic_api_error.zig").create(engine)));
    const result = engine.evalModule(
        \\const {APIError,AnthropicError,BadRequestError,APIConnectionError,APIConnectionTimeoutError}=sdkErrors;
        \\const headers=new Headers({'request-id':'owned-id','anthropic-workspace-id':'owned-workspace'}),body={type:'error',error:{type:'invalid_request_error',message:'owned rejection'}},failure=APIError.generate(400,body,undefined,headers);
        \\if(!(failure instanceof BadRequestError)||!(failure instanceof APIError)||!(failure instanceof AnthropicError)||!(failure instanceof Error)||failure.headers!==headers||failure.error!==body||failure.type!=='invalid_request_error'||failure.requestID!=='owned-id'||failure.workspaceID!=='owned-workspace'||failure.message!=='400 '+JSON.stringify(body))throw Error('SDK class and header identity');
        \\try{new APIConnectionError();throw Error('connection options unexpectedly defaulted')}catch(error){if(!(error instanceof TypeError))throw error}
        \\const marker={};if(new APIConnectionError({message:'',cause:marker}).message!=='Connection error.'||new APIConnectionError({cause:marker}).cause!==marker||new APIConnectionTimeoutError({message:''}).message!=='Connection error.'||new APIConnectionTimeoutError().message!=='Request timed out.')throw Error('connection constructor delegation');
        \\const makeMessage=APIError.makeMessage;try{APIError.makeMessage=()=>undefined;const value=new APIError();if(value.message!=='undefined'||!Object.hasOwn(value,'message'))throw Error('APIError super template coercion')}finally{APIError.makeMessage=makeMessage}
        \\const descriptor=Object.getOwnPropertyDescriptor(APIError,'generate');if(descriptor.enumerable||!descriptor.configurable||!descriptor.writable||APIError.generate.length!==4||Object.hasOwn(APIError.generate,'prototype'))throw Error('SDK static method metadata');
        \\let coercions=0;const raw={toString(){coercions++;throw Error('unexpected diagnostic coercion')}};try{new APIConnectionError({get message(){throw raw}});throw Error('missing options getter failure')}catch(error){if(error!==raw||coercions!==0)throw Error('constructor getter exception changed')}
        \\globalThis.retainedSdkFailure=failure;export const errorClasses=true;
    , "native-anthropic-api-errors.mjs") catch |err| {
        std.debug.print("Anthropic SDK errors: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
    const retained = try engine.evalModule(
        \\if(!(retainedSdkFailure.headers instanceof Headers)||retainedSdkFailure.headers.get('request-id')!=='owned-id'||retainedSdkFailure.type!=='invalid_request_error')throw Error('SDK error fields did not survive collection');delete globalThis.retainedSdkFailure;export const retained=true;
    , "native-anthropic-api-errors-retained.mjs");
    engine.freeValue(retained);
    c.JS_RunGC(engine.runtime);
}

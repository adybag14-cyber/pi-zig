const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const c = v.c;

fn install(engine: *v.em.Engine) !void {
    const Adapter = struct {
        fn predicate(scope: *v.Scope, key: c.JSValue, value: c.JSValue) !bool {
            const callback = try scope.global("strictPredicate");
            if (c.JS_IsUndefined(callback)) return false;
            return scope.truthy(try scope.call(callback, c.pi_js_undefined(), &.{ key, value }));
        }
        fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            var scope: v.Scope = .{ .engine = host };
            defer scope.deinit();
            var reason = c.pi_js_undefined();
            const value = @import("extensions/native_ai_constrained_sampling.zig").makeStrict(&scope, if (args.len > 0) args[0] else c.pi_js_undefined(), &reason, if (args.len > 1 and scope.truthy(args[1])) predicate else null) catch |err| {
                if (err != error.UnsupportedStrictJsonSchema) return err;
                const result = try scope.object();
                try scope.put(result, "unsupported", reason);
                return c.JS_DupValue(host.context, result);
            };
            return c.JS_DupValue(host.context, value);
        }
        fn tools(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            var scope: v.Scope = .{ .engine = host };
            defer scope.deinit();
            const compat = try scope.object();
            try scope.put(compat, "supportsStrictMode", c.pi_js_bool(host.context, 1));
            return @import("extensions/native_ai_openai_tools.zig").convert(host, if (args.len > 0) args[0] else c.pi_js_undefined(), compat);
        }
    };
    var scope: v.Scope = .{ .engine = engine };
    defer scope.deinit();
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(global, "strictSchema", try scope.own(try @import("extensions/native_node_function.zig").create(engine, "strictSchema", 1, Adapter.call, &.{})));
    try scope.put(global, "openAIStrictTools", try scope.own(try @import("extensions/native_node_function.zig").create(engine, "openAIStrictTools", 1, Adapter.tools, &.{})));
}

test "native constrained sampling OpenAI tool conversion delegates to guarded shared schema without swallowing guest errors" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{ .stack_limit = 128 * 1024 });
    defer engine.deinit();
    try install(engine);
    const result = try engine.evalModule(
        \\globalThis.structuredClone=x=>x;const sampling={type:'json_schema',strict:'require'};
        \\const tool={name:'fixture',description:'fixture',constrainedSampling:sampling,parameters:{type:'object',properties:{ok:{type:'boolean'}}}};
        \\const output=openAIStrictTools([tool])[0];if(output.function.strict!==true||output.function.parameters.additionalProperties!==false)throw Error('OpenAI strict delegation');
        \\const cycle={type:'object',properties:{},required:['loop']};cycle.properties.loop=cycle;tool.parameters=cycle;
        \\try{openAIStrictTools([tool]);throw Error('cycle accepted')}catch(error){if(!(error instanceof RangeError))throw error}
        \\const marker={toString(){throw Error('raw reason formatted')}};tool.parameters={type:'object',get properties(){throw marker}};
        \\try{openAIStrictTools([tool]);throw Error('getter accepted')}catch(error){if(error!==marker)throw error}
        \\export const delegated=true;
    , "native-openai-strict-delegation.mjs");
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}

test "native constrained sampling uses configured VM guard for both recursive schema walks" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{ .stack_limit = 128 * 1024 });
    defer engine.deinit();
    try install(engine);
    const result = engine.evalModule(
        \\globalThis.structuredClone=x=>x;
        \\function stackFailure(schema){try{strictSchema(schema);throw Error('cyclic schema unexpectedly returned')}catch(error){if(!(error instanceof RangeError))throw error}}
        \\const cycle={type:'object',properties:{},required:['loop']};cycle.properties.loop=cycle;stackFailure(cycle);
        \\let reads=0;const nullable={type:'string',get anyOf(){return reads++===0?undefined:[nullable]}};stackFailure({type:'object',properties:{nullable}});
        \\const normal=strictSchema({type:'object',properties:{ok:{type:'boolean'}}});if(normal.required[0]!=='ok'||normal.additionalProperties!==false||normal.properties.ok.anyOf[1].type!=='null')throw Error('guard damaged supported conversion');
        \\export const guarded=true;
    , "native-strict-schema-guard.mjs") catch |err| {
        std.debug.print("Strict schema guard: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}

test "native constrained sampling keeps guest predicate and getter exceptions distinct from unsupported schemas" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine);
    const result = engine.evalModule(
        \\globalThis.structuredClone=x=>x;const marker={identity:'guest'};
        \\globalThis.strictPredicate=(key,value)=>{if(key==='explode')throw marker;return key==='minimum'};
        \\try{strictSchema({type:'object',explode:true},true);throw Error('missing predicate exception')}catch(error){if(error!==marker)throw error}
        \\const unsupported=strictSchema({type:'object',minimum:1},true);if(unsupported.unsupported!=='minimum: 1 is unsupported')throw Error('unsupported reason changed');
        \\try{strictSchema({type:'object',get properties(){throw marker}},true);throw Error('missing getter exception')}catch(error){if(error!==marker)throw error}
        \\delete globalThis.strictPredicate;export const guestIdentity=true;
    , "native-strict-schema-errors.mjs") catch |err| {
        std.debug.print("Strict schema errors: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}

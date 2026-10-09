//! Private executable Pi tool validation workflow. Public registration waits for
//! the remaining compiler/reference and argument-clone contract qualification.
const std = @import("std");
const engine_mod = @import("engine.zig");
const vm = @import("native_values.zig");
const clone = @import("native_structured_clone.zig");
const coercion = @import("native_tool_coercion.zig");
const cache = @import("native_tool_validator_cache.zig");
const evaluator = @import("native_tool_validation.zig");
const c = engine_mod.c;
const Engine = engine_mod.Engine;

fn throwError(engine: *Engine, message: []const u8) !c.JSValue {
    return engine.checked(c.JS_Throw(engine.context, try createError(engine, message)));
}
fn createError(engine: *Engine, message: []const u8) !c.JSValue {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const constructor = try vm.get(engine, global, "Error");
    defer engine.freeValue(constructor);
    const text = try engine.checked(c.JS_NewStringLen(engine.context, message.ptr, message.len));
    defer engine.freeValue(text);
    var args = [_]c.JSValue{text};
    return engine.checked(c.JS_CallConstructor(engine.context, constructor, 1, &args));
}
fn objectFunction(engine: *Engine, name: [:0]const u8, args: []const c.JSValue) !c.JSValue {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const object = try vm.get(engine, global, "Object");
    defer engine.freeValue(object);
    return vm.invoke(engine, object, name, args);
}
fn legacyTypeBox(engine: *Engine, schema: c.JSValue) !bool {
    const symbols = try objectFunction(engine, "getOwnPropertySymbols", &.{schema});
    defer engine.freeValue(symbols);
    const marker = try cache.legacySymbol(engine);
    const included = try vm.invoke(engine, symbols, "includes", &.{marker});
    defer engine.freeValue(included);
    return c.JS_ToBool(engine.context, included) != 0;
}
pub fn validateArguments(engine: *Engine, tool: c.JSValue, call: c.JSValue) !c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const original = try vm.get(engine, call, "arguments");
    defer engine.freeValue(original);
    const clone_global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(clone_global);
    const clone_callback = try vm.get(engine, clone_global, "structuredClone");
    defer engine.freeValue(clone_callback);
    var clone_args = [_]c.JSValue{original};
    const args = if (c.JS_IsUndefined(clone_callback)) try clone.clone(engine, original) else try engine.checked(c.JS_Call(engine.context, clone_callback, c.pi_js_undefined(), 1, &clone_args));
    var returned = false;
    defer if (!returned) engine.freeValue(args);
    const validators = cache.validators(engine);
    {
        const parameters = try vm.get(engine, tool, "parameters");
        defer engine.freeValue(parameters);
        try coercion.normalize(engine, parameters, args, validators);
    }
    {
        const parameters = try vm.get(engine, tool, "parameters");
        defer engine.freeValue(parameters);
        const ignored = try coercion.convertTypeBox(engine, parameters, args, validators);
        engine.freeValue(ignored);
    }
    const parameters = try vm.get(engine, tool, "parameters");
    defer engine.freeValue(parameters);
    const validator = try cache.get(engine, parameters);
    defer engine.freeValue(validator);
    const symbol_parameters = try vm.get(engine, tool, "parameters");
    defer engine.freeValue(symbol_parameters);
    if (!try legacyTypeBox(engine, symbol_parameters)) {
        const coerce_parameters = try vm.get(engine, tool, "parameters");
        defer engine.freeValue(coerce_parameters);
        const coerced = try coercion.convertJsonSchema(engine, coerce_parameters, args, validators);
        defer engine.freeValue(coerced);
        if (!c.JS_IsStrictEqual(engine.context, coerced, args)) {
            if (c.JS_IsObject(args) and c.JS_IsObject(coerced)) {
                const names = try objectFunction(engine, "keys", &.{args});
                defer engine.freeValue(names);
                for (0..try vm.length(engine, names)) |index| {
                    const key = try engine.checked(c.JS_GetPropertyUint32(engine.context, names, @intCast(index)));
                    defer engine.freeValue(key);
                    const atom = c.JS_ValueToAtom(engine.context, key);
                    defer c.JS_FreeAtom(engine.context, atom);
                    if (c.JS_DeleteProperty(engine.context, args, atom, c.JS_PROP_THROW) < 0) return error.JavaScriptException;
                }
                const assigned = try objectFunction(engine, "assign", &.{ args, coerced });
                engine.freeValue(assigned);
            } else {
                return c.JS_DupValue(engine.context, if (try cache.check(engine, validator, coerced)) coerced else args);
            }
        }
    }
    if (try cache.check(engine, validator, args)) {
        returned = true;
        return args;
    }
    return engine.checked(c.JS_Throw(engine.context, try validationFailureValue(engine, validator, parameters, args, call)));
}
fn validationFailureValue(engine: *Engine, validator: c.JSValue, parameters: c.JSValue, args: c.JSValue, call: c.JSValue) !c.JSValue {
    const generation = engine.native_allocation_generation;
    return validationFailureValueOwned(engine, validator, parameters, args, call) catch |err| return engine.nativeAllocationError(err, generation);
}
fn validationFailureValueOwned(engine: *Engine, validator: c.JSValue, parameters: c.JSValue, args: c.JSValue, call: c.JSValue) !c.JSValue {
    _ = parameters;
    const errors = try vm.invoke(engine, validator, "Errors", &.{args});
    defer engine.freeValue(errors);
    const formatter = try engine.checked(c.JS_NewCFunction(engine.context, validationErrorLine, "", 1));
    defer engine.freeValue(formatter);
    const lines = try vm.invoke(engine, errors, "map", &.{formatter});
    defer engine.freeValue(lines);
    const separator = try engine.checked(c.JS_NewString(engine.context, "\n"));
    defer engine.freeValue(separator);
    const joined = try vm.invoke(engine, lines, "join", &.{separator});
    defer engine.freeValue(joined);
    const messages = if (c.JS_ToBool(engine.context, joined) != 0) try engine.toString(joined) else try engine.gpa.dupe(u8, "Unknown validation error");
    defer engine.gpa.free(messages);
    const name_value = try vm.get(engine, call, "name");
    defer engine.freeValue(name_value);
    const name = try engine.toString(name_value);
    defer engine.gpa.free(name);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const json = try vm.get(engine, global, "JSON");
    defer engine.freeValue(json);
    const stringify = try vm.get(engine, json, "stringify");
    defer engine.freeValue(stringify);
    const received_value = try vm.get(engine, call, "arguments");
    defer engine.freeValue(received_value);
    var encoded_args = [_]c.JSValue{ received_value, c.pi_js_null(), c.pi_js_int32(engine.context, 2) };
    const encoded = try engine.checked(c.JS_Call(engine.context, stringify, json, encoded_args.len, &encoded_args));
    defer engine.freeValue(encoded);
    const received = try engine.toString(encoded);
    defer engine.gpa.free(received);
    const message = try std.fmt.allocPrint(engine.gpa, "Validation failed for tool \"{s}\":\n{s}\n\nReceived arguments:\n{s}", .{ name, messages, received });
    defer engine.gpa.free(message);
    return createError(engine, message);
}
fn validationErrorLine(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return validationErrorLineOwned(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| {
        if (err == error.OutOfMemory) return engine.throwNativeOutOfMemory();
        return engine.throwCaptured();
    };
}
fn formattedErrorPath(engine: *Engine, error_value: c.JSValue) ![]u8 {
    const keyword = try vm.get(engine, error_value, "keyword");
    defer engine.freeValue(keyword);
    var required = c.pi_js_undefined();
    defer engine.freeValue(required);
    if (c.JS_IsString(keyword)) {
        const name = try engine.toString(keyword);
        defer engine.gpa.free(name);
        if (std.mem.eql(u8, name, "required")) {
            const params = try vm.get(engine, error_value, "params");
            defer engine.freeValue(params);
            const properties = try vm.get(engine, params, "requiredProperties");
            defer engine.freeValue(properties);
            if (!c.JS_IsUndefined(properties) and !c.JS_IsNull(properties)) required = try engine.checked(c.JS_GetPropertyUint32(engine.context, properties, 0));
        }
    }
    const path = try vm.get(engine, error_value, "instancePath");
    defer engine.freeValue(path);
    const regexp = @import("native_schema_regexp.zig");
    const start_text = try engine.checked(c.JS_NewString(engine.context, "^/"));
    defer engine.freeValue(start_text);
    const leading = try regexp.construct(engine, engine.intrinsic_regexp_constructor, start_text, null);
    defer engine.freeValue(leading);
    const empty = try engine.checked(c.JS_NewString(engine.context, ""));
    defer engine.freeValue(empty);
    const stripped = try vm.invoke(engine, path, "replace", &.{ leading, empty });
    defer engine.freeValue(stripped);
    const slash_text = try engine.checked(c.JS_NewString(engine.context, "/"));
    defer engine.freeValue(slash_text);
    const flags = try engine.checked(c.JS_NewString(engine.context, "g"));
    defer engine.freeValue(flags);
    const slashes = try regexp.construct(engine, engine.intrinsic_regexp_constructor, slash_text, flags);
    defer engine.freeValue(slashes);
    const dot = try engine.checked(c.JS_NewString(engine.context, "."));
    defer engine.freeValue(dot);
    const dotted = try vm.invoke(engine, stripped, "replace", &.{ slashes, dot });
    defer engine.freeValue(dotted);
    const base = try engine.toString(dotted);
    defer engine.gpa.free(base);
    if (c.JS_ToBool(engine.context, required) != 0) {
        const property = try engine.toString(required);
        defer engine.gpa.free(property);
        return if (c.JS_ToBool(engine.context, dotted) != 0) std.fmt.allocPrint(engine.gpa, "{s}.{s}", .{ base, property }) else engine.gpa.dupe(u8, property);
    }
    return engine.gpa.dupe(u8, if (c.JS_ToBool(engine.context, dotted) != 0) base else "root");
}
fn validationErrorLineOwned(engine: *Engine, error_value: c.JSValue) !c.JSValue {
    const path = try formattedErrorPath(engine, error_value);
    defer engine.gpa.free(path);
    const message_value = try vm.get(engine, error_value, "message");
    defer engine.freeValue(message_value);
    const message = try engine.toString(message_value);
    defer engine.gpa.free(message);
    const line = try std.fmt.allocPrint(engine.gpa, "  - {s}: {s}", .{ path, message });
    defer engine.gpa.free(line);
    return engine.checked(c.JS_NewStringLen(engine.context, line.ptr, line.len));
}
pub fn validateCall(engine: *Engine, tools: c.JSValue, call: c.JSValue) !c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    var captures = [_]c.JSValue{call};
    const predicate = try engine.checked(c.JS_NewCFunctionData(engine.context, toolMatches, 1, 0, captures.len, &captures));
    defer engine.freeValue(predicate);
    const tool = try vm.invoke(engine, tools, "find", &.{predicate});
    defer engine.freeValue(tool);
    if (c.JS_ToBool(engine.context, tool) != 0) return validateArguments(engine, tool, call);
    const name_value = try vm.get(engine, call, "name");
    defer engine.freeValue(name_value);
    const name = try engine.toString(name_value);
    defer engine.gpa.free(name);
    const message = try std.fmt.allocPrint(engine.gpa, "Tool \"{s}\" not found", .{name});
    defer engine.gpa.free(message);
    return throwError(engine, message);
}
fn toolMatches(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return toolMatchesOwned(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), data[0]) catch |err| {
        if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(context);
        return engine.throwCaptured();
    };
}
fn toolMatchesOwned(engine: *Engine, tool: c.JSValue, call: c.JSValue) !c.JSValue {
    const actual = try vm.get(engine, tool, "name");
    defer engine.freeValue(actual);
    const expected = try vm.get(engine, call, "name");
    defer engine.freeValue(expected);
    return c.pi_js_bool(engine.context, @intFromBool(c.JS_IsStrictEqual(engine.context, actual, expected)));
}
fn callback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const first = if (argc > 0) argv[0] else c.pi_js_undefined();
    const second = if (argc > 1) argv[1] else c.pi_js_undefined();
    return (if (magic == 0) validateArguments(engine, first, second) else validateCall(engine, first, second)) catch |err| {
        if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(context);
        if (err == error.JavaScriptException) return engine.throwCaptured();
        return c.JS_ThrowTypeError(context, "Tool validation: %s", @as([*:0]const u8, @errorName(err)));
    };
}
/// Install Pi's public validation functions before extension input. Every
/// root/subpath alias retains these exact function and module-state values.
pub fn install(engine: *Engine, exports: c.JSValue) !void {
    try cache.initializeOwnerState(engine);
    const arguments = try engine.checked(c.JS_NewCFunctionMagic(engine.context, callback, "validateToolArguments", 2, c.JS_CFUNC_generic_magic, 0));
    defer engine.freeValue(arguments);
    const call = try engine.checked(c.JS_NewCFunctionMagic(engine.context, callback, "validateToolCall", 2, c.JS_CFUNC_generic_magic, 1));
    defer engine.freeValue(call);
    try vm.put(engine, exports, "validateToolArguments", c.JS_DupValue(engine.context, arguments));
    try vm.put(engine, exports, "validateToolCall", c.JS_DupValue(engine.context, call));
    const validation = try vm.object(engine);
    defer engine.freeValue(validation);
    try vm.put(engine, validation, "validateToolArguments", c.JS_DupValue(engine.context, arguments));
    try vm.put(engine, validation, "validateToolCall", c.JS_DupValue(engine.context, call));
    inline for (.{ "@earendil-works/pi-ai/utils/validation", "@mariozechner/pi-ai/utils/validation", "pi-ai/utils/validation" }) |name| try engine.registerValueModule(name, validation);
}
pub fn testFunctions(engine: *Engine) !void {
    try cache.initializeOwnerState(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try vm.put(engine, global, "validateToolArguments", try engine.checked(c.JS_NewCFunctionMagic(engine.context, callback, "validateToolArguments", 2, c.JS_CFUNC_generic_magic, 0)));
    try vm.put(engine, global, "validateToolCall", try engine.checked(c.JS_NewCFunctionMagic(engine.context, callback, "validateToolCall", 2, c.JS_CFUNC_generic_magic, 1)));
    try vm.put(engine, global, "nativeDefaultClone", try engine.checked(c.JS_NewCFunction(engine.context, defaultClone, "nativeDefaultClone", 1)));
    try vm.put(engine, global, "nativeTypeConvert", try engine.checked(c.JS_NewCFunction(engine.context, defaultTypeConvert, "nativeTypeConvert", 2)));
    try vm.put(engine, global, "nativeTypeEvaluate", try engine.checked(c.JS_NewCFunction(engine.context, defaultTypeEvaluate, "nativeTypeEvaluate", 1)));
    try vm.put(engine, global, "nativeRegExp", try engine.checked(c.JS_NewCFunction(engine.context, defaultRegExp, "nativeRegExp", 2)));
}
fn defaultRegExp(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return @import("native_schema_regexp.zig").construct(engine, engine.intrinsic_regexp_constructor, if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else null) catch |err| {
        if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(context);
        return engine.throwCaptured();
    };
}
fn defaultTypeEvaluate(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const schema = if (argc > 0) argv[0] else c.pi_js_undefined();
    const kind = vm.get(engine, schema, "~kind") catch return engine.throwCaptured();
    defer engine.freeValue(kind);
    const label = engine.toString(kind) catch return engine.throwCaptured();
    defer engine.gpa.free(label);
    return coercion.evaluateLiteralKind(engine, schema, std.mem.eql(u8, label, "Enum")) catch |err| {
        if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(context);
        return engine.throwCaptured();
    };
}
fn defaultTypeConvert(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return coercion.convertTypeBox(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined(), cache.validators(engine)) catch |err| {
        if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(context);
        return engine.throwCaptured();
    };
}
fn defaultClone(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return clone.clone(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| {
        if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(context);
        return engine.throwCaptured();
    };
}

fn pipelineAllocationExercise(gpa: std.mem.Allocator) !void {
    const engine = try Engine.init(gpa, .{});
    defer engine.deinit();
    const fixture = try engine.eval("(()=>{const tag=(kind,schema)=>Object.defineProperty(schema,'~kind',{value:kind});return {tool:{parameters:tag('Object',{type:'object',properties:{n:tag('Integer',{type:'integer',minimum:1}),e:tag('Enum',{enum:[1,2]}),p:tag('TemplateLiteral',{type:'string',pattern:'^(a|b)$'}),ref:{$ref:'#/$defs/number'},items:tag('Array',{type:'array',items:tag('Number',{type:'number'})})},required:['n','e','p','ref','items'],$defs:{number:{type:'number',minimum:1}}})},call:{name:'fixture',arguments:{n:'3.7',e:'1',p:'a',ref:2,items:['1','2']}}}})()", "tool-pipeline-gpa-fixture", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(fixture);
    const tool = try vm.get(engine, fixture, "tool");
    defer engine.freeValue(tool);
    const call = try vm.get(engine, fixture, "call");
    defer engine.freeValue(call);
    const result = try validateArguments(engine, tool, call);
    defer engine.freeValue(result);
}
test "native durable VM full successful tool argument clone normalize typed conversion compiled references and JSON coercion unwind every allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, pipelineAllocationExercise, .{});
}
fn failureAllocationExercise(gpa: std.mem.Allocator) !void {
    const engine = try Engine.init(gpa, .{});
    defer engine.deinit();
    const fixture = try engine.eval("({schema:{type:'object',properties:{s:{type:'string',minLength:4,pattern:'^x'},n:{type:'number',minimum:3},items:{type:'array',items:false}},required:['s','n'],additionalProperties:false},args:{s:'bad',n:1,items:[1,2],extra:true},call:{name:'fixture',arguments:{s:'original',n:1}}})", "tool-failure-gpa-fixture", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(fixture);
    const schema = try vm.get(engine, fixture, "schema");
    defer engine.freeValue(schema);
    const args = try vm.get(engine, fixture, "args");
    defer engine.freeValue(args);
    const call = try vm.get(engine, fixture, "call");
    defer engine.freeValue(call);
    const compiled = try cache.get(engine, schema);
    defer engine.freeValue(compiled);
    const result = try validationFailureValue(engine, compiled, schema, args, call);
    defer engine.freeValue(result);
}
test "native durable VM failed tool argument validation builds complete owned Error and received JSON before diagnostics under every allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, failureAllocationExercise, .{});
}

test "native durable VM private tool validation workflow matches original nineteen coercion error format cases and mutable schema cache" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("typebox.zig").install(engine);
    try testFunctions(engine);
    errdefer std.debug.print("Tool validation VM failure: {s}\n", .{engine.last_error orelse "none"});
    const output = try engine.evalModule(
        \\import * as Type from 'typebox';
        \\const tagged={type:'object',properties:{n:{type:'number'}},required:['n'],[Symbol.for('TypeBox.Kind')]:'Object'},cases=[
        \\['plain-coerce',{type:'object',properties:{n:{type:'number'},s:{type:'string'},b:{type:'boolean'},optional:{type:'number'}},required:['n','s','b']},{n:'0x10',s:null,b:'true',optional:null}],
        \\['typed-coerce',Type.Object({n:Type.Number(),s:Type.String(),b:Type.Boolean(),optional:Type.Optional(Type.Number())}),{n:'TRUE',s:null,b:'FALSE',optional:null}],
        \\['symbol-stops-plain-coercion',tagged,{n:'3'}],
        \\['missing-many',{type:'object',properties:{n:{type:'number'},s:{type:'string',minLength:4}},required:['n','s'],additionalProperties:false},{extra:1}],
        \\['constraints',{type:'object',properties:{n:{type:'number',minimum:10,multipleOf:3},s:{type:'string',minLength:4,pattern:'^x'},a:{type:'array',minItems:2,uniqueItems:true,items:{type:'integer'}}},required:['n','s','a']},{n:5,s:'a',a:[1,1]}],
        \\['union',{anyOf:[{type:'string',minLength:2},{type:'number',minimum:10}]},false],
        \\['oneOf-many',{oneOf:[{type:'number'},{type:'integer'}]},3],
        \\['ref-local',{$defs:{n:{type:'number'}},type:'object',properties:{value:{$ref:'#/$defs/n'}},required:['value']},{value:2}],
        \\['ref-invalid',{$defs:{n:{type:'number'}},type:'object',properties:{value:{$ref:'#/$defs/n'}},required:['value']},{value:'2'}],
        \\['ref-optional-null',{$defs:{n:{type:'number'}},type:'object',properties:{value:{$ref:'#/$defs/n'}}},{value:null}],
        \\['ref-missing',{$ref:'#/$defs/missing'},{}],
        \\['format-email',{type:'string',format:'email'},'invalid'],
        \\['format-date',{type:'string',format:'date'},'2024-02-29'],
        \\['format-unknown',{type:'string',format:'fixture.unknown'},'anything'],
        \\['if-then',{type:'object',if:{required:['enabled']},then:{required:['value']}},{enabled:true}],
        \\['dependent-required',{type:'object',dependentRequired:{a:['b','c']}},{a:1}],
        \\['contains',{type:'array',contains:{type:'number',minimum:3},minContains:2,maxContains:3},[1,2]],
        \\['unevaluated',{allOf:[{properties:{a:{type:'number'}}}],unevaluatedProperties:false},{a:1,b:2}],
        \\['primitive-coerced-invalid',{type:'number',minimum:10},null],
        \\];
        \\const output=[];for(const [name,parameters,args] of cases){const tool={name:'fixture',parameters},call={id:'id',name:'fixture',arguments:args};try{const value=validateToolArguments(tool,call);output.push({name,value,input:args,detached:typeof value!=='object'||value===null||value!==args})}catch(error){output.push({name,error:{name:error.name,message:error.message}})}}
        \\const parameters={type:'object',properties:{n:{type:'number'}},required:['n']},tool={name:'mutable',parameters};validateToolArguments(tool,{id:'one',name:'mutable',arguments:{n:1}});parameters.properties.n.type='string';let cached;try{cached=validateToolArguments(tool,{id:'two',name:'mutable',arguments:{n:1}})}catch(error){cached={error:error.message}}
        \\let missing;try{validateToolCall([tool],{id:'missing',name:'absent',arguments:{}})}catch(error){missing={name:error.name,message:error.message}}globalThis.result=JSON.stringify({output,cached,missing});
        \\
    , "native-tool-validation-source-corpus");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-tool-validation-result", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer engine.gpa.free(text);
    try std.testing.expectEqualStrings(std.mem.trim(u8, @embedFile("../durable/fixtures/tool-validation-complete-1ced.json"), "\r\n "), text);
}

test "native durable VM tool refinement callbacks retain receiver error identity and original short circuit order" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("typebox.zig").install(engine);
    try testFunctions(engine);
    errdefer std.debug.print("Tool refinement VM failure: {s}\n", .{engine.last_error orelse "none"});
    const output = try engine.evalModule(
        \\import {Format} from 'typebox/format';
        \\const output=[];
        \\for(const [name,value] of [['valid',4],['refine-fail',3],['type-fail','bad']]){
        \\ const events=[],one={check(v){events.push(['one',v,this===one]);return v%2===0},error(v){events.push(['message-one',v,this===one]);return 'even expected'}},two={check(v){events.push(['two',v,this===two]);return v>10},error(v){events.push(['message-two',v,this===two]);return 'large expected'}};
        \\ const schema={type:'number','~refine':[one,two]};try{output.push({name,value:validateToolArguments({parameters:schema},{name:'fixture',arguments:value}),events})}catch(error){output.push({name,error:{name:error.name,message:error.message},events})}
        \\}
        \\const events=[];Format.Set('fixture',v=>{events.push(v);return false});try{validateToolArguments({parameters:{type:'string',minLength:5,format:'fixture'}},{name:'fixture',arguments:'bad'})}catch(error){output.push({name:'format-shortcircuit',error:{name:error.name,message:error.message},events})}Format.Reset();
        \\globalThis.result=JSON.stringify(output);
    , "native-tool-refinement-source-corpus");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-tool-refinement-result", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer engine.gpa.free(text);
    try std.testing.expectEqualStrings(std.mem.trim(u8, @embedFile("../durable/fixtures/tool-validation-refinements-1ced.json"), "\r\n "), text);
}

test "native durable VM tool validation preserves repeated schema getter order clone overrides original thrown errors and tools find callbacks" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try testFunctions(engine);
    errdefer std.debug.print("Tool accessor VM failure: {s}\n", .{engine.last_error orelse "none"});
    const output = try engine.evalModule(
        \\globalThis.structuredClone=nativeDefaultClone;
        \\const clone=globalThis.structuredClone,output=[];
        \\for(const invalid of [false,true]){
        \\ const events=[];let reads=0,argsReads=0;const schema={type:'object',properties:{n:{type:'number'}}},tool={get parameters(){events.push(['parameters',++reads]);return schema}},call={get name(){events.push('name');return 'fixture'},get arguments(){events.push(['arguments',++argsReads]);return {n:invalid?(argsReads===1?'bad':'received'):'3'}}};
        \\ globalThis.structuredClone=function(v){'use strict';events.push(['clone',this===undefined]);return clone(v)};
        \\ try{output.push({invalid,value:validateToolArguments(tool,call),events})}catch(error){output.push({invalid,error:{name:error.name,message:error.message},events})}
        \\}
        \\const events=[],raw=new Error('getter clone');raw.name='DataCloneError';globalThis.structuredClone=()=>{throw raw};try{validateToolArguments({get parameters(){events.push('unexpected');return {}}},{arguments:{}})}catch(error){output.push({cloneError:error===raw,events})}globalThis.structuredClone=clone;
        \\const tools=[{name:'other',parameters:{type:'object'}}],call={name:'fixture',arguments:{n:'3'}};let find;tools.find=function(predicate){find={receiver:this===tools,arity:predicate.length,predicate:predicate({name:'fixture'})};return {name:'chosen',parameters:{type:'object',properties:{n:{type:'number'}}}}};output.push({findValue:validateToolCall(tools,call),find});globalThis.result=JSON.stringify(output);
    , "native-tool-accessor-source-corpus");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-tool-accessor-result", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer engine.gpa.free(text);
    try std.testing.expectEqualStrings(std.mem.trim(u8, @embedFile("../durable/fixtures/tool-validation-accessor-order-1ced.json"), "\r\n "), text);
}

test "native durable VM coercion cycles reject with original RangeError while repeated shared values remain aliased" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("typebox.zig").install(engine);
    try testFunctions(engine);
    const output = try engine.evalModule(
        \\import * as T from 'typebox';
        \\const output=[],schema={type:'object',properties:{}},value={};schema.properties.self=schema;value.self=value;try{validateToolArguments({parameters:schema},{name:'fixture',arguments:value})}catch(error){output.push({name:'normalize-cycle',error:{name:error.name,message:error.message}})}
        \\const ref=Object.defineProperty({$id:'Node',$ref:'Node'},'~kind',{value:'Ref'}),cyclic=Object.defineProperty({$defs:{Node:ref},$ref:'Node'},'~kind',{value:'Cyclic'});try{nativeTypeConvert(cyclic,NaN)}catch(error){output.push({name:'typed-nan-cycle',error:{name:error.name,message:error.message}})}
        \\const shared={n:'3'},member=T.Object({n:T.Number()}),result=validateToolArguments({parameters:T.Object({a:member,b:member})},{name:'fixture',arguments:{a:shared,b:shared}});output.push({name:'shared',same:result.a===result.b,value:result.a.n,input:shared.n});globalThis.result=JSON.stringify(output);
    , "native-coercion-cycle-source-corpus");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-coercion-cycle-result", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer engine.gpa.free(text);
    try std.testing.expectEqualStrings(std.mem.trim(u8, @embedFile("../durable/fixtures/tool-coercion-cycles-shared-1ced.json"), "\r\n "), text);
}
test "native durable VM primitive TypeBox conversion matches all eight original kinds across special numbers strings booleans BigInts and absence" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try testFunctions(engine);
    errdefer std.debug.print("Primitive conversion VM failure: {s}\n", .{engine.last_error orelse "none"});
    const output = try engine.evalModule(
        \\const kinds=['Number','Integer','String','Boolean','Null','BigInt','Undefined','Void'],values=[undefined,null,true,false,'','  ','TRUE','false','1','01','1.2','-1.2','17n','001n','1N','Infinity','NaN','0x10','-1e2',17n,9007199254740992n,NaN,Infinity,-Infinity,0,-0,1,2,{},[],'NULL','undefined','0'];
        \\function describe(value){return typeof value==='bigint'?{type:'bigint',value:String(value)}:value===undefined?{type:'undefined'}:typeof value==='number'&&!Number.isFinite(value)?{type:'number',value:String(value)}:Object.is(value,-0)?{type:'number',value:'-0'}:{type:typeof value,value}}
        \\const output=[];for(const kind of kinds)for(let index=0;index<values.length;index++){try{output.push({kind,index,result:describe(nativeTypeConvert(Object.defineProperty({},'~kind',{value:kind}),nativeDefaultClone(values[index])))})}catch(error){output.push({kind,index,error:{name:error.name,message:error.message}})}}globalThis.result=JSON.stringify(output);
    , "native-primitive-conversion-source-corpus");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-primitive-conversion-result", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer engine.gpa.free(text);
    try std.testing.expectEqualStrings(std.mem.trim(u8, @embedFile("../durable/fixtures/typebox-primitive-conversion-matrix-1ced.json"), "\r\n "), text);
}

test "native durable VM finite pattern grammar and Enum evaluation match original expansion conversion ordering and invalid literal errors" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try testFunctions(engine);
    errdefer std.debug.print("Pattern Enum VM failure: {s}\n", .{engine.last_error orelse "none"});
    const output = try engine.evalModule(
        \\const patterns=['^x$','^(a|b)$','^(a|b)(1|2)$','^a|b$','^$','^()$','^(a|)$','^(|a)$','^((a|b)|c)$','^a.*$','^-?(?:0|[1-9][0-9]*)$','^(?!)$','^(true|false)$','^1$','^17n$','^a\\.b$','^a\\|b$','^[ab]$','^a+$','^a{2}$','^a$rest','bad','^^$',' ^x$','^ /*c*/ x$','^x/*c*/$','^x//c\n$','^a(b|c)d$','^((a)(b))$','^a(b|c)(d|e)$','^a(b|c|d)$','^a(b|c$','^a)$','^.*x$','^a-?(?:0|[1-9][0-9]*)n$','^a-?(?:0|[1-9][0-9]*)(?:\\.[0-9]+)?$','^((a|b)(c|d))$','^(a|a|b)$','^a b$','^Ω(猫|犬)$'];
        \\const enums=[[1,2],['1','2'],[true,false],[1,'1'],[17n,'17'],[],[1,1,2],['x'],[null],[undefined],[NaN],[{}]];
        \\const inputs=[undefined,null,true,false,0,1,2,'1','2','TRUE','x','ab','a1','b2',17n,{},[]];
        \\const describe=value=>typeof value==='bigint'?{type:'bigint',value:String(value)}:value===undefined?{type:'undefined'}:{type:typeof value,value};
        \\const tagged=(kind,schema)=>Object.defineProperty(schema,'~kind',{value:kind});
        \\const output=[];
        \\for(const [kind,fields] of [['TemplateLiteral',patterns.map(pattern=>({type:'string',pattern}))],['Enum',enums.map(values=>({enum:values}))]])for(let index=0;index<fields.length;index++){
        \\ const schema=tagged(kind,fields[index]);let evaluated;try{const value=nativeTypeEvaluate(schema);evaluated={kind:value['~kind'],schema:value}}catch(error){evaluated={error:{name:error.name,message:error.message,cause:error.cause&&describe(error.cause.value)}}}
        \\ const results=inputs.map(input=>{try{return describe(nativeTypeConvert(schema,nativeDefaultClone(input)))}catch(error){return {error:{name:error.name,message:error.message,cause:error.cause&&describe(error.cause.value)}}}});output.push({kind,index,evaluated,results});
        \\}
        \\globalThis.result=JSON.stringify(output,(_,value)=>typeof value==='bigint'?String(value)+'n':value);
    , "native-pattern-enum-source-corpus");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-pattern-enum-result", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer engine.gpa.free(text);
    try std.testing.expectEqualStrings(std.mem.trim(u8, @embedFile("../durable/fixtures/typebox-pattern-enum-conversion-1ced.json"), "\r\n "), text);
}
test "native durable VM TypeBox union candidate checks use original dynamic context and exhaustive branch evaluation" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try testFunctions(engine);
    errdefer std.debug.print("Contextual union VM failure: {s}\n", .{engine.last_error orelse "none"});
    const output = try engine.evalModule(
        \\const tag=(kind,schema)=>Object.defineProperty(schema,'~kind',{value:kind}),N=()=>tag('Number',{type:'number'}),B=()=>tag('Boolean',{type:'boolean'}),U=rules=>tag('Union',{anyOf:rules}),R=name=>tag('Ref',{$ref:name}),C=(defs,root)=>tag('Cyclic',{$defs:defs,$ref:root});
        \\const output=[];const describe=value=>value===undefined?{type:'undefined'}:{type:typeof value,value};
        \\function run(name,create,input){const events=[],raw={marker:true};try{const result=nativeTypeConvert(create(events,raw),input);output.push({name,result:describe(result),events})}catch(error){output.push({name,error:error===raw?'raw':{name:error.name,message:error.message},events})}}
        \\run('context-ref-number',()=>C({Number:N(),Root:U([R('Number'),B()])},'Root'),'3');
        \\run('context-ref-boolean',()=>C({Number:N(),Root:U([R('Number'),B()])},'Root'),'true');
        \\run('context-nested-ref',()=>C({Number:N(),Member:R('Number'),Root:U([R('Member'),B()])},'Root'),'4');
        \\run('context-ref-missing',()=>C({Root:U([R('missing'),B()])},'Root'),'true');
        \\run('dynamic-invalid-regexp',()=>U([{type:'string',pattern:'['},N()]),'3');
        \\run('candidate-check-all',(events)=>U([Object.assign(N(),{'~refine':[{check(v){events.push(['n',v]);return v===3},error(){events.push('unexpected-error');return 'bad'}}]}),Object.assign(B(),{'~refine':[{check(v){events.push(['b',v]);return true},error(){events.push('unexpected-error');return 'bad'}}]})]),'3');
        \\run('candidate-check-raw-after-success',(events,raw)=>U([N(),{'~refine':[{check(v){events.push(v);if(typeof v==='number')throw raw;return false},error(){return 'bad'}}]}]),'3');
        \\run('candidate-check-undefined-stop',(events)=>U([tag('Undefined',{type:'undefined'}),Object.assign(N(),{'~refine':[{check(v){events.push(v);return true},error(){return 'bad'}}]})]),null);
        \\run('candidate-all-convert-before-selection',(events,raw)=>U([N(),Object.defineProperty({},'~kind',{get(){events.push('kind');throw raw}})]),'3');
        \\globalThis.result=JSON.stringify(output);
    , "native-contextual-union-source-corpus");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-contextual-union-result", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer engine.gpa.free(text);
    try std.testing.expectEqualStrings(std.mem.trim(u8, @embedFile("../durable/fixtures/typebox-contextual-union-1ced.json"), "\r\n "), text);
}
test "native durable VM intrinsic schema regular expression diagnostics match original Unicode and legacy errors" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try testFunctions(engine);
    const output = try engine.evalModule(
        \\const patterns=['[','(','a)','a\\','*','+','?','a{2,1}','a{','a}','[z-a]','[\\d-a]','[a-\\d]','\\x','\\u','\\u{110000}','\\c','\\1','(?','(?x)','(?<a>x)(?<a>y)','(?<1>x)','\\k<x>','a**','(?=a)*','[a','[^','[\\p{Bad}]','\\p{Bad}','\\q','a{999999999999999999999999999999}','(?<=a)','[\\u{110000}]','[]','(?!)','[a/b]','(?>a)'];
        \\const output=[];for(const flags of ['u',''])for(const pattern of patterns){try{const value=nativeRegExp(pattern,flags);output.push({pattern,flags,source:value.source})}catch(error){output.push({pattern,flags,error:{name:error.name,message:error.message}})}}globalThis.result=JSON.stringify(output);
    , "native-intrinsic-regexp-errors");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-regexp-errors-result", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer engine.gpa.free(text);
    try std.testing.expectEqualStrings(std.mem.trim(u8, @embedFile("../durable/fixtures/schema-intrinsic-regexp-errors-1ced.json"), "\r\n "), text);
}

test "native durable VM logical and contains predicates retain original callback order exhaustive counts sparse arrays and minContains zero" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try testFunctions(engine);
    errdefer std.debug.print("Predicate callback VM failure: {s}\n", .{engine.last_error orelse "none"});
    const output = try engine.evalModule(
        \\const output=[];
        \\for(const [name,fields,input]of [['contains-all',{contains:true},[1,2]],['contains-false',{contains:false},[1,2]],['contains-bounds',{contains:true,minContains:3,maxContains:1},[1,2]],['contains-zero',{contains:true,minContains:0},[]],['contains-minzero-callbacks',{contains:true,minContains:0},[1,2]],['contains-sparse',{contains:true,minContains:2},[,2]],['not-false',{not:false},1],['not-true',{not:true},1],['allof-exhaustive',{allOf:[false,false,true]},1],['oneof-exhaustive',{oneOf:[true,true,true]},1]]){
        \\ const events=[],refine=(label,pass)=>({'~refine':[{check(v){events.push(['check',label,v]);return pass},error(v){events.push(['error',label,v]);return label}}]}),schema={type:Array.isArray(input)?'array':'number',...fields};
        \\ if('contains'in fields)schema.contains=refine('item',fields.contains);
        \\ if('not'in fields)schema.not=refine('not',fields.not);
        \\ if('allOf'in fields)schema.allOf=fields.allOf.map((pass,i)=>refine('all'+i,pass));
        \\ if('oneOf'in fields)schema.oneOf=fields.oneOf.map((pass,i)=>refine('one'+i,pass));
        \\ try{output.push({name,result:validateToolArguments({parameters:schema},{name:'fixture',arguments:input}),events})}catch(error){output.push({name,error:{name:error.name,message:error.message},events})}
        \\}
        \\globalThis.result=JSON.stringify(output);
    , "native-predicate-callback-source-corpus");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-predicate-callback-result", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer engine.gpa.free(text);
    try std.testing.expectEqualStrings(std.mem.trim(u8, @embedFile("../durable/fixtures/schema-predicate-callback-order-1ced.json"), "\r\n "), text);
}
test "native durable VM full object array and logical tool schema keyword errors match original localized paths and limits" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try testFunctions(engine);
    errdefer std.debug.print("Full keyword VM failure: {s}\n", .{engine.last_error orelse "none"});
    const output = try engine.evalModule(
        \\const cases=[
        \\ ['property-names-pattern',{propertyNames:{pattern:'^x'}},{a:1,b:2}],
        \\ ['property-names-multiple',{propertyNames:{minLength:3,pattern:'^x'}},{a:1,bb:2}],
        \\ ['property-names-nested',{properties:{child:{propertyNames:{pattern:'^x'}}}},{child:{a:1}}],
        \\ ['property-names-all-false',{propertyNames:false},{a:1,b:2}],
        \\ ['property-names-valid',{propertyNames:{pattern:'^x'}},{xyz:1}],
        \\ ['property-optional-undefined',{properties:{n:{type:'number'}}},{n:undefined}],
        \\ ['property-required-undefined',{properties:{n:{type:'number'}},required:['n']},{n:undefined}],
        \\ ['required-empty',{required:['','b']},{}],
        \\ ['required-escaped',{required:['a/b','c~d']},{}],
        \\ ['nested-required',{properties:{child:{required:['value']}}},{child:{}}],
        \\ ['additional-schema',{properties:{a:{type:'string'}},additionalProperties:{type:'number',minimum:10}},{a:'yes',b:1,c:'bad'}],
        \\ ['additional-schema-multiple',{additionalProperties:{type:'string',minLength:3}},{a:1,b:true}],
        \\ ['patterns-multiple',{patternProperties:{'^x':{type:'string'},'x$':{type:'number'}}},{x:true}],
        \\ ['dependencies-schema',{dependencies:{a:{required:['b']}}},{a:1}],
        \\ ['dependent-schema',{dependentSchemas:{a:{properties:{b:{type:'number'}},required:['b']}}},{a:1,b:'bad'}],
        \\ ['dependent-required-duplicates',{dependentRequired:{a:['b','b','c']}},{a:1}],
        \\ ['property-bounds-fraction',{minProperties:2.5,maxProperties:0.5},{a:1}],
        \\ ['property-bounds-negative-zero',{maxProperties:-0},{a:1}],
        \\ ['items-false',{items:false},[1,2]],
        \\ ['items-array-additional-false',{items:[{type:'number'}],additionalItems:false},[1,2,3]],
        \\ ['items-array-missing',{items:[{type:'number'},{type:'string'}]},[1]],
        \\ ['prefix-overflow',{prefixItems:[{type:'number'}],items:false},[1,2,3]],
        \\ ['prefix-items-same',{prefixItems:[{type:'string'}],items:{type:'boolean'}},[1,2,3]],
        \\ ['items-sparse',{items:{type:'number'}},[,1,,]],
        \\ ['array-bounds-fraction',{minItems:2.5,maxItems:0.5},[1]],
        \\ ['contains-zero-empty',{contains:false,minContains:0},[]],
        \\ ['contains-zero-invalid',{contains:false,minContains:0},[1]],
        \\ ['contains-bounds',{contains:{type:'number'},minContains:3,maxContains:1},[1,'bad',2]],
        \\ ['unevaluated-nested',{properties:{a:true},unevaluatedProperties:false},{a:1,b:2,c:3}],
        \\ ['unevaluated-array',{prefixItems:[true],unevaluatedItems:false},[1,2,3]],
        \\ ['conditional-then',{if:{required:['a']},then:{properties:{b:{type:'number'}},required:['b']}},{a:1,b:'bad'}],
        \\ ['conditional-else',{if:{required:['a']},else:{properties:{b:{type:'number'}},required:['b']}},{b:'bad'}],
        \\ ['many-errors',{properties:{a:false,b:false,c:false,d:false,e:false,f:false,g:false,h:false,i:false}},{a:1,b:2,c:3,d:4,e:5,f:6,g:7,h:8,i:9}],
        \\ ['allof-path',{allOf:[{properties:{a:false}},{properties:{b:false}}]},{a:1,b:2}],
        \\ ['type-array',{type:['number','string']},true],
        \\ ['type-empty',{type:[]},1],
        \\ ['enum-objects',{enum:[{a:1},{b:2}]},{a:2}],
        \\ ['required-unsafe',{required:['constructor','__proto__','prototype']},{}],
        \\ ['property-slash',{properties:{'a/b':false}},{'a/b':1}],
        \\ ['property-tilde',{properties:{'a~b':false}},{'a~b':1}]
        \\];
        \\const output=[];for(const [name,schema,args]of cases){try{output.push({name,result:validateToolArguments({parameters:schema},{name:'fixture',arguments:args})})}catch(error){output.push({name,error:{name:error.name,message:error.message}})}}globalThis.result=JSON.stringify(output);
    , "native-keyword-source-corpus");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-keyword-result", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer engine.gpa.free(text);
    try std.testing.expectEqualStrings(std.mem.trim(u8, @embedFile("../durable/fixtures/tool-schema-keywords-40-1ced.json"), "\r\n "), text);
}

test "native durable VM validation module captures legacy kind and WeakMap state once and ignores falsy overridden cache hits" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try testFunctions(engine);
    const output = try engine.evalModule(
        \\const output=[],OriginalWeakMap=WeakMap,originalFor=Symbol.for,marker=Symbol.for('TypeBox.Kind'),schema={type:'object',properties:{n:{type:'number'}},[marker]:'Object'},raw={owned:true};Symbol.for=function(){throw raw};globalThis.WeakMap=function(){throw raw};try{try{validateToolArguments({parameters:schema},{name:'fixture',arguments:{n:'3'}})}catch(error){output.push({name:'captured-symbol-cache',error:error===raw?'raw':{name:error.name,message:error.message}})}}finally{Symbol.for=originalFor;globalThis.WeakMap=OriginalWeakMap}
        \\const plain={type:'object',properties:{n:{type:'number'}}},events=[],originalGet=WeakMap.prototype.get;WeakMap.prototype.get=function(schema){events.push(schema===plain?'root':'child');return 0};try{output.push({name:'falsy-cache',result:validateToolArguments({parameters:plain},{name:'fixture',arguments:{n:'3'}}),events})}finally{WeakMap.prototype.get=originalGet}globalThis.result=JSON.stringify(output);
    , "native-validator-module-state-source");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-validator-module-state-result", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer engine.gpa.free(text);
    try std.testing.expectEqualStrings(std.mem.trim(u8, @embedFile("../durable/fixtures/tool-validation-module-state-1ced.json"), "\r\n "), text);
}

test "native durable VM cached Validator replacements retain Check Errors receivers mapping order raw errors and mutated cache identity" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try testFunctions(engine);
    const output = try engine.evalModule(
        \\const output=[],get=WeakMap.prototype.get,raw={owned:true};
        \\for(const name of ['accept','reject','throw-check','throw-errors','truthy-primitive','mutated-cached']){
        \\ const events=[],schema={type:'object'},call={name:'fixture',arguments:{value:1}};let validator;
        \\ if(name==='mutated-cached'){validateToolArguments({parameters:schema},call);validator=get.call((()=>{let owner;WeakMap.prototype.get=function(key){owner=this;return get.call(this,key)};try{validateToolArguments({parameters:schema},call)}finally{WeakMap.prototype.get=get}return owner})(),schema)}
        \\ else validator=name==='truthy-primitive'?7:{};
        \\ if(typeof validator==='object'){
        \\  Object.defineProperty(validator,'Check',{configurable:true,get(){events.push('get Check');return function(value){events.push(['Check',this===validator,value]);if(name==='throw-check')throw raw;return name==='accept'?1:0}}});
        \\  Object.defineProperty(validator,'Errors',{configurable:true,get(){events.push('get Errors');return function(value){events.push(['Errors',this===validator,value]);if(name==='throw-errors')throw raw;const rows=[{keyword:'required',params:{requiredProperties:['field']},instancePath:'/outer/path',message:'must be present'},{keyword:'type',instancePath:'',message:'root failure'}];const map=rows.map;rows.map=function(callback){events.push(['map',this===rows]);return map.call(this,callback)};return rows}}});
        \\ }
        \\ WeakMap.prototype.get=function(){events.push('cache');return validator};
        \\ try{try{output.push({name,result:validateToolArguments({parameters:schema},call),events})}catch(error){output.push({name,error:error===raw?'raw':{name:error.name,...(name==='truthy-primitive'?{}:{message:error.message})},events})}}finally{WeakMap.prototype.get=get}
        \\}
        \\globalThis.result=JSON.stringify(output);
    , "native-validator-cache-replacement-source");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-validator-cache-replacement-result", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer engine.gpa.free(text);
    try std.testing.expectEqualStrings(std.mem.trim(u8, @embedFile("../durable/fixtures/tool-validation-cache-replacement-1ced.json"), "\r\n "), text);
}

test "native durable VM public Pi ai validation root subpath imports match real Source functions aliases cloning coercion and owned failures" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("native_stream.zig").install(engine);
    const output = try engine.evalModule(
        \\import {validateToolArguments,validateToolCall} from '@earendil-works/pi-ai';
        \\import * as validation from '@earendil-works/pi-ai/utils/validation';
        \\import * as legacy from '@mariozechner/pi-ai/utils/validation';
        \\import * as short from 'pi-ai/utils/validation';
        \\if(legacy.validateToolArguments!==validateToolArguments||short.validateToolCall!==validateToolCall)throw Error('validation alias identity');
        \\const tool={name:'fixture',parameters:{type:'object',properties:{n:{type:'number'}},required:['n']}},original={name:'fixture',arguments:{n:'3'}},events=[];
        \\const result={names:[validateToolArguments.name,validateToolCall.name],arity:[validateToolArguments.length,validateToolCall.length],same:validateToolArguments===validation.validateToolArguments&&validateToolCall===validation.validateToolCall,first:validateToolArguments(tool,original),unchanged:original.arguments.n==='3',call:validateToolCall([tool],{name:'fixture',arguments:{n:'4'}})};
        \\try{validateToolCall([],{name:'missing',arguments:{}})}catch(error){result.missing={name:error.name,message:error.message}}
        \\try{validateToolArguments(tool,{name:'fixture',arguments:{n:'bad'}})}catch(error){result.invalid={name:error.name,message:error.message}}
        \\const custom={find(predicate){events.push([this===custom,typeof predicate,predicate(tool)]);return tool}};result.custom=validateToolCall(custom,{name:'fixture',arguments:{n:'5'}});result.events=events;
        \\globalThis.result=JSON.stringify(result);
    , "native-public-validation-imports-source");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-public-validation-imports-result", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer engine.gpa.free(text);
    try std.testing.expectEqualStrings(std.mem.trim(u8, @embedFile("../durable/fixtures/tool-validation-public-imports-1ced.json"), "\r\n "), text);
}

test "native durable VM required property literal names stay separate from root slash dot empty and prototype instance paths" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try testFunctions(engine);
    const output = try engine.evalModule(
        \\const output=[];
        \\for(const base of ['root','a/b','a.b','a~b','','__proto__'])for(const property of ['value','a/b','']){
        \\ const schema={type:'object',properties:{[base]:{type:'object',required:[property]}}},args={[base]:{}};
        \\ try{output.push({base,property,result:validateToolArguments({parameters:schema},{name:'fixture',arguments:args})})}catch(error){output.push({base,property,error:{name:error.name,message:error.message}})}
        \\}
        \\globalThis.result=JSON.stringify(output);
    , "native-required-property-source-names");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-required-property-source-result", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer engine.gpa.free(text);
    try std.testing.expectEqualStrings(std.mem.trim(u8, @embedFile("../durable/fixtures/tool-validation-required-names-1ced.json"), "\r\n "), text);
}

test "native durable VM caught raw validation callback exceptions never invoke their user string coercion" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try testFunctions(engine);
    const output = try engine.evalModule(
        \\const output=[],originalClone=globalThis.structuredClone??nativeDefaultClone,originalGet=WeakMap.prototype.get,originalError=Error;globalThis.structuredClone=originalClone;
        \\for(const name of ['clone','parameters','find','cache','Check','Errors','map','join','Error']){
        \\ const events=[],raw={toString(){events.push('coerce');return 'raw-owned'}},schema={type:'object'},tool={parameters:schema},call={name:'fixture',arguments:{}};
        \\ if(name==='clone')globalThis.structuredClone=function(){events.push('clone');throw raw};
        \\ if(name==='parameters')Object.defineProperty(tool,'parameters',{get(){events.push('parameters');throw raw}});
        \\ if(name==='cache')WeakMap.prototype.get=function(){events.push('cache');throw raw};
        \\ if(['Check','Errors','map','join'].includes(name))WeakMap.prototype.get=function(){return{Check(){events.push('Check');if(name==='Check')throw raw;return false},Errors(){events.push('Errors');if(name==='Errors')throw raw;return{map(){events.push('map');if(name==='map')throw raw;return{join(){events.push('join');throw raw}}}}}}};
        \\ if(name==='Error'){tool.parameters={type:'number'};globalThis.Error=function(){events.push('Error');throw raw}};
        \\ try{try{if(name==='find')validateToolCall({find(){events.push('find');throw raw}},call);else validateToolArguments(tool,call)}catch(error){output.push({name,raw:error===raw,events})}}finally{globalThis.structuredClone=originalClone;WeakMap.prototype.get=originalGet;globalThis.Error=originalError}
        \\}
        \\globalThis.result=JSON.stringify(output);
    , "native-validation-raw-coercion-source");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-validation-raw-coercion-result", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer engine.gpa.free(text);
    try std.testing.expectEqualStrings(std.mem.trim(u8, @embedFile("../durable/fixtures/tool-validation-raw-coercion-1ced.json"), "\r\n "), text);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
}

test "native durable VM raw validation diagnostic scope unwinds before uncaught host errors are reported" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try testFunctions(engine);
    const caught = try engine.eval("globalThis.hostCoercions=0;globalThis.hostRaw={toString(){hostCoercions++;return 'host diagnostic'}};const original=WeakMap.prototype.get;WeakMap.prototype.get=function(){throw hostRaw};try{try{validateToolArguments({parameters:{type:'object'}},{name:'fixture',arguments:{}})}catch(error){if(error!==hostRaw||hostCoercions!==0)throw Error('premature diagnostics')}}finally{WeakMap.prototype.get=original}", "native-validation-host-diagnostic-scope", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(caught);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
    try std.testing.expectError(error.JavaScriptException, engine.eval("throw hostRaw", "native-host-uncaught-diagnostic", c.JS_EVAL_TYPE_GLOBAL));
    try std.testing.expectEqualStrings("host diagnostic", engine.last_error.?);
    const count = try engine.eval("hostCoercions", "native-host-diagnostic-count", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(count);
    var number: i32 = 0;
    if (c.JS_ToInt32(engine.context, &number, count) < 0) return error.JavaScriptException;
    try std.testing.expectEqual(@as(i32, 1), number);
}

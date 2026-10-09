//! Owner-VM weak cache for compiled tool-schema checks. Private until the full
//! original validation API and its reference semantics have qualified.
const std = @import("std");
const engine_mod = @import("engine.zig");
const vm = @import("native_values.zig");
const evaluator = @import("native_tool_validation.zig");
const references = @import("native_schema_refs.zig");
const c = engine_mod.c;
const Engine = engine_mod.Engine;

fn cache(engine: *Engine) !c.JSValue {
    if (engine.native_tool_validator_cache) |value| return value;
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const constructor = try vm.get(engine, global, "WeakMap");
    defer engine.freeValue(constructor);
    const value = try engine.checked(c.JS_CallConstructor(engine.context, constructor, 0, null));
    engine.native_tool_validator_cache = value;
    return value;
}
/// Pi creates its cache and legacy kind token when the validation module loads.
/// Public installation must call this before executing extension code.
pub fn initializeOwnerState(engine: *Engine) !void {
    if (engine.native_tool_legacy_symbol == null) {
        const global = c.JS_GetGlobalObject(engine.context);
        defer engine.freeValue(global);
        const symbol = try vm.get(engine, global, "Symbol");
        defer engine.freeValue(symbol);
        const name = try engine.checked(c.JS_NewString(engine.context, "TypeBox.Kind"));
        defer engine.freeValue(name);
        engine.native_tool_legacy_symbol = try vm.invoke(engine, symbol, "for", &.{name});
    }
    _ = try cache(engine);
}
pub fn legacySymbol(engine: *Engine) !c.JSValue {
    try initializeOwnerState(engine);
    return engine.native_tool_legacy_symbol.?;
}
pub fn get(engine: *Engine, schema: c.JSValue) !c.JSValue {
    const generation = engine.native_allocation_generation;
    return getOwned(engine, schema) catch |err| return engine.nativeAllocationError(err, generation);
}
fn getOwned(engine: *Engine, schema: c.JSValue) !c.JSValue {
    const weak = try cache(engine);
    const previous = try vm.invoke(engine, weak, "get", &.{schema});
    if (c.JS_ToBool(engine.context, previous) != 0) return previous;
    engine.freeValue(previous);
    const use_unevaluated = try evaluator.usesUnevaluated(engine, schema);
    var arena = std.heap.ArenaAllocator.init(engine.gpa);
    defer arena.deinit();
    var snapshots: Snapshot = .{ .engine = engine, .refs = .{ .engine = engine, .a = arena.allocator(), .root = schema } };
    defer snapshots.pairs.deinit(engine.gpa);
    const compiled = try snapshots.walk(schema);
    defer engine.freeValue(compiled);
    if (c.JS_IsObject(compiled)) try vm.put(engine, compiled, "~nativeUnevaluated", c.pi_js_bool(engine.context, @intFromBool(use_unevaluated)));
    const validator = try vm.object(engine);
    errdefer engine.freeValue(validator);
    var captures = [_]c.JSValue{ compiled, schema };
    try vm.put(engine, validator, "Check", try engine.checked(c.JS_NewCFunctionData2(engine.context, validatorMethod, "Check", 1, 0, captures.len, &captures)));
    try vm.put(engine, validator, "Errors", try engine.checked(c.JS_NewCFunctionData2(engine.context, validatorMethod, "Errors", 1, 1, captures.len, &captures)));
    // WeakMap supplies the original primitive-key failure, including boolean
    // schemas: normalization catches this compile/cache error upstream.
    const result = try vm.invoke(engine, weak, "set", &.{ schema, validator });
    engine.freeValue(result);
    return validator;
}
pub fn check(engine: *Engine, compiled: c.JSValue, value: c.JSValue) !bool {
    const generation = engine.native_allocation_generation;
    const checked = vm.invoke(engine, compiled, "Check", &.{value}) catch |err| return engine.nativeAllocationError(err, generation);
    defer engine.freeValue(checked);
    return c.JS_ToBool(engine.context, checked) != 0;
}
fn validatorMethod(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return validatorMethodOwned(engine, receiver, captures[0], captures[1], if (argc > 0) argv[0] else c.pi_js_undefined(), magic != 0) catch |err| {
        if (err == error.OutOfMemory) return engine.throwNativeOutOfMemory();
        return engine.throwCaptured();
    };
}
fn validatorMethodOwned(engine: *Engine, receiver: c.JSValue, compiled: c.JSValue, schema: c.JSValue, value: c.JSValue, errors: bool) !c.JSValue {
    if (!errors) return c.pi_js_bool(engine.context, @intFromBool(try evaluator.checkCompiled(engine, compiled, value)));
    const result = try vm.array(engine);
    errdefer engine.freeValue(result);
    // Source Errors re-enters the receiver's current Check method. User
    // overrides and cached replacement objects therefore remain observable.
    if (try check(engine, receiver, value)) return result;
    var evaluated = try evaluator.evaluate(engine, schema, value);
    defer evaluated.deinit(engine.gpa);
    for (evaluated.failures, 0..) |failure, index| {
        const row = try vm.object(engine);
        var consumed = false;
        errdefer if (!consumed) engine.freeValue(row);
        const base = if (failure.required_properties.len != 0) failure.required_base else failure.path;
        const path = if (base.len == 0 or (failure.required_properties.len == 0 and std.mem.eql(u8, base, "root"))) try engine.gpa.dupe(u8, "") else blk: {
            const pointer = try std.fmt.allocPrint(engine.gpa, "/{s}", .{base});
            for (pointer) |*character| if (character.* == '.') {
                character.* = '/';
            };
            break :blk pointer;
        };
        defer engine.gpa.free(path);
        try vm.put(engine, row, "keyword", try engine.checked(c.JS_NewString(engine.context, if (failure.required_properties.len != 0) "required" else "native")));
        if (failure.required_properties.len != 0) {
            const params = try vm.object(engine);
            defer engine.freeValue(params);
            const required = try vm.array(engine);
            defer engine.freeValue(required);
            for (failure.required_properties, 0..) |property, property_index| {
                const name = try engine.checked(c.JS_NewStringLen(engine.context, property.ptr, property.len));
                if (c.JS_SetPropertyUint32(engine.context, required, @intCast(property_index), name) < 0) return error.JavaScriptException;
            }
            try vm.put(engine, params, "requiredProperties", c.JS_DupValue(engine.context, required));
            try vm.put(engine, row, "params", c.JS_DupValue(engine.context, params));
        }
        try vm.put(engine, row, "instancePath", try engine.checked(c.JS_NewStringLen(engine.context, path.ptr, path.len)));
        try vm.put(engine, row, "message", try engine.checked(c.JS_NewStringLen(engine.context, failure.message.ptr, failure.message.len)));
        consumed = true;
        if (c.JS_SetPropertyUint32(engine.context, result, @intCast(index), row) < 0) return error.JavaScriptException;
    }
    return result;
}
pub fn validators(engine: *Engine) @import("native_tool_coercion.zig").Validators {
    return .{ .engine = engine, .context = engine, .compile = compileCallback, .check = checkCallback };
}
fn compileCallback(context: *anyopaque, schema: c.JSValue) !c.JSValue {
    return get(@ptrCast(@alignCast(context)), schema);
}
fn checkCallback(context: *anyopaque, compiled: c.JSValue, value: c.JSValue) !bool {
    return check(@ptrCast(@alignCast(context)), compiled, value);
}
const Pair = struct { source: c.JSValue, target: c.JSValue };
const Snapshot = struct {
    engine: *Engine,
    refs: references.Stack,
    pairs: std.ArrayList(Pair) = .empty,
    fn constant(self: *Snapshot, value: c.JSValue) !c.JSValue {
        // Emit.Constant in 1.3.27 writes BigInt's decimal text without an n
        // suffix. Accelerated checks therefore use a Number constant; the
        // original schema remains unchanged for dynamic conversion/errors.
        if (!c.JS_IsBigInt(value)) return c.JS_DupValue(self.engine.context, value);
        const text = try self.engine.toString(value);
        defer self.engine.gpa.free(text);
        return c.JS_NewFloat64(self.engine.context, std.fmt.parseFloat(f64, text) catch unreachable);
    }
    fn property(self: *Snapshot, source: c.JSValue, key: []const u8) !c.JSValue {
        const atom = c.JS_NewAtomLen(self.engine.context, key.ptr, key.len);
        defer c.JS_FreeAtom(self.engine.context, atom);
        return self.engine.checked(c.JS_GetProperty(self.engine.context, source, atom));
    }
    fn put(self: *Snapshot, target: c.JSValue, key: []const u8, value: c.JSValue) !void {
        const atom = c.JS_NewAtomLen(self.engine.context, key.ptr, key.len);
        defer c.JS_FreeAtom(self.engine.context, atom);
        if (c.JS_DefinePropertyValue(self.engine.context, target, atom, value, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    }
    fn dictionary(self: *Snapshot, source: c.JSValue, dependency: bool) !c.JSValue {
        const result = try self.engine.checked(c.JS_NewObjectProto(self.engine.context, c.pi_js_null()));
        errdefer self.engine.freeValue(result);
        var keys: [*c]c.JSPropertyEnum = null;
        var length: u32 = 0;
        if (c.JS_GetOwnPropertyNames(self.engine.context, &keys, &length, source, c.JS_GPN_STRING_MASK) < 0) return error.JavaScriptException;
        defer c.JS_FreePropertyEnum(self.engine.context, keys, length);
        for (0..length) |index| {
            const value = try self.engine.checked(c.JS_GetProperty(self.engine.context, source, keys[index].atom));
            defer self.engine.freeValue(value);
            const target = if (dependency and c.JS_IsArray(value)) try self.copyArray(value, false) else try self.walk(value);
            if (c.JS_DefinePropertyValue(self.engine.context, result, keys[index].atom, target, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
        }
        return result;
    }
    fn copyArray(self: *Snapshot, source: c.JSValue, nested: bool) anyerror!c.JSValue {
        const result = try vm.array(self.engine);
        errdefer self.engine.freeValue(result);
        for (0..try vm.length(self.engine, source)) |index| {
            const item = try self.engine.checked(c.JS_GetPropertyUint32(self.engine.context, source, @intCast(index)));
            defer self.engine.freeValue(item);
            const target = if (nested) try self.walk(item) else try self.constant(item);
            if (c.JS_SetPropertyUint32(self.engine.context, result, @intCast(index), target) < 0) return error.JavaScriptException;
        }
        return result;
    }
    fn walk(self: *Snapshot, schema: c.JSValue) anyerror!c.JSValue {
        try @import("native_schema_guards.zig").assertRoot(self.engine, schema);
        if (!c.JS_IsObject(schema)) return c.JS_DupValue(self.engine.context, schema);
        for (self.pairs.items) |pair| if (c.JS_IsStrictEqual(self.engine.context, pair.source, schema)) return c.JS_DupValue(self.engine.context, pair.target);
        const result = try self.engine.checked(c.JS_NewObjectProto(self.engine.context, c.pi_js_null()));
        errdefer self.engine.freeValue(result);
        try self.pairs.append(self.engine.gpa, .{ .source = schema, .target = result });
        const mark = try self.refs.push(schema);
        defer self.refs.pop(mark);
        // The compiler snapshots schema keywords. The preceding source-style
        // unevaluated scan reads annotations without serializing host values.
        for ([_][:0]const u8{ "type", "const", "enum", "required", "dependentRequired", "minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum", "multipleOf", "minLength", "maxLength", "pattern", "format", "minItems", "maxItems", "uniqueItems", "minContains", "maxContains", "minProperties", "maxProperties", "~refine" }) |key| {
            const value = try @import("native_schema_guards.zig").read(self.engine, schema, key);
            defer self.engine.freeValue(value);
            if (c.JS_IsUndefined(value)) {
                if (!std.mem.eql(u8, key, "const")) continue;
                const atom = c.JS_NewAtom(self.engine.context, "const");
                defer c.JS_FreeAtom(self.engine.context, atom);
                const found = c.JS_HasProperty(self.engine.context, schema, atom);
                if (found < 0) return error.JavaScriptException;
                if (found == 0) continue;
            }
            const target = if (c.JS_IsArray(value) and (std.mem.eql(u8, key, "type") or std.mem.eql(u8, key, "required") or std.mem.eql(u8, key, "enum") or std.mem.eql(u8, key, "~refine"))) try self.copyArray(value, false) else try self.constant(value);
            try self.put(result, key, target);
            if (std.mem.eql(u8, key, "pattern")) try vm.put(self.engine, result, "~nativePattern", try @import("native_schema_guards.zig").compilePattern(self.engine, value));
        }
        for ([_][:0]const u8{ "additionalItems", "additionalProperties", "contains", "if", "then", "else", "not", "propertyNames", "unevaluatedItems", "unevaluatedProperties" }) |key| {
            const value = try @import("native_schema_guards.zig").read(self.engine, schema, key);
            defer self.engine.freeValue(value);
            if (c.JS_IsUndefined(value)) continue;
            try self.put(result, key, try self.walk(value));
        }
        for ([_][:0]const u8{ "allOf", "anyOf", "oneOf", "prefixItems", "items" }) |key| {
            const value = try @import("native_schema_guards.zig").read(self.engine, schema, key);
            defer self.engine.freeValue(value);
            if (c.JS_IsUndefined(value)) continue;
            try self.put(result, key, if (c.JS_IsArray(value)) try self.copyArray(value, true) else try self.walk(value));
        }
        for ([_][:0]const u8{ "properties", "patternProperties", "dependencies", "dependentSchemas" }) |key| {
            const value = try @import("native_schema_guards.zig").read(self.engine, schema, key);
            defer self.engine.freeValue(value);
            if (!c.JS_IsObject(value)) continue;
            try self.put(result, key, try self.dictionary(value, std.mem.eql(u8, key, "dependencies")));
            if (std.mem.eql(u8, key, "patternProperties")) {
                const patterns = try self.engine.checked(c.JS_NewObjectProto(self.engine.context, c.pi_js_null()));
                defer self.engine.freeValue(patterns);
                var keys: [*c]c.JSPropertyEnum = null;
                var length: u32 = 0;
                if (c.JS_GetOwnPropertyNames(self.engine.context, &keys, &length, value, c.JS_GPN_STRING_MASK) < 0) return error.JavaScriptException;
                defer c.JS_FreePropertyEnum(self.engine.context, keys, length);
                for (0..length) |index| {
                    const name = try self.engine.checked(c.JS_AtomToString(self.engine.context, keys[index].atom));
                    defer self.engine.freeValue(name);
                    const regexp = try @import("native_schema_guards.zig").compilePattern(self.engine, name);
                    if (c.JS_DefinePropertyValue(self.engine.context, patterns, keys[index].atom, regexp, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
                }
                try vm.put(self.engine, result, "~nativePatternProperties", c.JS_DupValue(self.engine.context, patterns));
            }
        }
        const resolved = try vm.array(self.engine);
        defer self.engine.freeValue(resolved);
        var count: u32 = 0;
        for ([_][:0]const u8{ "$ref", "$recursiveRef", "$dynamicRef" }) |keyword| {
            const reference = try vm.get(self.engine, schema, keyword);
            defer self.engine.freeValue(reference);
            if (!c.JS_IsString(reference)) continue;
            const label = try self.engine.toString(reference);
            defer self.engine.gpa.free(label);
            const resolution = try self.refs.resolve(keyword, label);
            defer resolution.deinit(self.engine);
            self.refs.entry = resolution;
            defer self.refs.entry = null;
            const target = try self.walk(resolution.schema);
            if (c.JS_SetPropertyUint32(self.engine.context, resolved, count, target) < 0) return error.JavaScriptException;
            count += 1;
        }
        if (count != 0) try vm.put(self.engine, result, "~nativeReferences", c.JS_DupValue(self.engine.context, resolved));
        return result;
    }
};

fn testCompile(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return testCompileOwned(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| {
        if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(context);
        return engine.throwCaptured();
    };
}
fn testCompileOwned(engine: *Engine, schema: c.JSValue) !c.JSValue {
    const compiled = try get(engine, schema);
    defer engine.freeValue(compiled);
    const result = try vm.object(engine);
    errdefer engine.freeValue(result);
    var captures = [_]c.JSValue{ compiled, schema };
    try vm.put(engine, result, "Check", try engine.checked(c.JS_NewCFunctionData(engine.context, testValidator, 1, 0, captures.len, &captures)));
    try vm.put(engine, result, "Errors", try engine.checked(c.JS_NewCFunctionData(engine.context, testValidator, 1, 1, captures.len, &captures)));
    return result;
}
fn testValidator(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return testValidatorOwned(engine, data[0], data[1], if (argc > 0) argv[0] else c.pi_js_undefined(), magic != 0) catch |err| {
        if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(context);
        return engine.throwCaptured();
    };
}
fn testValidatorOwned(engine: *Engine, compiled: c.JSValue, schema: c.JSValue, value: c.JSValue, errors: bool) !c.JSValue {
    const valid = try check(engine, compiled, value);
    if (!errors) return c.pi_js_bool(engine.context, @intFromBool(valid));
    const result = try vm.array(engine);
    errdefer engine.freeValue(result);
    if (valid) return result;
    var evaluated = try evaluator.evaluate(engine, schema, value);
    defer evaluated.deinit(engine.gpa);
    for (evaluated.failures, 0..) |failure, index| if (c.JS_SetPropertyUint32(engine.context, result, @intCast(index), try engine.checked(c.JS_NewStringLen(engine.context, failure.message.ptr, failure.message.len))) < 0) return error.JavaScriptException;
    return result;
}

test "native durable VM compiled tool schema cache preserves identity and snapshots checks before coercion mutation" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const schema = try engine.eval("({type:'object',properties:{n:{type:'number'}},required:['n']})", "validator-cache-schema", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(schema);
    const first = try get(engine, schema);
    defer engine.freeValue(first);
    const second = try get(engine, schema);
    defer engine.freeValue(second);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, first, second));
    const properties = try vm.get(engine, schema, "properties");
    defer engine.freeValue(properties);
    const n = try vm.get(engine, properties, "n");
    defer engine.freeValue(n);
    try vm.put(engine, n, "type", try engine.checked(c.JS_NewString(engine.context, "string")));
    const value = try engine.eval("({n:1})", "validator-cache-value", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(value);
    try std.testing.expect(try check(engine, first, value));
    var errors = try evaluator.evaluate(engine, schema, value);
    defer errors.deinit(engine.gpa);
    try std.testing.expect(!errors.valid);
}

test "native durable VM compiled references and regexes stay fixed while error walks and refinement objects preserve source live identity" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try vm.put(engine, global, "Compile", try engine.checked(c.JS_NewCFunction(engine.context, testCompile, "Compile", 1)));
    errdefer std.debug.print("Compiled schema VM failure: {s}\n", .{engine.last_error orelse "none"});
    const output = try engine.evalModule(
        \\const output=[];const OriginalURL=globalThis.URL,OriginalRegExp=globalThis.RegExp;
        \\for(const [name,schema,valid,invalid,globalName]of [['refs',{$defs:{n:{type:'number'}},properties:{n:{$ref:'#/$defs/n'}}},{n:3},{n:'bad'},'URL'],['pattern',{type:'string',pattern:'^x'},'xyz','bad','RegExp'],['pattern-properties',{patternProperties:{'^n':{type:'number'}},additionalProperties:false},{n:3},{x:3},'RegExp']]){
        \\ const validator=Compile(schema),raw={name};globalThis[globalName]=function(){throw raw};let thrown;try{validator.Errors(invalid)}catch(error){thrown=error===raw}output.push({name,valid:validator.Check(valid),invalid:validator.Check(invalid),validErrors:validator.Errors(valid).length,thrown});globalThis.URL=OriginalURL;globalThis.RegExp=OriginalRegExp;
        \\}
        \\const schema={properties:{n:{type:'number'}}},validator=Compile(schema);Object.prototype.type='array';Object.prototype.$id='http://[';let prototype;try{prototype=validator.Check({n:3})}finally{delete Object.prototype.type;delete Object.prototype.$id}output.push({name:'prototype',valid:prototype});
        \\const refinement={check:()=>false,error:()=> 'failed'},refine=Compile({'~refine':[refinement]});refinement.error=0;output.push({name:'refine-error-mutated',valid:refine.Check(1),errors:refine.Errors(1).length});
        \\const constant={n:1},constantValidator=Compile({const:constant});constant.n=2;output.push({name:'const-object-live',valid:constantValidator.Check({n:2}),old:constantValidator.Check({n:1})});globalThis.result=JSON.stringify(output);
    , "native-compiled-schema-source-corpus");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-compiled-schema-result", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer engine.gpa.free(text);
    try std.testing.expectEqualStrings(std.mem.trim(u8, @embedFile("../durable/fixtures/schema-compiled-reference-pattern-cache-1ced.json"), "\r\n "), text);
}

test "native durable VM exact numeric bounds and divisibility match original six hundred Number BigInt comparisons and errors" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try vm.put(engine, global, "Compile", try engine.checked(c.JS_NewCFunction(engine.context, testCompile, "Compile", 1)));
    errdefer std.debug.print("Numeric BigInt VM failure: {s}\n", .{engine.last_error orelse "none"});
    const output = try engine.evalModule(
        \\const keywords=['minimum','maximum','exclusiveMinimum','exclusiveMaximum','multipleOf'],limits=[0,-0,0.5,-0.5,3,3n,9007199254740993n,1n<<128n,-(1n<<128n),1e100],values=[0,0n,1.5,-1.5,3n,-3n,9007199254740992,9007199254740993n,1n<<128n,(1n<<128n)+1n,-(1n<<129n),1e100];
        \\const output=[];for(const keyword of keywords)for(let bound=0;bound<limits.length;bound++)for(let index=0;index<values.length;index++){try{const validator=Compile({[keyword]:limits[bound]}),value=values[index];output.push({keyword,bound,index,valid:validator.Check(value),errors:validator.Errors(value)})}catch(error){output.push({keyword,bound,index,error:{name:error.name,message:error.message}})}}globalThis.result=JSON.stringify(output);
    , "native-numeric-bigint-source-corpus");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-numeric-bigint-result", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer engine.gpa.free(text);
    try std.testing.expectEqualStrings(std.mem.trim(u8, @embedFile("../durable/fixtures/schema-numeric-bigint-600-1ced.json"), "\r\n "), text);
}

fn allocationExercise(gpa: std.mem.Allocator) !void {
    const engine = try Engine.init(gpa, .{});
    defer engine.deinit();
    const schema = try engine.eval("({type:'object',properties:{n:{type:'number',minimum:3n,multipleOf:1n},s:{type:'string',pattern:'^x'},a:{type:'array',items:{anyOf:[{type:'number'},{type:'string'}]},uniqueItems:true}},patternProperties:{'^extra':{type:'boolean'}},required:['n','s','a'],additionalProperties:false})", "validator-cache-gpa-schema", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(schema);
    const compiled = try get(engine, schema);
    defer engine.freeValue(compiled);
    const input = try engine.eval("({n:3,s:'xyz',a:[1,'two'],extra:true})", "validator-cache-gpa-input", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(input);
    try std.testing.expect(try check(engine, compiled, input));
    try vm.put(engine, input, "n", c.JS_NewInt32(engine.context, 1));
    try std.testing.expect(!try check(engine, compiled, input));
    var errors = try evaluator.evaluate(engine, schema, input);
    defer errors.deinit(gpa);
}
test "native durable VM compiled schema weak cache patterns numeric comparisons checks and error walks unwind every native allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationExercise, .{});
}

//! Authored selected Node24.14 options controls. The JavaScript pairs share the
//! actual native options serializers and real process installation. Native
//! startup/provenance controls are separate. Install only; no execution claim.
const std = @import("std");
const a = @import("extensions/native_node_argument_values.zig");
const c = a.c;
const config = @import("extensions/native_node_options_config.zig");
const bindings = @import("extensions/native_node_options_binding.zig");
const options = @import("extensions/native_node_options.zig");

const Holder = struct { probe: *Probe, index: usize };
const Probe = struct {
    engine: *a.v.em.Engine,
    holder_class: c.JSClassID = 0,
    freed: [3]u32 = .{ 0, 0, 0 },
    fatal_slot: ?usize = null,
    first: c.JSValue,
    holders: [3]Holder = undefined,
};
var active_probe: ?*Probe = null;
fn preserveFatal(probe: *Probe) c.JSValue {
    _ = probe.engine.throwNativeOutOfMemoryFatal();
    const reason = c.JS_GetException(probe.engine.context);
    if (c.JS_IsUndefined(probe.first)) probe.first = a.duplicate(probe.engine, reason);
    return c.JS_Throw(probe.engine.context, reason);
}
fn releaseHolder(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const holder: *Holder = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    holder.probe.freed[holder.index] += 1;
    if (holder.probe.fatal_slot == holder.index) _ = preserveFatal(holder.probe);
}
fn holderIndex(context: ?*c.JSContext, argc: c_int, argv: [*c]c.JSValue) ?u32 {
    if (argc < 1) return null;
    var index: u32 = 0;
    if (c.JS_ToUint32(context, &index, argv[0]) < 0 or index >= 3) return null;
    return index;
}
fn makeHolder(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const index = holderIndex(context, argc, argv) orelse return c.JS_ThrowTypeError(context, "actual options holder index required");
    const probe = active_probe.?;
    const result = c.JS_NewObjectClass(context, probe.holder_class);
    if (c.JS_IsException(result)) return result;
    _ = c.JS_SetOpaque(result, &probe.holders[index]);
    return result;
}
fn freedCount(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const index = holderIndex(context, argc, argv) orelse return c.JS_ThrowTypeError(context, "actual options holder index required");
    return c.JS_NewUint32(context, active_probe.?.freed[index]);
}
fn nativeFatal(_: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return preserveFatal(active_probe.?);
}
fn privateData(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = a.v.em.Engine.fromContext(context.?);
    _ = engine.throwNativeOutOfMemory();
    return c.JS_GetException(context);
}
fn flaggedData(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const result = privateData(context, receiver, argc, argv);
    c.JS_SetUncatchableError(context, result);
    return result;
}
fn publishBody(s: *a.Scope, name: [*:0]const u8, value: c.JSValue) !c.JSValue {
    const global = try s.checked(c.JS_GetGlobalObject(s.engine.context));
    try s.define(global, name, value, c.JS_PROP_C_W_E);
    return c.pi_js_undefined();
}
fn bindingRecord(s: *a.Scope) !c.JSValue {
    const pair = try bindings.create(s.engine);
    var incoming = [_]c.JSValue{ pair.values, pair.embedder };
    for (&incoming, 0..) |*slot, position| {
        const value = slot.*; slot.* = c.pi_js_undefined();
        _ = s.own(value) catch |err| {
            for (incoming[position + 1 ..]) |*remaining| s.boundary.release(remaining);
            return err;
        };
    }
    const result = try s.objectProto(c.pi_js_null());
    try s.define(result, "values", pair.values, c.JS_PROP_C_W_E);
    try s.define(result, "embedder", pair.embedder, c.JS_PROP_C_W_E);
    return a.duplicate(s.engine, result);
}
const Fixture = struct {
    environment: std.process.Environ.Map,
    engine: *a.v.em.Engine,
    owner: ?c.JSValue = null,
    probe: Probe,
    native: bool,
    fn init(self: *Fixture, native: bool) !void {
        self.native = native;
        self.environment = .init(std.testing.allocator);
        errdefer self.environment.deinit();
        try self.environment.put("NODE_OPTIONS", "--conditions=environment --no-addons --preserve-symlinks");
        try self.environment.put("NODE_PENDING_DEPRECATION", "1");
        try self.environment.put("NODE_PRESERVE_SYMLINKS_MAIN", "1");
        self.engine = try a.v.em.Engine.init(std.testing.allocator, .{ .node_options = .{
            .values = .{ .conditions = &.{"base"} },
            .features = .{ .strip_types = true, .quic = false },
            .embedder = .{ .has_embedder_preload = true },
            .exec_arguments = &.{ "--conditions", "command", "--no-preserve-symlinks-main" },
        } });
        errdefer self.engine.deinit();
        self.owner = null;
        errdefer if (self.owner) |owner| self.engine.freeValue(owner);
        self.probe = .{ .engine = self.engine, .first = c.pi_js_undefined() };
        for (&self.probe.holders, 0..) |*holder, index| holder.* = .{ .probe = &self.probe, .index = index };
        active_probe = &self.probe;
        errdefer active_probe = null;
        try @import("extensions/native_process.zig").install(self.engine, std.testing.io, &self.environment, &.{"native-node-options-control"});
        _ = c.JS_NewClassID(self.engine.runtime, &self.probe.holder_class);
        const definition: c.JSClassDef = .{ .class_name = "Actual options expression temporary", .finalizer = releaseHolder };
        if (c.JS_NewClass(self.engine.runtime, self.probe.holder_class, &definition) < 0) return error.OutOfMemory;
        try self.engine.bindFunction("actualOptionsHolder", makeHolder, 1);
        try self.engine.bindFunction("actualOptionsFreedCount", freedCount, 1);
        try self.engine.bindFunction("actualOptionsFatal", nativeFatal, 0);
        try self.engine.bindFunction("actualOptionsPrivateData", privateData, 0);
        try self.engine.bindFunction("actualOptionsFlaggedData", flaggedData, 0);
        if (native) {
            self.owner = try options.acquire(self.engine);
            _ = try a.expression(self.engine, publishBody, .{ "actualNodeOptions", self.owner.? });
        } else {
            const record = try a.expression(self.engine, bindingRecord, .{});
            defer self.engine.freeValue(record);
            _ = try a.expression(self.engine, publishBody, .{ "actualNodeOptionsBindings", record });
            const evaluated = try self.engine.evalModule(@embedFile("extensions/fixtures/native-node-options-source.mjs") ++
                "\nglobalThis.actualNodeOptions = createNodeOptionsSource(actualNodeOptionsBindings);\n", "actual-node-options-source.mjs");
            self.engine.freeValue(evaluated);
            self.owner = try self.value("actualNodeOptions");
        }
    }
    fn deinit(self: *Fixture) void {
        self.probe.fatal_slot = null;
        self.engine.freeValue(self.probe.first);
        if (self.owner) |owner| self.engine.freeValue(owner);
        self.engine.deinit();
        active_probe = null;
        self.environment.deinit();
    }
    fn run(self: *Fixture, tail: []const u8) !void {
        const source = try std.mem.concat(self.engine.gpa, u8, &.{ @embedFile("extensions/fixtures/native-node-options-observer.mjs"), "\n", tail });
        defer self.engine.gpa.free(source);
        const result = try self.engine.evalModule(source, "actual-node-options-observer.mjs");
        self.engine.freeValue(result);
    }
    fn value(self: *Fixture, name: [*:0]const u8) !c.JSValue {
        const global = try self.engine.checked(c.JS_GetGlobalObject(self.engine.context));
        defer self.engine.freeValue(global);
        return self.engine.checked(c.JS_GetPropertyStr(self.engine.context, global, name));
    }
};
fn observe(comptime name: []const u8) !void {
    inline for (.{ false, true }) |native| {
        var fixture: Fixture = undefined; try fixture.init(native); defer fixture.deinit();
        fixture.run(name ++ "(actualNodeOptions);") catch |err| {
            std.debug.print("actual Node options native={any}, observer={s}, failure={s}, captured={s}\n",
                .{ native, name, @errorName(err), fixture.engine.last_error orelse "<no captured source>" });
            return err;
        };
        try fixture.engine.checkNativeEntry();
    }
}
fn freeTokens(tokens: []const []const u8) void {
    for (tokens) |token| std.testing.allocator.free(token);
    std.testing.allocator.free(tokens);
}
fn expectTokens(raw: []const u8, expected: []const []const u8) !void {
    const actual = try config.tokenize(std.testing.allocator, raw);
    defer freeTokens(actual);
    try std.testing.expectEqual(expected.len, actual.len);
    for (actual, expected) |value, wanted| try std.testing.expectEqualStrings(wanted, value);
}

test "native actual Node options environment tokenizer preserves exact quoting and escapes" {
    try expectTokens("", &.{});
    try expectTokens("  \"\"  ", &.{});
    try expectTokens("--conditions=\"a b\" --require \"one\\ two\"", &.{ "--conditions=a b", "--require", "one two" });
    try expectTokens("a\\b a\tb a\nb", &.{ "a\\b", "a\tb", "a\nb" });
    try expectTokens("x\"\"y \"a\\\"b\" \"q\\\\r\"", &.{ "xy", "a\"b", "q\\r" });
    try std.testing.expectError(error.InvalidNodeOptionsEscape, config.tokenize(std.testing.allocator, "\"tail\\"));
    try std.testing.expectError(error.UnterminatedNodeOptionsString, config.tokenize(std.testing.allocator, "\"tail"));
}
test "native actual Node options Engine copies native input strings and execution token lists" {
    var condition = [_]u8{ 'b', 'a', 's', 'e' };
    var warning = [_]u8{ 'l', 'o', 'g' };
    var command = [_]u8{ 'e', 'x', 'e', 'c' };
    var conditions = [_][]const u8{condition[0..]};
    var arguments = [_][]const u8{ "--conditions", command[0..] };
    const engine = try a.v.em.Engine.init(std.testing.allocator, .{ .node_options = .{
        .values = .{ .conditions = &conditions, .redirect_warnings = &warning },
        .features = .{ .strip_types = false }, .exec_arguments = &arguments,
    } });
    defer engine.deinit();
    condition[0] = 'X'; warning[0] = 'X'; command[0] = 'X';
    conditions[0] = "replaced"; arguments[0] = "--invalid";
    const owner = engine.node_options.?;
    try std.testing.expectEqualStrings("base", owner.original.values.conditions[0]);
    try std.testing.expectEqualStrings("log", owner.original.values.redirect_warnings);
    try std.testing.expectEqualStrings("--conditions", owner.original.exec_arguments[0]);
    try std.testing.expectEqualStrings("exec", owner.original.exec_arguments[1]);
    var environment: std.process.Environ.Map = .init(std.testing.allocator); defer environment.deinit();
    try environment.put("NODE_OPTIONS", "--conditions=environment");
    try @import("extensions/native_process.zig").install(engine, std.testing.io, &environment, &.{"separate-pi-argv"});
    try std.testing.expectEqual(@as(usize, 3), owner.values.conditions.len);
    try std.testing.expectEqualStrings("base", owner.values.conditions[0]);
    try std.testing.expectEqualStrings("environment", owner.values.conditions[1]);
    try std.testing.expectEqualStrings("exec", owner.values.conditions[2]);
    try std.testing.expectEqual(@as(?bool, false), owner.values.strip_types);
}
test "native actual Node options environment and exec parser preserve implication and Boolean semantics" {
    const engine = try a.v.em.Engine.init(std.testing.allocator, .{ .node_options = .{
        .features = .{ .strip_types = false },
        .exec_arguments = &.{ "--no-addons", "--preserve_symlinks=false", "-C", "last", "--experimental-transform-types", "--no-strip-types" },
    } });
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator); defer environment.deinit();
    try environment.put("NODE_OPTIONS", "--conditions=first --no-preserve-symlinks");
    try environment.put("NODE_PENDING_DEPRECATION", "01");
    try environment.put("NODE_PRESERVE_SYMLINKS_MAIN", "1");
    try environment.put("NODE_USE_ENV_PROXY", "1");
    const owner = engine.node_options.?;
    try owner.captureEnvironment(&environment);
    try std.testing.expect(owner.values.preserve_symlinks);
    try std.testing.expect(owner.values.preserve_symlinks_main);
    try std.testing.expect(!owner.values.pending_deprecation and !owner.values.allow_native_addons);
    try std.testing.expect(owner.values.use_env_proxy and owner.values.transform_types and owner.values.enable_source_maps);
    try std.testing.expectEqual(@as(?bool, false), owner.values.strip_types);
    try std.testing.expectEqual(@as(usize, 2), owner.values.conditions.len);
    try std.testing.expectEqualStrings("first", owner.values.conditions[0]);
    try std.testing.expectEqualStrings("last", owner.values.conditions[1]);
}
test "native actual Node options failed environment capture rolls back before a real retry" {
    const engine = try a.v.em.Engine.init(std.testing.allocator, .{ .node_options = .{
        .values = .{ .conditions = &.{"original"} }, .features = .{ .strip_types = true },
    } });
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator); defer environment.deinit();
    try environment.put("NODE_OPTIONS", "--conditions=discarded \"unfinished");
    const owner = engine.node_options.?;
    const before = owner.memory.used.load(.acquire);
    try std.testing.expectError(error.UnterminatedNodeOptionsString, owner.captureEnvironment(&environment));
    try std.testing.expect(!owner.environment_ready and owner.environment_arena == null);
    try std.testing.expectEqual(before, owner.memory.used.load(.acquire));
    try std.testing.expectEqual(@as(usize, 1), owner.values.conditions.len);
    try std.testing.expectEqualStrings("original", owner.values.conditions[0]);
    try environment.put("NODE_OPTIONS", "--conditions=retry");
    try owner.captureEnvironment(&environment);
    try std.testing.expectEqual(@as(usize, 2), owner.values.conditions.len);
    try std.testing.expectEqualStrings("retry", owner.values.conditions[1]);
    try environment.put("NODE_OPTIONS", "--conditions=too-late");
    try owner.captureEnvironment(&environment);
    try std.testing.expectEqualStrings("retry", owner.values.conditions[1]);
}
test "native actual Node options separate empty argument differs from equals empty argument" {
    inline for (.{ false, true }) |equals| {
        const engine = try a.v.em.Engine.init(std.testing.allocator, .{ .node_options = .{
            .features = .{ .strip_types = true },
            .exec_arguments = if (equals) &.{"--conditions="} else &.{ "--conditions", "" },
        } });
        defer engine.deinit();
        var environment: std.process.Environ.Map = .init(std.testing.allocator); defer environment.deinit();
        if (equals) try std.testing.expectError(error.NodeOptionRequiresArgument, engine.node_options.?.captureEnvironment(&environment))
        else {
            try engine.node_options.?.captureEnvironment(&environment);
            try std.testing.expectEqual(@as(usize, 1), engine.node_options.?.values.conditions.len);
            try std.testing.expectEqualStrings("", engine.node_options.?.values.conditions[0]);
        }
    }
}
fn publishBindingBeforeBootstrap(s: *a.Scope) !c.JSValue {
    const record = try s.own(try a.expression(s.engine, bindingRecord, .{}));
    return publishBody(s, "actualOptionsBootstrapBinding", record);
}
test "native actual Node options binding throws the actual bootstrap Error before serialization" {
    const engine = try a.v.em.Engine.init(std.testing.allocator, .{ .node_options = .{ .features = .{ .strip_types = true } } });
    defer engine.deinit();
    _ = try a.expression(engine, publishBindingBeforeBootstrap, .{});
    const embedder_result = try engine.evalModule(
        \\let reason;
        \\try { actualOptionsBootstrapBinding.embedder(); } catch (error) { reason=error; }
        \\if (!(reason instanceof Error) || reason.code!=="ERR_OPTIONS_BEFORE_BOOTSTRAPPING")
        \\  throw new Error("real prebootstrap embedder Error");
    , "actual-node-options-embedder-bootstrap-error.mjs");
    engine.freeValue(embedder_result);
    try std.testing.expect(!engine.node_options.?.serialized);
    const result = try engine.evalModule(
        \\const OriginalError = Error;
        \\globalThis.Error = function(){ throw "replacement must not run"; };
        \\for (const method of ["values","embedder"]) {
        \\  let reason;
        \\  try { actualOptionsBootstrapBinding[method](); } catch (error) { reason=error; }
        \\  if (!(reason instanceof OriginalError) || reason.code!=="ERR_OPTIONS_BEFORE_BOOTSTRAPPING" ||
        \\      reason.message!=="Should not query options before bootstrapping is done") throw new OriginalError("real bootstrap Error contract");
        \\  const descriptor=Object.getOwnPropertyDescriptor(reason,"message");
        \\  if (!descriptor || descriptor.enumerable || !descriptor.configurable || !descriptor.writable) throw new OriginalError("real bootstrap message descriptor");
        \\}
        \\const oldCode=Object.getOwnPropertyDescriptor(OriginalError.prototype,"code");
        \\Object.defineProperty(OriginalError.prototype,"code",{value:"inherited readonly code",writable:false,configurable:true});
        \\try {
        \\  for (const method of ["values","embedder"]) {
        \\    let reason;
        \\    try { actualOptionsBootstrapBinding[method](); } catch (error) { reason=error; }
        \\    if (!(reason instanceof OriginalError) ||
        \\        reason.message!=="Should not query options before bootstrapping is done" ||
        \\        reason.code!=="inherited readonly code" || Object.hasOwn(reason,"code"))
        \\      throw new OriginalError("bootstrap Object::Set must retain its nonthrowing failed assignment");
        \\  }
        \\} finally {
        \\  if (oldCode) Object.defineProperty(OriginalError.prototype,"code",oldCode);
        \\  else delete OriginalError.prototype.code;
        \\}
    , "actual-node-options-bootstrap-error.mjs");
    engine.freeValue(result);
    try std.testing.expect(engine.node_options.?.serialized);
}
test "native actual Node options selected serializer defines fresh null prototype data records" {
    var fixture: Fixture = undefined; try fixture.init(true); defer fixture.deinit();
    const record = try a.expression(fixture.engine, bindingRecord, .{}); defer fixture.engine.freeValue(record);
    _ = try a.expression(fixture.engine, publishBody, .{ "actualOptionsBootstrapBinding", record });
    try fixture.run(
        \\const names=["--conditions","--addons","host","port","hasEmbedderPreload"];
        \\const old=names.map(name=>Object.getOwnPropertyDescriptor(Object.prototype,name));
        \\let setterCalls=0;
        \\try {
        \\  for(const name of names)Object.defineProperty(Object.prototype,name,{configurable:true,set(){setterCalls++;}});
        \\  const one=actualOptionsBootstrapBinding.values(),two=actualOptionsBootstrapBinding.values();
        \\  optionsAssert(Object.getPrototypeOf(one)===null&&Object.getPrototypeOf(two)===null,"actual null-prototype native result");
        \\  optionsAssert(one!==two&&one["--conditions"]!==two["--conditions"],"fresh serializer object and list identity");
        \\  optionsAssert(Object.getPrototypeOf(one["--inspect-port"])===null,"actual host-port null prototype");
        \\  for(const name of ["--addons","--no-addons","--conditions","--experimental-quic"]) {
        \\    const descriptor=Object.getOwnPropertyDescriptor(one,name);
        \\    optionsAssert(descriptor&&descriptor.writable&&descriptor.enumerable&&descriptor.configurable&&"value" in descriptor,"actual own data "+name);
        \\  }
        \\  const keys=Object.keys(one);
        \\  optionsAssert(keys.indexOf("--no-addons")<keys.indexOf("--addons"),"negated Boolean defined before original");
        \\  optionsAssert(!Object.hasOwn(one,"--no-experimental-quic")&&one["--experimental-quic"]===undefined,"real disabled QUIC no-op");
        \\  optionsAssert(actualOptionsBootstrapBinding.embedder().hasEmbedderPreload===true&&setterCalls===0,"own fields bypass inherited setters");
        \\} finally {for(let i=0;i<names.length;i++)optionsRestore(Object.prototype,names[i],old[i]);}
    );
    try std.testing.expect(fixture.engine.node_options.?.serialized);
}
test "native actual Node options ordinary declaration shapes retain original construction behavior" { try observe("observeOptionsShapes"); }
test "native actual Node options native selected values and embedder flags feed both declarations" { try observe("observeOptionsValues"); }
test "native actual Node options lazy caches and refresh preserve the actual startup snapshot" { try observe("observeOptionsCache"); }
test "native actual Node options computed key reentry retains its selected dictionary" { try observe("observeOptionsKeyRefresh"); }
test "native actual Node options live unauthorized predicate is strict and warning occurs once" { try observe("observeOptionsWarningPredicate"); }
test "native actual Node options warning flag precedes a failed live warning getter" { try observe("observeOptionsWarningFailure"); }
test "native actual Node options chained receivers and selected warning callee retire at Source boundaries" {
    inline for (.{ false, true }) |native| {
        var fixture: Fixture = undefined; try fixture.init(native); defer fixture.deinit();
        try fixture.run("observeOptionsChainRetirement(actualNodeOptions);");
        try std.testing.expectEqual([3]u32{ 1, 1, 1 }, fixture.probe.freed);
        try fixture.engine.checkNativeEntry();
    }
}
test "native actual Node options private DATA remains ordinary through four fresh callback routes" {
    inline for (.{ false, true }) |native| {
        inline for (0..4) |route| {
            var fixture: Fixture = undefined; try fixture.init(native); defer fixture.deinit();
            try fixture.run(std.fmt.comptimePrint("observeOptionsPrivateData(actualNodeOptions,{d});", .{route}));
            try fixture.engine.checkNativeEntry();
        }
    }
}
test "native actual Node options successful flagged warning return remains discarded DATA" {
    inline for (.{ false, true }) |native| {
        var fixture: Fixture = undefined; try fixture.init(native); defer fixture.deinit();
        try fixture.run("observeOptionsFlaggedReturn(actualNodeOptions);");
        const data = try fixture.value("actualOptionsSelectedData"); defer fixture.engine.freeValue(data);
        try std.testing.expect(c.JS_IsUncatchableError(data));
        try std.testing.expect(c.pi_js_native_allocation_error_generation(data) != 0);
        try fixture.engine.checkNativeEntry();
    }
}
fn progress(fixture: *Fixture) !c.JSValue {
    try fixture.run("globalThis.actualOptionsProgress={process:0,environment:0,value:0,warning:0,after:0,caught:0};");
    return fixture.value("actualOptionsProgress");
}
fn verifyFatal(fixture: *Fixture, result: anyerror!void, record: c.JSValue, expected: [6]u32) !void {
    try std.testing.expectError(error.JavaScriptException, result);
    const reason = fixture.engine.captured_exception orelse return error.MissingActualOptionsFatalReason;
    try std.testing.expect(c.JS_IsStrictEqual(fixture.engine.context, reason, fixture.probe.first));
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expect(c.pi_js_native_allocation_error_generation(reason) != 0);
    try std.testing.expect(fixture.engine.native_fatal_invocation == null);
    inline for (.{ "process", "environment", "value", "warning", "after", "caught" }, 0..) |name, index| {
        // Only retained known own numeric data is read after fatal completion.
        const value = c.JS_GetPropertyStr(fixture.engine.context, record, name);
        defer fixture.engine.freeValue(value);
        try std.testing.expect(c.JS_IsNumber(value));
        var count: u32 = 0;
        try std.testing.expectEqual(@as(c_int, 0), c.JS_ToUint32(fixture.engine.context, &count, value));
        try std.testing.expectEqual(expected[index], count);
    }
}
test "native actual Node options real warning getter fatal prevents guest continuation and catch" {
    inline for (.{ false, true }) |native| {
        var fixture: Fixture = undefined; try fixture.init(native); defer fixture.deinit();
        const record = try progress(&fixture); defer fixture.engine.freeValue(record);
        const result = fixture.run(
            \\installOptionsFatalRoute(false);
            \\try{actualNodeOptions.getAllowUnauthorized();actualOptionsProgress.after++;}
            \\catch{actualOptionsProgress.caught++;}
        );
        try verifyFatal(&fixture, result, record, .{ 2, 0, 0, 1, 0, 0 });
    }
}
test "native actual Node options process receiver retirement fatal prevents the next environment getter" {
    inline for (.{ false, true }) |native| {
        var fixture: Fixture = undefined; try fixture.init(native); defer fixture.deinit();
        const record = try progress(&fixture); defer fixture.engine.freeValue(record);
        fixture.probe.fatal_slot = 0;
        const result = fixture.run(
            \\installOptionsFatalRoute(true);
            \\try{actualNodeOptions.getAllowUnauthorized();actualOptionsProgress.after++;}
            \\catch{actualOptionsProgress.caught++;}
        );
        try verifyFatal(&fixture, result, record, .{ 1, 1, 0, 0, 0, 0 });
        try std.testing.expectEqual(@as(u32, 1), fixture.probe.freed[0]);
    }
}
fn callAlreadyPending(fixture: *Fixture, function: c.JSValue) !void {
    const result = try a.call(fixture.engine, function, c.pi_js_undefined(), &.{});
    fixture.engine.freeValue(result);
}
test "native actual Node options already current fatal prevents entry to the selected callable" {
    var fixture: Fixture = undefined; try fixture.init(true); defer fixture.deinit();
    const record = try progress(&fixture); defer fixture.engine.freeValue(record);
    try fixture.run("installOptionsFatalRoute(true);");
    const function = try a.field(fixture.engine, fixture.owner.?, "getAllowUnauthorized"); defer fixture.engine.freeValue(function);
    _ = preserveFatal(&fixture.probe);
    try verifyFatal(&fixture, callAlreadyPending(&fixture, function), record, .{ 0, 0, 0, 0, 0, 0 });
}
test "native actual Node options completed private owner preserves function and configuration identity" {
    var fixture: Fixture = undefined; try fixture.init(true); defer fixture.deinit();
    const again = try options.acquire(fixture.engine); defer fixture.engine.freeValue(again);
    try std.testing.expect(c.JS_IsStrictEqual(fixture.engine.context, fixture.owner.?, again));
    const retained = fixture.engine.node_options.?;
    try fixture.run("actualNodeOptions.refreshOptions();observeOptionsValues(actualNodeOptions);");
    try std.testing.expect(fixture.engine.node_options.? == retained);
    try std.testing.expect(retained.bootstrapped and retained.serialized);
}

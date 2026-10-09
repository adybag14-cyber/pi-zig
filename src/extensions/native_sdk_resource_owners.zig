//! An actual ResourceLoader's native scope owns its private invocation broker.
//! Main membership and JSON context cannot create this scope or SDK admission.
const std = @import("std");
const engine_mod = @import("engine.zig");
const Engine = engine_mod.Engine;
const c = engine_mod.c;
const group_mod = @import("native_group.zig");
const bindings = @import("native_bindings.zig");
const sdk = @import("native_sdk.zig");
const vm = @import("native_values.zig");
pub const Scope = struct {
    engine: *Engine,
    group: *group_mod.Group,
    renderers: ?*@import("native_renderers.zig").Manager,
    broker: bindings.Bindings.InvocationBroker = .{},
    provider_clock: u64 = 0,
    references: usize = 1,
    retired: bool = false,
    runtime_invalidated: bool = false,
    next_retired: ?*Scope = null,
    owner_value: ?c.JSValue = null,
    bound_lease: ?@import("native_sdk_model_bridge.zig").Lease = null,
    pub fn retain(self: *Scope) *Scope {
        self.references += 1;
        return self;
    }
    pub fn release(self: *Scope) void {
        std.debug.assert(self.references != 0);
        self.references -= 1;
        if (self.references == 0) {
            self.closeRenderers();
            self.engine.gpa.destroy(self);
        }
    }
    pub fn closeRenderers(self: *Scope) void {
        const renderer = self.renderers orelse return;
        self.renderers = null;
        renderer.deinit();
    }
};
fn finalizer(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const engine: *Engine = @ptrCast(@alignCast(c.JS_GetRuntimeOpaque(runtime)));
    const scope: *Scope = @ptrCast(@alignCast(c.JS_GetOpaque(value, engine.native_sdk_resource_scope_class) orelse return));
    _ = c.JS_SetOpaque(value, null);
    if (!scope.retired and engine.native_sdk_extension_group == @as(?*anyopaque, @ptrCast(scope.group)) and !scope.group.deinitializing) {
        scope.retired = true;
        // A class finalizer must not invoke guest component disposal. Retire
        // API tokens now; the owner VM drains native registrations later.
        for (scope.group.entries.items) |entry| if (entry.sdk_scope == scope) entry.binding.retireScopeValuesRT(runtime);
        if (scope.renderers) |renderers| renderers.retireScopeValuesRT(runtime);
        _ = scope.retain();
        scope.next_retired = if (engine.native_sdk_resource_retire_pending) |raw| @ptrCast(@alignCast(raw)) else null;
        engine.native_sdk_resource_retire_pending = scope;
    }
    if (scope.owner_value) |owner_value| {
        scope.owner_value = null;
        c.JS_FreeValueRT(runtime, owner_value);
    }
    scope.release();
}
fn mark(runtime: ?*c.JSRuntime, value: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
    const engine: *Engine = @ptrCast(@alignCast(c.JS_GetRuntimeOpaque(runtime)));
    const scope: *Scope = @ptrCast(@alignCast(c.JS_GetOpaque(value, engine.native_sdk_resource_scope_class) orelse return));
    if (scope.owner_value) |owner_value| c.JS_MarkValue(runtime, owner_value, marker);
    if (!scope.retired and engine.native_sdk_extension_group == @as(?*anyopaque, @ptrCast(scope.group)) and !scope.group.deinitializing) {
        for (scope.group.entries.items) |entry| if (entry.sdk_scope == scope) entry.binding.markScopeValues(runtime, marker);
        if (scope.renderers) |renderers| renderers.markScopeValues(runtime, marker);
    }
}
pub fn create(group: *group_mod.Group) !c.JSValue {
    const engine = group.engine;
    engine.native_sdk_resource_owner_pump = pump;
    engine.native_sdk_resource_owner_deinit = deinit;
    if (engine.native_sdk_resource_scope_class == 0) {
        var id: c.JSClassID = 0;
        _ = c.JS_NewClassID(engine.runtime, &id);
        const definition: c.JSClassDef = .{ .class_name = "Private SDK resource owner", .finalizer = finalizer, .gc_mark = mark };
        if (c.JS_NewClass(engine.runtime, id, &definition) < 0) return error.OutOfMemory;
        engine.native_sdk_resource_scope_class = id;
    }
    const scope = try engine.gpa.create(Scope);
    errdefer engine.gpa.destroy(scope);
    const renderers = try @import("native_renderers.zig").Manager.init(engine);
    errdefer renderers.deinit();
    scope.* = .{ .engine = engine, .group = group, .renderers = renderers };
    const result = try engine.checked(c.JS_NewObjectClass(engine.context, engine.native_sdk_resource_scope_class));
    errdefer engine.freeValue(result);
    try group.sdk_scopes.ensureUnusedCapacity(engine.gpa, 1);
    _ = c.JS_SetOpaque(result, scope);
    scope.owner_value = c.JS_DupValue(engine.context, result);
    group.sdk_scopes.appendAssumeCapacity(scope.retain());
    return result;
}
pub fn fromValue(group: *group_mod.Group, value: c.JSValue) !*Scope {
    if (group.engine.native_sdk_resource_scope_class == 0) return error.InvalidSDKResourceOwner;
    const scope: *Scope = @ptrCast(@alignCast(c.JS_GetOpaque(value, group.engine.native_sdk_resource_scope_class) orelse return error.InvalidSDKResourceOwner));
    if (scope.engine != group.engine or scope.group != group or scope.retired or group.deinitializing) return error.InvalidSDKResourceOwner;
    return scope;
}
pub fn pump(engine: *Engine) !bool {
    var worked = false;
    while (engine.native_sdk_resource_retire_pending) |raw| {
        const scope: *Scope = @ptrCast(@alignCast(raw));
        engine.native_sdk_resource_retire_pending = scope.next_retired;
        scope.next_retired = null;
        defer scope.release();
        if (engine.native_sdk_extension_group == @as(?*anyopaque, @ptrCast(scope.group)) and !scope.group.deinitializing) {
            while (true) {
                var found: ?u64 = null;
                for (scope.group.entries.items) |entry| if (entry.sdk_scope == scope) {
                    found = entry.id;
                    break;
                };
                try scope.group.remove(found orelse break);
            }
            for (scope.group.sdk_scopes.items, 0..) |candidate, index| if (candidate == scope) {
                _ = scope.group.sdk_scopes.orderedRemove(index);
                scope.release();
                break;
            };
        }
        worked = true;
    }
    return worked;
}
pub fn deinit(engine: *Engine) void {
    engine.native_sdk_resource_owner_pump = null;
    engine.native_sdk_resource_owner_deinit = null;
    while (engine.native_sdk_resource_retire_pending) |raw| {
        const scope: *Scope = @ptrCast(@alignCast(raw));
        engine.native_sdk_resource_retire_pending = scope.next_retired;
        scope.release();
    }
}
pub fn uninitialized(engine: *Engine) !c.JSValue {
    const message = try engine.checked(c.JS_NewString(engine.context, "Extension runtime not initialized. Action methods cannot be called during extension loading."));
    defer engine.freeValue(message);
    const reason = try @import("native_js_values.zig").builtin(engine, "Error", &.{message});
    return engine.checked(c.JS_Throw(engine.context, reason));
}
fn sessionScopeValue(engine: *Engine, session_data: c.JSValue) !c.JSValue {
    const captured = try vm.get(engine, session_data, "_sdkExtensionOwnerScope");
    if (!c.JS_IsUndefined(captured)) return captured;
    engine.freeValue(captured);
    const resource = try vm.get(engine, session_data, "resourceLoader");
    defer engine.freeValue(resource);
    const raw = c.JS_GetOpaque(resource, engine.native_sdk_class) orelse return c.pi_js_undefined();
    const loader: *sdk.State = @ptrCast(@alignCast(raw));
    if (loader.kind != .resource_loader) return c.pi_js_undefined();
    return vm.get(engine, loader.data, "_sdkExtensionOwnerScope");
}
fn sessionScope(owner: *sdk.State) !?*Scope {
    const engine = owner.engine;
    const value = try sessionScopeValue(engine, owner.data);
    defer engine.freeValue(value);
    if (c.JS_IsUndefined(value)) return null;
    if (engine.native_sdk_resource_scope_class == 0) return error.InvalidSDKResourceOwner;
    return @ptrCast(@alignCast(c.JS_GetOpaque(value, engine.native_sdk_resource_scope_class) orelse return error.InvalidSDKResourceOwner));
}
/// Owned IDs from the actual constructor-captured runtime incarnation. Calls
/// made before constructor binding may inspect only the loader's current one.
pub fn sessionOwnerIds(engine: *Engine, session_data: c.JSValue) !c.JSValue {
    const value = try sessionScopeValue(engine, session_data);
    defer engine.freeValue(value);
    if (c.JS_IsUndefined(value)) return c.pi_js_undefined();
    const group: *group_mod.Group = @ptrCast(@alignCast(engine.native_sdk_extension_group orelse return error.NativeSDKExtensionGroupUnavailable));
    _ = try fromValue(group, value);
    return vm.get(engine, value, "_extensionOwnerIds");
}
pub fn sessionScopeRetired(owner: *sdk.State) !bool {
    const scope = (try sessionScope(owner)) orelse return false;
    return scope.retired or owner.engine.native_sdk_extension_group != @as(?*anyopaque, @ptrCast(scope.group));
}
pub fn assertSessionScope(owner: *sdk.State, group: *group_mod.Group) !void {
    const scope = (try sessionScope(owner)) orelse return;
    if (scope.retired or scope.group != group or scope.engine != group.engine) return error.InvalidSDKResourceOwner;
}
pub fn bindSession(owner: *sdk.State) !void {
    const scope = (try sessionScope(owner)) orelse return;
    const engine = owner.engine;
    const group: *group_mod.Group = @ptrCast(@alignCast(engine.native_sdk_extension_group orelse return error.NativeSDKExtensionGroupUnavailable));
    try assertSessionScope(owner, group);
    const lease = try sdk.sessionModelLease(owner);
    const session = try sdk.sessionDataSessionValue(engine, owner.data);
    defer engine.freeValue(session);
    const value = scope.owner_value orelse return error.InvalidSDKResourceOwner;
    try vm.put(engine, owner.data, "_sdkExtensionOwnerScope", c.JS_DupValue(engine.context, value));
    if (c.JS_DefinePropertyValueStr(engine.context, value, "_boundSession", c.JS_DupValue(engine.context, session), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    scope.bound_lease = lease;
}
/// Disposing any runner invalidates the shared ExtensionRuntime for this
/// loader incarnation. A later constructor or bind does not clear that state.
/// Handler ownership and pure definitions remain alive until graph retirement.
pub fn invalidateSessionRuntime(owner: *sdk.State) !void {
    const value = try vm.get(owner.engine, owner.data, "_sdkExtensionOwnerScope");
    defer owner.engine.freeValue(value);
    if (c.JS_IsUndefined(value) or owner.engine.native_sdk_resource_scope_class == 0) return;
    const scope: *Scope = @ptrCast(@alignCast(c.JS_GetOpaque(value, owner.engine.native_sdk_resource_scope_class) orelse return error.InvalidSDKResourceOwner));
    if (scope.engine != owner.engine) return error.InvalidSDKResourceOwner;
    scope.runtime_invalidated = true;
}
/// Pi's runtime availability is independent of an event's actual session
/// context. Live B contexts still work after shared runner A invalidates Pi.
pub fn assertPiRuntime(caller: *bindings.Bindings) !void {
    if (!caller.sdk_resource_owner) return;
    const engine = caller.engine;
    const group: *group_mod.Group = @ptrCast(@alignCast(engine.native_sdk_extension_group orelse return error.NativeSDKExtensionGroupUnavailable));
    if (try group.selected(caller.owner_id) != caller) return error.StaleNativeExtensionOwner;
    for (group.entries.items) |entry| if (entry.binding == caller) {
        const scope = entry.sdk_scope orelse return error.InvalidSDKResourceOwner;
        if (scope.runtime_invalidated) try stale(engine);
        return;
    };
    return error.StaleNativeExtensionOwner;
}
pub fn releaseContext(engine: *Engine, context: bindings.Bindings.SdkContext) void {
    engine.freeValue(context.session);
    engine.freeValue(context.registry);
    engine.freeValue(context.manager);
}
fn stale(engine: *Engine) !void {
    const text = @import("native_context_lifetime.zig").default_message;
    const message = try engine.checked(c.JS_NewStringLen(engine.context, text.ptr, text.len));
    defer engine.freeValue(message);
    const reason = try @import("native_js_values.zig").builtin(engine, "Error", &.{message});
    _ = try engine.checked(c.JS_Throw(engine.context, reason));
}
pub fn defaultContext(caller: *bindings.Bindings) !?bindings.Bindings.SdkContext {
    if (!caller.sdk_resource_owner) return null;
    const engine = caller.engine;
    if (engine.native_sdk_default_admission) |admit| try admit(engine, caller.owner_id);
    const group: *group_mod.Group = @ptrCast(@alignCast(engine.native_sdk_extension_group orelse return error.NativeSDKExtensionGroupUnavailable));
    if (try group.selected(caller.owner_id) != caller) return error.StaleNativeExtensionOwner;
    var selected: ?*Scope = null;
    for (group.entries.items) |entry| if (entry.binding == caller) {
        selected = entry.sdk_scope;
        break;
    };
    const scope = selected orelse return error.InvalidSDKResourceOwner;
    const expected = scope.bound_lease orelse return null;
    const object = scope.owner_value orelse return error.StaleNativeExtensionOwner;
    const session = try vm.get(engine, object, "_boundSession");
    errdefer engine.freeValue(session);
    const owner = try sdk.state(engine, session);
    const actual = sdk.sessionModelLease(owner) catch {
        try stale(engine);
        unreachable;
    };
    if (actual.generation != expected.generation or actual.runtime_id != expected.runtime_id) {
        try stale(engine);
        unreachable;
    }
    try assertSessionScope(owner, group);
    const registry = try vm.get(engine, owner.data, "modelRegistry");
    errdefer engine.freeValue(registry);
    const manager = try vm.get(engine, owner.data, "sessionManager");
    return .{ .session = session, .registry = registry, .manager = manager, .lease = actual };
}
/// Root the exact session, registry and manager before observing private data.
pub const Caller = struct {
    engine: *Engine,
    session: c.JSValue,
    registry: c.JSValue,
    manager: c.JSValue,
    owner: *sdk.State,
    pub fn deinit(self: *Caller) void {
        self.engine.freeValue(self.session);
        self.engine.freeValue(self.registry);
        self.engine.freeValue(self.manager);
    }
    pub fn owns(self: *Caller, id: u64) !bool {
        const ids = try sessionOwnerIds(self.engine, self.owner.data);
        defer self.engine.freeValue(ids);
        if (!c.JS_IsArray(ids)) return false;
        for (0..try vm.length(self.engine, ids)) |index| {
            const value = try self.engine.checked(c.JS_GetPropertyUint32(self.engine.context, ids, @intCast(index)));
            defer self.engine.freeValue(value);
            var integer: i64 = 0;
            if (c.JS_ToInt64(self.engine.context, &integer, value) < 0) return error.JavaScriptException;
            if (integer > 0 and @as(u64, @intCast(integer)) == id) return true;
        }
        return false;
    }
};
pub fn retainCaller(caller: *bindings.Bindings) !Caller {
    const engine = caller.engine;
    const scope = caller.sdk_context orelse return error.NativeSDKContextUnavailable;
    var retained: Caller = .{ .engine = engine, .session = c.JS_DupValue(engine.context, scope.session), .registry = c.JS_DupValue(engine.context, scope.registry), .manager = c.JS_DupValue(engine.context, scope.manager), .owner = undefined };
    errdefer retained.deinit();
    const group: *group_mod.Group = @ptrCast(@alignCast(engine.native_sdk_extension_group orelse return error.NativeSDKExtensionGroupUnavailable));
    if (try group.selected(caller.owner_id) != caller) return error.StaleNativeExtensionOwner;
    retained.owner = try sdk.state(engine, retained.session);
    try assertSessionScope(retained.owner, group);
    const actual = try sdk.sessionModelLease(retained.owner);
    if (actual.runtime_id != scope.lease.runtime_id or actual.generation != scope.lease.generation) return error.InvalidNativeSDKModelLease;
    const registry = try vm.get(engine, retained.owner.data, "modelRegistry");
    defer engine.freeValue(registry);
    const manager = try vm.get(engine, retained.owner.data, "sessionManager");
    defer engine.freeValue(manager);
    const lease = try sdk.modelRegistryLease(engine, retained.registry);
    if (!c.JS_IsStrictEqual(engine.context, registry, retained.registry) or !c.JS_IsStrictEqual(engine.context, manager, retained.manager) or lease.runtime_id != actual.runtime_id) return error.InvalidNativeSDKContext;
    return retained;
}

test "ToolInfo shared SDK loader disposal invalidates Pi across constructors while live session contexts and new incarnations remain independent" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    const main = try group.add("<main>");
    try main.installSchemas();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_size = try temporary.dir.realPath(std.testing.io, &root_buffer);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try vm.put(engine, global, "sharedLoaderCwd", try sdk.text(engine, root_buffer[0..root_size]));
    const source = @embedFile("../durable/fixtures/sdk-shared-loader-dispose-1ced.json");
    try vm.put(engine, global, "sharedLoaderSource", try engine.checked(c.JS_ParseJSON(engine.context, source, source.len, "actual-shared-loader-disposal")));
    const before = try group.manifest();
    defer engine.gpa.free(before);
    const output = engine.evalModule(
        \\import{createAgentSession,SessionManager,SettingsManager,DefaultResourceLoader,ModelRuntime}from'@earendil-works/pi-coding-agent';
        \\const cwd=sharedLoaderCwd,runtime=await ModelRuntime.create({modelsPath:null,refreshOnCreate:false,credentials:{read:async()=>undefined,list:async()=>[]}}),settings=SettingsManager.inMemory({defaultTools:[]}),cases=[],events=[];let savedPi,generation=0;
        \\const probe=pi=>{try{return{name:pi.getSessionName(),names:pi.getAllTools().map(tool=>tool.name)}}catch(error){return{errorName:error.name,error:error.message}}};
        \\const loader=new DefaultResourceLoader({cwd,agentDir:cwd,settingsManager:settings,noExtensions:true,noSkills:true,noPromptTemplates:true,noThemes:true,noContextFiles:true,extensionFactories:[pi=>{savedPi=pi;const incarnation=++generation;pi.registerTool({name:'owned',description:'owned',parameters:{type:'object'},execute:async()=>({content:[]})});pi.on('session_start',(_,ctx)=>{let current;try{current={name:ctx.sessionManager.getSessionName(),idle:ctx.isIdle()}}catch(error){current={error:error.message}}events.push({incarnation,context:current,pi:probe(pi)})})}]});
        \\const create=async name=>{const{session}=await createAgentSession({cwd,resourceLoader:loader,modelRuntime:runtime,sessionManager:SessionManager.inMemory(cwd),settingsManager:settings,tools:['owned']});session.setSessionName(name);return session};
        \\await loader.reload();const originalPi=savedPi,A=await create('A');await A.bindExtensions({});cases.push({phase:'A',pi:probe(originalPi)});
        \\const B=await create('B');cases.push({phase:'B-before-A-dispose',pi:probe(originalPi)});A.dispose();cases.push({phase:'A-disposed',pi:probe(originalPi),pureB:B.getAllTools().map(tool=>tool.name)});
        \\let registered=false;try{originalPi.on('after-dispose',()=>{});registered=true}catch(error){if(error.message!==sharedLoaderSource.cases[2].pi.error)throw error}if(registered)throw Error('stale runtime registration admitted');
        \\await B.bindExtensions({});cases.push({phase:'B-bind-after-A-dispose',pi:probe(originalPi)});await B.bindExtensions({});cases.push({phase:'B-rebind',pi:probe(originalPi)});
        \\await loader.reload();const nextPi=savedPi,C=await create('C');await C.bindExtensions({});cases.push({phase:'new-incarnation',oldPi:probe(originalPi),newPi:probe(nextPi),same:originalPi===nextPi});
        \\B.dispose();cases.push({phase:'old-B-disposed-new-C-live',pi:probe(nextPi)});C.dispose();
        \\if(JSON.stringify({cases,events})!==JSON.stringify({cases:sharedLoaderSource.cases,events:sharedLoaderSource.events}))throw Error(JSON.stringify({cases,events,source:sharedLoaderSource}));
    , "actual-shared-loader-disposal") catch |err| {
        std.debug.print("Actual shared SDK runtime disposal: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(output);
    const after = try group.manifest();
    defer engine.gpa.free(after);
    try std.testing.expectEqualStrings(before, after);
}

test "ToolInfo actual OLD SDK Pi retains its constructor runtime across direct loader reload and new constructor binding" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    const main = try group.add("<main>");
    try main.installSchemas();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const path_size = try temporary.dir.realPath(std.testing.io, &path_buffer);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try vm.put(engine, global, "ownedCwd", try sdk.text(engine, path_buffer[0..path_size]));
    const source = @embedFile("../durable/fixtures/sdk-resource-old-pi-reload-1ced.json");
    const fixture = try engine.checked(c.JS_ParseJSON(engine.context, source, source.len, "actual-old-Pi"));
    defer engine.freeValue(fixture);
    try vm.put(engine, global, "oldPiFixture", c.JS_DupValue(engine.context, fixture));
    const event_source = @embedFile("../durable/fixtures/sdk-resource-old-pi-events-1ced.json");
    const event_fixture = try engine.checked(c.JS_ParseJSON(engine.context, event_source, event_source.len, "actual-old-Pi-events"));
    defer engine.freeValue(event_fixture);
    try vm.put(engine, global, "oldPiEventFixture", c.JS_DupValue(engine.context, event_fixture));
    const before = try group.manifest();
    defer engine.gpa.free(before);
    const output = engine.evalModule(
        \\import{createAgentSession,SessionManager,SettingsManager,DefaultResourceLoader}from'@earendil-works/pi-coding-agent';
        \\let currentPi,number=0;const observed=[],events=[],cwd=ownedCwd,settings=SettingsManager.inMemory({defaultTools:[]});
        \\const loader=new DefaultResourceLoader({cwd,agentDir:cwd,settingsManager:settings,noExtensions:true,noSkills:true,noPromptTemplates:true,noThemes:true,noContextFiles:true,extensionFactories:[{factory:pi=>{currentPi=pi;number++;const generation=number;pi.on('session_start',()=>events.push({generation,names:pi.getAllTools().map(t=>t.name),sessionName:pi.getSessionName()}));pi.registerTool({name:'own'+number,description:'own',parameters:{type:'object',properties:{}},execute:async()=>({content:[]})})}}]});
        \\const check=(phase,pi)=>{try{observed.push({phase,names:pi.getAllTools().map(t=>t.name),sessionName:pi.getSessionName()})}catch(error){observed.push({phase,error:error.message,errorName:error.name})}};
        \\const create=async(name,tool)=>{const{session}=await createAgentSession({cwd,agentDir:cwd,sessionManager:SessionManager.inMemory(cwd),settingsManager:settings,resourceLoader:loader,tools:[tool],model:{id:'fixture',name:'Fixture',api:'openai-responses',provider:'fixture',baseUrl:'https://example.invalid',reasoning:false,input:['text'],cost:{input:0,output:0,cacheRead:0,cacheWrite:0},contextWindow:8192,maxTokens:1024}});session.setSessionName(name);return session;};
        \\await loader.reload();const oldPi=currentPi;check('old-loaded',oldPi);
        \\const A=await create('A','own1');check('old-A-created',oldPi);await A.bindExtensions({});check('old-A-bound',oldPi);
        \\await loader.reload();const newPi=currentPi;observed.push({phase:'reload-identity',same:oldPi===newPi});check('old-after-reload',oldPi);check('new-after-reload',newPi);
        \\const B=await create('B','own2');check('old-after-B-created',oldPi);check('new-after-B-created',newPi);await B.bindExtensions({});check('old-after-B-bound',oldPi);check('new-after-B-bound',newPi);
        \\if(A.getAllTools().map(t=>t.name).join(',')!=='own1'||B.getAllTools().map(t=>t.name).join(',')!=='own2')throw Error('session incarnation changed');
        \\await A.bindExtensions({});if(JSON.stringify(events)!==JSON.stringify(oldPiEventFixture))throw Error(JSON.stringify({events,source:oldPiEventFixture}));
        \\A.dispose();check('old-after-A-disposed',oldPi);check('new-after-A-disposed',newPi);
        \\B.dispose();check('old-after-B-disposed',oldPi);check('new-after-B-disposed',newPi);
        \\if(JSON.stringify(observed)!==JSON.stringify(oldPiFixture))throw Error(JSON.stringify({observed,source:oldPiFixture}));
    , "actual-old-pi-reload-incarnations.mjs") catch |err| {
        std.debug.print("Actual OLD SDK Pi: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(output);
    const after = try group.manifest();
    defer engine.gpa.free(after);
    try std.testing.expectEqualStrings(before, after);
}

test "ToolInfo SDK reload incarnations preserve the live constructor owner and collect every failed unrooted candidate allocation" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const engine = try Engine.init(failing.allocator(), .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    const main = try group.add("<main>");
    try main.installSchemas();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const path_size = try temporary.dir.realPath(std.testing.io, &path_buffer);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try vm.put(engine, global, "ownedCwd", try sdk.text(engine, path_buffer[0..path_size]));
    const namespace = try engine.evalModule(
        \\import{createAgentSession,SessionManager,SettingsManager,DefaultResourceLoader}from'@earendil-works/pi-coding-agent';
        \\const cwd=ownedCwd,settings=SettingsManager.inMemory({defaultTools:[]});
        \\export const loader=new DefaultResourceLoader({cwd,agentDir:cwd,settingsManager:settings,noExtensions:true,noSkills:true,noPromptTemplates:true,noThemes:true,noContextFiles:true,extensionFactories:[{factory:pi=>pi.registerTool({name:'own',description:'own',parameters:{type:'object'},execute(){return{content:[]}}})}]});
        \\await loader.reload();export const{session}=await createAgentSession({cwd,agentDir:cwd,resourceLoader:loader,settingsManager:settings,sessionManager:SessionManager.inMemory(cwd),tools:['own'],model:{id:'fixture',provider:'fixture',api:'openai-responses',name:'Fixture',input:['text'],contextWindow:8192,maxTokens:1024,cost:{input:0,output:0,cacheRead:0,cacheWrite:0}}});
    , "sdk-reload-incarnation-allocations.mjs");
    defer engine.freeValue(namespace);
    const loader = try vm.get(engine, namespace, "loader");
    defer engine.freeValue(loader);
    const loader_state = try sdk.state(engine, loader);
    const session = try vm.get(engine, namespace, "session");
    defer engine.freeValue(session);
    const owner = try sdk.state(engine, session);
    const original = (try sessionScope(owner)).?;
    const original_lease = try sdk.sessionModelLease(owner);
    const main_manifest = try group.manifest();
    defer engine.gpa.free(main_manifest);
    var complete = false;
    var failures: usize = 0;
    for (0..2048) |offset| {
        failing.has_induced_failure = false;
        failing.fail_index = failing.alloc_index + offset;
        @import("native_sdk_resources.zig").factories(engine, loader_state.data) catch |err| {
            failing.fail_index = std.math.maxInt(usize);
            try std.testing.expect(failing.has_induced_failure);
            try std.testing.expect(err == error.OutOfMemory or err == error.JavaScriptException);
        };
        failing.fail_index = std.math.maxInt(usize);
        const induced = failing.has_induced_failure;
        if (induced) failures += 1;
        engine.beginInvocation();
        for (0..3) |_| {
            c.JS_RunGC(engine.runtime);
            _ = try engine.pumpControls();
        }
        try std.testing.expect(!original.retired);
        try std.testing.expectEqual(original, (try sessionScope(owner)).?);
        try std.testing.expectEqual(original_lease, try sdk.sessionModelLease(owner));
        const current_value = try vm.get(engine, loader_state.data, "_sdkExtensionOwnerScope");
        defer engine.freeValue(current_value);
        const current = try fromValue(group, current_value);
        try std.testing.expectEqual(@as(usize, if (current == original) 1 else 2), group.sdk_scopes.items.len);
        const manifest = try group.manifest();
        defer engine.gpa.free(manifest);
        try std.testing.expectEqualStrings(main_manifest, manifest);
        const rows = try vm.invoke(engine, session, "getAllTools", &.{});
        defer engine.freeValue(rows);
        try std.testing.expectEqual(@as(usize, 1), try vm.length(engine, rows));
        if (!induced) {
            complete = true;
            break;
        }
    }
    try std.testing.expect(complete and failures != 0);
}

test "ToolInfo constructor-bound SDK loader defaults use the actual session with explicit event and stale-fence precedence" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    const main = try group.add("<main>");
    try main.installSchemas();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const path_size = try temporary.dir.realPath(std.testing.io, &path_buffer);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try vm.put(engine, global, "ownedCwd", try sdk.text(engine, path_buffer[0..path_size]));
    const namespace = try engine.evalModule(
        "import{createAgentSession,SessionManager,SettingsManager,DefaultResourceLoader}from'@earendil-works/pi-coding-agent';let api;const cwd=ownedCwd,settings=SettingsManager.inMemory({defaultTools:[]}),loader=new DefaultResourceLoader({cwd,agentDir:cwd,settingsManager:settings,noExtensions:true,noSkills:true,noPromptTemplates:true,noThemes:true,noContextFiles:true,extensionFactories:[{name:'default',factory:pi=>{api=pi;pi.registerTool({name:'shared',description:'shared',parameters:{type:'object'},execute(){return{content:[]}}})}}]});await loader.reload();let before;try{api.getAllTools()}catch(e){before=e.message}if(!before?.startsWith('Extension runtime not initialized'))throw Error('unbound runtime');" ++
            "const make=async tag=>(await createAgentSession({cwd,agentDir:cwd,resourceLoader:loader,settingsManager:SettingsManager.inMemory({defaultTools:[],defaultProvider:tag}),sessionManager:SessionManager.inMemory(cwd),tools:['shared',tag],customTools:[{name:tag,description:tag,parameters:{type:'object'},execute(){return{content:[]}}}],model:{id:'fixture',provider:'fixture',api:'openai-responses',name:'Fixture',input:['text'],contextWindow:8192,maxTokens:1024,cost:{input:0,output:0,cacheRead:0,cacheWrite:0}}})).session;" ++
            "export const a=await make('A');if(api.getAllTools().map(t=>t.name).join(',')!=='shared,A'||api.getSettings().defaultProvider!=='A')throw Error('constructor A binding');export const b=await make('B');if(api.getAllTools().map(t=>t.name).join(',')!=='shared,B'||api.getSettings().defaultProvider!=='B')throw Error('constructor B binding');globalThis.savedDefaultApi=api;export{loader};",
        "sdk-constructor-default-scope.mjs",
    );
    defer engine.freeValue(namespace);
    const a = try vm.get(engine, namespace, "a");
    defer engine.freeValue(a);
    const owner = try sdk.state(engine, a);
    const registry = try vm.get(engine, owner.data, "modelRegistry");
    defer engine.freeValue(registry);
    const manager = try vm.get(engine, owner.data, "sessionManager");
    defer engine.freeValue(manager);
    const loader_value = try vm.get(engine, namespace, "loader");
    defer engine.freeValue(loader_value);
    const loader = try sdk.state(engine, loader_value);
    const ids = try vm.get(engine, loader.data, "extensionOwnerIds");
    defer engine.freeValue(ids);
    const id_value = try engine.checked(c.JS_GetPropertyUint32(engine.context, ids, 0));
    defer engine.freeValue(id_value);
    var id: i64 = 0;
    if (c.JS_ToInt64(engine.context, &id, id_value) < 0) return error.JavaScriptException;
    const private = try group.selected(@intCast(id));
    const Denied = struct {
        fn call(_: *Engine, _: u64) !void {
            return error.DefaultSDKAdmissionDenied;
        }
    };
    engine.native_sdk_default_admission = Denied.call;
    const saved = try private.pushSdkContext(.{ .session = a, .registry = registry, .manager = manager, .lease = try sdk.sessionModelLease(owner) });
    const override = try engine.eval("if(savedDefaultApi.getAllTools().map(t=>t.name).join(',')!=='shared,A')throw Error('explicit event override');true", "sdk-explicit-scope-override.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(override);
    private.restoreSdkContext(saved);
    const denied = try engine.eval("let denied=false;try{savedDefaultApi.getAllTools()}catch(e){denied=e.message.includes('DefaultSDKAdmissionDenied')}if(!denied)throw Error('stale event default escape');true", "sdk-default-denial-precedence.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(denied);
    engine.native_sdk_default_admission = null;
    const restored = try engine.eval("if(savedDefaultApi.getAllTools().map(t=>t.name).join(',')!=='shared,B')throw Error('default not restored');true", "sdk-default-restored.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(restored);
    const b = try vm.get(engine, namespace, "b");
    defer engine.freeValue(b);
    const disposed = try vm.invoke(engine, b, "dispose", &.{});
    engine.freeValue(disposed);
    const stale_result = try engine.eval("let stale=false;try{savedDefaultApi.getAllTools()}catch(e){stale=e.message.startsWith('This extension ctx is stale')}if(!stale)throw Error('disposed default SDK lease');true", "sdk-default-disposed.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(stale_result);
}

test "ToolInfo SDK loader and Pi retain the session through marked JS edges while independent definitions and abandoned cycles collect" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    const main = try group.add("<main>");
    try main.installSchemas();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const path_size = try temporary.dir.realPath(std.testing.io, &path_buffer);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try vm.put(engine, global, "ownedCwd", try sdk.text(engine, path_buffer[0..path_size]));
    const setup = try engine.evalModule(
        "import{createAgentSession,SessionManager,SettingsManager,DefaultResourceLoader}from'@earendil-works/pi-coding-agent';globalThis.makeGcProbe=async keep=>{let api;const cwd=ownedCwd,settings=SettingsManager.inMemory({defaultTools:[]}),loader=new DefaultResourceLoader({cwd,agentDir:cwd,settingsManager:settings,noExtensions:true,noSkills:true,noPromptTemplates:true,noThemes:true,noContextFiles:true,extensionFactories:[{factory:pi=>{api=pi;pi.registerTool({name:'independent',description:'independent',parameters:{type:'object'},execute(){return{content:[]}}})}}]});await loader.reload();const{session}=await createAgentSession({cwd,agentDir:cwd,resourceLoader:loader,settingsManager:settings,sessionManager:SessionManager.inMemory(cwd),tools:['independent'],model:{id:'fixture',provider:'fixture',api:'openai-responses',name:'Fixture',input:['text'],contextWindow:8192,maxTokens:1024,cost:{input:0,output:0,cacheRead:0,cacheWrite:0}}});return{weak:new WeakRef(session),retained:keep==='loader'?loader:keep==='pi'?api:keep==='definition'?session.getToolDefinition('independent'):null}};export const proof=true;",
        "sdk-gc-retention-setup.mjs",
    );
    engine.freeValue(setup);
    for ([_][]const u8{ "loader", "pi", "definition", "none" }, [_]bool{ true, true, false, false }) |keep, expected| {
        const source = try std.fmt.allocPrint(engine.gpa, "globalThis.probe=await makeGcProbe('{s}');export const proof=true", .{keep});
        defer engine.gpa.free(source);
        const created = try engine.evalModule(source, "sdk-gc-create.mjs");
        engine.freeValue(created);
        for (0..3) |_| {
            c.JS_RunGC(engine.runtime);
            _ = try engine.pumpControls();
        }
        const alive = try engine.eval("Boolean(probe.weak.deref())", "sdk-gc-check.js", c.JS_EVAL_TYPE_GLOBAL);
        defer engine.freeValue(alive);
        try std.testing.expectEqual(expected, c.JS_ToBool(engine.context, alive) == 1);
        const dropped = try engine.eval("probe.retained=null;probe=null;true", "sdk-gc-drop.js", c.JS_EVAL_TYPE_GLOBAL);
        engine.freeValue(dropped);
        if (expected) {
            // deref() keeps the Session until this host job ends, even after
            // every explicit strong reference is dropped in the same job.
            c.JS_RunGC(engine.runtime);
            try std.testing.expectEqual(@as(usize, 1), group.sdk_scopes.items.len);
        }
        engine.finishJob();
        for (0..3) |_| {
            c.JS_RunGC(engine.runtime);
            _ = try engine.pumpControls();
        }
        if (group.sdk_scopes.items.len != 0) std.debug.print("SDK scope GC keep={s}, remaining={d}\n", .{ keep, group.sdk_scopes.items.len });
        try std.testing.expectEqual(@as(usize, 0), group.sdk_scopes.items.len);
        try std.testing.expectEqual(@as(usize, 1), group.entries.items.len);
    }
}

test "ToolInfo constructor-bound SDK default admission restores private context after every admitted metadata query allocation failure" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const engine = try Engine.init(failing.allocator(), .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    const main = try group.add("<main>");
    try main.installSchemas();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const path_size = try temporary.dir.realPath(std.testing.io, &path_buffer);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try vm.put(engine, global, "ownedCwd", try sdk.text(engine, path_buffer[0..path_size]));
    const namespace = try engine.evalModule(
        "import{createAgentSession,SessionManager,SettingsManager,DefaultResourceLoader}from'@earendil-works/pi-coding-agent';let api;const cwd=ownedCwd,settings=SettingsManager.inMemory({defaultTools:[]}),loader=new DefaultResourceLoader({cwd,agentDir:cwd,settingsManager:settings,noExtensions:true,noSkills:true,noPromptTemplates:true,noThemes:true,noContextFiles:true,extensionFactories:[{factory:pi=>{api=pi;pi.registerTool({name:'own',description:'own',parameters:{type:'object'},execute(){return{content:[]}}})}}]});await loader.reload();export const{session}=await createAgentSession({cwd,agentDir:cwd,resourceLoader:loader,settingsManager:settings,sessionManager:SessionManager.inMemory(cwd),tools:['own'],model:{id:'fixture',provider:'fixture',api:'openai-responses',name:'Fixture',input:['text'],contextWindow:8192,maxTokens:1024,cost:{input:0,output:0,cacheRead:0,cacheWrite:0}}});export{api,loader};",
        "sdk-default-query-allocations.mjs",
    );
    defer engine.freeValue(namespace);
    const api = try vm.get(engine, namespace, "api");
    defer engine.freeValue(api);
    const session = try vm.get(engine, namespace, "session");
    defer engine.freeValue(session);
    const owner = try sdk.state(engine, session);
    const lease = try sdk.sessionModelLease(owner);
    var private: ?*bindings.Bindings = null;
    for (group.entries.items) |entry| if (entry.sdk_scope != null) {
        private = entry.binding;
        break;
    };
    const Query = struct {
        fn run(actual: *group_mod.Group, original_api: c.JSValue) !void {
            actual.native_tool_catalog_cache.deinit();
            actual.native_tool_catalog_cache = .init(actual.engine);
            const rows = try vm.invoke(actual.engine, original_api, "getAllTools", &.{});
            defer actual.engine.freeValue(rows);
            try std.testing.expectEqual(@as(usize, 1), try vm.length(actual.engine, rows));
        }
    };
    try Query.run(group, api);
    var complete = false;
    var failures: usize = 0;
    for (0..1024) |offset| {
        failing.has_induced_failure = false;
        failing.fail_index = failing.alloc_index + offset;
        Query.run(group, api) catch |err| {
            failing.fail_index = std.math.maxInt(usize);
            try std.testing.expect(failing.has_induced_failure);
            try std.testing.expect(err == error.OutOfMemory or err == error.JavaScriptException);
            try std.testing.expect(private.?.sdk_context == null);
            try std.testing.expect(private.?.broker.?.active == null);
            try std.testing.expectEqual(lease, try sdk.sessionModelLease(owner));
            try Query.run(group, api);
            failures += 1;
            continue;
        };
        failing.fail_index = std.math.maxInt(usize);
        if (!failing.has_induced_failure) {
            complete = true;
            break;
        }
    }
    try std.testing.expect(complete and failures != 0);
    try std.testing.expect(private.?.sdk_context == null);
}

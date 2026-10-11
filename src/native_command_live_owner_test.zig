const std = @import("std");
const js = @import("extensions/native_js_values.zig");
const bindings = @import("extensions/native_bindings.zig");
const group_mod = @import("extensions/native_group.zig");
const projection = @import("extensions/native_command_live_projection.zig");
const command = @import("extensions/native_command_autocomplete.zig");
const sdk = @import("extensions/native_sdk.zig");
const c = js.c;
fn createProvider(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(ctx.?);
    return command.create(engine, if (argc > 0) args[0] else c.pi_js_undefined(), c.pi_js_undefined()) catch |err| @import("extensions/native_tui_alt_frame.zig").fail(engine, err);
}
fn mainProject(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(ctx.?);
    const value = mainProjectValue(engine, if (argc > 0) args[0] else c.pi_js_undefined(), roots) catch |err| return @import("extensions/native_tui_alt_frame.zig").fail(engine, err);
    return value;
}
fn mainProjectValue(engine: *js.Engine, snapshot: c.JSValue, roots: [*c]c.JSValue) !c.JSValue {
    var class: i64 = 0;
    if (c.JS_ToInt64(engine.context, &class, roots[1]) < 0) return js.capture(engine);
    const binding = bindings.Bindings.liveOwner(engine, roots[0], @intCast(class)) orelse return error.StaleNativeExtensionOwner;
    const group: *group_mod.Group = @ptrCast(@alignCast(engine.native_sdk_extension_group orelse return error.StaleNativeExtensionOwner));
    return projection.project(group, binding, snapshot);
}
fn bindProject(engine: *js.Engine, binding: *bindings.Bindings, name: [*:0]const u8) !void {
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    var roots = [_]c.JSValue{ binding.owner_token, c.JS_NewInt64(engine.context, binding.owner_class) };
    const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, mainProject, name, 1, 0, 2, &roots));
    try js.define(engine, root, name, function);
}
fn setup(gpa: std.mem.Allocator) !*js.Engine {
    const engine = try js.Engine.init(gpa, .{ .memory_limit = 64 * 1024 * 1024 });
    errdefer engine.deinit();
    engine.native_io = std.testing.io;
    var environment: std.process.Environ.Map = .init(gpa);
    defer environment.deinit();
    try @import("extensions/native_process.zig").install(engine, std.testing.io, &environment, &.{"live-command-source"});
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    try @import("extensions/abort_signal.zig").install(engine);
    try @import("extensions/native_tui.zig").install(engine);
    try engine.bindFunction("createLiveCommandProvider", createProvider, 1);
    return engine;
}
fn replay(engine: *js.Engine, source: []const u8, filename: [:0]const u8) !void {
    const value = engine.evalModule(source, filename) catch |err| {
        std.debug.print("Live command metadata failure: {s}\n", .{engine.last_error orelse @errorName(err)});
        return err;
    };
    engine.freeValue(value);
    c.JS_RunGC(engine.runtime);
}
fn sourceAuthority(engine: *js.Engine) !void {
    const bytes = @embedFile("extensions/fixtures/main-live-command-metadata-source.json");
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    try js.define(engine, root, "liveCommandMetadataSource", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "actual-source-live-metadata")));
    const retained = @embedFile("extensions/fixtures/main-live-command-retained-registration-source.json");
    try js.define(engine, root, "liveCommandRetainedSource", try engine.checked(c.JS_ParseJSON(engine.context, retained.ptr, retained.len, "actual-source-retained-registration")));
}
const context = "{hasUI:false,commands:[],sessionName:'original'}";
fn sdkProject(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(ctx.?);
    return sdkProjectValue(engine, if (argc > 0) args[0] else c.pi_js_undefined()) catch |err| @import("extensions/native_tui_alt_frame.zig").fail(engine, err);
}
fn sdkProjectValue(engine: *js.Engine, session: c.JSValue) !c.JSValue {
    const state = try sdk.state(engine, session);
    const sdk_owners = @import("extensions/native_sdk_resource_owners.zig");
    const rows = try sdk_owners.sessionExtensionRows(engine, state.data);
    defer engine.freeValue(rows);
    const group: *group_mod.Group = @ptrCast(@alignCast(engine.native_sdk_extension_group orelse return error.StaleNativeExtensionOwner));
    var selected: ?*bindings.Bindings = null;
    for (group.entries.items) |entry| {
        if (entry.sdk_scope == null) continue;
        const candidate = entry.binding.sdk_command_row orelse continue;
        for (0..try sdk.length(engine, rows)) |index| {
            const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, rows, @intCast(index)));
            defer engine.freeValue(row);
            if (c.JS_IsStrictEqual(engine.context, row, candidate)) {
                selected = entry.binding;
                break;
            }
        }
        if (selected != null) break;
    }
    const binding = selected orelse return error.StaleNativeExtensionOwner;
    const registry = try sdk.get(engine, state.data, "modelRegistry");
    defer engine.freeValue(registry);
    const manager = try sdk.publicField(state, "sessionManager");
    defer engine.freeValue(manager);
    const saved = try binding.pushSdkContext(.{ .session = session, .registry = registry, .manager = manager, .lease = try sdk.sessionModelLease(state) });
    defer binding.restoreSdkContext(saved);
    const snapshot = try js.object(engine);
    defer engine.freeValue(snapshot);
    return projection.project(group, binding, snapshot);
}
fn sdkInvalidate(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(ctx.?);
    sdkLifecycleValue(engine, if (argc > 0) args[0] else c.pi_js_undefined(), false) catch |err| return @import("extensions/native_tui_alt_frame.zig").fail(engine, err);
    return c.pi_js_undefined();
}
fn sdkRemove(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(ctx.?);
    sdkLifecycleValue(engine, if (argc > 0) args[0] else c.pi_js_undefined(), true) catch |err| return @import("extensions/native_tui_alt_frame.zig").fail(engine, err);
    return c.pi_js_undefined();
}
fn sdkLifecycleValue(engine: *js.Engine, session: c.JSValue, remove: bool) !void {
    const state = try sdk.state(engine, session);
    const sdk_owners = @import("extensions/native_sdk_resource_owners.zig");
    if (!remove) return sdk_owners.invalidateSessionRuntime(state);
    const rows = try sdk_owners.sessionExtensionRows(engine, state.data);
    defer engine.freeValue(rows);
    const group: *group_mod.Group = @ptrCast(@alignCast(engine.native_sdk_extension_group orelse return error.StaleNativeExtensionOwner));
    var ids: std.ArrayList(u64) = .empty;
    defer ids.deinit(engine.gpa);
    for (group.entries.items) |entry| {
        if (entry.sdk_scope == null) continue;
        const candidate = entry.binding.sdk_command_row orelse continue;
        for (0..try sdk.length(engine, rows)) |index| {
            const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, rows, @intCast(index)));
            defer engine.freeValue(row);
            if (c.JS_IsStrictEqual(engine.context, row, candidate)) {
                try ids.append(engine.gpa, entry.id);
                break;
            }
        }
    }
    for (ids.items) |id| try group.remove(id);
}
test "Live command metadata Main aliases retain exact callable and hint identity across GC" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    const first = try group.add("first-command-owner.mjs");
    const second = try group.add("second-command-owner.mjs");
    try first.loadFactory("export default pi=>{globalThis.firstCommandPi=pi;globalThis.liveHint={toString(){return '<topic>'}};globalThis.firstCommandCallback=function(prefix){return [{value:prefix,label:this.name}]};globalThis.firstCommandDefinition={description:'first',argumentHint:liveHint,getArgumentCompletions:firstCommandCallback,handler(){}};pi.registerCommand('same:1',{handler(){}});pi.registerCommand('same',firstCommandDefinition)}", "first-command-owner.mjs");
    try second.loadFactory("export default pi=>{globalThis.secondCommandCallback=function(prefix){return [{value:prefix,label:this.name}]};pi.registerCommand('same',{description:'second',argumentHint:liveHint,getArgumentCompletions:secondCommandCallback,handler(){}})}", "second-command-owner.mjs");
    try bindProject(engine, first, "projectLiveMain");
    try sourceAuthority(engine);
    try replay(
        engine,
        "const rows=projectLiveMain(" ++ context ++ ");globalThis.retainedLiveRows=rows;const sourceAliases=liveCommandMetadataSource.cases.find(row=>row.id==='literal-before').rawIdentity.map(row=>row.invocationName);if(JSON.stringify(rows.map(row=>row.name))!==JSON.stringify(sourceAliases))throw Error('actual Source collision aliases');if(rows[1].getArgumentCompletions!==firstCommandCallback||rows[2].getArgumentCompletions!==secondCommandCallback||rows[1].argumentHint!==liveHint||rows[2].argumentHint!==liveHint)throw Error('identity');for(const row of rows)if(Object.getPrototypeOf(row)!==Object.prototype||Object.prototype.toString.call(row)!=='[object Object]')throw Error('ordinary row');rows[1].description='caller copy';if(firstCommandDefinition.description!=='first')throw Error('definition mutated');",
        "live-command-main-aliases.mjs",
    );
    try replay(engine, "if(retainedLiveRows[1].getArgumentCompletions!==firstCommandCallback||retainedLiveRows[1].argumentHint!==liveHint)throw Error('GC lost identity');const result=await createLiveCommandProvider(retainedLiveRows).getSuggestions(['/same:2 p'],0,9,{force:false});if(result.prefix!=='p'||result.items[0].label!=='same:2')throw Error('ordinary receiver');", "live-command-main-gc.mjs");
}
test "Live command metadata callback scope preserves one argument promises thenables nested unowned calls and original reasons" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    const owner = try group.add("argument-command-owner.mjs");
    try owner.loadFactory(
        \\export default pi=>{globalThis.liveCommandReason={original:true};globalThis.argumentCommandPi=pi;globalThis.argumentTrace=[];pi.registerCommand('owned',{handler(){},getArgumentCompletions:async function(prefix){argumentTrace.push({prefix,argc:arguments.length,name:this.name,ordinary:Object.getPrototypeOf(this)===Object.prototype});if(prefix==='throw')throw liveCommandReason;const inner=createLiveCommandProvider([{name:'inner',getArgumentCompletions(){return ['nested']}}]);await inner.getSuggestions(['/inner q'],0,8,{force:false});await new Promise(resolve=>setTimeout(resolve,1));pi.setSessionName(prefix);return{then(resolve){argumentTrace.push({thenOwner:pi.getSessionName()});resolve([{value:prefix,label:this===undefined?'wrong':'owned'}])}}}})}
    , "argument-command-owner.mjs");
    try bindProject(engine, owner, "projectLiveArguments");
    try replay(
        engine,
        "const rows=projectLiveArguments(" ++ context ++ "),provider=createLiveCommandProvider(rows);for(const prefix of ['sync','promise']){const line='/owned '+prefix,result=await provider.getSuggestions([line],0,line.length,{force:false});if(result.prefix!==prefix||result.items[0].value!==prefix)throw Error('argument result');}let caught=false;try{await provider.getSuggestions(['/owned throw'],0,12,{force:false})}catch(error){if(error!==liveCommandReason)throw Error('original reason replaced');caught=true}if(!caught||argumentTrace.filter(row=>row.prefix).some(row=>row.argc!==1||row.name!=='owned'||!row.ordinary))throw Error('callback call shape');if(argumentTrace.filter(row=>row.thenOwner).map(row=>row.thenOwner).join(',')!=='sync,promise')throw Error('thenable lost owner action snapshot');",
        "live-command-arguments.mjs",
    );
}
test "Live command metadata same-owner replacement preserves the retained Source callback and fresh projection" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    const owner = try group.add("replace-command-owner.mjs");
    try owner.loadFactory("export default pi=>{globalThis.replaceCommandPi=pi;pi.registerCommand('owned',{handler(){},getArgumentCompletions(){return [{value:'old',label:'old'}]}})}", "replace-command-owner.mjs");
    try bindProject(engine, owner, "projectLiveReplacement");
    try sourceAuthority(engine);
    try replay(
        engine,
        "const row=projectLiveReplacement(" ++ context ++ ")[0],provider=createLiveCommandProvider([row]);replaceCommandPi.registerCommand('unrelated',{handler(){}});if((await provider.getSuggestions(['/owned p'],0,8,{force:false})).items[0].value!=='old')throw Error('unrelated registration invalidated callback');replaceCommandPi.registerCommand('owned',{handler(){},getArgumentCompletions(){return [{value:'new',label:'new'}]}});const retained=await provider.getSuggestions(['/owned p'],0,8,{force:false});if(JSON.stringify(retained)!==JSON.stringify(liveCommandRetainedSource.cases.find(row=>row.phase==='replaced-registration-retained-provider').value))throw Error('retained Source callback changed after replacement');const fresh=createLiveCommandProvider(projectLiveReplacement(" ++ context ++ "));if((await fresh.getSuggestions(['/owned p'],0,8,{force:false})).items[0].value!=='new')throw Error('new definition unavailable');",
        "live-command-replacement.mjs",
    );
}
test "Live command metadata owner retirement preserves pure JS results and fences original native capabilities" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    var group: ?*group_mod.Group = try group_mod.Group.init(engine);
    defer if (group) |current| current.deinit();
    const owner = try group.?.add("retire-command-owner.mjs");
    try owner.loadFactory("export default pi=>pi.registerCommand('owned',{handler(){},getArgumentCompletions(){return new Promise(resolve=>globalThis.finishRetiredCommand=resolve)}})", "retire-command-owner.mjs");
    try bindProject(engine, owner, "projectLiveRetirement");
    const started = try engine.eval("globalThis.retiredCommandProvider=createLiveCommandProvider(projectLiveRetirement(" ++ context ++ "));globalThis.retiredCommandPending=retiredCommandProvider.getSuggestions(['/owned p'],0,8,{force:false});", "live-command-retire-begin.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(started);
    try group.?.remove(owner.owner_id);
    try replay(engine, "finishRetiredCommand([{value:'late',label:'late'}]);const result=await retiredCommandPending;if(result.items[0].value!=='late')throw Error('Source late pure completion was rejected');", "live-command-retire-late.mjs");
    const fresh = try group.?.add("fresh-command-owner.mjs");
    try fresh.loadFactory("export default pi=>{pi.registerCommand('fresh',{handler(){},getArgumentCompletions(){return [{value:'fresh',label:'fresh'}]}});pi.registerCommand('cap',{handler(){},getArgumentCompletions(){return [{value:pi.getSessionName(),label:'cap'}]}})}", "fresh-command-owner.mjs");
    try bindProject(engine, fresh, "projectBeforeGroupRetirement");
    const retained = try engine.eval("globalThis.afterGroupRetirementProvider=createLiveCommandProvider(projectBeforeGroupRetirement(" ++ context ++ "));", "live-command-group-retain.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(retained);
    group.?.deinit();
    group = null;
    try replay(engine, "if((await afterGroupRetirementProvider.getSuggestions(['/fresh p'],0,8,{force:false})).items[0].value!=='fresh')throw Error('Source pure original callback blocked after Group retirement');let rejected=false;try{await afterGroupRetirementProvider.getSuggestions(['/cap p'],0,6,{force:false})}catch(error){rejected=error.name==='Error'&&error.message.includes('ctx is stale')}if(!rejected)throw Error('retired native capability admitted');afterGroupRetirementProvider.commands[0].getArgumentCompletions=function(prefix){return [{value:'replacement',label:'replacement'}]};if((await afterGroupRetirementProvider.getSuggestions(['/fresh p'],0,8,{force:false})).items[0].value!=='replacement')throw Error('Source replaced pure callback blocked');", "live-command-group-retired.mjs");
}
test "Live command metadata genuine SDK owners isolate aliases sessions reload and late completion from Main" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    const main = try group.add("main-command-sdk-boundary.mjs");
    try main.installSchemas();
    try main.loadFactory("export default pi=>pi.registerCommand('main-only',{handler(){}})", "main-command-sdk-boundary.mjs");
    try bindProject(engine, main, "projectSdkBoundaryMain");
    try engine.bindFunction("projectActualSdkCommands", sdkProject, 1);
    try replay(engine,
        \\import{createAgentSession,DefaultResourceLoader,ModelRuntime,SessionManager,SettingsManager}from'@earendil-works/pi-coding-agent';
        \\const runtime=await ModelRuntime.create({modelsPath:null,refreshOnCreate:false,credentials:{read:async()=>undefined,list:async()=>[]}}),settings=SettingsManager.inMemory({defaultTools:[]}),callbacks=[],hints=[];let finishA,generation=0;
        \\const makeLoader=(label,names)=>new DefaultResourceLoader({cwd:'/live-command-'+label,agentDir:'/live-command-'+label,noExtensions:true,noSkills:true,noThemes:true,noPromptTemplates:true,noContextFiles:true,extensionFactories:names.map((registered,index)=>({name:label+index,factory(pi){const hint={label},callback=function(prefix){const owner=pi.getSessionName();if(label==='A'&&prefix==='late')return new Promise(resolve=>finishA=resolve);return Promise.resolve([{value:owner+':'+prefix,label:this.name}])};callbacks.push(callback);hints.push(hint);for(const name of registered)pi.registerCommand(name,{description:label,argumentHint:hint,getArgumentCompletions:callback,handler(){}})}}))});
        \\const loaderA=makeLoader('A',[['same:1','same'],['same']]),loaderB=makeLoader('B',[['b-only']]);await loaderA.reload();await loaderB.reload();
        \\const make=async(label,loader)=>{const{session}=await createAgentSession({cwd:'/live-command-'+label,modelRuntime:runtime,resourceLoader:loader,sessionManager:SessionManager.inMemory('/live-command-'+label),settingsManager:settings,tools:[]});session.setSessionName(label);await session.bindExtensions({});return session};const A=await make('A',loaderA),B=await make('B',loaderB);
        \\const rowsA=projectActualSdkCommands(A),rowsB=projectActualSdkCommands(B);if(rowsA.map(row=>row.name).join(',')!=='same:1,same:2,same:3'||rowsB.map(row=>row.name).join(',')!=='b-only')throw Error('SDK alias/isolation');if(projectSdkBoundaryMain({commands:[]}).map(row=>row.name).join(',')!=='main-only')throw Error('SDK registrations leaked into Main');for(const row of [...rowsA,...rowsB])if(!callbacks.includes(row.getArgumentCompletions)||!hints.includes(row.argumentHint))throw Error('SDK callback/hint identity');
        \\const providerA=createLiveCommandProvider(rowsA),providerB=createLiveCommandProvider(rowsB);let value=await providerA.getSuggestions(['/same:2 p'],0,9,{force:false});if(value.items[0].value!=='A:p'||value.items[0].label!=='same:2')throw Error('borrowed B owner context');value=await providerB.getSuggestions(['/b-only p'],0,9,{force:false});if(value.items[0].value!=='B:p')throw Error('B context');
        \\await loaderA.reload();const C=await make('C',loaderA);if((await providerA.getSuggestions(['/same:2 p'],0,9,{force:false})).items[0].value!=='A:p')throw Error('live old incarnation rebound after reload');if((await createLiveCommandProvider(projectActualSdkCommands(C)).getSuggestions(['/same:2 p'],0,9,{force:false})).items[0].value!=='C:p')throw Error('new incarnation context');
        \\const late=providerA.getSuggestions(['/same:2 late'],0,12,{force:false});A.dispose();finishA([{value:'late',label:'late'}]);if((await late).items[0].value!=='late')throw Error('Source SDK late pure completion was rejected');if((await providerB.getSuggestions(['/b-only q'],0,9,{force:false})).items[0].value!=='B:q')throw Error('A disposal poisoned B');B.dispose();C.dispose();
    , "live-command-actual-sdk-boundaries.mjs");
}
test "Live command metadata same Binding context replacement keeps pure JS and independently owned capability use" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    const first = try group.add("context-command-first.mjs");
    const second = try group.add("context-command-second.mjs");
    try first.loadFactory("export default pi=>{globalThis.contextFirstPi=pi;pi.registerCommand('pure',{handler(){},getArgumentCompletions(){return [{value:'pure',label:this.name}]}});pi.registerCommand('cap',{handler(){},getArgumentCompletions(){return [{value:pi.getSessionName(),label:this.name}]}});pi.registerCommand('other',{handler(){},getArgumentCompletions(){return [{value:contextSecondPi.getSessionName(),label:this.name}]}});pi.registerCommand('pending-other',{handler(){},getArgumentCompletions:async function(){await new Promise(resolve=>globalThis.finishContextOther=resolve);return [{value:contextSecondPi.getSessionName(),label:this.name}]}})}", "context-command-first.mjs");
    try second.loadFactory("export default pi=>{globalThis.contextSecondPi=pi}", "context-command-second.mjs");
    try second.setContext("{\"sessionName\":\"B\",\"commands\":[]}");
    try bindProject(engine, first, "projectContextCommands");
    const created = try engine.eval("globalThis.contextProvider=createLiveCommandProvider(projectContextCommands(" ++ context ++ "));globalThis.pendingContextOther=contextProvider.getSuggestions(['/pending-other p'],0,16,{force:false});", "context-command-begin.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(created);
    try first.invalidateContext();
    try first.setContext("{\"sessionName\":\"must-not-borrow-new-A\",\"commands\":[]}");
    try replay(engine, "finishContextOther();if((await pendingContextOther).items[0].value!=='B')throw Error('pending fresh B poisoned');if((await contextProvider.getSuggestions(['/pure p'],0,7,{force:false})).items[0].value!=='pure')throw Error('pure context retirement blocked');let rejected=false;try{await contextProvider.getSuggestions(['/cap p'],0,6,{force:false})}catch(error){rejected=error.name==='Error'&&error.message.includes('ctx is stale')}if(!rejected)throw Error('old A borrowed new context');if((await contextProvider.getSuggestions(['/other p'],0,8,{force:false})).items[0].value!=='B')throw Error('same-turn fresh B poisoned');const row=contextProvider.commands.find(row=>row.name==='pure');row.getArgumentCompletions=function(prefix){return [{value:contextSecondPi.getSessionName()+':'+prefix,label:this.name}]};if((await contextProvider.getSuggestions(['/pure p'],0,7,{force:false})).items[0].value!=='B:p')throw Error('replacement borrowed old owner');", "context-command-source-lifetime.mjs");
}
fn replaySdkSource(engine: *js.Engine, bytes: []const u8, original: []const u8, result_name: []const u8, count: usize, filename: [:0]const u8) !void {
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    try js.define(engine, root, "actualCommandLifetimeSource", try engine.checked(c.JS_ParseJSON(engine.context, original.ptr, original.len, "actual-command-lifetime-source")));
    try engine.bindFunction("projectActualSdkCommands", sdkProject, 1);
    try engine.bindFunction("invalidateActualSdkRunner", sdkInvalidate, 1);
    try engine.bindFunction("removeActualSdkExtensions", sdkRemove, 1);
    var scratch = std.testing.tmpDir(.{});
    defer scratch.cleanup();
    var path: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const size = try scratch.dir.realPath(std.testing.io, &path);
    try js.define(engine, root, "liveCommandSourceDirectory", try sdk.text(engine, path[0..size]));
    const suffix = try std.fmt.allocPrint(engine.gpa, "\nif({s}.length!=={d})throw Error('Source lifetime count');for(let index=0;index<{d};index++)if(JSON.stringify({s}[index])!==JSON.stringify(actualCommandLifetimeSource.cases[index]))throw Error(JSON.stringify({{index,actual:{s}[index],expected:actualCommandLifetimeSource.cases[index]}}));", .{ result_name, count, count, result_name, result_name });
    defer engine.gpa.free(suffix);
    const source = try std.mem.concat(engine.gpa, u8, &.{ "import{createAgentSession,DefaultResourceLoader,ModelRuntime,SessionManager,SettingsManager}from'@earendil-works/pi-coding-agent';const sourceFixtureDirectory=liveCommandSourceDirectory;\n", bytes, suffix });
    defer engine.gpa.free(source);
    try replay(engine, source, filename);
}
test "Live command metadata actual Source18 pure replaced callback pending and own capability lifetime records" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    const main = try group.add("source18-command-lifetime-root.mjs");
    try main.installSchemas();
    try replaySdkSource(engine, @embedFile("extensions/fixtures/main-live-command-retirement-entry-native.input.txt"), @embedFile("extensions/fixtures/main-live-command-retirement-entry-source.json"), "liveCommandRetirementCases", 18, "actual-source18-command-lifetime.mjs");
}
test "Live command metadata actual Source12 shared Pi runtime binding and independent captured contexts" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    const main = try group.add("source12-command-shared-runtime-root.mjs");
    try main.installSchemas();
    try replaySdkSource(engine, @embedFile("extensions/fixtures/main-live-command-shared-runtime-native.input.txt"), @embedFile("extensions/fixtures/main-live-command-shared-runtime-source.json"), "liveCommandSharedRuntimeCases", 12, "actual-source12-command-shared-runtime.mjs");
}
test "Live command metadata actual Source12 A disposal invalidates shared Pi while B C contexts stay independently live" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    const main = try group.add("source12-command-shared-dispose-root.mjs");
    try main.installSchemas();
    try replaySdkSource(engine, @embedFile("extensions/fixtures/main-live-command-shared-dispose-native.input.txt"), @embedFile("extensions/fixtures/main-live-command-shared-dispose-source.json"), "liveCommandSharedRuntimeCases", 12, "actual-source12-command-shared-dispose.mjs");
}
fn allocationFailure(engine: *js.Engine, gpa: std.mem.Allocator, err: anyerror, generation: u64, stage: []const u8) anyerror {
    const actual = engine.nativeAllocationError(err, generation);
    if (actual != error.OutOfMemory) {
        std.debug.print("Live command GPA stage={s} {s}, generation={d}->{d}, original={s}\n", .{ stage, @errorName(actual), generation, engine.native_allocation_generation, engine.last_error orelse "none" });
        var known = std.testing.FailingAllocator.init(std.testing.allocator, .{});
        if (gpa.vtable.alloc == known.allocator().vtable.alloc and gpa.vtable.free == known.allocator().vtable.free) {
            const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
            std.debug.print("Live command GPA index={d}, current={d}, induced={}\n", .{ failing.fail_index, failing.alloc_index, failing.has_induced_failure });
            if (failing.has_induced_failure) std.debug.print("{f}\n", .{std.debug.FormatStackTrace{ .stack_trace = failing.getStackTrace() }});
        }
    }
    return actual;
}
fn allocationProbe(gpa: std.mem.Allocator) !void {
    const engine = try setup(gpa);
    defer engine.deinit();
    const generation = engine.native_allocation_generation;
    const group = group_mod.Group.init(engine) catch |err| return allocationFailure(engine, gpa, err, generation, "Group.init");
    defer group.deinit();
    const owner = group.add("gpa-command-owner.mjs") catch |err| return allocationFailure(engine, gpa, err, generation, "Group.add");
    owner.loadFactory("export default pi=>pi.registerCommand('owned',{argumentHint:'<x>',handler(){},getArgumentCompletions:async function(prefix){await Promise.resolve();return [{value:prefix,label:this.name}]}})", "gpa-command-owner.mjs") catch |err| return allocationFailure(engine, gpa, err, generation, "loadFactory");
    bindProject(engine, owner, "projectLiveGpa") catch |err| return allocationFailure(engine, gpa, err, generation, "bindProject");
    const result = engine.evalModule("const rows=projectLiveGpa(" ++ context ++ "),provider=globalThis.gpaRetainedCommandProvider=createLiveCommandProvider(rows),result=await provider.getSuggestions(['/owned p'],0,8,{force:false});if(result.prefix!=='p'||result.items[0].value!=='p'||result.items[0].label!=='owned'||rows[0].argumentHint!=='<x>')throw Error('actual allocation-path behavior');", "live-command-owner-allocation.mjs") catch |err| return allocationFailure(engine, gpa, err, generation, "eval-live");
    engine.freeValue(result);
    owner.invalidateContext() catch |err| return allocationFailure(engine, gpa, err, generation, "context-retirement");
    const late = engine.evalModule("const result=await gpaRetainedCommandProvider.getSuggestions([\"/owned p\"],0,8,{force:false});if(result.items[0].value!==\"p\")throw Error(\"Source retired pure callback failed during GPA\");", "live-command-retired-allocation.mjs") catch |err| return allocationFailure(engine, gpa, err, generation, "eval-retired");
    engine.freeValue(late);
    c.JS_RunGC(engine.runtime);
}
test "Live command metadata exhaustive host allocation unwinds projection arguments scope and retirement" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationProbe, .{});
}

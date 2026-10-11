const std = @import("std");
const js = @import("extensions/native_js_values.zig");
const c = js.c;
const strategy = @import("extensions/native_image_resize_strategy.zig");
const worker = @import("extensions/native_image_vm_worker.zig");
const option_graph = @import("extensions/native_image_resize_options.zig");
const promises = @import("extensions/native_image_worker_promise.zig");
const image_api = @import("extensions/native_image_resize_api.zig");
const dimension_note = @import("extensions/native_image_dimension_note.zig");
test "native image JavaScript-valued strategy public SDK exports execute native worker and dimension note with no Node host" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    const group = try @import("extensions/native_group.zig").Group.init(engine);
    defer group.deinit();
    const owner = try group.add("image-public-api-owner");
    try owner.installSchemas();
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const input = @embedFile("ai/fixtures/photon-source-8x5.png");
    try js.define(engine, root, "imageInputBuffer", try engine.checked(c.JS_NewArrayBufferCopy(engine.context, input.ptr, input.len)));
    const result = engine.evalModule(
        \\import{resizeImage,formatDimensionNote}from'@earendil-works/pi-coding-agent';
        \\const value=await resizeImage(new Uint8Array(imageInputBuffer),'image/png',{maxWidth:4,maxHeight:3});
        \\if(value.width!==4||value.height!==3||formatDimensionNote(value)!=='[Image: original 8x5, displayed at 4x3. Multiply coordinates by 2.00 to map to original image.]')throw Error('public SDK native image behavior');
        \\if(Object.getPrototypeOf(resizeImage)!==Object.getPrototypeOf(async()=>{})||Object.hasOwn(resizeImage,'prototype'))throw Error('public native async function metadata');
    , "image-public-sdk-native") catch |err| {
        std.debug.print("Public SDK image exports: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
}
fn noteAllocation(gpa: std.mem.Allocator) !void {
    const engine = try js.Engine.init(gpa, .{});
    defer engine.deinit();
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    try js.define(engine, root, "candidateFormatDimensionNote", try dimension_note.create(engine));
    const generation = engine.native_allocation_generation;
    const result = engine.eval("candidateFormatDimensionNote({wasResized:true,originalWidth:8,originalHeight:5,width:4,height:3})", "image-note-allocation", c.JS_EVAL_TYPE_GLOBAL) catch |err| {
        const actual = engine.nativeAllocationError(err, generation);
        if (actual != error.OutOfMemory) std.debug.print("Image note GPA: {s} generation={d}->{d} original={s}\n", .{ @errorName(actual), generation, engine.native_allocation_generation, engine.last_error orelse "no diagnostic" });
        return actual;
    };
    engine.freeValue(result);
}
test "native image JavaScript-valued strategy dimension notes release every native allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, noteAllocation, .{});
}
test "native image JavaScript-valued strategy public function metadata and fourteen original dimension note cases" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    try js.define(engine, root, "candidateResizeImage", try image_api.create(engine));
    try js.define(engine, root, "candidateFormatDimensionNote", try dimension_note.create(engine));
    const fixture = @embedFile("extensions/fixtures/image-public-contract-89e5-source.json");
    try js.define(engine, root, "imagePublicSource", try engine.checked(c.JS_ParseJSON(engine.context, fixture.ptr, fixture.len, "image-public-contract-89e5-source")));
    const result = engine.evalModule(
        \\const formatDimensionNote=candidateFormatDimensionNote;
        \\function metadata(fn){let construct;try{Reflect.construct(function(){},[],fn);construct=true}catch(cause){construct=cause.name}return{name:fn.name,length:fn.length,keys:Reflect.ownKeys(fn).map(String),asyncPrototype:Object.getPrototypeOf(fn)===Object.getPrototypeOf(async()=>{}),construct,nameDescriptor:Object.getOwnPropertyDescriptor(fn,'name'),lengthDescriptor:Object.getOwnPropertyDescriptor(fn,'length')}}
        \\const actualMetadata={resize:metadata(candidateResizeImage),note:metadata(formatDimensionNote)};
        \\if(JSON.stringify(actualMetadata)!==JSON.stringify(imagePublicSource.metadata))throw Error(JSON.stringify({actualMetadata,expected:imagePublicSource.metadata}));
    ++ @embedFile("extensions/fixtures/image-dimension-note-89e5.input.txt") ++
        \\if(imageNoteRows.length!==14||imagePublicSource.rows.length!==14)throw Error('dimension note Source count');
        \\for(let index=0;index<14;index++){const actual=imageNoteRows[index],expected=imagePublicSource.rows[index];
        \\ if(['bigints','mixed-numeric','null','undefined','symbol'].includes(expected.id)){
        \\  if(actual.error?.name!==expected.error.name||typeof actual.error.message!=='string')throw Error('builtin error class/wording type');
        \\  // Preserve the original message in the fixture. Engine-generated
        \\  // builtin wording differs; every other field and custom reason is exact.
        \\  actual.error.message=expected.error.message;
        \\ }
        \\ if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({index,actual,expected}));
        \\}
    , "image-public-functions-89e5-native") catch |err| {
        std.debug.print("Image public functions: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
}
fn allocationCase(allocator: std.mem.Allocator) !void {
    var serialized_allocator: @import("test_support/locked_allocator.zig").Locked = .{ .backing = allocator };
    const engine = try js.Engine.init(serialized_allocator.allocator(), .{ .host_await_timeout_ms = 5000 });
    defer engine.deinit();
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try js.define(engine, global, "candidateResizeImage", try image_api.create(engine));
    const input = @embedFile("ai/fixtures/photon-source-8x5.png");
    try js.define(engine, global, "imageInputBuffer", try engine.checked(c.JS_NewArrayBufferCopy(engine.context, input.ptr, input.len)));
    const generation = engine.native_allocation_generation;
    const result = engine.evalModule("await candidateResizeImage(new Uint8Array(imageInputBuffer),'image/png',{maxWidth:4,maxHeight:3})", "image-allocation-lifecycle") catch |err| {
        const actual = engine.nativeAllocationError(err, generation);
        if (actual != error.OutOfMemory) {
            std.debug.print("Image allocation failure original={s} classified={s} nativeGeneration={d}->{d}\n", .{ @errorName(err), @errorName(actual), generation, engine.native_allocation_generation });
            if (engine.captured_exception) |exception| {
                const message = c.JS_ToCString(engine.context, exception);
                if (message != null) {
                    defer c.JS_FreeCString(engine.context, message);
                    std.debug.print("Actual image exception {s}\n", .{std.mem.span(message)});
                }
            }
        }
        return actual;
    };
    engine.freeValue(result);
}
test "native image JavaScript-valued strategy releases every induced allocator failure and recovers" {
    var baseline = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    try allocationCase(baseline.allocator());
    const total = baseline.alloc_index;
    try std.testing.expectEqual(baseline.allocated_bytes, baseline.freed_bytes);
    std.debug.print("IMAGE_ALLOCATION_TOTAL {d}\n", .{total});
    for (0..total) |index| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = index });
        if (allocationCase(failing.allocator())) |_| {
            std.debug.print("IMAGE_ALLOCATION_UNEXPECTED_SUCCESS index={d}/{d} actual={d} induced={}\n", .{ index, total, failing.alloc_index, failing.has_induced_failure });
            if (failing.has_induced_failure) return error.SwallowedOutOfMemoryError;
            return error.NondeterministicMemoryUsage;
        } else |err| {
            if (err != error.OutOfMemory) {
                std.debug.print("IMAGE_ALLOCATION_UNEXPECTED_ERROR index={d}/{d} actual={d} induced={} error={s}\n", .{ index, total, failing.alloc_index, failing.has_induced_failure, @errorName(err) });
                return err;
            }
            try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
        }
    }
    try allocationCase(std.testing.allocator);
}
test "native image JavaScript-valued strategy matches every actual public worker result" {
    const engine = try js.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 5000 });
    defer engine.deinit();
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try js.define(engine, global, "candidateResizeImage", try image_api.create(engine));
    const input = @embedFile("ai/fixtures/photon-source-8x5.png");
    try js.define(engine, global, "imageInputBuffer", try engine.checked(c.JS_NewArrayBufferCopy(engine.context, input.ptr, input.len)));
    const fixture = @embedFile("extensions/fixtures/image-resize-public-worker-ea.json");
    const captured = try engine.checked(c.JS_ParseJSON(engine.context, fixture.ptr, fixture.len, "actual-image-worker-source"));
    try js.define(engine, global, "imageWorkerSource", captured);
    const result = try engine.evalModule(
        \\const bytes=new Uint8Array(imageInputBuffer),cases=[['defaults',undefined],['width',{maxWidth:4}],['height',{maxHeight:2}],['both',{maxWidth:5,maxHeight:2}],['fractional',{maxWidth:3.5,maxHeight:2.2}],['zero-width',{maxWidth:0}],['zero-height',{maxHeight:0}],['undefined-width',{maxWidth:undefined}],['undefined-height',{maxHeight:undefined}],['undefined-bytes',{maxBytes:undefined}],['undefined-quality',{maxWidth:4,jpegQuality:undefined}],['nan-width',{maxWidth:NaN}],['nan-height',{maxHeight:NaN}],['nan-bytes',{maxBytes:NaN}],['nan-quality',{maxWidth:4,jpegQuality:NaN}],['infinite-width',{maxWidth:Infinity}],['negative-width',{maxWidth:-1}],['equal-byte-limit',{maxBytes:4*Math.ceil(bytes.length/3)}],['below-byte-limit',{maxBytes:4*Math.ceil(bytes.length/3)-1}],['small-byte-budget',{maxBytes:100}],['zero-byte-budget',{maxBytes:0}],['string-quality',{maxWidth:4,jpegQuality:'85'}]];
        \\for(let index=0;index<cases.length;index++){const[name,options]=cases[index],before=[...bytes],row=imageWorkerSource.rows[index];let result,error;try{result=await candidateResizeImage(bytes,'image/png',options)}catch(cause){error={name:cause.name,message:cause.message}};const same=result===row.result||(result&&row.result&&Reflect.ownKeys(result).length===Reflect.ownKeys(row.result).length&&Reflect.ownKeys(row.result).every(key=>Object.is(result[key],row.result[key])));if(row.name!==name||JSON.stringify(error)!==JSON.stringify(row.error)||!same||JSON.stringify([...bytes])!==JSON.stringify(before))throw Error(JSON.stringify({name,error,result,expected:row}));}
        \\if(cases.length!==22||imageWorkerSource.rows.length!==24)throw Error('actual public Source coverage');
    , "native-public-image-worker-source");
    engine.freeValue(result);
}
test "native image JavaScript-valued strategy isolates simultaneous worker requests" {
    const engine = try js.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 5000 });
    defer engine.deinit();
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try js.define(engine, global, "candidateResizeImage", try image_api.create(engine));
    const input = @embedFile("ai/fixtures/photon-source-8x5.png");
    try js.define(engine, global, "imageInputBuffer", try engine.checked(c.JS_NewArrayBufferCopy(engine.context, input.ptr, input.len)));
    const result = try engine.evalModule(
        \\const bytes=new Uint8Array(imageInputBuffer),before=[...bytes];
        \\const results=await Promise.all([candidateResizeImage(bytes,'image/png',{maxWidth:4}),candidateResizeImage(bytes,'image/png',{maxHeight:2}),candidateResizeImage(bytes,'image/png')]);
        \\if(results[0].width!==4||results[0].height!==3||results[1].height!==2||results[2].wasResized!==false||JSON.stringify([...bytes])!==JSON.stringify(before))throw Error('concurrent image request isolation');
    , "image-concurrent-requests");
    engine.freeValue(result);
}
test "native image JavaScript-valued strategy matches latest worker shared options and invalid MIME fallback chronology" {
    const engine = try js.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 5000 });
    defer engine.deinit();
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try js.define(engine, global, "candidateResizeImage", try image_api.create(engine));
    const input = @embedFile("ai/fixtures/photon-source-8x5.png");
    try js.define(engine, global, "imageInputBuffer", try engine.checked(c.JS_NewArrayBufferCopy(engine.context, input.ptr, input.len)));
    const fixture = @embedFile("extensions/fixtures/image-worker-boundary-89e5-source.json");
    try js.define(engine, global, "imageBoundarySource", try engine.checked(c.JS_ParseJSON(engine.context, fixture.ptr, fixture.len, "image-boundary-89e5-source")));
    const result = engine.evalModule(
        \\const rows=[];
        \\for(const name of ['shared-options','boxed-mime','undefined-mime','null-mime']){
        \\ const calls=[],input=new Uint8Array(imageInputBuffer),before=[...input],mime=name==='boxed-mime'?new String('image/png'):name==='undefined-mime'?undefined:name==='null-mime'?null:'image/png';
        \\ const shared=new SharedArrayBuffer(8),options={get maxWidth(){calls.push('maxWidth');return 4},get maxHeight(){calls.push('maxHeight');return 3},shared,view:new Uint8Array(shared)};
        \\ const result=await candidateResizeImage(input,mime,options);
        \\ rows.push({name,calls,result,mimeIdentity:result===null?null:result.mimeType===mime,inputUnchanged:JSON.stringify([...input])===JSON.stringify(before)});
        \\}
        \\if(rows.length!==4||imageBoundarySource.rows.length!==4)throw Error('latest image Source count');
        \\for(let index=0;index<rows.length;index++)if(JSON.stringify(rows[index])!==JSON.stringify(imageBoundarySource.rows[index]))throw Error(JSON.stringify({index,actual:rows[index],expected:imageBoundarySource.rows[index]}));
    , "image-boundary-89e5-native") catch |err| {
        std.debug.print("Latest image boundary: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
}
test "native image JavaScript-valued strategy closes an unawaited worker promise with its VM" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    errdefer engine.deinit();
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    var encoded_mime = blk: {
        const mime = try engine.checked(c.JS_NewString(engine.context, "image/png"));
        defer engine.freeValue(mime);
        break :blk try option_graph.serializeForWorker(engine, mime);
    };
    defer encoded_mime.deinit(std.testing.allocator);
    var encoded_options = blk: {
        const options = try engine.eval("({maxWidth:4})", "unawaited-image-options", c.JS_EVAL_TYPE_GLOBAL);
        defer engine.freeValue(options);
        break :blk try option_graph.serializeForWorker(engine, options);
    };
    defer encoded_options.deinit(std.testing.allocator);
    const task = try worker.Worker.start(std.testing.allocator, @embedFile("ai/fixtures/photon-source-8x5.png"), encoded_mime, encoded_options);
    const promise = promises.create(engine, task) catch |err| {
        task.deinit();
        return err;
    };
    engine.freeValue(promise);
    // Scheduler destruction releases its native callback owner, which joins
    // the exact worker before allocator and runtime destruction complete.
    engine.deinit();
}
test "native image JavaScript-valued strategy public candidate keeps clone and fallback getter traces" {
    const engine = try js.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 5000 });
    defer engine.deinit();
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try js.define(engine, global, "candidateResizeImage", try image_api.create(engine));
    const input = @embedFile("ai/fixtures/photon-source-8x5.png");
    const buffer = try engine.checked(c.JS_NewArrayBufferCopy(engine.context, input.ptr, input.len));
    defer engine.freeValue(buffer);
    try js.define(engine, global, "imageInputBuffer", c.JS_DupValue(engine.context, buffer));
    const result = try engine.evalModule(
        \\const bytes=new Uint8Array(imageInputBuffer),before=[...bytes],calls=[];
        \\const options={get maxWidth(){calls.push('maxWidth');return 4},get maxHeight(){calls.push('maxHeight');return 3}};
        \\const result=await candidateResizeImage(bytes,'image/png',options);if(result.width!==4||result.height!==3||JSON.stringify(calls)!=='["maxWidth","maxHeight"]'||JSON.stringify([...bytes])!==JSON.stringify(before))throw Error('Source worker options/input mismatch');
        \\const mutable=new Uint8Array(imageInputBuffer.slice(0)),mutations=[];const isolated=await candidateResizeImage(mutable,'image/png',{get maxWidth(){mutations.push('maxWidth');mutable.fill(0);return 4},get maxHeight(){mutations.push('maxHeight');return 3}});if(isolated.data!==result.data||!mutable.every(value=>value===0)||JSON.stringify(mutations)!=='["maxWidth","maxHeight"]')throw Error('worker byte copy must precede option clone');
        \\const marker={original:true},failed=[];const rejected={get maxWidth(){failed.push('maxWidth');throw marker}};let promise;try{promise=candidateResizeImage(bytes,'image/png',rejected)}catch(error){throw Error('async image threw synchronously')};try{await promise;throw Error('missing image rejection')}catch(error){if(error!==marker)throw error};if(JSON.stringify(failed)!=='["maxWidth","maxWidth"]')throw Error('fallback original getter trace');
    , "native-image-public-candidate");
    engine.freeValue(result);
}
test "native image JavaScript-valued strategy settles its worker promise on the owner VM" {
    const engine = try js.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 5000 });
    defer engine.deinit();
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    const mime = try engine.checked(c.JS_NewString(engine.context, "image/png"));
    defer engine.freeValue(mime);
    const options = try engine.eval("({maxWidth:4,maxHeight:3})", "image-promise-options", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(options);
    var encoded_mime = try option_graph.serializeForWorker(engine, mime);
    defer encoded_mime.deinit(std.testing.allocator);
    var encoded_options = try option_graph.serializeForWorker(engine, options);
    defer encoded_options.deinit(std.testing.allocator);
    const task = try worker.Worker.start(std.testing.allocator, @embedFile("ai/fixtures/photon-source-8x5.png"), encoded_mime, encoded_options);
    const promise = promises.create(engine, task) catch |err| {
        task.deinit();
        return err;
    };
    defer engine.freeValue(promise);
    const result = try engine.awaitValue(promise);
    defer engine.freeValue(result);
    const width = try js.get(engine, result, "width");
    defer engine.freeValue(width);
    var numeric: i32 = 0;
    if (c.JS_ToInt32(engine.context, &numeric, width) < 0) return js.capture(engine);
    try std.testing.expectEqual(@as(i32, 4), numeric);
}
test "native image JavaScript-valued strategy executes on an independent owned worker VM" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const mime = try engine.checked(c.JS_NewString(engine.context, "image/png"));
    defer engine.freeValue(mime);
    const options = try engine.eval("({maxWidth:4,maxHeight:3})", "image-worker-options", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(options);
    var encoded_mime = try option_graph.serializeForWorker(engine, mime);
    defer encoded_mime.deinit(std.testing.allocator);
    var encoded_options = try option_graph.serializeForWorker(engine, options);
    defer encoded_options.deinit(std.testing.allocator);
    const task = try worker.Worker.start(std.testing.allocator, @embedFile("ai/fixtures/photon-source-8x5.png"), encoded_mime, encoded_options);
    defer task.deinit();
    const result = try task.result(engine);
    defer engine.freeValue(result);
    try std.testing.expect(task.isDone());
    const width = try js.get(engine, result, "width");
    defer engine.freeValue(width);
    var value: i32 = 0;
    if (c.JS_ToInt32(engine.context, &value, width) < 0) return js.capture(engine);
    try std.testing.expectEqual(@as(i32, 4), value);
}
test "native image JavaScript-valued strategy matches actual original resized bytes and dimension types" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const mime = try engine.checked(c.JS_NewString(engine.context, "image/png"));
    defer engine.freeValue(mime);
    const options = try engine.eval("({maxWidth:4,maxHeight:3})", "image-js-options", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(options);
    const result = try strategy.resize(engine, @embedFile("ai/fixtures/photon-source-8x5.png"), mime, options);
    defer engine.freeValue(result);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try js.define(engine, global, "nativeImageResult", c.JS_DupValue(engine.context, result));
    const check = try engine.eval(
        \\if(nativeImageResult.data!=='iVBORw0KGgoAAAANSUhEUgAAAAQAAAADCAYAAAC09K7GAAAAPklEQVR4AQEzAMz/AG2IfvSNhGvRhneO33qLffEArF5i5mhkof9ohpvogZtY9wCHepPddJ180aFKePVNbJf/1A4coj83usMAAAAASUVORK5CYII='||nativeImageResult.width!==4||nativeImageResult.height!==3||nativeImageResult.originalWidth!==8||nativeImageResult.originalHeight!==5||nativeImageResult.mimeType!=='image/png'||nativeImageResult.wasResized!==true)throw Error('Source image result mismatch');
    , "image-js-source-result", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(check);
}

//! Highlighter-local inline roots: actual VM WeakRef and spill-failure ownership.
const std = @import("std");
const em = @import("extensions/engine.zig");
const Scope = @import("extensions/native_highlight_scope.zig").Scope;
const c = em.c;
fn eval(engine: *em.Engine, source: []const u8) !void {
    const value = try engine.eval(source, "highlight-scope-regression.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(value);
}
fn collect(engine: *em.Engine) void {
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
}
test "native highlight inline roots32 and33 retain actual VM objects until full scope retirement" {
    const owners = c.pi_js_native_memory_owners();
    for ([_]usize{ 32, 33 }) |count| {
        {
            const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
            defer engine.deinit();
            const program = try std.fmt.allocPrint(std.testing.allocator, "globalThis.scopeTargets=Array.from({{length:{d}}},()=>({{}}));globalThis.scopeWeak=scopeTargets.map(value=>new WeakRef(value));", .{count});
            defer std.testing.allocator.free(program);
            try eval(engine, program);
            {
                var scope: Scope = .{ .engine = engine };
                defer scope.deinit();
                const global = c.JS_GetGlobalObject(engine.context);
                defer engine.freeValue(global);
                const targets = try engine.checked(c.JS_GetPropertyStr(engine.context, global, "scopeTargets"));
                for (0..count) |index| _ = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, targets, @intCast(index))));
                engine.freeValue(targets);
                try eval(engine, "delete globalThis.scopeTargets;");
                collect(engine);
                try eval(engine, "if(!scopeWeak.every(value=>value.deref()!==undefined))throw Error('Scope root collected early');");
                try std.testing.expectEqual(@as(usize, 32), scope.inline_count);
                try std.testing.expectEqual(count - 32, scope.spill_values.items.len);
            }
            collect(engine);
            try eval(engine, "if(!scopeWeak.every(value=>value.deref()===undefined))throw Error('Scope root retained after retirement');delete globalThis.scopeWeak;");
        }
        try std.testing.expectEqual(owners, c.pi_js_native_memory_owners());
    }
}
test "native highlight inline roots first spill failure frees incoming value without releasing existing32" {
    const owners = c.pi_js_native_memory_owners();
    {
        const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
        defer engine.deinit();
        {
            var scope: Scope = .{ .engine = engine };
            defer scope.deinit();
            for (0..32) |_| _ = try scope.object();
            const incoming = try engine.eval("globalThis.scopeFailureWeak=new WeakRef(globalThis.scopeFailureTarget={});scopeFailureTarget", "highlight-scope-spill.js", c.JS_EVAL_TYPE_GLOBAL);
            var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
            const saved = engine.gpa;
            {
                engine.gpa = failing.allocator();
                defer engine.gpa = saved;
                try std.testing.expectError(error.OutOfMemory, scope.own(incoming));
            }
            try std.testing.expect(failing.has_induced_failure);
            try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
            try std.testing.expectEqual(@as(usize, 32), scope.inline_count);
            try std.testing.expectEqual(@as(usize, 0), scope.spill_values.items.len);
            try eval(engine, "delete globalThis.scopeFailureTarget;");
            collect(engine);
            try eval(engine, "if(scopeFailureWeak.deref()!==undefined)throw Error('Failed incoming root retained');delete globalThis.scopeFailureWeak;");
        }
    }
    try std.testing.expectEqual(owners, c.pi_js_native_memory_owners());
}
test "native highlight inline roots nested actual grammar scanner completes128 levels and recovers" {
    const owners = c.pi_js_native_memory_owners();
    {
        const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
        defer engine.deinit();
        const eager = try @import("extensions/native_syntax_highlight.zig").createEager(engine);
        defer eager.deinit(engine);
        {
            var s: Scope = .{ .engine = engine };
            defer s.deinit();
            const global = try s.own(c.JS_GetGlobalObject(engine.context));
            try s.put(global, "scopeCore", eager.core);
        }
        // Stack completion/recovery regression, not a new original-source golden.
        // The unchanged genuine74 comparator independently checks Source semantics.
        try eval(engine,
            \\scopeCore.registerLanguage('inline-nested',()=>({contains:[{className:'section',begin:/\(/,end:/\)/,contains:['self']}]}));
            \\for(const depth of [32,64,128]){const code='('.repeat(depth)+'owned'+')'.repeat(depth);const result=scopeCore.highlight(code,{language:'inline-nested',ignoreIllegals:false});if(result.errorRaised||result.illegal||result.code!==code||(result.value.match(/hljs-section/g)||[]).length!==depth)throw Error('Nested grammar stack or token regression');}
            \\scopeCore.unregisterLanguage('inline-nested');const recovered=scopeCore.highlight('{}',{language:'json'});if(recovered.errorRaised||recovered.illegal)throw Error('Post-nesting recovery failed');delete globalThis.scopeCore;
        );
        collect(engine);
    }
    try std.testing.expectEqual(owners, c.pi_js_native_memory_owners());
}

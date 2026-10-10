//! Native document token, revocable draft and detached committed snapshot facade.
const std = @import("std");
const engine_mod = @import("engine.zig");
const durable = @import("native_durable.zig");
const sdk = @import("native_sdk.zig");
const backend = @import("../durable/backend/root.zig");
const json = backend.json;
const c = engine_mod.c;
const Engine = engine_mod.Engine;
const Pair = struct { target: c.JSValue, proxy: c.JSValue };
const Document = struct { address: json.Owned, record: json.Owned, baseline: json.Owned, definition: c.JSValue, target: c.JSValue, pairs: std.ArrayList(Pair) = .empty, created: bool, plan: ?usize, version: u64, stored_version: u64, deltas_since_base: u64 = 0, retired: bool = false, write_index: ?usize = null };
const Cached = struct { address: json.Owned, record: json.Owned, value: c.JSValue, version: u64 };
pub const Cache = struct {
    engine: *Engine,
    items: std.ArrayList(Cached) = .empty,
    pub fn deinit(self: *Cache, runtime: ?*c.JSRuntime) void {
        for (self.items.items) |*item| {
            item.address.deinit();
            item.record.deinit();
            c.JS_FreeValueRT(runtime, item.value);
        }
        self.items.deinit(self.engine.gpa);
        self.engine.gpa.destroy(self);
    }
    pub fn mark(self: *Cache, runtime: ?*c.JSRuntime, marker: ?*const c.JS_MarkFunc) void {
        for (self.items.items) |item| c.JS_MarkValue(runtime, item.value, marker);
    }
    fn get(self: *Cache, address_value: json.Value, version: u64) ?*Cached {
        for (self.items.items) |*item| if (json.equal(item.address.value, address_value) and item.version == version) return item;
        return null;
    }
    fn put(self: *Cache, address_value: json.Value, record: json.Value, value: c.JSValue, version: u64) !void {
        for (self.items.items) |*item| if (json.equal(item.address.value, address_value)) {
            self.engine.freeValue(item.value);
            item.value = c.JS_DupValue(self.engine.context, value);
            item.version = version;
            return;
        };
        var address_copy = try json.Owned.empty(self.engine.gpa);
        errdefer address_copy.deinit();
        address_copy.value = try json.clone(address_copy.arena.allocator(), address_value);
        var record_copy = try json.Owned.empty(self.engine.gpa);
        errdefer record_copy.deinit();
        record_copy.value = try json.clone(record_copy.arena.allocator(), record);
        try self.items.ensureUnusedCapacity(self.engine.gpa, 1);
        self.items.appendAssumeCapacity(.{ .address = address_copy, .record = record_copy, .value = c.JS_DupValue(self.engine.context, value), .version = version });
    }
};
fn cache(engine: *Engine, session: c.JSValue) !*Cache {
    const owner = try durable.state(engine, session);
    if (owner.document_cache) |value| return value;
    const value = try engine.gpa.create(Cache);
    value.* = .{ .engine = engine };
    owner.document_cache = value;
    return value;
}
pub const Drafts = struct {
    engine: *Engine,
    owner: *durable.State,
    prepared: bool = false,
    adopted: bool = false,
    items: std.ArrayList(Document) = .empty,
    prepared_cache: std.ArrayList(Cached) = .empty,
    pub fn deinit(self: *Drafts, runtime: ?*c.JSRuntime) void {
        for (self.items.items) |*doc| {
            doc.address.deinit();
            doc.record.deinit();
            doc.baseline.deinit();
            c.JS_FreeValueRT(runtime, doc.definition);
            c.JS_FreeValueRT(runtime, doc.target);
            for (doc.pairs.items) |pair| {
                c.JS_FreeValueRT(runtime, pair.target);
                c.JS_FreeValueRT(runtime, pair.proxy);
            }
            doc.pairs.deinit(self.engine.gpa);
        }
        self.items.deinit(self.engine.gpa);
        for (self.prepared_cache.items) |*item| {
            item.address.deinit();
            item.record.deinit();
            c.JS_FreeValueRT(runtime, item.value);
        }
        self.prepared_cache.deinit(self.engine.gpa);
        self.engine.gpa.destroy(self);
    }
    pub fn mark(self: *Drafts, runtime: ?*c.JSRuntime, marker: ?*const c.JS_MarkFunc) void {
        for (self.prepared_cache.items) |item| c.JS_MarkValue(runtime, item.value, marker);
        for (self.items.items) |doc| {
            c.JS_MarkValue(runtime, doc.definition, marker);
            c.JS_MarkValue(runtime, doc.target, marker);
            for (doc.pairs.items) |pair| {
                c.JS_MarkValue(runtime, pair.target, marker);
                c.JS_MarkValue(runtime, pair.proxy, marker);
            }
        }
    }
    pub fn finish(self: *Drafts) !void {
        self.prepared = true;
        const tx = self.owner.transaction.?;
        const values = try cache(self.engine, self.owner.parent);
        try values.items.ensureUnusedCapacity(self.engine.gpa, self.items.items.len);
        try self.prepared_cache.ensureUnusedCapacity(self.engine.gpa, self.items.items.len);
        for (self.items.items) |doc| {
            if (doc.retired) continue;
            if (values.get(doc.address.value, doc.version)) |existing| {
                if (json.equal(json.get(existing.record.value, "id") orelse .null, json.get(doc.record.value, "id") orelse .null)) {
                    var current = try durable.owned(self.engine, doc.target);
                    defer current.deinit();
                    if (json.equal(current.value, doc.baseline.value)) continue;
                }
            }
            var address_copy = try json.Owned.empty(self.engine.gpa);
            errdefer address_copy.deinit();
            address_copy.value = try json.clone(address_copy.arena.allocator(), doc.address.value);
            var record_copy = try json.Owned.empty(self.engine.gpa);
            errdefer record_copy.deinit();
            record_copy.value = try json.clone(record_copy.arena.allocator(), doc.record.value);
            self.prepared_cache.appendAssumeCapacity(.{ .address = address_copy, .record = record_copy, .value = c.JS_DupValue(self.engine.context, doc.target), .version = doc.version });
        }
        for (self.items.items) |*doc| {
            if (doc.retired) {
                var retirement = try json.Owned.empty(self.engine.gpa);
                defer retirement.deinit();
                retirement.value = .{ .object = .empty };
                try retirement.value.object.put(retirement.arena.allocator(), "type", .{ .string = "document.retire" });
                try retirement.value.object.put(retirement.arena.allocator(), "id", try json.required(doc.record.value, "id"));
                try tx.documentCommand(retirement.value);
            }
            var value = try durable.owned(self.engine, doc.target);
            defer value.deinit();
            if (doc.plan) |index| {
                const plan = &self.owner.plans.items[index];
                try plan.value.object.getPtr("content").?.object.put(plan.arena.allocator(), "value", try json.clone(plan.arena.allocator(), value.value));
                continue;
            }
            if (!doc.created and doc.version <= doc.stored_version and json.equal(value.value, doc.baseline.value)) continue;
            var write = try json.Owned.empty(self.engine.gpa);
            defer write.deinit();
            const a = write.arena.allocator();
            write.value = .{ .object = .empty };
            try write.value.object.put(a, "type", .{ .string = if (doc.created) "document.create" else "document.change" });
            if (doc.created) try write.value.object.put(a, "record", try json.clone(a, doc.record.value)) else try write.value.object.put(a, "id", try json.required(doc.record.value, "id"));
            var content: json.Value = .{ .object = .empty };
            try content.object.put(a, "version", .{ .integer = @intCast(doc.version) });
            var operations: json.Value = .{ .array = .init(a) };
            var path: std.ArrayList(json.Value) = .empty;
            defer path.deinit(self.engine.gpa);
            try differences(a, self.engine.gpa, doc.baseline.value, value.value, &path, &operations);
            if (!doc.created) try tx.documentPublicationOps(try json.asInteger(try json.required(doc.record.value, "id")), operations);
            const base = doc.created or doc.version > doc.stored_version;
            try content.object.put(a, "kind", .{ .string = if (base) "base" else "delta" });
            try content.object.put(a, if (base) "value" else "ops", if (base) try json.clone(a, value.value) else operations);
            try write.value.object.put(a, "content", content);
            try tx.documentCommand(write.value);
            doc.write_index = tx.writes.array.items.len - 1;
        }
        tx.before_storage = finalizePredicates;
        tx.before_storage_context = self;
        tx.after_storage = afterStorage;
        tx.after_storage_context = self;
    }
    fn finalizePredicates(raw: ?*anyopaque) !void {
        const self: *Drafts = @ptrCast(@alignCast(raw.?));
        const engine = self.engine;
        const tx = self.owner.transaction.?;
        if (std.Thread.getCurrentId() != tx.ownerThread) return error.VMCallbackOnWorker;
        for (self.items.items) |doc| {
            if (doc.write_index == null) continue;
            const doc_id = try json.asInteger(try json.required(doc.record.value, "id"));
            var matched: ?*json.Value = null;
            for (tx.writes.array.items) |*write| {
                const tag = try json.asString(try json.required(write.*, "type"));
                if (!std.mem.eql(u8, tag, "document.change")) continue;
                if (try json.asInteger(try json.required(write.*, "id")) == doc_id) {
                    matched = write.object.getPtr("content");
                    break;
                }
            }
            const content = matched orelse continue;
            if (!std.mem.eql(u8, try json.asString(try json.required(content.*, "kind")), "delta")) continue;
            const predicate = try sdk.get(engine, doc.definition, "checkpointWhen");
            defer engine.freeValue(predicate);
            if (!c.JS_IsFunction(engine.context, predicate)) continue;
            const ops = try durable.jsValue(engine, try json.required(content.*, "ops"));
            defer engine.freeValue(ops);
            const info = try sdk.object(engine);
            defer engine.freeValue(info);
            try sdk.put(engine, info, "deltasSinceBase", c.JS_NewInt64(engine.context, @intCast(doc.deltas_since_base)));
            var args = [_]c.JSValue{ doc.target, ops, info };
            const result = try engine.checked(c.JS_Call(engine.context, predicate, doc.definition, args.len, &args));
            defer engine.freeValue(result);
            var operations = try durable.owned(engine, ops);
            defer operations.deinit();
            const a = tx.owned.arena.allocator();
            const stored_ops = try json.clone(a, operations.value);
            try tx.preparedDocumentOps.put(a, try json.asInteger(try json.required(doc.record.value, "id")), stored_ops);
            if (c.JS_ToBool(engine.context, result) > 0) {
                var value = try durable.owned(engine, doc.target);
                defer value.deinit();
                _ = content.object.orderedRemove("ops");
                try content.object.put(a, "kind", .{ .string = "base" });
                try content.object.put(a, "value", try json.clone(a, value.value));
            } else try content.object.put(a, "ops", stored_ops);
        }
    }
    fn afterStorage(raw: ?*anyopaque) !void {
        const self: *Drafts = @ptrCast(@alignCast(raw.?));
        if (std.Thread.getCurrentId() != self.owner.transaction.?.ownerThread) return error.VMCallbackOnWorker;
        try self.adopt(self.owner.parent);
    }
    pub fn adopt(self: *Drafts, session: c.JSValue) !void {
        if (self.adopted) return;
        const values = try cache(self.engine, session);
        for (self.prepared_cache.items) |prepared| {
            var replaced = false;
            for (values.items.items) |*item| if (json.equal(item.address.value, prepared.address.value)) {
                item.address.deinit();
                item.record.deinit();
                self.engine.freeValue(item.value);
                item.* = prepared;
                replaced = true;
                break;
            };
            if (!replaced) values.items.appendAssumeCapacity(prepared);
        }
        self.prepared_cache.clearRetainingCapacity();
        for (self.items.items) |doc| if (doc.retired) {
            var index: usize = 0;
            while (index < values.items.items.len) {
                const item = &values.items.items[index];
                if (!json.equal(item.address.value, doc.address.value)) {
                    index += 1;
                    continue;
                }
                // A replacement at the same address keeps the final incarnation.
                var replaced = false;
                for (self.items.items) |later| if (!later.retired and json.equal(later.address.value, doc.address.value)) {
                    replaced = true;
                    break;
                };
                if (replaced) break;
                var removed = values.items.orderedRemove(index);
                removed.address.deinit();
                removed.record.deinit();
                self.engine.freeValue(removed.value);
            }
        };
        self.adopted = true;
    }
};
pub fn publicationValue(owner: *durable.State, record: json.Value, version: u64) ?c.JSValue {
    const values = owner.document_cache orelse return null;
    for (values.items.items) |item| {
        if (item.version == version and json.equal(json.get(item.record.value, "id") orelse .null, json.get(record, "id") orelse .null)) return item.value;
    }
    return null;
}
/// Native scheduler document commands do not pass through VM Drafts.adopt.
/// Adopt their already-owned publication on the VM owner before observers or
/// waiters run; preserve the canonical VM object when it was adopted already.
pub fn adoptNativePublication(owner: *durable.State, changes: json.Value) !void {
    if (std.Thread.getCurrentId() != owner.owner_thread) return error.VMCallbackOnWorker;
    const values = owner.document_cache orelse return;
    const engine = owner.engine;
    for (changes.array.items) |change| {
        const kind = json.get(change, "type") orelse continue;
        if (kind != .string or !std.mem.eql(u8, kind.string, "document")) continue;
        const record = json.get(change, "record") orelse continue;
        const id = try json.asInteger(try json.required(record, "id"));
        var index: usize = 0;
        while (index < values.items.items.len) {
            const item = &values.items.items[index];
            if (try json.asInteger(try json.required(item.record.value, "id")) != id) {
                index += 1;
                continue;
            }
            const value = json.get(change, "value") orelse .null;
            const version = json.get(change, "version");
            if (value == .null or version == null or version.? == .null or try json.asInteger(version.?) != item.version) {
                var retired = values.items.orderedRemove(index);
                retired.address.deinit();
                retired.record.deinit();
                engine.freeValue(retired.value);
                continue;
            }
            var prior = try durable.owned(engine, item.value);
            defer prior.deinit();
            if (!json.equal(prior.value, value)) {
                const adopted = try durable.jsValue(engine, value);
                engine.freeValue(item.value);
                item.value = adopted;
            }
            index += 1;
        }
    }
}
pub fn install(engine: *Engine, exports: c.JSValue) !void {
    try sdk.put(engine, exports, "defineDoc", try engine.checked(c.JS_NewCFunction(engine.context, define, "defineDoc", 1)));
    try sdk.put(engine, exports, "defineDocFamily", try engine.checked(c.JS_NewCFunction(engine.context, define, "defineDocFamily", 1)));
}
fn define(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return definition(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| durable.reject(engine, err);
}
fn definition(engine: *Engine, source: c.JSValue) !c.JSValue {
    const version = try sdk.get(engine, source, "version");
    defer engine.freeValue(version);
    if (try durable.number(engine, version) == 0) return error.InvalidDocumentVersion;
    const token = try sdk.object(engine);
    errdefer engine.freeValue(token);
    try sdk.put(engine, token, "definition", c.JS_DupValue(engine.context, source));
    return token;
}
fn field(engine: *Engine, definition_value: c.JSValue, name: [*:0]const u8) ![]u8 {
    const value = try sdk.get(engine, definition_value, name);
    defer engine.freeValue(value);
    return engine.toString(value);
}
const Address = struct { value: json.Owned, next: usize };
fn address(engine: *Engine, definition_value: c.JSValue, args: []const c.JSValue) !Address {
    var value = try json.Owned.empty(engine.gpa);
    errdefer value.deinit();
    const a = value.arena.allocator();
    const kind = try field(engine, definition_value, "kind");
    defer engine.gpa.free(kind);
    const scope_name = try field(engine, definition_value, "scope");
    defer engine.gpa.free(scope_name);
    var scope: json.Value = .{ .object = .empty };
    try scope.object.put(a, "kind", .{ .string = try a.dupe(u8, scope_name) });
    var index: usize = 0;
    if (!std.mem.eql(u8, scope_name, "session")) {
        if (!std.mem.eql(u8, scope_name, "conversation") and !std.mem.eql(u8, scope_name, "task")) return error.InvalidDocumentScope;
        if (args.len == 0) return error.DocumentOwnerRequired;
        try scope.object.put(a, if (std.mem.eql(u8, scope_name, "conversation")) "conversationId" else "taskId", .{ .integer = @intCast(try durable.number(engine, args[0])) });
        index += 1;
    }
    value.value = .{ .object = .empty };
    try value.value.object.put(a, "kind", .{ .string = try a.dupe(u8, kind) });
    try value.value.object.put(a, "scope", scope);
    const family = try sdk.get(engine, definition_value, "family");
    defer engine.freeValue(family);
    if (c.JS_ToBool(engine.context, family) > 0) {
        if (args.len <= index) return error.DocumentFamilyKeyRequired;
        const key = try engine.toString(args[index]);
        defer engine.gpa.free(key);
        try value.value.object.put(a, "key", .{ .string = try a.dupe(u8, key) });
        index += 1;
    }
    return .{ .value = value, .next = index };
}
pub fn acquire(engine: *Engine, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const owner = try durable.state(engine, receiver);
    const native = owner.transaction.?;
    if (!native.active) return error.TransactionClosed;
    const token = args[0];
    const definition_value = try sdk.get(engine, token, "definition");
    defer engine.freeValue(definition_value);
    const desired_version = try sdk.get(engine, definition_value, "version");
    defer engine.freeValue(desired_version);
    const version = try durable.number(engine, desired_version);
    var stored_version = version;
    var deltas_since_base: u64 = 0;
    var resolved = try address(engine, definition_value, args[1..]);
    defer resolved.value.deinit();
    if (owner.documents == null) {
        const drafts = try engine.gpa.create(Drafts);
        drafts.* = .{ .engine = engine, .owner = owner };
        owner.documents = drafts;
    }
    const drafts = owner.documents.?;
    var replacing = false;
    var prior_index = drafts.items.items.len;
    while (prior_index > 0) {
        prior_index -= 1;
        const doc = drafts.items.items[prior_index];
        if (!json.equal(doc.address.value, resolved.value.value)) continue;
        if (doc.retired) {
            replacing = true;
            break;
        }
        const value = try proxy(drafts, receiver, prior_index, doc.target);
        defer engine.freeValue(value);
        return sdk.promise(engine, value);
    }
    var admitted = false;
    var record = try json.Owned.empty(engine.gpa);
    errdefer if (!admitted) record.deinit();
    var baseline = try json.Owned.empty(engine.gpa);
    errdefer if (!admitted) baseline.deinit();
    const a = record.arena.allocator();
    var created = false;
    var planned: ?usize = null;
    for (owner.plans.items, 0..) |plan, index| {
        if (replacing) break;
        const candidate = try json.required(plan.value, "record");
        if (!try backend.memory.sameAddress(candidate, resolved.value.value)) continue;
        record.value = try json.clone(a, candidate);
        baseline.value = try json.clone(baseline.arena.allocator(), try json.required(try json.required(plan.value, "content"), "value"));
        planned = index;
        break;
    }
    var current_state: backend.memory.Memory = .{ .gpa = engine.gpa, .state = try native.session.storage.snapshot(engine.gpa) };
    defer current_state.deinit();
    if (planned == null) {
        var found = if (replacing) null else try backend.query.findDocument(engine.gpa, &current_state, resolved.value.value, .current);
        defer if (found) |*value| value.deinit();
        if (found) |value| {
            record.value = try json.clone(a, value.value);
            var contents = (try native.session.storage.readDocument(engine.gpa, try json.asInteger(try json.required(record.value, "id")), .current)).?;
            defer contents.deinit();
            stored_version = try json.asInteger(try json.required(contents.value, "version"));
            deltas_since_base = try json.asInteger(try json.required(contents.value, "deltasSinceBase"));
            var materialized = try materialize(engine, definition_value, record.value, contents.value);
            defer materialized.deinit();
            baseline.value = try json.clone(baseline.arena.allocator(), materialized.value);
            const cached = try cache(engine, owner.parent);
            if (cached.get(resolved.value.value, version)) |cached_value| {
                var existing = try durable.owned(engine, cached_value.value);
                defer existing.deinit();
                baseline.value = try json.clone(baseline.arena.allocator(), existing.value);
            }
        } else {
            created = true;
            record.value = try json.clone(a, resolved.value.value);
            const scope = try json.required(record.value, "scope");
            const scope_kind = try json.asString(try json.required(scope, "kind"));
            if (std.mem.eql(u8, scope_kind, "conversation")) {
                const id = try json.asInteger(try json.required(scope, "conversationId"));
                if ((try native.currentRecord(id, .conversation)) == null) try sourceError(engine, "Conversation {d} does not exist", .{id});
            } else if (std.mem.eql(u8, scope_kind, "task")) {
                const id = try json.asInteger(try json.required(scope, "taskId"));
                const task = (try native.currentRecord(id, .task)) orelse {
                    try sourceError(engine, "Task {d} does not exist", .{id});
                    return error.JavaScriptException;
                };
                if (std.mem.eql(u8, try json.asString(try json.required(try json.required(task, "state"), "status")), "terminal")) try sourceError(engine, "Task {d} is terminal", .{id});
            }
            if (std.mem.eql(u8, try json.asString(try json.required(scope, "kind")), "conversation")) {
                inline for (.{ "history", "fork" }) |name| {
                    const text = try field(engine, definition_value, name);
                    defer engine.gpa.free(text);
                    try record.value.object.put(a, name, .{ .string = try a.dupe(u8, text) });
                }
            }
            const initial = try sdk.get(engine, definition_value, "initial");
            defer engine.freeValue(initial);
            var initial_args = [_]c.JSValue{if (resolved.next + 1 < args.len) args[resolved.next + 1] else c.pi_js_undefined()};
            const family = try sdk.get(engine, definition_value, "family");
            defer engine.freeValue(family);
            const value = try engine.checked(c.JS_Call(engine.context, initial, definition_value, if (c.JS_ToBool(engine.context, family) > 0) 1 else 0, &initial_args));
            defer engine.freeValue(value);
            var copied = try durable.owned(engine, value);
            defer copied.deinit();
            baseline.value = try json.clone(baseline.arena.allocator(), copied.value);
            try record.value.object.put(a, "id", .{ .integer = @intCast(try native.session.storage.mintId()) });
        }
    }
    const version_value = try sdk.get(engine, definition_value, "version");
    defer engine.freeValue(version_value);
    const target = try durable.jsValue(engine, baseline.value);
    errdefer if (!admitted) engine.freeValue(target);
    try drafts.items.ensureUnusedCapacity(engine.gpa, 1);
    const index = drafts.items.items.len;
    var owned_address = try json.Owned.empty(engine.gpa);
    errdefer if (!admitted) owned_address.deinit();
    owned_address.value = try json.clone(owned_address.arena.allocator(), resolved.value.value);
    drafts.items.appendAssumeCapacity(.{ .address = owned_address, .record = record, .baseline = baseline, .definition = c.JS_DupValue(engine.context, definition_value), .target = target, .created = created, .plan = planned, .version = try durable.number(engine, version_value), .stored_version = stored_version, .deltas_since_base = deltas_since_base });
    admitted = true;
    const borrowed = try proxy(drafts, receiver, index, target);
    defer engine.freeValue(borrowed);
    return sdk.promise(engine, borrowed);
}
fn sourceError(engine: *Engine, comptime format: []const u8, args: anytype) !void {
    const message = try std.fmt.allocPrint(engine.gpa, format, args);
    defer engine.gpa.free(message);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const constructor = try sdk.get(engine, global, "Error");
    defer engine.freeValue(constructor);
    const text = try sdk.text(engine, message);
    defer engine.freeValue(text);
    var parameters = [_]c.JSValue{text};
    const failure = try engine.checked(c.JS_CallConstructor(engine.context, constructor, 1, &parameters));
    _ = try engine.checked(c.JS_Throw(engine.context, failure));
}
pub fn retire(engine: *Engine, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const owner = try durable.state(engine, receiver);
    if (!owner.transaction.?.active) return error.TransactionClosed;
    const definition_value = try sdk.get(engine, args[0], "definition");
    defer engine.freeValue(definition_value);
    var resolved = try address(engine, definition_value, args[1..]);
    defer resolved.value.deinit();
    if (owner.documents) |drafts| {
        var index = drafts.items.items.len;
        while (index > 0) {
            index -= 1;
            const doc = &drafts.items.items[index];
            if (json.equal(doc.address.value, resolved.value.value)) {
                doc.retired = true;
                return sdk.promise(engine, c.pi_js_undefined());
            }
        }
    }
    var model: backend.memory.Memory = .{ .gpa = engine.gpa, .state = try owner.transaction.?.session.storage.snapshot(engine.gpa) };
    defer model.deinit();
    var record = (try backend.query.findDocument(engine.gpa, &model, resolved.value.value, .current)) orelse return sdk.promise(engine, c.pi_js_undefined());
    defer record.deinit();
    const promise = try acquire(engine, receiver, args);
    defer engine.freeValue(promise);
    const draft = try engine.awaitValue(promise);
    engine.freeValue(draft);
    owner.documents.?.items.items[owner.documents.?.items.items.len - 1].retired = true;
    return sdk.promise(engine, c.pi_js_undefined());
}
fn proxy(drafts: *Drafts, owner: c.JSValue, index: usize, target: c.JSValue) !c.JSValue {
    const engine = drafts.engine;
    const doc = &drafts.items.items[index];
    for (doc.pairs.items) |pair| if (c.JS_IsStrictEqual(engine.context, pair.target, target)) return c.JS_DupValue(engine.context, pair.proxy);
    const handler = try sdk.object(engine);
    defer engine.freeValue(handler);
    var data = [_]c.JSValue{ owner, c.JS_NewInt64(engine.context, @intCast(index)) };
    inline for (.{ "get", "set", "deleteProperty", "ownKeys", "has", "getOwnPropertyDescriptor" }, 0..) |name, operation| try sdk.put(engine, handler, name, try engine.checked(c.JS_NewCFunctionData(engine.context, trap, 3, @intCast(operation), data.len, &data)));
    try doc.pairs.ensureUnusedCapacity(engine.gpa, 1);
    const value = try engine.checked(c.JS_NewProxy(engine.context, target, handler));
    doc.pairs.appendAssumeCapacity(.{ .target = c.JS_DupValue(engine.context, target), .proxy = c.JS_DupValue(engine.context, value) });
    return value;
}
fn trap(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, operation: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return trapOwned(engine, argv[0..@intCast(argc)], operation, data) catch |err| durable.reject(engine, err);
}
fn trapOwned(engine: *Engine, args: []const c.JSValue, operation: c_int, data: [*c]c.JSValue) !c.JSValue {
    const owner = try durable.state(engine, data[0]);
    if (!owner.transaction.?.active or owner.documents.?.prepared) return error.TransactionClosed;
    const index: usize = @intCast(try durable.number(engine, data[1]));
    if (operation >= 3) {
        const global = c.JS_GetGlobalObject(engine.context);
        defer engine.freeValue(global);
        const reflect = try sdk.get(engine, global, "Reflect");
        defer engine.freeValue(reflect);
        if (operation == 3) return sdk.invoke(engine, reflect, "ownKeys", &.{args[0]});
        if (operation == 4) return sdk.invoke(engine, reflect, "has", &.{ args[0], args[1] });
        const descriptor = try sdk.invoke(engine, reflect, "getOwnPropertyDescriptor", &.{ args[0], args[1] });
        errdefer engine.freeValue(descriptor);
        if (!c.JS_IsUndefined(descriptor)) {
            const value = try sdk.get(engine, descriptor, "value");
            defer engine.freeValue(value);
            if (c.JS_IsObject(value) and !c.JS_IsFunction(engine.context, value)) try sdk.put(engine, descriptor, "value", try proxy(owner.documents.?, data[0], index, value));
        }
        return descriptor;
    }
    const atom = c.JS_ValueToAtom(engine.context, args[1]);
    if (atom == c.JS_ATOM_NULL) return error.JavaScriptException;
    defer c.JS_FreeAtom(engine.context, atom);
    if (operation == 0) {
        const value = try engine.checked(c.JS_GetProperty(engine.context, args[0], atom));
        if (c.JS_IsObject(value) and !c.JS_IsFunction(engine.context, value)) {
            defer engine.freeValue(value);
            return proxy(owner.documents.?, data[0], index, value);
        }
        return value;
    }
    if (operation == 2) {
        const deleted = c.JS_DeleteProperty(engine.context, args[0], atom, c.JS_PROP_THROW);
        if (deleted < 0) return error.JavaScriptException;
        return c.pi_js_bool(engine.context, @intFromBool(deleted != 0));
    }
    if (c.JS_IsSymbol(args[1])) return error.NonJsonDocumentProperty;
    const is_array = c.JS_IsArray(args[0]);
    if (c.JS_IsUndefined(args[2]) and !is_array) {
        const deleted = c.JS_DeleteProperty(engine.context, args[0], atom, c.JS_PROP_THROW);
        if (deleted < 0) return error.JavaScriptException;
        return c.pi_js_bool(engine.context, 1);
    }
    if (is_array) {
        const key = try engine.toString(args[1]);
        defer engine.gpa.free(key);
        const count = try sdk.length(engine, args[0]);
        if (std.mem.eql(u8, key, "length")) {
            const requested = try durable.number(engine, args[2]);
            if (requested > std.math.maxInt(u32)) return error.InvalidDocumentArrayLength;
            var fill_index: u32 = @intCast(count);
            while (fill_index < requested) : (fill_index += 1) if (c.JS_SetPropertyUint32(engine.context, args[0], fill_index, c.pi_js_null()) < 0) return error.JavaScriptException;
            if (c.JS_SetProperty(engine.context, args[0], atom, c.JS_DupValue(engine.context, args[2])) < 0) return error.JavaScriptException;
            return c.pi_js_bool(engine.context, 1);
        }
        if (key.len == 0 or (key.len > 1 and key[0] == '0')) return error.InvalidDocumentArrayProperty;
        for (key) |byte| if (byte < '0' or byte > '9') return error.InvalidDocumentArrayProperty;
        const array_index = std.fmt.parseInt(u32, key, 10) catch return error.InvalidDocumentArrayProperty;
        if (array_index == std.math.maxInt(u32) or array_index > count) return error.SparseDocumentArray;
    }
    if (c.JS_IsUndefined(args[2]) or c.JS_IsFunction(engine.context, args[2]) or c.JS_IsSymbol(args[2])) return error.NonJsonDocumentValue;
    var seen: std.ArrayList(c.JSValue) = .empty;
    defer seen.deinit(engine.gpa);
    try strictJson(engine, args[2], &seen);
    var copy = try durable.owned(engine, args[2]);
    defer copy.deinit();
    const value = try durable.jsValue(engine, copy.value);
    const set = if (is_array) c.JS_SetProperty(engine.context, args[0], atom, value) else c.JS_DefinePropertyValue(engine.context, args[0], atom, value, c.JS_PROP_C_W_E);
    if (set < 0) return error.JavaScriptException;
    return c.pi_js_bool(engine.context, 1);
}
pub fn unload(engine: *Engine, session: c.JSValue) !c.JSValue {
    var data = [_]c.JSValue{session};
    const callback = try engine.checked(c.JS_NewCFunctionData(engine.context, unloadQueued, 0, 0, data.len, &data));
    defer engine.freeValue(callback);
    return durable.enqueue(engine, session, callback);
}
fn unloadQueued(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const owner = durable.state(engine, data[0]) catch |err| return durable.reject(engine, err);
    if (owner.document_cache) |values| {
        owner.document_cache = null;
        values.deinit(engine.runtime);
    }
    return c.pi_js_undefined();
}
fn strictJson(engine: *Engine, value: c.JSValue, seen: *std.ArrayList(c.JSValue)) !void {
    if (c.JS_IsUndefined(value) or c.JS_IsFunction(engine.context, value) or c.JS_IsSymbol(value) or c.JS_IsBigInt(value)) return error.NonJsonDocumentValue;
    if (c.JS_IsNumber(value)) {
        var number: f64 = 0;
        if (c.JS_ToFloat64(engine.context, &number, value) < 0) return error.JavaScriptException;
        if (!std.math.isFinite(number)) return error.NonFiniteDocumentValue;
    }
    if (!c.JS_IsObject(value)) return;
    for (seen.items) |previous| if (c.JS_IsStrictEqual(engine.context, previous, value)) return error.CyclicDocumentValue;
    try seen.append(engine.gpa, value);
    defer _ = seen.pop();
    var properties: [*c]c.JSPropertyEnum = null;
    var count: u32 = 0;
    if (c.JS_GetOwnPropertyNames(engine.context, &properties, &count, value, c.JS_GPN_STRING_MASK | c.JS_GPN_ENUM_ONLY) < 0) return error.JavaScriptException;
    defer c.JS_FreePropertyEnum(engine.context, properties, count);
    for (0..count) |index| {
        const child = try engine.checked(c.JS_GetProperty(engine.context, value, properties[index].atom));
        defer engine.freeValue(child);
        try strictJson(engine, child, seen);
    }
}
pub fn snapshot(engine: *Engine, session: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const native = try durable.state(engine, session);
    if (native.closing) return error.SessionClosed;
    const definition_value = try sdk.get(engine, args[0], "definition");
    defer engine.freeValue(definition_value);
    var resolved = try address(engine, definition_value, args[1..]);
    defer resolved.value.deinit();
    const version_value = try sdk.get(engine, definition_value, "version");
    defer engine.freeValue(version_value);
    if ((try cache(engine, session)).get(resolved.value.value, try durable.number(engine, version_value))) |value| {
        try checkSemantics(engine, definition_value, value.record.value);
        return sdk.promise(engine, value.value);
    }
    const arguments = try sdk.array(engine);
    defer engine.freeValue(arguments);
    for (args) |value| try sdk.append(engine, arguments, c.JS_DupValue(engine.context, value));
    var data = [_]c.JSValue{ session, arguments };
    const callback = try engine.checked(c.JS_NewCFunctionData(engine.context, snapshotQueued, 0, 0, data.len, &data));
    defer engine.freeValue(callback);
    return durable.enqueue(engine, session, callback);
}
pub fn snapshotAsOf(engine: *Engine, session: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const arguments = try sdk.array(engine);
    defer engine.freeValue(arguments);
    for (args) |value| try sdk.append(engine, arguments, c.JS_DupValue(engine.context, value));
    var data = [_]c.JSValue{ session, arguments };
    const callback = try engine.checked(c.JS_NewCFunctionData(engine.context, snapshotQueued, 0, 1, data.len, &data));
    defer engine.freeValue(callback);
    return durable.enqueue(engine, session, callback);
}
fn snapshotQueued(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, historical: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    var args: std.ArrayList(c.JSValue) = .empty;
    defer {
        for (args.items) |value| engine.freeValue(value);
        args.deinit(engine.gpa);
    }
    const count = sdk.length(engine, data[1]) catch |err| return durable.reject(engine, err);
    args.ensureTotalCapacity(engine.gpa, count) catch |err| return durable.reject(engine, err);
    for (0..count) |index| {
        const value = engine.checked(c.JS_GetPropertyUint32(engine.context, data[1], @intCast(index))) catch |err| return durable.reject(engine, err);
        args.appendAssumeCapacity(value);
    }
    return (if (historical == 1) historicalDirect(engine, data[0], args.items) else snapshotDirect(engine, data[0], args.items)) catch |err| durable.reject(engine, err);
}
fn historicalDirect(engine: *Engine, session: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const native = try durable.state(engine, session);
    if (native.closing) return error.SessionClosed;
    const definition_value = try sdk.get(engine, args[0], "definition");
    defer engine.freeValue(definition_value);
    const history = try field(engine, definition_value, "history");
    defer engine.gpa.free(history);
    if (!std.mem.eql(u8, history, "rewindable")) return error.DocumentDoesNotRetainHistory;
    var resolved = try address(engine, definition_value, args[1..]);
    defer resolved.value.deinit();
    const at_index = resolved.next + 1;
    if (args.len <= at_index + 1) return error.DocumentHistoricalPointRequired;
    const conversation = try json.asInteger(try json.required(try json.required(resolved.value.value, "scope"), "conversationId"));
    var entry = (try native.session.?.storage.readEntry(engine.gpa, try durable.number(engine, args[at_index]), conversation)) orelse return error.DocumentHistoricalEntryMissing;
    defer entry.deinit();
    const source_conversation = try json.required(try json.required(entry.value, "entry"), "conversationId");
    try resolved.value.value.object.getPtr("scope").?.object.put(resolved.value.arena.allocator(), "conversationId", source_conversation);
    const point: backend.memory.Point = .{ .seq = try json.asInteger(try json.required(entry.value, "commitSeq")) };
    var model: backend.memory.Memory = .{ .gpa = engine.gpa, .state = try native.session.?.storage.snapshot(engine.gpa) };
    defer model.deinit();
    var record = (try backend.query.findDocument(engine.gpa, &model, resolved.value.value, point)) orelse return sdk.promise(engine, c.pi_js_undefined());
    defer record.deinit();
    var contents = (try native.session.?.storage.readDocument(engine.gpa, try json.asInteger(try json.required(record.value, "id")), point)).?;
    defer contents.deinit();
    var value = try materialize(engine, definition_value, record.value, contents.value);
    defer value.deinit();
    const result = try durable.jsValue(engine, value.value);
    defer engine.freeValue(result);
    return sdk.promise(engine, result);
}
fn snapshotDirect(engine: *Engine, session: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const native = try durable.state(engine, session);
    if (native.closing) return error.SessionClosed;
    const definition_value = try sdk.get(engine, args[0], "definition");
    defer engine.freeValue(definition_value);
    var resolved = try address(engine, definition_value, args[1..]);
    defer resolved.value.deinit();
    const values = try cache(engine, session);
    const version_value = try sdk.get(engine, definition_value, "version");
    defer engine.freeValue(version_value);
    const version = try durable.number(engine, version_value);
    if (values.get(resolved.value.value, version)) |value| {
        try checkSemantics(engine, definition_value, value.record.value);
        return sdk.promise(engine, value.value);
    }
    var model: backend.memory.Memory = .{ .gpa = engine.gpa, .state = try native.session.?.storage.snapshot(engine.gpa) };
    defer model.deinit();
    var found = (try backend.query.findDocument(engine.gpa, &model, resolved.value.value, .current)) orelse return sdk.promise(engine, c.pi_js_undefined());
    defer found.deinit();
    var contents = (try native.session.?.storage.readDocument(engine.gpa, try json.asInteger(try json.required(found.value, "id")), .current)).?;
    defer contents.deinit();
    var materialized = try materialize(engine, definition_value, found.value, contents.value);
    defer materialized.deinit();
    const value = try durable.jsValue(engine, materialized.value);
    defer engine.freeValue(value);
    try values.put(resolved.value.value, found.value, value, version);
    return sdk.promise(engine, value);
}
pub const Observation = struct { value: c.JSValue, record: json.Owned, version: u64, context: c.JSValue };
pub fn observe(engine: *Engine, session: c.JSValue, args: []const c.JSValue) !?Observation {
    return observeDirect(engine, session, args, true);
}
pub fn observeState(engine: *Engine, session: c.JSValue, args: []const c.JSValue) !?Observation {
    return observeDirect(engine, session, args, false);
}
fn observeDirect(engine: *Engine, session: c.JSValue, args: []const c.JSValue, guard_watch: bool) !?Observation {
    const definition_value = try sdk.get(engine, args[0], "definition");
    defer engine.freeValue(definition_value);
    var resolved = try address(engine, definition_value, args[1..]);
    defer resolved.value.deinit();
    const context = if (resolved.next + 1 < args.len) args[resolved.next + 1] else c.pi_js_undefined();
    const signal = try sdk.get(engine, context, "abortSignal");
    defer engine.freeValue(signal);
    if (guard_watch and !c.JS_IsUndefined(signal)) {
        const aborted = try sdk.get(engine, signal, "aborted");
        defer engine.freeValue(aborted);
        if (c.JS_ToBool(engine.context, aborted) > 0) {
            const failure = try @import("native_durable_context.zig").abortError(engine, signal);
            _ = try engine.checked(c.JS_Throw(engine.context, failure));
        }
    }
    const promise = try snapshotDirect(engine, session, args);
    defer engine.freeValue(promise);
    const value = try engine.awaitValue(promise);
    errdefer engine.freeValue(value);
    if (c.JS_IsUndefined(value)) {
        engine.freeValue(value);
        return null;
    }
    const version_value = try sdk.get(engine, definition_value, "version");
    defer engine.freeValue(version_value);
    const version = try durable.number(engine, version_value);
    const item = (try cache(engine, session)).get(resolved.value.value, version).?;
    var record = try json.Owned.empty(engine.gpa);
    errdefer record.deinit();
    record.value = try json.clone(record.arena.allocator(), item.record.value);
    return .{ .value = value, .record = record, .version = version, .context = c.JS_DupValue(engine.context, context) };
}
fn checkSemantics(engine: *Engine, definition_value: c.JSValue, record: json.Value) !void {
    const scope = try field(engine, definition_value, "scope");
    defer engine.gpa.free(scope);
    if (!std.mem.eql(u8, scope, try json.asString(try json.required(try json.required(record, "scope"), "kind")))) return error.DocumentDefinitionSemanticsMismatch;
    if (std.mem.eql(u8, scope, "conversation")) inline for (.{ "history", "fork" }) |name| {
        const text = try field(engine, definition_value, name);
        defer engine.gpa.free(text);
        if (!std.mem.eql(u8, text, try json.asString(try json.required(record, name)))) return error.DocumentDefinitionSemanticsMismatch;
    };
}
fn materialize(engine: *Engine, definition_value: c.JSValue, record: json.Value, stored: json.Value) !json.Owned {
    try checkSemantics(engine, definition_value, record);
    const requested_version = try sdk.get(engine, definition_value, "version");
    defer engine.freeValue(requested_version);
    const version = try durable.number(engine, requested_version);
    const stored_version = try json.asInteger(try json.required(stored, "version"));
    if (stored_version > version) return error.DocumentVersionTooNew;
    if (stored_version == version) {
        var result = try json.Owned.empty(engine.gpa);
        errdefer result.deinit();
        result.value = try json.clone(result.arena.allocator(), try json.required(stored, "value"));
        return result;
    }
    const migration = try sdk.get(engine, definition_value, "migrate");
    defer engine.freeValue(migration);
    if (!c.JS_IsFunction(engine.context, migration)) return error.DocumentMigrationRequired;
    const input = try durable.jsValue(engine, try json.required(stored, "value"));
    defer engine.freeValue(input);
    var args = [_]c.JSValue{ input, c.JS_NewInt64(engine.context, @intCast(stored_version)) };
    const result = try engine.checked(c.JS_Call(engine.context, migration, definition_value, args.len, &args));
    defer engine.freeValue(result);
    return durable.owned(engine, result);
}
fn emit(a: std.mem.Allocator, operations: *json.Value, verb: []const u8, path: []const json.Value, payload: ?json.Value) !void {
    var tuple: json.Value = .{ .array = .init(a) };
    try tuple.array.append(.{ .string = verb });
    if (!std.mem.eql(u8, verb, "r")) {
        var copied: json.Value = .{ .array = .init(a) };
        for (path) |segment| try copied.array.append(try json.clone(a, segment));
        try tuple.array.append(copied);
    }
    if (payload) |value| try tuple.array.append(try json.clone(a, value));
    try operations.array.append(tuple);
}
fn differences(a: std.mem.Allocator, gpa: std.mem.Allocator, before: json.Value, after: json.Value, path: *std.ArrayList(json.Value), operations: *json.Value) anyerror!void {
    if (json.equal(before, after)) return;
    if (before == .object and after == .object) {
        // Chord folds unsafe property segments into the containing object.
        for (before.object.keys()) |key| if (std.mem.eql(u8, key, "__proto__") or std.mem.eql(u8, key, "constructor") or std.mem.eql(u8, key, "prototype")) {
            const replacement = after.object.get(key);
            if (replacement == null or !json.equal(before.object.get(key).?, replacement.?)) return emit(a, operations, if (path.items.len == 0) "r" else "s", path.items, after);
        };
        for (after.object.keys()) |key| if (std.mem.eql(u8, key, "__proto__") or std.mem.eql(u8, key, "constructor") or std.mem.eql(u8, key, "prototype")) {
            const original = before.object.get(key);
            if (original == null or !json.equal(original.?, after.object.get(key).?)) return emit(a, operations, if (path.items.len == 0) "r" else "s", path.items, after);
        };
        for (before.object.keys()) |key| if (!after.object.contains(key)) {
            try path.append(gpa, .{ .string = key });
            defer _ = path.pop();
            try emit(a, operations, "d", path.items, null);
        };
        for (after.object.keys(), after.object.values()) |key, value| {
            try path.append(gpa, .{ .string = key });
            defer _ = path.pop();
            if (before.object.get(key)) |previous| try differences(a, gpa, previous, value, path, operations) else try emit(a, operations, "s", path.items, value);
        }
        return;
    }
    if (before == .array and after == .array) {
        const left = before.array.items;
        const right = after.array.items;
        if (left.len == right.len) {
            for (left, right, 0..) |previous, value, index| {
                try path.append(gpa, .{ .integer = @intCast(index) });
                defer _ = path.pop();
                try differences(a, gpa, previous, value, path, operations);
            }
            return;
        }
        var prefix: usize = 0;
        while (prefix < @min(left.len, right.len) and json.equal(left[prefix], right[prefix])) : (prefix += 1) {}
        var suffix: usize = 0;
        while (suffix < @min(left.len, right.len) - prefix and json.equal(left[left.len - suffix - 1], right[right.len - suffix - 1])) : (suffix += 1) {}
        var tuple: json.Value = .{ .array = .init(a) };
        try tuple.array.append(.{ .string = "p" });
        var copied: json.Value = .{ .array = .init(a) };
        for (path.items) |segment| try copied.array.append(try json.clone(a, segment));
        try tuple.array.append(copied);
        try tuple.array.append(.{ .integer = @intCast(prefix) });
        try tuple.array.append(.{ .integer = @intCast(left.len - prefix - suffix) });
        var inserted: json.Value = .{ .array = .init(a) };
        for (right[prefix .. right.len - suffix]) |value| try inserted.array.append(try json.clone(a, value));
        try tuple.array.append(inserted);
        try operations.array.append(tuple);
        return;
    }
    if (before == .string and after == .string and path.items.len > 0 and std.mem.startsWith(u8, after.string, before.string)) return emit(a, operations, "a", path.items, .{ .string = after.string[before.string.len..] });
    try emit(a, operations, if (path.items.len == 0) "r" else "s", path.items, after);
}

fn allocationExercise(gpa: std.mem.Allocator) !void {
    const engine = try Engine.init(gpa, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    const storage = try durable.memoryObject(engine);
    defer engine.freeValue(storage);
    const session = try durable.sessionObject(engine, storage);
    defer engine.freeValue(session);
    const input = try engine.eval("({kind:'gpa.doc',version:1,scope:'session',initial(){return{nested:{n:1},items:[]}},checkpointWhen(value,ops,info){return false}})", "document-user-definition-fixture", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(input);
    const token = try definition(engine, input);
    defer engine.freeValue(token);
    const Call = struct {
        engine: *Engine,
        session: c.JSValue,
        token: c.JSValue,
        transaction: ?c.JSValue = null,
        number: i64 = 2,
        fn apply(raw: ?*anyopaque, native: *@import("../durable/session.zig").Transaction, _: @import("../durable/types.zig").Context) !json.Value {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            const tx = try durable.transactionObject(self.engine, native, self.session);
            self.transaction = tx;
            const promise = try acquire(self.engine, tx, &.{self.token});
            defer self.engine.freeValue(promise);
            const value = try self.engine.awaitValue(promise);
            defer self.engine.freeValue(value);
            const drafts = (try durable.state(self.engine, tx)).documents.?;
            const nested = try sdk.get(self.engine, drafts.items.items[0].target, "nested");
            defer self.engine.freeValue(nested);
            const key = try sdk.text(self.engine, "n");
            defer self.engine.freeValue(key);
            var data = [_]c.JSValue{ tx, c.JS_NewInt64(self.engine.context, 0) };
            const mutated = try trapOwned(self.engine, &.{ nested, key, c.JS_NewInt64(self.engine.context, self.number) }, 1, &data);
            self.engine.freeValue(mutated);
            try drafts.finish();
            return .null;
        }
    };
    var call: Call = .{ .engine = engine, .session = session, .token = token };
    defer if (call.transaction) |tx| engine.freeValue(tx);
    var result = try (try durable.state(engine, session)).session.?.commit(Call.apply, &call, .{}, .{});
    defer result.deinit();
    try (try durable.state(engine, call.transaction.?)).documents.?.adopt(session);
    engine.freeValue(call.transaction.?);
    call.transaction = null;
    call.number = 3;
    var second = try (try durable.state(engine, session)).session.?.commit(Call.apply, &call, .{}, .{});
    defer second.deinit();
    try (try durable.state(engine, call.transaction.?)).documents.?.adopt(session);
}
test "native durable VM document addresses proxies native publication and cache admission release every GPA failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationExercise, .{});
}

//! Persistent Pi credential storage compatible with upstream `auth.json`.
//!
//! The file is a JSON object keyed by arbitrary provider IDs. Each provider has
//! one type-tagged credential (`api_key` or `oauth`). Reads use a shared
//! advisory lock and writes use an exclusive advisory lock so cooperating Pi
//! processes cannot interleave read/modify/write operations.
const std = @import("std");
const Io = std.Io;

pub const CredentialType = enum { api_key, oauth };

pub const ApiKeyCredential = struct {
    key: ?[]u8 = null,

    pub fn deinit(self: *ApiKeyCredential, gpa: std.mem.Allocator) void {
        if (self.key) |key| gpa.free(key);
        self.* = undefined;
    }
};

pub const OAuthCredential = struct {
    refresh: []u8,
    access: []u8,
    expires: i64,
    scope: ?[]u8 = null,
    account_id: ?[]u8 = null,
    enterprise_url: ?[]u8 = null,
    available_model_ids: [][]u8 = &.{},
    available_model_ids_present: bool = false,

    pub fn deinit(self: *OAuthCredential, gpa: std.mem.Allocator) void {
        gpa.free(self.refresh);
        gpa.free(self.access);
        if (self.scope) |scope| gpa.free(scope);
        if (self.account_id) |account_id| gpa.free(account_id);
        if (self.enterprise_url) |enterprise_url| gpa.free(enterprise_url);
        for (self.available_model_ids) |id| gpa.free(id);
        if (self.available_model_ids.len > 0) gpa.free(self.available_model_ids);
        self.* = undefined;
    }
};

pub const Credential = union(CredentialType) {
    api_key: ApiKeyCredential,
    oauth: OAuthCredential,

    /// Deep-copy credential material into `gpa`. This is used by transactional
    /// live reload so a process-local login can be restored if replacement
    /// provider construction fails after the old runtime has been detached.
    pub fn clone(self: *const Credential, gpa: std.mem.Allocator) !Credential {
        return switch (self.*) {
            .api_key => |cred| .{ .api_key = .{
                .key = if (cred.key) |key| try gpa.dupe(u8, key) else null,
            } },
            .oauth => |cred| blk: {
                const refresh = try gpa.dupe(u8, cred.refresh);
                errdefer gpa.free(refresh);
                const access = try gpa.dupe(u8, cred.access);
                errdefer gpa.free(access);
                const scope = if (cred.scope) |value| try gpa.dupe(u8, value) else null;
                errdefer if (scope) |value| gpa.free(value);
                const account_id = if (cred.account_id) |value| try gpa.dupe(u8, value) else null;
                errdefer if (account_id) |value| gpa.free(value);
                const enterprise_url = if (cred.enterprise_url) |value| try gpa.dupe(u8, value) else null;
                errdefer if (enterprise_url) |value| gpa.free(value);

                var available_model_ids: [][]u8 = &.{};
                if (cred.available_model_ids.len > 0) {
                    available_model_ids = try gpa.alloc([]u8, cred.available_model_ids.len);
                    var copied: usize = 0;
                    errdefer {
                        for (available_model_ids[0..copied]) |id| gpa.free(id);
                        gpa.free(available_model_ids);
                    }
                    for (cred.available_model_ids, 0..) |id, index| {
                        available_model_ids[index] = try gpa.dupe(u8, id);
                        copied += 1;
                    }
                }

                break :blk .{ .oauth = .{
                    .refresh = refresh,
                    .access = access,
                    .expires = cred.expires,
                    .scope = scope,
                    .account_id = account_id,
                    .enterprise_url = enterprise_url,
                    .available_model_ids = available_model_ids,
                    .available_model_ids_present = cred.available_model_ids_present,
                } };
            },
        };
    }

    pub fn deinit(self: *Credential, gpa: std.mem.Allocator) void {
        switch (self.*) {
            .api_key => |*cred| cred.deinit(gpa),
            .oauth => |*cred| cred.deinit(gpa),
        }
    }
};

/// Callback used by `modifyOAuthJson`. `current_json` is the complete current
/// OAuth credential (including extension-defined fields), or null when absent.
/// A returned owned JSON object replaces the credential; null leaves it unchanged.
pub const ModifyOAuthJsonFn = *const fn (
    ?*anyopaque,
    std.mem.Allocator,
    ?[]const u8,
) anyerror!?[]u8;

fn ensureOAuthCommitNotAborted(abort_flag: ?*const bool) !void {
    if (abort_flag) |flag| if (@atomicLoad(bool, flag, .acquire)) return error.Canceled;
}

pub const CredentialInfo = struct {
    provider_id: []u8,
    credential_type: CredentialType,

    pub fn deinit(self: *CredentialInfo, gpa: std.mem.Allocator) void {
        gpa.free(self.provider_id);
        self.* = undefined;
    }
};

pub const AuthStorage = struct {
    gpa: std.mem.Allocator,
    io: Io,
    path: []u8,

    pub fn init(gpa: std.mem.Allocator, io: Io, agent_dir: []const u8) !AuthStorage {
        return initPath(gpa, io, try std.fs.path.join(gpa, &.{ agent_dir, "auth.json" }));
    }

    pub fn initPath(gpa: std.mem.Allocator, io: Io, owned_path: []u8) AuthStorage {
        return .{ .gpa = gpa, .io = io, .path = owned_path };
    }

    pub fn deinit(self: *AuthStorage) void {
        self.gpa.free(self.path);
        self.* = undefined;
    }

    fn ensureParent(self: *const AuthStorage) !void {
        if (std.fs.path.dirname(self.path)) |parent| {
            try std.Io.Dir.cwd().createDirPath(self.io, parent);
        }
    }

    fn permissions0600() std.Io.File.Permissions {
        if (@hasDecl(std.Io.File.Permissions, "fromMode")) {
            return std.Io.File.Permissions.fromMode(0o600);
        }
        return .default_file;
    }

    fn openLocked(self: *const AuthStorage, lock: std.Io.File.Lock) !std.Io.File {
        try self.ensureParent();
        const file = try std.Io.Dir.cwd().createFile(self.io, self.path, .{
            .read = true,
            .truncate = false,
            .lock = lock,
            .permissions = permissions0600(),
        });
        // Existing auth files may predate this implementation. Tighten their
        // permissions as upstream Pi does; unsupported platforms simply keep
        // their native default representation.
        file.setPermissions(self.io, permissions0600()) catch {};
        return file;
    }

    fn readLockedAlloc(self: *const AuthStorage, file: std.Io.File) ![]u8 {
        const file_len = try file.length(self.io);
        if (file_len > 4 * 1024 * 1024) return error.AuthFileTooLarge;
        if (file_len == 0) return self.gpa.dupe(u8, "{}");
        const len: usize = @intCast(file_len);
        const data = try self.gpa.alloc(u8, len);
        errdefer self.gpa.free(data);
        const got = try file.readPositionalAll(self.io, data, 0);
        if (got != len) return error.UnexpectedEndOfFile;
        return data;
    }

    fn parseCredential(self: *const AuthStorage, value: std.json.Value) !?Credential {
        if (value != .object) return null;
        const type_value = value.object.get("type") orelse return null;
        if (type_value != .string) return null;

        if (std.mem.eql(u8, type_value.string, "api_key")) {
            var key: ?[]u8 = null;
            if (value.object.get("key")) |key_value| {
                if (key_value == .string) key = try self.gpa.dupe(u8, key_value.string);
            }
            return .{ .api_key = .{ .key = key } };
        }
        if (std.mem.eql(u8, type_value.string, "oauth")) {
            const refresh_value = value.object.get("refresh") orelse return null;
            const access_value = value.object.get("access") orelse return null;
            const expires_value = value.object.get("expires") orelse return null;
            if (refresh_value != .string or access_value != .string or expires_value != .integer) return null;
            const refresh = try self.gpa.dupe(u8, refresh_value.string);
            errdefer self.gpa.free(refresh);
            const access = try self.gpa.dupe(u8, access_value.string);
            errdefer self.gpa.free(access);
            var scope: ?[]u8 = null;
            if (value.object.get("scope")) |scope_value| {
                if (scope_value == .string) scope = try self.gpa.dupe(u8, scope_value.string);
            }
            errdefer if (scope) |scope_value| self.gpa.free(scope_value);
            var account_id: ?[]u8 = null;
            if (value.object.get("accountId")) |account_value| {
                if (account_value == .string and account_value.string.len > 0) account_id = try self.gpa.dupe(u8, account_value.string);
            }
            errdefer if (account_id) |account_value| self.gpa.free(account_value);
            var enterprise_url: ?[]u8 = null;
            if (value.object.get("enterpriseUrl")) |enterprise_value| {
                if (enterprise_value == .string and enterprise_value.string.len > 0) enterprise_url = try self.gpa.dupe(u8, enterprise_value.string);
            }
            errdefer if (enterprise_url) |enterprise_value| self.gpa.free(enterprise_value);
            var available: std.ArrayList([]u8) = .empty;
            var available_present = false;
            errdefer {
                for (available.items) |id| self.gpa.free(id);
                available.deinit(self.gpa);
            }
            if (value.object.get("availableModelIds")) |models_value| if (models_value == .array) {
                available_present = true;
                for (models_value.array.items) |item| {
                    if (item != .string or item.string.len == 0) continue;
                    try available.append(self.gpa, try self.gpa.dupe(u8, item.string));
                }
            };
            return .{ .oauth = .{
                .refresh = refresh,
                .access = access,
                .expires = expires_value.integer,
                .scope = scope,
                .account_id = account_id,
                .enterprise_url = enterprise_url,
                .available_model_ids = try available.toOwnedSlice(self.gpa),
                .available_model_ids_present = available_present,
            } };
        }
        return null;
    }

    pub fn read(self: *const AuthStorage, provider_id: []const u8) !?Credential {
        const file = try self.openLocked(.shared);
        defer file.close(self.io);
        const raw = try self.readLockedAlloc(file);
        defer self.gpa.free(raw);
        var parsed = std.json.parseFromSlice(std.json.Value, self.gpa, raw, .{}) catch return error.InvalidAuthJson;
        defer parsed.deinit();
        if (parsed.value != .object) return error.InvalidAuthJson;
        const value = parsed.value.object.get(provider_id) orelse return null;
        return self.parseCredential(value);
    }

    pub fn list(self: *const AuthStorage) ![]CredentialInfo {
        const file = try self.openLocked(.shared);
        defer file.close(self.io);
        const raw = try self.readLockedAlloc(file);
        defer self.gpa.free(raw);
        var parsed = std.json.parseFromSlice(std.json.Value, self.gpa, raw, .{}) catch return error.InvalidAuthJson;
        defer parsed.deinit();
        if (parsed.value != .object) return error.InvalidAuthJson;

        var result: std.ArrayList(CredentialInfo) = .empty;
        errdefer {
            for (result.items) |*item| item.deinit(self.gpa);
            result.deinit(self.gpa);
        }
        var it = parsed.value.object.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.* != .object) continue;
            const type_value = entry.value_ptr.object.get("type") orelse continue;
            if (type_value != .string) continue;
            const credential_type: CredentialType = if (std.mem.eql(u8, type_value.string, "api_key"))
                .api_key
            else if (std.mem.eql(u8, type_value.string, "oauth"))
                .oauth
            else
                continue;
            try result.append(self.gpa, .{
                .provider_id = try self.gpa.dupe(u8, entry.key_ptr.*),
                .credential_type = credential_type,
            });
        }
        return try result.toOwnedSlice(self.gpa);
    }

    fn parseRootForWrite(self: *const AuthStorage, raw: []const u8) !std.json.Parsed(std.json.Value) {
        var parsed = std.json.parseFromSlice(std.json.Value, self.gpa, if (raw.len == 0) "{}" else raw, .{}) catch return error.InvalidAuthJson;
        errdefer parsed.deinit();
        if (parsed.value != .object) return error.InvalidAuthJson;
        return parsed;
    }

    fn writeParsed(self: *const AuthStorage, file: std.Io.File, root: std.json.Value) !void {
        var out: std.Io.Writer.Allocating = .init(self.gpa);
        defer out.deinit();
        try std.json.Stringify.value(root, .{ .whitespace = .indent_2 }, &out.writer);
        try out.writer.writeByte('\n');
        try file.setLength(self.io, 0);
        try file.writePositionalAll(self.io, out.written(), 0);
    }

    pub fn setApiKey(self: *const AuthStorage, provider_id: []const u8, key: ?[]const u8) !void {
        const file = try self.openLocked(.exclusive);
        defer file.close(self.io);
        const raw = try self.readLockedAlloc(file);
        defer self.gpa.free(raw);
        var parsed = try self.parseRootForWrite(raw);
        defer parsed.deinit();
        const a = parsed.arena.allocator();

        var credential_object: std.json.ObjectMap = .empty;
        try credential_object.put(a, "type", .{ .string = "api_key" });
        if (key) |api_key| {
            try credential_object.put(a, "key", .{ .string = try a.dupe(u8, api_key) });
        }
        try parsed.value.object.put(a, try a.dupe(u8, provider_id), .{ .object = credential_object });
        try self.writeParsed(file, parsed.value);
    }

    fn validateOAuthValue(value: std.json.Value) !void {
        if (value != .object) return error.InvalidOAuthCredential;
        if (value.object.get("type")) |type_value| {
            if (type_value != .string or !std.mem.eql(u8, type_value.string, "oauth")) return error.InvalidOAuthCredential;
        }
        const refresh = value.object.get("refresh") orelse return error.InvalidOAuthCredential;
        const access = value.object.get("access") orelse return error.InvalidOAuthCredential;
        const expires = value.object.get("expires") orelse return error.InvalidOAuthCredential;
        if (refresh != .string or access != .string or expires != .integer) return error.InvalidOAuthCredential;
    }

    fn parseOAuthIntoArena(arena: std.mem.Allocator, raw: []const u8) !std.json.Value {
        var value = std.json.parseFromSliceLeaky(std.json.Value, arena, raw, .{}) catch return error.InvalidOAuthCredential;
        try validateOAuthValue(value);
        try value.object.put(arena, "type", .{ .string = "oauth" });
        return value;
    }

    /// Return the complete persisted credential object without projecting away
    /// provider-defined fields. This is used by dynamic model refresh contexts;
    /// the caller owns the returned JSON slice.
    pub fn readCredentialJson(self: *const AuthStorage, provider_id: []const u8) !?[]u8 {
        const file = try self.openLocked(.shared);
        defer file.close(self.io);
        const raw = try self.readLockedAlloc(file);
        defer self.gpa.free(raw);
        var parsed = std.json.parseFromSlice(std.json.Value, self.gpa, raw, .{}) catch return error.InvalidAuthJson;
        defer parsed.deinit();
        if (parsed.value != .object) return error.InvalidAuthJson;
        const value = parsed.value.object.get(provider_id) orelse return null;
        if (value != .object) return error.InvalidCredential;
        const type_value = value.object.get("type") orelse return error.InvalidCredential;
        if (type_value != .string or
            (!std.mem.eql(u8, type_value.string, "api_key") and !std.mem.eql(u8, type_value.string, "oauth")))
            return error.InvalidCredential;
        if (std.mem.eql(u8, type_value.string, "oauth")) try validateOAuthValue(value);
        if (std.mem.eql(u8, type_value.string, "api_key")) {
            if (value.object.get("key")) |key| if (key != .string and key != .null) return error.InvalidCredential;
        }
        var out: std.Io.Writer.Allocating = .init(self.gpa);
        errdefer out.deinit();
        try std.json.Stringify.value(value, .{}, &out.writer);
        return @as(?[]u8, try out.toOwnedSlice());
    }

    /// Return the complete persisted OAuth object without dropping
    /// extension-specific credential fields. The caller owns the JSON slice.
    pub fn readOAuthJson(self: *const AuthStorage, provider_id: []const u8) !?[]u8 {
        const file = try self.openLocked(.shared);
        defer file.close(self.io);
        const raw = try self.readLockedAlloc(file);
        defer self.gpa.free(raw);
        var parsed = std.json.parseFromSlice(std.json.Value, self.gpa, raw, .{}) catch return error.InvalidAuthJson;
        defer parsed.deinit();
        if (parsed.value != .object) return error.InvalidAuthJson;
        const value = parsed.value.object.get(provider_id) orelse return null;
        try validateOAuthValue(value);
        const type_value = value.object.get("type") orelse return error.InvalidOAuthCredential;
        if (type_value != .string or !std.mem.eql(u8, type_value.string, "oauth")) return error.InvalidOAuthCredential;
        var out: std.Io.Writer.Allocating = .init(self.gpa);
        errdefer out.deinit();
        try std.json.Stringify.value(value, .{}, &out.writer);
        return @as(?[]u8, try out.toOwnedSlice());
    }

    /// Persist a complete extension OAuth credential atomically. Unknown
    /// fields are retained and `type` is normalized to the upstream value.
    pub fn setOAuthJson(self: *const AuthStorage, provider_id: []const u8, credential_json: []const u8) !void {
        return self.setOAuthJsonAbortable(provider_id, credential_json, null);
    }

    /// Abort-aware variant used by extension OAuth login. Cancellation is
    /// checked once before acquiring the credential lock and again immediately
    /// before the write, mirroring upstream CredentialStore.modify semantics.
    pub fn setOAuthJsonAbortable(
        self: *const AuthStorage,
        provider_id: []const u8,
        credential_json: []const u8,
        abort_flag: ?*const bool,
    ) !void {
        try ensureOAuthCommitNotAborted(abort_flag);
        const file = try self.openLocked(.exclusive);
        defer file.close(self.io);
        const raw = try self.readLockedAlloc(file);
        defer self.gpa.free(raw);
        var parsed = try self.parseRootForWrite(raw);
        defer parsed.deinit();
        const a = parsed.arena.allocator();
        const credential_value = try parseOAuthIntoArena(a, credential_json);
        try parsed.value.object.put(a, try a.dupe(u8, provider_id), credential_value);
        try ensureOAuthCommitNotAborted(abort_flag);
        try self.writeParsed(file, parsed.value);
    }

    /// Run a serialized read/modify/write transaction while retaining the full
    /// OAuth object. The callback executes under the exclusive auth-file lock,
    /// matching upstream CredentialStore.modify semantics and preventing two
    /// refreshers from overwriting each other. The returned slice is the final
    /// credential state and is owned by the caller.
    pub fn modifyOAuthJson(
        self: *const AuthStorage,
        provider_id: []const u8,
        context: ?*anyopaque,
        callback: ModifyOAuthJsonFn,
    ) !?[]u8 {
        return self.modifyOAuthJsonAbortable(provider_id, context, callback, null);
    }

    /// Abort-aware serialized credential transaction. A refresh callback may
    /// finish after its signal is cancelled; the second guard prevents that
    /// late result from replacing the last valid credential.
    pub fn modifyOAuthJsonAbortable(
        self: *const AuthStorage,
        provider_id: []const u8,
        context: ?*anyopaque,
        callback: ModifyOAuthJsonFn,
        abort_flag: ?*const bool,
    ) !?[]u8 {
        try ensureOAuthCommitNotAborted(abort_flag);
        const file = try self.openLocked(.exclusive);
        defer file.close(self.io);
        const raw = try self.readLockedAlloc(file);
        defer self.gpa.free(raw);
        var parsed = try self.parseRootForWrite(raw);
        defer parsed.deinit();

        var current_json: ?[]u8 = null;
        if (parsed.value.object.get(provider_id)) |current| {
            try validateOAuthValue(current);
            const type_value = current.object.get("type") orelse return error.InvalidOAuthCredential;
            if (type_value != .string or !std.mem.eql(u8, type_value.string, "oauth")) return error.InvalidOAuthCredential;
            var encoded: std.Io.Writer.Allocating = .init(self.gpa);
            errdefer encoded.deinit();
            try std.json.Stringify.value(current, .{}, &encoded.writer);
            current_json = try encoded.toOwnedSlice();
        }
        defer if (current_json) |value| self.gpa.free(value);

        const replacement_json = try callback(context, self.gpa, current_json);
        defer if (replacement_json) |value| self.gpa.free(value);
        try ensureOAuthCommitNotAborted(abort_flag);
        if (replacement_json) |replacement| {
            const a = parsed.arena.allocator();
            const credential_value = try parseOAuthIntoArena(a, replacement);
            try parsed.value.object.put(a, try a.dupe(u8, provider_id), credential_value);
            try self.writeParsed(file, parsed.value);

            var encoded: std.Io.Writer.Allocating = .init(self.gpa);
            errdefer encoded.deinit();
            try std.json.Stringify.value(credential_value, .{}, &encoded.writer);
            return @as(?[]u8, try encoded.toOwnedSlice());
        }
        if (current_json) |current| return @as(?[]u8, try self.gpa.dupe(u8, current));
        return null;
    }

    pub fn setOAuth(self: *const AuthStorage, provider_id: []const u8, credential: OAuthCredential) !void {
        const file = try self.openLocked(.exclusive);
        defer file.close(self.io);
        const raw = try self.readLockedAlloc(file);
        defer self.gpa.free(raw);
        var parsed = try self.parseRootForWrite(raw);
        defer parsed.deinit();
        const a = parsed.arena.allocator();

        var credential_object: std.json.ObjectMap = .empty;
        try credential_object.put(a, "type", .{ .string = "oauth" });
        try credential_object.put(a, "refresh", .{ .string = try a.dupe(u8, credential.refresh) });
        try credential_object.put(a, "access", .{ .string = try a.dupe(u8, credential.access) });
        try credential_object.put(a, "expires", .{ .integer = credential.expires });
        if (credential.scope) |scope| try credential_object.put(a, "scope", .{ .string = try a.dupe(u8, scope) });
        if (credential.account_id) |account_id| try credential_object.put(a, "accountId", .{ .string = try a.dupe(u8, account_id) });
        if (credential.enterprise_url) |enterprise_url| try credential_object.put(a, "enterpriseUrl", .{ .string = try a.dupe(u8, enterprise_url) });
        if (credential.available_model_ids_present or credential.available_model_ids.len > 0) {
            var array = std.json.Array.init(a);
            for (credential.available_model_ids) |model_id| try array.append(.{ .string = try a.dupe(u8, model_id) });
            try credential_object.put(a, "availableModelIds", .{ .array = array });
        }
        try parsed.value.object.put(a, try a.dupe(u8, provider_id), .{ .object = credential_object });
        try self.writeParsed(file, parsed.value);
    }

    pub fn delete(self: *const AuthStorage, provider_id: []const u8) !void {
        const file = try self.openLocked(.exclusive);
        defer file.close(self.io);
        const raw = try self.readLockedAlloc(file);
        defer self.gpa.free(raw);
        var parsed = try self.parseRootForWrite(raw);
        defer parsed.deinit();
        _ = parsed.value.object.orderedRemove(provider_id);
        try self.writeParsed(file, parsed.value);
    }
};

pub const RuntimeCredentials = struct {
    gpa: std.mem.Allocator,
    store: *AuthStorage,
    overrides: std.StringHashMap([]u8),

    pub fn init(gpa: std.mem.Allocator, store: *AuthStorage) RuntimeCredentials {
        return .{ .gpa = gpa, .store = store, .overrides = std.StringHashMap([]u8).init(gpa) };
    }

    pub fn deinit(self: *RuntimeCredentials) void {
        var it = self.overrides.iterator();
        while (it.next()) |entry| {
            self.gpa.free(entry.key_ptr.*);
            self.gpa.free(entry.value_ptr.*);
        }
        self.overrides.deinit();
        self.* = undefined;
    }

    pub fn setRuntimeApiKey(self: *RuntimeCredentials, provider_id: []const u8, api_key: []const u8) !void {
        if (self.overrides.getPtr(provider_id)) |existing| {
            self.gpa.free(existing.*);
            existing.* = try self.gpa.dupe(u8, api_key);
            return;
        }
        try self.overrides.put(try self.gpa.dupe(u8, provider_id), try self.gpa.dupe(u8, api_key));
    }

    pub fn removeRuntimeApiKey(self: *RuntimeCredentials, provider_id: []const u8) bool {
        if (self.overrides.fetchRemove(provider_id)) |removed| {
            self.gpa.free(removed.key);
            self.gpa.free(removed.value);
            return true;
        }
        return false;
    }

    pub fn hasRuntimeApiKey(self: *const RuntimeCredentials, provider_id: []const u8) bool {
        return self.overrides.contains(provider_id);
    }

    pub fn read(self: *const RuntimeCredentials, provider_id: []const u8) !?Credential {
        if (self.overrides.get(provider_id)) |value| {
            return .{ .api_key = .{ .key = try self.gpa.dupe(u8, value) } };
        }
        return self.store.read(provider_id);
    }

    pub fn delete(self: *RuntimeCredentials, provider_id: []const u8) !void {
        try self.store.delete(provider_id);
        _ = self.removeRuntimeApiKey(provider_id);
    }
};

fn tempAuthPath(gpa: std.mem.Allocator, tmp: *std.testing.TmpDir) ![]u8 {
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(std.testing.io, &path_buf);
    return std.fs.path.join(gpa, &.{ path_buf[0..n], "auth.json" });
}

test "auth storage reads writes lists and deletes arbitrary provider ids" {
    const gpa = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var store = AuthStorage.initPath(gpa, std.testing.io, try tempAuthPath(gpa, &tmp));
    defer store.deinit();

    try store.setApiKey("my-company/proxy", "sk-secret");
    var credential = (try store.read("my-company/proxy")).?;
    defer credential.deinit(gpa);
    try std.testing.expectEqualStrings("sk-secret", credential.api_key.key.?);

    const entries = try store.list();
    defer {
        for (entries) |*entry| entry.deinit(gpa);
        gpa.free(entries);
    }
    try std.testing.expectEqual(@as(usize, 1), entries.len);
    try std.testing.expectEqualStrings("my-company/proxy", entries[0].provider_id);
    try std.testing.expectEqual(CredentialType.api_key, entries[0].credential_type);

    try store.delete("my-company/proxy");
    try std.testing.expect((try store.read("my-company/proxy")) == null);
}

test "auth storage OAuth is compatible with upstream field names" {
    const gpa = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var store = AuthStorage.initPath(gpa, std.testing.io, try tempAuthPath(gpa, &tmp));
    defer store.deinit();

    const oauth = OAuthCredential{
        .refresh = @constCast("refresh-1"),
        .access = @constCast("access-1"),
        .expires = 1_800_000_000_000,
    };
    try store.setOAuth("anthropic", oauth);
    var credential = (try store.read("anthropic")).?;
    defer credential.deinit(gpa);
    try std.testing.expectEqualStrings("refresh-1", credential.oauth.refresh);
    try std.testing.expectEqualStrings("access-1", credential.oauth.access);
    try std.testing.expectEqual(@as(i64, 1_800_000_000_000), credential.oauth.expires);
}

test "auth storage preserves unknown credential fields while updating another provider" {
    const gpa = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try tempAuthPath(gpa, &tmp);
    var store = AuthStorage.initPath(gpa, std.testing.io, path);
    defer store.deinit();

    try std.Io.Dir.cwd().writeFile(std.testing.io, .{
        .sub_path = store.path,
        .data =
        \\{
        \\  "radius": {"type":"oauth","refresh":"r","access":"a","expires":99,"accountId":"keep-me"}
        \\}
        ,
    });
    try store.setApiKey("custom-provider", "custom-key");
    const raw = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, store.path, gpa, .limited(64 * 1024));
    defer gpa.free(raw);
    try std.testing.expect(std.mem.indexOf(u8, raw, "accountId") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw, "keep-me") != null);
}

test "extension OAuth JSON transactions preserve arbitrary fields and rollback invalid replacements" {
    const gpa = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var store = AuthStorage.initPath(gpa, std.testing.io, try tempAuthPath(gpa, &tmp));
    defer store.deinit();

    try store.setOAuthJson("extension", "{\"refresh\":\"r1\",\"access\":\"a1\",\"expires\":10,\"tenant\":{\"id\":7},\"flags\":[\"x\",\"y\"]}");
    const initial = (try store.readOAuthJson("extension")).?;
    defer gpa.free(initial);
    try std.testing.expect(std.mem.indexOf(u8, initial, "\"type\":\"oauth\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, initial, "\"tenant\":{\"id\":7}") != null);

    const Modifier = struct {
        calls: usize = 0,

        fn update(raw: ?*anyopaque, allocator: std.mem.Allocator, current_json: ?[]const u8) anyerror!?[]u8 {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.calls += 1;
            const current = current_json orelse return error.MissingCurrentOAuthCredential;
            var parsed = try std.json.parseFromSlice(std.json.Value, allocator, current, .{});
            defer parsed.deinit();
            try std.testing.expect(parsed.value == .object);
            try std.testing.expect(parsed.value.object.get("tenant") != null);
            try parsed.value.object.put(allocator, "access", .{ .string = "a2" });
            try parsed.value.object.put(allocator, "expires", .{ .integer = 999 });
            var out: std.Io.Writer.Allocating = .init(allocator);
            errdefer out.deinit();
            try std.json.Stringify.value(parsed.value, .{}, &out.writer);
            return @as(?[]u8, try out.toOwnedSlice());
        }

        fn keep(_: ?*anyopaque, _: std.mem.Allocator, current_json: ?[]const u8) anyerror!?[]u8 {
            try std.testing.expect(current_json != null);
            return null;
        }

        fn invalid(_: ?*anyopaque, allocator: std.mem.Allocator, _: ?[]const u8) anyerror!?[]u8 {
            return @as(?[]u8, try allocator.dupe(u8, "{\"refresh\":\"missing-required-fields\"}"));
        }
    };

    var modifier = Modifier{};
    const updated = (try store.modifyOAuthJson("extension", &modifier, Modifier.update)).?;
    defer gpa.free(updated);
    try std.testing.expectEqual(@as(usize, 1), modifier.calls);
    try std.testing.expect(std.mem.indexOf(u8, updated, "\"access\":\"a2\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, updated, "\"tenant\":{\"id\":7}") != null);
    const kept = (try store.modifyOAuthJson("extension", null, Modifier.keep)).?;
    defer gpa.free(kept);
    try std.testing.expectEqualStrings(updated, kept);

    try std.testing.expectError(error.InvalidOAuthCredential, store.modifyOAuthJson("extension", null, Modifier.invalid));
    const after_invalid = (try store.readOAuthJson("extension")).?;
    defer gpa.free(after_invalid);
    try std.testing.expectEqualStrings(updated, after_invalid);
}

test "extension OAuth abort-aware transactions reject late replacements without changing storage" {
    const gpa = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var store = AuthStorage.initPath(gpa, std.testing.io, try tempAuthPath(gpa, &tmp));
    defer store.deinit();

    const initial_json = "{\"refresh\":\"stable-refresh\",\"access\":\"stable-access\",\"expires\":100,\"custom\":{\"keep\":true}}";
    try store.setOAuthJson("extension-abort", initial_json);

    const LateModifier = struct {
        abort_flag: *bool,

        fn replace(raw: ?*anyopaque, allocator: std.mem.Allocator, current_json: ?[]const u8) anyerror!?[]u8 {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            try std.testing.expect(current_json != null);
            @atomicStore(bool, self.abort_flag, true, .release);
            return @as(?[]u8, try allocator.dupe(u8, "{\"refresh\":\"late-refresh\",\"access\":\"late-access\",\"expires\":999}"));
        }
    };

    var aborted = false;
    var modifier = LateModifier{ .abort_flag = &aborted };
    try std.testing.expectError(
        error.Canceled,
        store.modifyOAuthJsonAbortable("extension-abort", &modifier, LateModifier.replace, &aborted),
    );
    const after_late_refresh = (try store.readOAuthJson("extension-abort")).?;
    defer gpa.free(after_late_refresh);
    try std.testing.expect(std.mem.indexOf(u8, after_late_refresh, "\"access\":\"stable-access\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, after_late_refresh, "\"keep\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, after_late_refresh, "late-access") == null);

    try std.testing.expectError(
        error.Canceled,
        store.setOAuthJsonAbortable(
            "extension-abort",
            "{\"refresh\":\"blocked-refresh\",\"access\":\"blocked-access\",\"expires\":1000}",
            &aborted,
        ),
    );
    const after_blocked_login = (try store.readOAuthJson("extension-abort")).?;
    defer gpa.free(after_blocked_login);
    try std.testing.expectEqualStrings(after_late_refresh, after_blocked_login);
}

test "runtime credentials override persistent values without writing them" {
    const gpa = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var store = AuthStorage.initPath(gpa, std.testing.io, try tempAuthPath(gpa, &tmp));
    defer store.deinit();
    try store.setApiKey("openai", "persistent");

    var runtime = RuntimeCredentials.init(gpa, &store);
    defer runtime.deinit();
    try runtime.setRuntimeApiKey("openai", "runtime");
    var over = (try runtime.read("openai")).?;
    defer over.deinit(gpa);
    try std.testing.expectEqualStrings("runtime", over.api_key.key.?);

    _ = runtime.removeRuntimeApiKey("openai");
    var persisted = (try runtime.read("openai")).?;
    defer persisted.deinit(gpa);
    try std.testing.expectEqualStrings("persistent", persisted.api_key.key.?);
}

test "auth storage Codex OAuth preserves accountId" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    var store = try AuthStorage.init(gpa, io, path_buf[0..n]);
    defer store.deinit();
    try store.setOAuth("openai-codex", .{
        .refresh = @constCast("refresh"),
        .access = @constCast("access"),
        .expires = 1234,
        .account_id = @constCast("acct-42"),
    });
    var cred = (try store.read("openai-codex")).?;
    defer cred.deinit(gpa);
    try std.testing.expectEqualStrings("acct-42", cred.oauth.account_id.?);
}

test "auth storage GitHub Copilot preserves enterprise and available models" {
    const gpa = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try tempAuthPath(gpa, &tmp);
    var store = AuthStorage.initPath(gpa, std.testing.io, path);
    defer store.deinit();
    var ids = [_][]u8{ @constCast("gpt-5"), @constCast("claude-sonnet-4") };
    try store.setOAuth("github-copilot", .{
        .refresh = @constCast("gh-access"),
        .access = @constCast("copilot-access"),
        .expires = 1234,
        .enterprise_url = @constCast("company.ghe.com"),
        .available_model_ids = &ids,
        .available_model_ids_present = true,
    });
    var cred = (try store.read("github-copilot")).?;
    defer cred.deinit(gpa);
    try std.testing.expectEqualStrings("company.ghe.com", cred.oauth.enterprise_url.?);
    try std.testing.expect(cred.oauth.available_model_ids_present);
    try std.testing.expectEqual(@as(usize, 2), cred.oauth.available_model_ids.len);
    try std.testing.expectEqualStrings("claude-sonnet-4", cred.oauth.available_model_ids[1]);
}

test "credential clone owns complete OAuth state" {
    const gpa = std.testing.allocator;
    var ids = [_][]u8{ @constCast("model-a"), @constCast("model-b") };
    var source: Credential = .{ .oauth = .{
        .refresh = @constCast("refresh-177"),
        .access = @constCast("access-177"),
        .expires = 177,
        .scope = @constCast("scope-177"),
        .account_id = @constCast("account-177"),
        .enterprise_url = @constCast("enterprise-177.example"),
        .available_model_ids = &ids,
        .available_model_ids_present = true,
    } };
    var cloned = try source.clone(gpa);
    defer cloned.deinit(gpa);

    try std.testing.expectEqualStrings("refresh-177", cloned.oauth.refresh);
    try std.testing.expectEqualStrings("access-177", cloned.oauth.access);
    try std.testing.expectEqual(@as(i64, 177), cloned.oauth.expires);
    try std.testing.expectEqualStrings("scope-177", cloned.oauth.scope.?);
    try std.testing.expectEqualStrings("account-177", cloned.oauth.account_id.?);
    try std.testing.expectEqualStrings("enterprise-177.example", cloned.oauth.enterprise_url.?);
    try std.testing.expect(cloned.oauth.available_model_ids_present);
    try std.testing.expectEqual(@as(usize, 2), cloned.oauth.available_model_ids.len);
    try std.testing.expectEqualStrings("model-b", cloned.oauth.available_model_ids[1]);
    try std.testing.expect(@intFromPtr(cloned.oauth.refresh.ptr) != @intFromPtr(source.oauth.refresh.ptr));
    try std.testing.expect(@intFromPtr(cloned.oauth.available_model_ids[0].ptr) != @intFromPtr(source.oauth.available_model_ids[0].ptr));
}

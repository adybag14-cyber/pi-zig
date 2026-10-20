//! Selected Node v24.13 package JSON parser controls over the actual simdjson
//! ondemand implementation and real charged native allocation owner.
//! These are native parser/ownership controls. Filesystem/cache/JS binding,
//! original Node reference execution and full loader qualification are separate.
const std = @import("std");
const c = @cImport({
    @cUndef("_FORTIFY_SOURCE");
    @cDefine("_FORTIFY_SOURCE", "0");
    @cInclude("engine_abi.h");
    @cInclude("native_node_package_json_parser.h");
});
const memory_limit: usize = 64 * 1024 * 1024;
const Config = struct {
    value: ?*c.PiNodePackageJsonConfig,
    fn deinit(self: *Config) void {
        const value = self.value;
        self.value = null;
        c.pi_node_package_json_config_destroy(value);
    }
    fn views(self: *const Config) c.PiNodePackageJsonViews {
        var result: c.PiNodePackageJsonViews = undefined;
        c.pi_node_package_json_config_views(self.value.?, &result);
        return result;
    }
};
const Fixture = struct {
    runtime: ?*c.JSRuntime = null,
    memory: ?*anyopaque = null,
    parser: ?*c.PiNodePackageJsonParser = null,
    before_parser: usize = 0,
    fn init(self: *Fixture) !void {
        self.* = .{};
        self.runtime = c.pi_js_new_runtime(memory_limit, &self.memory) orelse
            return error.OutOfMemory;
        errdefer self.deinit();
        self.before_parser = self.used();
        self.parser = c.pi_node_package_json_parser_create(self.memory) orelse
            return error.OutOfMemory;
    }
    fn used(self: *const Fixture) usize {
        return c.pi_js_native_memory_used(self.memory);
    }
    fn dropParser(self: *Fixture) void {
        const parser = self.parser;
        self.parser = null;
        c.pi_node_package_json_parser_destroy(parser);
    }
    fn closeRuntime(self: *Fixture) void {
        if (self.runtime) |runtime| {
            self.runtime = null;
            c.JS_FreeRuntime(runtime);
        }
        if (self.memory) |memory| {
            self.memory = null;
            c.pi_js_release_memory_owner(memory);
        }
    }
    fn deinit(self: *Fixture) void {
        self.dropParser();
        self.closeRuntime();
    }
    fn parse(self: *Fixture, input: []const u8) !Config {
        var result: ?*c.PiNodePackageJsonConfig = null;
        const status = c.pi_node_package_json_parse(self.parser.?, input.ptr, input.len, &result);
        errdefer c.pi_node_package_json_config_destroy(result);
        try std.testing.expectEqual(@as(c_int, c.PI_NODE_PACKAGE_JSON_OK), status);
        try std.testing.expect(result != null);
        return .{ .value = result };
    }
    fn fails(self: *Fixture, input: []const u8, expected: c_int) !void {
        var result: ?*c.PiNodePackageJsonConfig = null;
        const status = c.pi_node_package_json_parse(self.parser.?, input.ptr, input.len, &result);
        defer c.pi_node_package_json_config_destroy(result);
        try std.testing.expectEqual(expected, status);
        try std.testing.expect(result == null);
    }
};
const Budget = struct {
    owner: ?*anyopaque,
    bytes: usize,
    fn leave(f: *Fixture, headroom: usize) !Budget {
        const available = memory_limit - f.used();
        try std.testing.expect(headroom <= available);
        const bytes = available - headroom;
        try std.testing.expectEqual(@as(c_int, 1),
            c.pi_js_native_memory_reserve(f.memory, bytes));
        return .{ .owner = f.memory, .bytes = bytes };
    }
    fn release(self: *Budget) void {
        const bytes = self.bytes;
        self.bytes = 0;
        if (bytes != 0) c.pi_js_native_memory_release(self.owner, bytes);
    }
};
fn spanBytes(value: c.PiNodePackageJsonSpan) []const u8 {
    if (value.length == 0) return "";
    return value.data[0..value.length];
}
fn expectSpan(expected: []const u8, actual: c.PiNodePackageJsonSpan) !void {
    try std.testing.expectEqual(@as(c_int, 1), actual.present);
    try std.testing.expect(actual.data != null);
    try std.testing.expectEqualStrings(expected, spanBytes(actual));
}
fn expectAbsent(actual: c.PiNodePackageJsonSpan) !void {
    try std.testing.expectEqual(@as(c_int, 0), actual.present);
    try std.testing.expect(actual.data == null);
    try std.testing.expectEqual(@as(usize, 0), actual.length);
}
fn expectRaw(input: []const u8, appended: usize, actual: c.PiNodePackageJsonSpan) !void {
    try std.testing.expectEqual(@as(c_int, 1), actual.present);
    const bytes = spanBytes(actual);
    try std.testing.expectEqual(input.len + appended, bytes.len);
    try std.testing.expectEqualStrings(input, bytes[0..input.len]);
    for (bytes[input.len..]) |byte| try std.testing.expectEqual(@as(u8, ' '), byte);
}
fn longField(name: []const u8, length: usize, byte: u8) ![]u8 {
    const payload = try std.testing.allocator.alloc(u8, length);
    defer std.testing.allocator.free(payload);
    @memset(payload, byte);
    return std.fmt.allocPrint(std.testing.allocator, "{{\"{s}\":\"{s}\"}}", .{ name, payload });
}

test "native package JSON parser absent fields preserve none and exact raw padding" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var config = try f.parse("{}"); defer config.deinit();
    const values = config.views();
    try expectSpan("none", values.type);
    inline for (.{ "name", "main", "imports", "exports", "scripts" }) |name|
        try expectAbsent(@field(values, name));
    try expectRaw("{}", 64, values.raw_json);
}
test "native package JSON parser selects actual strings and raw object array fields" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const input = "{\"name\":\"pkg\",\"main\":\"entry.js\",\"type\":\"module\",\"imports\":{ \"#x\" : \"./x.js\" },\"exports\":[ \"./a.js\", \"./b.js\" ],\"scripts\":{\"build\":\"go\"}}";
    var config = try f.parse(input); defer config.deinit();
    const values = config.views();
    try expectSpan("pkg", values.name);
    try expectSpan("entry.js", values.main);
    try expectSpan("module", values.type);
    try expectSpan("{ \"#x\" : \"./x.js\" }", values.imports);
    try expectSpan("[ \"./a.js\", \"./b.js\" ]", values.exports);
    try expectSpan("{\"build\":\"go\"}", values.scripts);
}
test "native package JSON parser compares raw keys and retains last recognized duplicates" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var config = try f.parse("{\"name\":\"first\",\"na\\u006de\":\"escaped\",\"name\":\"last\",\"main\":\"a\",\"main\":\"b\",\"t\\u0079pe\":\"module\"}");
    defer config.deinit();
    const values = config.views();
    try expectSpan("last", values.name);
    try expectSpan("b", values.main);
    try expectSpan("none", values.type);
}
test "native package JSON parser actual name and type conversion errors remain invalid" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const invalid = [_][]const u8{
        "{\"name\":1}", "{\"name\":null}", "{\"name\":{}}",
        "{\"type\":false}", "{\"type\":[]}", "{\"name\":\"\\uD800\"}",
    };
    for (invalid) |input| {
        try f.fails(input, c.PI_NODE_PACKAGE_JSON_INVALID);
        var next = try f.parse("{\"name\":\"recovered\"}");
        defer next.deinit();
        try expectSpan("recovered", next.views().name);
    }
}
test "native package JSON parser main ignores nonstring values without erasing the earlier value" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var config = try f.parse("{\"main\":\"keep\",\"main\":null,\"main\":1,\"main\":{},\"main\":[],\"main\":false}");
    defer config.deinit();
    try expectSpan("keep", config.views().main);
    var absent = try f.parse("{\"main\":17}"); defer absent.deinit();
    try expectAbsent(absent.views().main);
}
test "native package JSON parser imports exports ignore scalars and preserve empty strings" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var config = try f.parse("{\"imports\":[1,2],\"imports\":false,\"exports\":{\"a\":1},\"exports\":null}");
    defer config.deinit();
    try expectSpan("[1,2]", config.views().imports);
    try expectSpan("{\"a\":1}", config.views().exports);
    var empty = try f.parse("{\"imports\":\"\",\"exports\":\"\"}"); defer empty.deinit();
    try expectSpan("", empty.views().imports);
    try expectSpan("", empty.views().exports);
}
test "native package JSON parser type changes only for the two actual accepted strings" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var first = try f.parse("{\"type\":\"unexpected\"}"); defer first.deinit();
    try expectSpan("none", first.views().type);
    var second = try f.parse("{\"type\":\"module\",\"type\":\"unexpected\",\"type\":\"\"}"); defer second.deinit();
    try expectSpan("module", second.views().type);
    var third = try f.parse("{\"type\":\"module\",\"type\":\"commonjs\"}"); defer third.deinit();
    try expectSpan("commonjs", third.views().type);
}
test "native package JSON parser scripts accepts only raw objects and retains earlier object" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var config = try f.parse("{\"scripts\":{ \"a\" : \"x\" },\"scripts\":[1],\"scripts\":\"ignored\",\"scripts\":null}");
    defer config.deinit();
    try expectSpan("{ \"a\" : \"x\" }", config.views().scripts);
    var absent = try f.parse("{\"scripts\":[]}"); defer absent.deinit();
    try expectAbsent(absent.views().scripts);
}
test "native package JSON parser selected strings preserve Unicode and embedded NUL lengths" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var config = try f.parse("{\"name\":\"a\\u0000b\",\"main\":\"\\u00e9\\ud83d\\ude00\",\"exports\":\"\\u0000\"}");
    defer config.deinit();
    try expectSpan("a\x00b", config.views().name);
    try expectSpan("\xc3\xa9\xf0\x9f\x98\x80", config.views().main);
    try expectSpan("\x00", config.views().exports);
    try f.fails("{\"name\":\"\xff\"}", c.PI_NODE_PACKAGE_JSON_INVALID);
}
test "native package JSON parser padding counts original ASCII trailing whitespace only" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const input = "{} \t\r\n";
    var mixed = try f.parse(input); defer mixed.deinit();
    try expectRaw(input, 60, mixed.views().raw_json);
    const enough = "{}" ++ (" " ** 70);
    var padded = try f.parse(enough); defer padded.deinit();
    try expectRaw(enough, 0, padded.views().raw_json);
}
test "native package JSON parser removes exactly one BOM for parsing and retains raw bytes" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const input = "\xef\xbb\xbf{\"name\":\"bom\"}";
    var config = try f.parse(input); defer config.deinit();
    try expectSpan("bom", config.views().name);
    try expectRaw(input, 64, config.views().raw_json);
    try f.fails("\xef\xbb\xbf\xef\xbb\xbf{}", c.PI_NODE_PACKAGE_JSON_INVALID);
}
test "native package JSON parser actual grammar failures do not poison later valid parses" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const invalid = [_][]const u8{ "", "[]", "null", "{\"name\":", "{\"name\":\"unterminated}", "{\"name\":\"ok\"," };
    for (invalid) |input| try f.fails(input, c.PI_NODE_PACKAGE_JSON_INVALID);
    var config = try f.parse("{\"name\":\"after-errors\"}"); defer config.deinit();
    try expectSpan("after-errors", config.views().name);
}
test "native package JSON parser capacity reuse leaves earlier copied configurations unchanged" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var first = try f.parse("{\"name\":\"first\"}"); defer first.deinit();
    const input = try longField("name", 8192, 'q'); defer std.testing.allocator.free(input);
    var larger = try f.parse(input); defer larger.deinit();
    const retained = f.used();
    var last = try f.parse("{\"name\":\"last\"}"); defer last.deinit();
    try expectSpan("first", first.views().name);
    try expectSpan("last", last.views().name);
    const long_name = larger.views().name;
    try std.testing.expectEqual(@as(usize, 8192), long_name.length);
    for (spanBytes(long_name)) |byte| try std.testing.expectEqual(@as(u8, 'q'), byte);
    last.deinit();
    try std.testing.expectEqual(retained, f.used());
}
test "native package JSON parser config retains its native memory owner after parser and runtime retirement" {
    const owners = c.pi_js_native_memory_owners();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var config = try f.parse("{\"name\":\"independent\",\"exports\":{\"x\":1}}"); defer config.deinit();
    f.dropParser();
    f.closeRuntime();
    try std.testing.expectEqual(owners + 1, c.pi_js_native_memory_owners());
    try expectSpan("independent", config.views().name);
    try expectSpan("{\"x\":1}", config.views().exports);
    config.deinit();
    try std.testing.expectEqual(owners, c.pi_js_native_memory_owners());
}
test "native package JSON parser real creation quota failure rolls back before later successful creation" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    f.dropParser();
    const before = f.used();
    var budget = try Budget.leave(&f, 0); defer budget.release();
    const failed = c.pi_node_package_json_parser_create(f.memory);
    defer c.pi_node_package_json_parser_destroy(failed);
    try std.testing.expect(failed == null);
    try std.testing.expectEqual(before + budget.bytes, f.used());
    budget.release();
    f.parser = c.pi_node_package_json_parser_create(f.memory) orelse return error.OutOfMemory;
    var config = try f.parse("{}"); defer config.deinit();
    try expectSpan("none", config.views().type);
}
test "native package JSON parser first allocation failure has no output and remains a terminal native result" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const before = f.used();
    var budget = try Budget.leave(&f, 0); defer budget.release();
    try f.fails("{}", c.PI_NODE_PACKAGE_JSON_MEMORY);
    try std.testing.expectEqual(before + budget.bytes, f.used());
    budget.release();
    try f.fails("{}", c.PI_NODE_PACKAGE_JSON_MEMORY);
    try std.testing.expectEqual(before, f.used());
    f.dropParser();
    try std.testing.expectEqual(f.before_parser, f.used());
}
test "native package JSON parser partial real allocation failure retires every retained parser block" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const input = try longField("name", 8192, 'p'); defer std.testing.allocator.free(input);
    const before = f.used();
    // The real raw input fits. Its following large string/index allocations
    // fail under the actual shared quota, while a smaller native implementation
    // object can remain owned by the real partially initialized parser.
    var budget = try Budget.leave(&f, input.len + 4096); defer budget.release();
    try f.fails(input, c.PI_NODE_PACKAGE_JSON_MEMORY);
    try std.testing.expect(f.used() > before + budget.bytes);
    f.dropParser();
    try std.testing.expectEqual(f.before_parser + budget.bytes, f.used());
    budget.release();
    try std.testing.expectEqual(f.before_parser, f.used());
}
test "native package JSON parser field-copy quota failure preserves prior config and exact retained parser charge" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const input = try longField("name", 8192, 'r'); defer std.testing.allocator.free(input);
    var prior = try f.parse(input); defer prior.deinit();
    const before = f.used();
    // The already-created parser needs no growth. The new Config and raw input
    // fit, but the genuine selected name-copy allocation cannot fit.
    var budget = try Budget.leave(&f, input.len + 512); defer budget.release();
    try f.fails(input, c.PI_NODE_PACKAGE_JSON_MEMORY);
    try std.testing.expectEqual(before + budget.bytes, f.used());
    try std.testing.expectEqual(@as(usize, 8192), prior.views().name.length);
    for (spanBytes(prior.views().name)) |byte| try std.testing.expectEqual(@as(u8, 'r'), byte);
    budget.release();
    try std.testing.expectEqual(before, f.used());
}
const ConfigWorker = struct {
    config: ?*c.PiNodePackageJsonConfig,
    correct: bool = false,
    thread_id: std.Thread.Id = undefined,
    fn run(self: *ConfigWorker) void {
        self.thread_id = std.Thread.getCurrentId();
        var views: c.PiNodePackageJsonViews = undefined;
        c.pi_node_package_json_config_views(self.config.?, &views);
        self.correct = views.name.present == 1 and
            std.mem.eql(u8, spanBytes(views.name), "native-worker");
        const config = self.config;
        self.config = null;
        c.pi_node_package_json_config_destroy(config);
    }
};
test "native package JSON parser native worker owns config bytes beyond runtime and caller retirement" {
    const owners = c.pi_js_native_memory_owners();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var config = try f.parse("{\"name\":\"native-worker\"}"); defer config.deinit();
    var worker: ConfigWorker = .{ .config = config.value };
    config.value = null;
    defer c.pi_node_package_json_config_destroy(worker.config);
    f.dropParser();
    f.closeRuntime();
    try std.testing.expectEqual(owners + 1, c.pi_js_native_memory_owners());
    const current = std.Thread.getCurrentId();
    const thread = try std.Thread.spawn(.{}, ConfigWorker.run, .{&worker});
    thread.join();
    try std.testing.expect(worker.correct and worker.thread_id != current);
    try std.testing.expect(worker.config == null);
    try std.testing.expectEqual(owners, c.pi_js_native_memory_owners());
}
const ParseWorker = struct {
    parser: *c.PiNodePackageJsonParser,
    output: ?*c.PiNodePackageJsonConfig = null,
    status: c_int = -1,
    fn run(self: *ParseWorker) void {
        const input = "{\"name\":\"separate-domain\"}";
        self.status = c.pi_node_package_json_parse(self.parser, input.ptr, input.len, &self.output);
    }
};
test "native package JSON parser concurrent native scopes keep their actual allocator domains separate" {
    var first: Fixture = undefined; try first.init(); defer first.deinit();
    var second: Fixture = undefined; try second.init(); defer second.deinit();
    const first_before = first.used();
    var budget = try Budget.leave(&first, 0); defer budget.release();
    var a_worker: ParseWorker = .{ .parser = first.parser.? };
    defer c.pi_node_package_json_config_destroy(a_worker.output);
    var b_worker: ParseWorker = .{ .parser = second.parser.? };
    defer c.pi_node_package_json_config_destroy(b_worker.output);
    const first_thread = try std.Thread.spawn(.{}, ParseWorker.run, .{&a_worker});
    const second_thread = std.Thread.spawn(.{}, ParseWorker.run, .{&b_worker}) catch |err| {
        first_thread.join();
        return err;
    };
    first_thread.join();
    second_thread.join();
    try std.testing.expectEqual(@as(c_int, c.PI_NODE_PACKAGE_JSON_MEMORY), a_worker.status);
    try std.testing.expect(a_worker.output == null);
    try std.testing.expectEqual(first_before + budget.bytes, first.used());
    try std.testing.expectEqual(@as(c_int, c.PI_NODE_PACKAGE_JSON_OK), b_worker.status);
    try std.testing.expect(b_worker.output != null);
    var views: c.PiNodePackageJsonViews = undefined;
    c.pi_node_package_json_config_views(b_worker.output.?, &views);
    try expectSpan("separate-domain", views.name);
}

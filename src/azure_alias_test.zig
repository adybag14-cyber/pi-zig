//! Native Azure identity migration across catalog, settings and credentials.
const std = @import("std");
const providers = @import("ai/providers.zig");
const models_file = @import("coding_agent/models_file.zig");
const effective_catalog = @import("coding_agent/effective_catalog.zig");
const model_resolver = @import("coding_agent/model_resolver.zig");
const runtime_config = @import("coding_agent/runtime_config.zig");
const storage = @import("auth/storage.zig");

test "Azure legacy configuration applies once to canonical catalog and retains each model API" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "models.json", .data =
        \\{"providers":{"azure-openai-responses":{"apiKey":"alias-test-key","modelOverrides":{"gpt-5.4":{"name":"Alias GPT","maxTokens":512}},"models":[{"id":"custom-azure"}]}}}
    });
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(io, &path_buffer);
    const path = path_buffer[0..length];
    var file = try models_file.load(gpa, io, path);
    defer file.deinit();
    try std.testing.expect(file.findProvider("azure") != null);
    const custom = file.findModel("azure", "custom-azure").?;
    try std.testing.expectEqualStrings("azure", custom.info.providerName());
    try std.testing.expectEqual(@import("ai/api.zig").Api.azure_openai_responses, custom.api);
    const catalog = try effective_catalog.build(gpa, &file);
    defer gpa.free(catalog);
    var gpt_count: usize = 0;
    var deepseek: ?providers.ModelInfo = null;
    for (catalog) |model| if (providers.providerIdsEqual(model.providerName(), "azure")) {
        if (std.mem.eql(u8, model.id, "gpt-5.4")) {
            gpt_count += 1;
            try std.testing.expectEqualStrings("Alias GPT", model.display);
            try std.testing.expectEqual(@as(u64, 512), model.max_tokens);
        }
        if (std.mem.eql(u8, model.id, "deepseek-v4-pro")) deepseek = model;
    };
    try std.testing.expectEqual(@as(usize, 1), gpt_count);
    try std.testing.expect(deepseek != null);
    var environment = std.process.Environ.Map.init(gpa);
    defer environment.deinit();
    var runtime = try runtime_config.resolveForModel(gpa, io, &environment, &file, deepseek.?, .{ .agent_dir = path });
    defer runtime.deinit();
    try std.testing.expectEqualStrings("azure", runtime.provider_id);
    try std.testing.expectEqualStrings("alias-test-key", runtime.api_key.?);
    try std.testing.expectEqual(@import("ai/api.zig").Api.openai_completions, runtime.api);
}

test {
    _ = providers;
    _ = model_resolver;
    _ = storage;
}

//! pi-zig CLI: full coding agent (print / interactive / json / rpc).
const std = @import("std");
const Io = std.Io;
const pi_zig = @import("pi_zig");

const config = pi_zig.config;
const ai = pi_zig.ai;
const agent = pi_zig.agent;
const tui = pi_zig.tui;
const coding = pi_zig.coding_agent;

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const gpa = init.gpa;
    const io = init.io;
    const environ: *const std.process.Environ.Map = init.environ_map;

    const raw_args = try init.minimal.args.toSlice(arena);
    var cli = try coding.args.parseArgs(arena, raw_args);

    if (cli.help) {
        var buf: [64]u8 = undefined;
        var stdout: Io.File.Writer = .init(.stdout(), io, &buf);
        try coding.args.printHelp(&stdout.interface);
        try stdout.interface.flush();
        return;
    }
    if (cli.version) {
        try tui.render.printLine(io, config.identity);
        return;
    }

    // Package manager subcommands
    if (cli.command) |cmd| {
        try runPackageCommand(gpa, io, environ, arena, cmd, cli.command_args.items);
        return;
    }

    const cwd = try std.process.currentPathAlloc(io, arena);

    // Agent dir
    const agent_dir: ?[]const u8 = config.agentDir(arena, environ) catch null;

    // Project trust: default true; --no-approve disables project .pi resources
    const trust_project = cli.approve orelse true;

    // Settings
    var settings = try coding.settings.loadMergeTrusted(gpa, io, agent_dir, cwd, trust_project);
    defer settings.deinit(gpa);

    if (cli.list_models) {
        try listModels(io, cli.list_models_query);
        return;
    }

    // Resolve provider / model / keys
    var provider = ai.resolveProvider(cli.provider orelse settings.provider, environ);
    if (cli.mock_script == null) {
        if (environ.get(config.ENV_MOCK_SCRIPT)) |p| {
            cli.mock_script = p;
        }
    }
    if (cli.mock_script != null) provider = .mock;
    if (cli.offline and cli.mock_script == null) {
        try tui.render.printLine(io, "error: --offline requires --mock-script <file> or PI_MOCK_SCRIPT");
        std.process.exit(2);
    }

    var model: ?[]const u8 = cli.model orelse settings.model orelse environ.get(config.ENV_MODEL) orelse ai.providers.defaultModel(provider);
    var provider_name: ?[]const u8 = try arena.dupe(u8, provider.name());

    var api_key = ai.resolveApiKey(provider, cli.api_key, environ);
    // credentials file fallback
    if (api_key == null and agent_dir != null) {
        const key_name = switch (provider) {
            .openai => "OPENAI_API_KEY",
            .anthropic => "ANTHROPIC_API_KEY",
            .google => "GOOGLE_API_KEY",
            .mock => "PI_API_KEY",
        };
        if (try coding.settings.loadCredential(arena, io, agent_dir.?, key_name)) |k| {
            api_key = k;
        }
    }

    const base_url: []const u8 = cli.base_url orelse environ.get(config.ENV_OPENAI_BASE) orelse ai.providers.defaultBaseUrl(provider);

    // Session directory
    const session_dir = try config.sessionDirForCwd(arena, environ, cwd, cli.session_dir);
    if (!cli.no_session) {
        config.ensureDir(io, session_dir) catch {};
    }

    // Session load / create
    var sess = try agent.session.Session.init(gpa, "pending", cwd);
    defer sess.deinit();
    var session_path: ?[]const u8 = null;

    if (cli.fork) |fork_src| {
        const src_path = try resolveSessionPath(arena, io, session_dir, fork_src);
        var loaded = agent.session.Session.load(gpa, io, src_path) catch {
            try tui.render.printLine(io, "error: could not fork session");
            std.process.exit(2);
        };
        defer loaded.deinit();
        sess.deinit();
        const new_id = try agent.session.generateSessionId(arena);
        sess = try loaded.fork(gpa, new_id);
        session_path = try agent.session.newSessionPath(arena, session_dir, new_id);
    } else if (cli.session) |sp| {
        const path = try resolveSessionPath(arena, io, session_dir, sp);
        if (agent.session.Session.load(gpa, io, path)) |loaded| {
            sess.deinit();
            sess = loaded;
            session_path = path;
        } else |_| {
            // new session at path
            const id = try agent.session.generateSessionId(arena);
            gpa.free(sess.id);
            sess.id = try gpa.dupe(u8, id);
            session_path = path;
        }
    } else if (cli.continue_session) {
        if (try agent.session.mostRecentSessionPath(arena, io, session_dir)) |path| {
            if (agent.session.Session.load(gpa, io, path)) |loaded| {
                sess.deinit();
                sess = loaded;
                session_path = path;
            } else |_| {}
        }
    } else if (!cli.no_session) {
        const id = try agent.session.generateSessionId(arena);
        gpa.free(sess.id);
        sess.id = try gpa.dupe(u8, id);
        session_path = try agent.session.newSessionPath(arena, session_dir, id);
    }

    if (cli.name) |n| try sess.setName(n);

    // Context / skills / prompts
    var context_count: usize = 0;
    var skills_count: usize = 0;
    var system_body: []const u8 = agent.default_system_prompt;
    var context_prompt: []const u8 = "";
    var owned_system: ?[]u8 = null;
    defer if (owned_system) |s| gpa.free(s);
    var owned_context: ?[]u8 = null;
    defer if (owned_context) |c| gpa.free(c);

    if (!cli.no_context_files) {
        var bundle = try coding.context.discoverTrusted(gpa, io, cwd, agent_dir, trust_project);
        defer bundle.deinit(gpa);
        context_count = bundle.files.len;
        owned_context = try coding.context.assembleContextPrompt(gpa, bundle.files);
        context_prompt = owned_context.?;

        // packages skills dirs
        var pkg_skill_dirs: []const []const u8 = &.{};
        var pkg_dirs_owned: ?[]const []const u8 = null;
        defer if (pkg_dirs_owned) |dirs| {
            for (dirs) |d| gpa.free(d);
            gpa.free(dirs);
        };
        if (agent_dir) |ad| {
            const pkgs = try coding.packages.list(gpa, io, ad);
            defer {
                for (pkgs) |*p| {
                    var mut = p.*;
                    mut.deinit(gpa);
                }
                gpa.free(pkgs);
            }
            pkg_dirs_owned = try coding.packages.packageSkillDirs(gpa, pkgs);
            pkg_skill_dirs = pkg_dirs_owned.?;
        }

        var skills_summary: []const u8 = "";
        var owned_skills_sum: ?[]u8 = null;
        defer if (owned_skills_sum) |s| gpa.free(s);

        if (!cli.no_skills) {
            var skills_list = try coding.skills.discoverTrusted(gpa, io, cwd, agent_dir, pkg_skill_dirs, trust_project);
            if (cli.skills.items.len > 0) {
                skills_list = try coding.skills.filterByNames(gpa, skills_list, cli.skills.items);
            }
            defer {
                for (skills_list) |*s| {
                    var mut = s.*;
                    mut.deinit(gpa);
                }
                gpa.free(skills_list);
            }
            skills_count = skills_list.len;
            owned_skills_sum = try coding.skills.summarize(gpa, skills_list);
            skills_summary = owned_skills_sum.?;
        }

        // CLI system prompt overrides + optional thinking guidance
        const base = cli.system_prompt orelse bundle.system_override orelse agent.default_system_prompt;
        owned_system = try coding.system_prompt.assemble(gpa, .{
            .base_prompt = base,
            .system_override = if (cli.system_prompt != null) cli.system_prompt else bundle.system_override,
            .append_system = bundle.append_system,
            .context_prompt = "", // context passed separately to agent as context_prompt
            .skills_summary = skills_summary,
            .extra_appends = cli.append_system_prompt.items,
            .thinking_level = cli.thinking,
        });
        system_body = owned_system.?;
    } else if (cli.system_prompt) |sp| {
        if (cli.thinking) |level| {
            owned_system = try std.fmt.allocPrint(gpa, "{s}\n\nThinking level: {s}. Reason carefully at this depth.", .{ sp, level });
            system_body = owned_system.?;
        } else {
            system_body = sp;
        }
    } else if (cli.thinking) |level| {
        owned_system = try std.fmt.allocPrint(gpa, "{s}\n\nThinking level: {s}. Reason carefully at this depth.", .{ agent.default_system_prompt, level });
        system_body = owned_system.?;
    }

    // File args @file into messages
    for (cli.file_args.items) |fp| {
        const data = std.Io.Dir.cwd().readFileAlloc(io, fp, arena, .limited(2 * 1024 * 1024)) catch continue;
        const labeled = try std.fmt.allocPrint(arena, "File {s}:\n{s}", .{ fp, data });
        try cli.messages.append(arena, labeled);
    }

    // Prompt templates
    if (!cli.no_prompt_templates and cli.prompt_templates.items.len > 0) {
        const templates = try coding.prompts.discover(gpa, io, cwd, agent_dir);
        defer {
            for (templates) |*t| {
                var mut = t.*;
                mut.deinit(gpa);
            }
            gpa.free(templates);
        }
        for (cli.prompt_templates.items) |tn| {
            if (coding.prompts.findByName(templates, tn)) |t| {
                const keys = [_][]const u8{ "cwd", "model", "provider" };
                const values = [_][]const u8{ cwd, model orelse "", provider_name orelse "" };
                const expanded = try coding.prompts.expand(arena, t.content, &keys, &values);
                try cli.messages.append(arena, expanded);
            }
        }
    }

    // Tool filter (--no-builtin-tools disables the built-in suite)
    const tool_filter = agent.tools.ToolFilter{
        .allow = cli.tools orelse settings.tools,
        .exclude = cli.exclude_tools,
        .no_tools = cli.no_tools or cli.no_builtin_tools,
    };

    const max_turns = settings.max_turns;

    // Model client storage (fields remain live so /model can mutate `.model`)
    var mock_storage: ?ai.mock.MockModel = null;
    defer if (mock_storage) |*m| m.deinit(gpa);
    var openai_storage: ?ai.openai.OpenAIClient = null;
    var anthropic_storage: ?ai.anthropic.AnthropicClient = null;
    var google_storage: ?ai.google.GoogleClient = null;
    var active_model_field: ?*[]const u8 = null;
    var model_display_owned: bool = false;

    const client: ai.ModelClient = blk: {
        if (cli.mock_script) |path| {
            const raw = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(4 * 1024 * 1024));
            defer gpa.free(raw);
            mock_storage = try ai.mock.MockModel.loadFromJson(gpa, raw);
            break :blk mock_storage.?.client();
        } else if (provider == .anthropic) {
            const key = api_key orelse {
                try tui.render.printLine(io, "error: set ANTHROPIC_API_KEY or --api-key (or --mock-script)");
                std.process.exit(2);
            };
            anthropic_storage = .{
                .gpa = gpa,
                .io = io,
                .api_key = key,
                .base_url = if (cli.base_url != null) base_url else ai.providers.defaultBaseUrl(.anthropic),
                .model = model.?,
            };
            active_model_field = &anthropic_storage.?.model;
            break :blk anthropic_storage.?.client();
        } else if (provider == .google) {
            const key = api_key orelse {
                try tui.render.printLine(io, "error: set GOOGLE_API_KEY or GEMINI_API_KEY or --api-key");
                std.process.exit(2);
            };
            google_storage = .{
                .gpa = gpa,
                .io = io,
                .api_key = key,
                .base_url = if (cli.base_url != null) base_url else ai.providers.defaultBaseUrl(.google),
                .model = model.?,
            };
            active_model_field = &google_storage.?.model;
            break :blk google_storage.?.client();
        } else if (api_key) |key| {
            openai_storage = .{
                .gpa = gpa,
                .io = io,
                .api_key = key,
                .base_url = base_url,
                .model = model.?,
            };
            active_model_field = &openai_storage.?.model;
            break :blk openai_storage.?.client();
        } else {
            try tui.render.printLine(io, "error: no model configured. Set OPENAI_API_KEY / ANTHROPIC_API_KEY / GOOGLE_API_KEY or --mock-script.");
            try tui.render.printLine(io, "See `pi --help`.");
            std.process.exit(2);
        }
    };

    // Mutable agent config so /reload can update prompts for subsequent turns
    var agent_cfg = agent.AgentConfig{
        .max_turns = max_turns,
        .system_prompt = system_body,
        .context_prompt = context_prompt,
        .tool_filter = tool_filter,
        .verbose = cli.verbose,
    };

    var live = coding.live_state.LiveState{
        .gpa = gpa,
        .io = io,
        .cwd = cwd,
        .agent_dir = agent_dir,
        .trust_project = trust_project,
        .thinking = cli.thinking,
        .agent_cfg = &agent_cfg,
        .owned_system = &owned_system,
        .owned_context = &owned_context,
        .model_display = &model,
        .active_model = active_model_field,
        .model_display_owned = &model_display_owned,
    };
    _ = &live;

    // Export only mode
    if (cli.export_path) |ep| {
        if (cli.messages.items.len > 0) {
            // run first then export
            const prompt = try joinMessages(arena, cli.messages.items);
            var result = try agent.run(gpa, io, cwd, client, &sess, prompt, agent_cfg, null, null);
            defer result.deinit(gpa);
        }
        const html = try coding.export_html.exportHtml(gpa, &sess);
        defer gpa.free(html);
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = ep, .data = html });
        if (session_path) |sp| {
            if (!cli.no_session) try sess.save(io, sp);
        }
        return;
    }

    // RPC mode
    if (cli.mode == .rpc) {
        try runRpcMode(gpa, io, arena, cwd, client, &sess, agent_cfg, session_path, cli.no_session);
        return;
    }

    // Print / one-shot
    if (cli.print or cli.mode == .json) {
        const prompt = try joinMessages(arena, cli.messages.items);
        if (prompt.len == 0) {
            try tui.render.printLine(io, "error: print mode requires a prompt message");
            std.process.exit(2);
        }

        if (cli.mode == .json) {
            var emitter = coding.modes.JsonEmitter{ .io = io };
            var result = try agent.run(gpa, io, cwd, client, &sess, prompt, agent_cfg, coding.modes.JsonEmitter.onEvent, &emitter);
            defer result.deinit(gpa);
            // done event already emitted by agent loop
        } else {
            var emitter = coding.modes.PrintEmitter{ .io = io, .verbose = cli.verbose };
            var result = try agent.run(gpa, io, cwd, client, &sess, prompt, agent_cfg, coding.modes.PrintEmitter.onEvent, &emitter);
            defer result.deinit(gpa);
            if (!cli.verbose) try tui.render.printLine(io, result.final_text);
        }

        if (session_path) |sp| {
            if (!cli.no_session) try sess.save(io, sp);
        }
        return;
    }

    // Interactive REPL
    try tui.render.renderHeader(io, config.version, context_count, skills_count);
    try tui.render.printLine(io, "Type a prompt and press Enter. Commands: /help /quit /session");

    const settings_text = try coding.settings.formatSettings(arena, settings);

    if (cli.messages.items.len > 0) {
        const prompt = try joinMessages(arena, cli.messages.items);
        try runOne(gpa, io, cwd, client, &sess, prompt, agent_cfg, cli.verbose);
        if (session_path) |sp| {
            if (!cli.no_session) try sess.save(io, sp);
        }
    }

    // --resume lists sessions then continues REPL
    if (cli.resume_session) {
        try tui.render.printLine(io, "Sessions:");
        const sessions = try agent.session.listSessions(gpa, io, session_dir);
        defer {
            for (sessions) |*s| {
                var mut = s.*;
                mut.deinit(gpa);
            }
            gpa.free(sessions);
        }
        for (sessions) |s| {
            const msg = try std.fmt.allocPrint(arena, "  {s}  {s}", .{ s.id, s.path });
            try tui.render.printLine(io, msg);
        }
    }

    var stdin_buf: [4096]u8 = undefined;
    var stdin_reader: Io.File.Reader = .init(.stdin(), io, &stdin_buf);

    while (true) {
        try tui.render.writeAll(io, "> ");
        const line = readLine(&stdin_reader, arena) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };
        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        if (trimmed.len == 0) continue;

        if (trimmed[0] == '/') {
            const slash_ctx = coding.slash.SlashContext{
                .gpa = gpa,
                .io = io,
                .cwd = cwd,
                .sess = &sess,
                .session_path = session_path,
                .session_dir = session_dir,
                .agent_dir = agent_dir,
                .model = &model,
                .provider = &provider_name,
                .settings_text = settings_text,
                .trust_project = trust_project,
                .live = &live,
            };
            const sr = try coding.slash.handle(slash_ctx, trimmed);
            switch (sr) {
                .quit => break,
                .handled => {
                    if (session_path) |sp| {
                        if (!cli.no_session) try sess.save(io, sp);
                    }
                    continue;
                },
                .not_command, .run_prompt => {},
            }
        }

        // agent_cfg is var; by-value copy picks up /reload and /model side effects on prompts.
        try runOne(gpa, io, cwd, client, &sess, trimmed, agent_cfg, cli.verbose);
        if (session_path) |sp| {
            if (!cli.no_session) try sess.save(io, sp);
        }
    }

    if (session_path) |sp| {
        if (!cli.no_session) try sess.save(io, sp);
    }
}

fn runOne(
    gpa: std.mem.Allocator,
    io: Io,
    cwd: []const u8,
    client: ai.ModelClient,
    sess: *agent.session.Session,
    prompt: []const u8,
    agent_cfg: agent.AgentConfig,
    verbose: bool,
) !void {
    var emitter = coding.modes.PrintEmitter{ .io = io, .verbose = verbose };
    var result = try agent.run(gpa, io, cwd, client, sess, prompt, agent_cfg, coding.modes.PrintEmitter.onEvent, &emitter);
    defer result.deinit(gpa);
    if (!verbose) try tui.render.printLine(io, result.final_text);
}

fn runRpcMode(
    gpa: std.mem.Allocator,
    io: Io,
    arena: std.mem.Allocator,
    cwd: []const u8,
    client: ai.ModelClient,
    sess: *agent.session.Session,
    agent_cfg: agent.AgentConfig,
    session_path: ?[]const u8,
    no_session: bool,
) !void {
    var stdin_buf: [8192]u8 = undefined;
    var stdin_reader: Io.File.Reader = .init(.stdin(), io, &stdin_buf);

    while (true) {
        const line = readLine(&stdin_reader, arena) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };
        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        if (trimmed.len == 0) continue;

        var req = coding.modes.parseRpcLine(gpa, trimmed) catch {
            try coding.modes.writeRpcError(io, "?", "invalid request");
            continue;
        };
        defer coding.modes.freeRpcRequest(gpa, &req);

        if (std.mem.eql(u8, req.method, "quit") or std.mem.eql(u8, req.method, "exit")) {
            try coding.modes.writeRpcResult(io, req.id, "bye");
            break;
        }
        if (std.mem.eql(u8, req.method, "ping")) {
            try coding.modes.writeRpcResult(io, req.id, "pong");
            continue;
        }
        if (std.mem.eql(u8, req.method, "prompt")) {
            const prompt = req.params_prompt orelse "";
            var result = try agent.run(gpa, io, cwd, client, sess, prompt, agent_cfg, null, null);
            defer result.deinit(gpa);
            try coding.modes.writeRpcResult(io, req.id, result.final_text);
            if (session_path) |sp| {
                if (!no_session) try sess.save(io, sp);
            }
            continue;
        }
        try coding.modes.writeRpcError(io, req.id, "unknown method");
    }
}

fn runPackageCommand(
    gpa: std.mem.Allocator,
    io: Io,
    environ: *const std.process.Environ.Map,
    arena: std.mem.Allocator,
    cmd: []const u8,
    cmd_args: []const []const u8,
) !void {
    const agent_dir = config.agentDir(arena, environ) catch {
        try tui.render.printLine(io, "error: cannot resolve agent dir (set HOME/USERPROFILE or PI_AGENT_DIR)");
        std.process.exit(2);
    };
    config.ensureDir(io, agent_dir) catch {};
    const cwd = try std.process.currentPathAlloc(io, arena);

    if (std.mem.eql(u8, cmd, "install")) {
        if (cmd_args.len == 0) {
            try tui.render.printLine(io, "usage: pi install path:./local-pkg");
            std.process.exit(2);
        }
        var installed = try coding.packages.install(gpa, io, agent_dir, cmd_args[0], cwd);
        defer installed.deinit(gpa);
        const msg = try std.fmt.allocPrint(arena, "Installed package {s} -> {s}", .{ installed.name, installed.path });
        try tui.render.printLine(io, msg);
    } else if (std.mem.eql(u8, cmd, "list")) {
        const packages = try coding.packages.list(gpa, io, agent_dir);
        defer {
            for (packages) |*p| {
                var mut = p.*;
                mut.deinit(gpa);
            }
            gpa.free(packages);
        }
        if (packages.len == 0) {
            try tui.render.printLine(io, "(no packages)");
        } else {
            for (packages) |p| {
                const msg = try std.fmt.allocPrint(arena, "{s}\t{s}", .{ p.name, p.path });
                try tui.render.printLine(io, msg);
            }
        }
    } else if (std.mem.eql(u8, cmd, "remove") or std.mem.eql(u8, cmd, "uninstall")) {
        if (cmd_args.len == 0) {
            try tui.render.printLine(io, "usage: pi remove <name>");
            std.process.exit(2);
        }
        if (try coding.packages.remove(gpa, io, agent_dir, cmd_args[0])) {
            try tui.render.printLine(io, "Removed.");
        } else {
            try tui.render.printLine(io, "Package not found.");
        }
    }
}

fn listModels(io: Io, query: ?[]const u8) !void {
    for (ai.providers.known_models) |m| {
        if (query) |q| {
            if (std.mem.indexOf(u8, m.id, q) == null and std.mem.indexOf(u8, m.display, q) == null) continue;
        }
        var buf: [256]u8 = undefined;
        const line = try std.fmt.bufPrint(&buf, "{s}/{s}\t{s}", .{ m.provider.name(), m.id, m.display });
        try tui.render.printLine(io, line);
    }
}

fn resolveSessionPath(arena: std.mem.Allocator, io: Io, session_dir: []const u8, path_or_id: []const u8) ![]const u8 {
    // Absolute or exists as path
    if (std.mem.indexOfScalar(u8, path_or_id, '/') != null or std.mem.indexOfScalar(u8, path_or_id, '\\') != null or std.mem.endsWith(u8, path_or_id, ".jsonl")) {
        return path_or_id;
    }
    // try as file in session dir
    const candidate = try agent.session.newSessionPath(arena, session_dir, path_or_id);
    std.Io.Dir.cwd().access(io, candidate, .{}) catch {
        // partial id match
        const sessions = try agent.session.listSessions(arena, io, session_dir);
        for (sessions) |s| {
            if (std.mem.indexOf(u8, s.id, path_or_id) != null or std.mem.startsWith(u8, s.id, path_or_id)) {
                return s.path;
            }
        }
        return candidate;
    };
    return candidate;
}

fn joinMessages(arena: std.mem.Allocator, msgs: []const []const u8) ![]const u8 {
    if (msgs.len == 0) return "";
    if (msgs.len == 1) return msgs[0];
    var out: std.ArrayList(u8) = .empty;
    for (msgs, 0..) |m, i| {
        if (i > 0) try out.append(arena, ' ');
        try out.appendSlice(arena, m);
    }
    return try out.toOwnedSlice(arena);
}

fn readLine(reader: *Io.File.Reader, arena: std.mem.Allocator) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(arena);
    while (true) {
        const n = reader.interface.takeByte() catch |err| switch (err) {
            error.EndOfStream => {
                if (list.items.len == 0) return error.EndOfStream;
                break;
            },
            else => return err,
        };
        if (n == '\n') break;
        if (n == '\r') continue;
        try list.append(arena, n);
    }
    return try list.toOwnedSlice(arena);
}

test "identity stable" {
    try std.testing.expect(std.mem.indexOf(u8, pi_zig.identity, "pi") != null);
}

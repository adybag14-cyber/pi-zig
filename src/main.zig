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

    // Package / monorepo C subcommands
    if (cli.command) |cmd| {
        if (std.mem.eql(u8, cmd, "install") or std.mem.eql(u8, cmd, "list") or
            std.mem.eql(u8, cmd, "remove") or std.mem.eql(u8, cmd, "uninstall"))
        {
            try runPackageCommand(gpa, io, environ, arena, cmd, cli.command_args.items);
            return;
        }
        try runSurfaceCommand(gpa, io, environ, arena, cmd, cli.command_args.items);
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
            .openai, .openai_compat => "OPENAI_API_KEY",
            .anthropic => "ANTHROPIC_API_KEY",
            .google => "GOOGLE_API_KEY",
            .mock => "PI_API_KEY",
        };
        if (try coding.settings.loadCredential(arena, io, agent_dir.?, key_name)) |k| {
            api_key = k;
        }
    }

    const base_url: []const u8 = blk: {
        if (cli.base_url) |u| break :blk u;
        if (environ.get(config.ENV_OPENAI_BASE)) |u| break :blk u;
        // Named openai_compat gateways from --provider (e.g. ollama, groq, xai)
        if (cli.provider) |pname| {
            if (ai.providers.compatBaseUrl(pname)) |u| break :blk u;
        }
        break :blk ai.providers.defaultBaseUrl(provider);
    };

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
    } else {
        // Ephemeral session still needs a real id for JSON/RPC session headers.
        const id = try agent.session.generateSessionId(arena);
        gpa.free(sess.id);
        sess.id = try gpa.dupe(u8, id);
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
    var owned_skills_summary: ?[]u8 = null;
    defer if (owned_skills_summary) |s| gpa.free(s);

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
            owned_skills_summary = try coding.skills.summarize(gpa, skills_list);
            skills_summary = owned_skills_summary.?;
        }

        // CLI system prompt overrides + optional thinking guidance
        const thinking_eff_early = cli.thinking orelse settings.thinking_level;
        const base = cli.system_prompt orelse bundle.system_override orelse agent.default_system_prompt;
        owned_system = try coding.system_prompt.assemble(gpa, .{
            .base_prompt = base,
            .system_override = if (cli.system_prompt != null) cli.system_prompt else bundle.system_override,
            .append_system = bundle.append_system,
            .context_prompt = "", // context passed separately to agent as context_prompt
            .skills_summary = skills_summary,
            .extra_appends = cli.append_system_prompt.items,
            .thinking_level = thinking_eff_early,
        });
        system_body = owned_system.?;
    } else if (cli.system_prompt) |sp| {
        const thinking_eff_early = cli.thinking orelse settings.thinking_level;
        if (thinking_eff_early) |level| {
            owned_system = try std.fmt.allocPrint(gpa, "{s}\n\nThinking level: {s}. Reason carefully at this depth.", .{ sp, level });
            system_body = owned_system.?;
        } else {
            system_body = sp;
        }
    } else {
        const thinking_eff_early = cli.thinking orelse settings.thinking_level;
        if (thinking_eff_early) |level| {
            owned_system = try std.fmt.allocPrint(gpa, "{s}\n\nThinking level: {s}. Reason carefully at this depth.", .{ agent.default_system_prompt, level });
            system_body = owned_system.?;
        }
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

    // Model client pool (rebuildable on provider switch)
    var mock_storage: ?ai.mock.MockModel = null;
    defer if (mock_storage) |*m| m.deinit(gpa);
    var client_pool: coding.live_state.ClientPool = .{
        .gpa = gpa,
        .io = io,
    };
    defer client_pool.deinit();
    var active_model_field: ?*[]const u8 = null;
    var model_display_owned: bool = false;

    // Resolve keys for pool (env/credentials already in api_key for primary provider)
    const openai_key = ai.providers.resolveApiKey(.openai, cli.api_key, environ) orelse
        (if (agent_dir) |ad| coding.settings.loadCredential(gpa, io, ad, "OPENAI_API_KEY") catch null else null);
    const anthropic_key = ai.providers.resolveApiKey(.anthropic, cli.api_key, environ) orelse
        (if (agent_dir) |ad| coding.settings.loadCredential(gpa, io, ad, "ANTHROPIC_API_KEY") catch null else null);
    const google_key = ai.providers.resolveApiKey(.google, cli.api_key, environ) orelse
        (if (agent_dir) |ad| coding.settings.loadCredential(gpa, io, ad, "GOOGLE_API_KEY") catch null else null);
    client_pool.setKeys(openai_key, anthropic_key, google_key, base_url);
    // Thinking API budgets applied before first switchTo so request bodies include them.
    const thinking_eff_early_pool = cli.thinking orelse settings.thinking_level;
    client_pool.setThinkingFromString(thinking_eff_early_pool);

    const use_mock = cli.mock_script != null;
    if (cli.mock_script) |path| {
        const raw = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(4 * 1024 * 1024));
        defer gpa.free(raw);
        mock_storage = try ai.mock.MockModel.loadFromJson(gpa, raw);
    } else {
        client_pool.switchTo(provider, model.?) catch {
            try tui.render.printLine(io, "error: no model configured. Set OPENAI_API_KEY / ANTHROPIC_API_KEY / GOOGLE_API_KEY or --mock-script.");
            try tui.render.printLine(io, "See `pi --help`.");
            std.process.exit(2);
        };
        active_model_field = client_pool.modelPtr();
    }
    // Always re-read live client (after /model provider switch rebuilds pool)
    const getClient = struct {
        fn call(mock: ?*ai.mock.MockModel, pool: *coding.live_state.ClientPool, is_mock: bool) ai.ModelClient {
            if (is_mock) return mock.?.client();
            return pool.client;
        }
    }.call;

    // Shared cooperative abort for mid-bash kill + mid-HTTP cancel (all modes).
    var shared_abort: bool = false;
    client_pool.setAbortFlag(&shared_abort);

    // Mutable agent config so /reload can update prompts for subsequent turns
    var agent_cfg = agent.AgentConfig{
        .max_turns = max_turns,
        .system_prompt = system_body,
        .context_prompt = context_prompt,
        .tool_filter = tool_filter,
        .verbose = cli.verbose,
        .compact_keep_recent = settings.compaction_keep_recent,
        .abort_flag = &shared_abort,
    };

    const thinking_eff = cli.thinking orelse settings.thinking_level;

    var live = coding.live_state.LiveState{
        .gpa = gpa,
        .io = io,
        .cwd = cwd,
        .agent_dir = agent_dir,
        .trust_project = trust_project,
        .thinking = thinking_eff,
        .agent_cfg = &agent_cfg,
        .owned_system = &owned_system,
        .owned_context = &owned_context,
        .owned_skills_summary = &owned_skills_summary,
        .model_display = &model,
        .active_model = active_model_field,
        .model_display_owned = &model_display_owned,
        .client_pool = if (cli.mock_script == null) &client_pool else null,
        .provider_name = &provider_name,
    };
    _ = &live;

    // Export only mode
    if (cli.export_path) |ep| {
        if (cli.messages.items.len > 0) {
            // run first then export
            const prompt = try joinMessages(arena, cli.messages.items);
            var result = try agent.run(gpa, io, cwd, getClient(if (mock_storage) |*m| m else null, &client_pool, use_mock), &sess, prompt, agent_cfg, null, null);
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
        try runRpcMode(gpa, io, arena, cwd, &client_pool, &sess, &agent_cfg, &live, &provider_name, session_path, cli.no_session, use_mock, if (mock_storage) |*m| m else null);
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
            var emitter = coding.modes.JsonEmitter{
                .io = io,
                .session_id = sess.id,
                .cwd = cwd,
            };
            var result = try agent.run(gpa, io, cwd, getClient(if (mock_storage) |*m| m else null, &client_pool, use_mock), &sess, prompt, agent_cfg, coding.modes.JsonEmitter.onEvent, &emitter);
            defer result.deinit(gpa);
            // done event already emitted by agent loop
        } else {
            var emitter = coding.modes.PrintEmitter{ .io = io, .verbose = cli.verbose };
            var result = try agent.run(gpa, io, cwd, getClient(if (mock_storage) |*m| m else null, &client_pool, use_mock), &sess, prompt, agent_cfg, coding.modes.PrintEmitter.onEvent, &emitter);
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
        try runOne(gpa, io, cwd, getClient(if (mock_storage) |*m| m else null, &client_pool, use_mock), &sess, prompt, agent_cfg, cli.verbose);
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
                .client = getClient(if (mock_storage) |*m| m else null, &client_pool, use_mock),
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
        try runOne(gpa, io, cwd, getClient(if (mock_storage) |*m| m else null, &client_pool, use_mock), &sess, trimmed, agent_cfg, cli.verbose);
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
    client_pool: *coding.live_state.ClientPool,
    sess: *agent.session.Session,
    agent_cfg: *agent.AgentConfig,
    live: *coding.live_state.LiveState,
    provider_name: *?[]const u8,
    session_path: ?[]const u8,
    no_session: bool,
    use_mock: bool,
    mock_storage: ?*ai.mock.MockModel,
) !void {
    var abort_flag: bool = false;
    var steer_queue: std.ArrayList([]const u8) = .empty;
    var follow_up_queue: std.ArrayList([]const u8) = .empty;
    defer {
        for (steer_queue.items) |m| gpa.free(m);
        steer_queue.deinit(gpa);
        for (follow_up_queue.items) |m| gpa.free(m);
        follow_up_queue.deinit(gpa);
    }
    agent_cfg.abort_flag = &abort_flag;
    // Mid-HTTP cancel: live OpenAI/Anthropic SSE writers poll this flag.
    client_pool.setAbortFlag(&abort_flag);
    agent_cfg.steer_queue = &steer_queue;
    agent_cfg.follow_up_queue = &follow_up_queue;

    // Always-on stdin inbox thread so abort/steer work while agent.run is in flight.
    const Inbox = struct {
        mutex: std.Io.Mutex = .init,
        cond: std.Io.Condition = .init,
        lines: std.ArrayList([]u8) = .empty,
        closed: bool = false,
    };
    const inbox = try gpa.create(Inbox);
    inbox.* = .{};
    defer {
        for (inbox.lines.items) |l| gpa.free(l);
        inbox.lines.deinit(gpa);
        gpa.destroy(inbox);
    }

    const StdinCtx = struct {
        gpa: std.mem.Allocator,
        io: Io,
        inbox: *Inbox,
    };
    const sctx = try gpa.create(StdinCtx);
    sctx.* = .{ .gpa = gpa, .io = io, .inbox = inbox };
    const stdin_thread = try std.Thread.spawn(.{}, struct {
        fn run(ctx: *StdinCtx) void {
            defer ctx.gpa.destroy(ctx);
            var buf: [8192]u8 = undefined;
            var reader: Io.File.Reader = .init(.stdin(), ctx.io, &buf);
            while (true) {
                const line = readLine(&reader, ctx.gpa) catch {
                    ctx.inbox.mutex.lockUncancelable(ctx.io);
                    ctx.inbox.closed = true;
                    ctx.inbox.cond.broadcast(ctx.io);
                    ctx.inbox.mutex.unlock(ctx.io);
                    return;
                };
                ctx.inbox.mutex.lockUncancelable(ctx.io);
                ctx.inbox.lines.append(ctx.gpa, line) catch {
                    ctx.gpa.free(line);
                };
                ctx.inbox.cond.signal(ctx.io);
                ctx.inbox.mutex.unlock(ctx.io);
            }
        }
    }.run, .{sctx});
    // Detach: may block forever on stdin readLine; process exit reclaims the thread.
    stdin_thread.detach();

    // Emit session header once so clients can correlate (json.md / rpc.md)
    {
        var hdr = coding.modes.JsonEmitter{
            .io = io,
            .session_id = sess.id,
            .cwd = cwd,
        };
        hdr.emitHeader();
    }

    // Agent busy state for concurrent control commands
    var agent_busy = std.atomic.Value(bool).init(false);

    while (true) {
        // Wait for a line
        inbox.mutex.lockUncancelable(io);
        while (inbox.lines.items.len == 0 and !inbox.closed) {
            inbox.cond.waitUncancelable(io, &inbox.mutex);
        }
        if (inbox.lines.items.len == 0 and inbox.closed) {
            inbox.mutex.unlock(io);
            break;
        }
        const line = inbox.lines.orderedRemove(0);
        inbox.mutex.unlock(io);
        defer gpa.free(line);

        // Strict JSONL: strip optional CR only
        var trimmed = std.mem.trim(u8, line, " \t");
        if (trimmed.len > 0 and trimmed[trimmed.len - 1] == '\r') {
            trimmed = trimmed[0 .. trimmed.len - 1];
        }
        trimmed = std.mem.trim(u8, trimmed, " \t");
        if (trimmed.len == 0) continue;

        var req = coding.modes.parseRpcLine(gpa, trimmed) catch {
            try coding.modes.writeRpcResponse(io, "", "error", false, "{\"error\":\"invalid request\"}");
            continue;
        };
        defer coding.modes.freeRpcRequest(gpa, &req);

        // Concurrent commands always allowed
        if (std.mem.eql(u8, req.method, "abort")) {
            abort_flag = true;
            try coding.modes.writeRpcResponse(io, req.id, "abort", true, null);
            continue;
        }
        if (std.mem.eql(u8, req.method, "steer")) {
            const p = req.params_prompt orelse "";
            try steer_queue.append(gpa, try gpa.dupe(u8, p));
            try coding.modes.writeRpcResponse(io, req.id, "steer", true, null);
            continue;
        }
        if (std.mem.eql(u8, req.method, "follow_up")) {
            // Delivered only when agent would stop (idle), not mid tool-batch
            const p = req.params_prompt orelse "";
            try follow_up_queue.append(gpa, try gpa.dupe(u8, p));
            try coding.modes.writeRpcResponse(io, req.id, "follow_up", true, null);
            continue;
        }
        if (std.mem.eql(u8, req.method, "ping")) {
            try coding.modes.writeRpcResponse(io, req.id, "ping", true, "\"pong\"");
            continue;
        }

        // While agent is busy, only concurrent commands above are accepted for other methods
        if (agent_busy.load(.acquire)) {
            try coding.modes.writeRpcResponse(io, req.id, req.method, false, "{\"error\":\"agent busy; use abort/steer/follow_up/ping\"}");
            continue;
        }

        if (std.mem.eql(u8, req.method, "quit") or std.mem.eql(u8, req.method, "exit")) {
            try coding.modes.writeRpcResponse(io, req.id, req.method, true, null);
            break;
        }
        if (std.mem.eql(u8, req.method, "new_session")) {
            while (sess.entries.items.len > 0) {
                var e = sess.entries.pop().?;
                e.deinit(gpa);
            }
            if (sess.tip_id) |t| {
                gpa.free(t);
                sess.tip_id = null;
            }
            try coding.modes.writeRpcResponse(io, req.id, "new_session", true, "{\"cancelled\":false}");
            continue;
        }
        if (std.mem.eql(u8, req.method, "get_available_models")) {
            const data = try formatAvailableModelsJson(arena);
            try coding.modes.writeRpcResponse(io, req.id, "get_available_models", true, data);
            continue;
        }
        if (std.mem.eql(u8, req.method, "set_model")) {
            const mid = req.model_id orelse {
                try coding.modes.writeRpcResponse(io, req.id, "set_model", false, "{\"error\":\"modelId required\"}");
                continue;
            };
            if (req.provider) |p| {
                // Arena-owned so it outlives freeRpcRequest
                provider_name.* = try arena.dupe(u8, p);
            }
            try coding.live_state.applyModel(live, mid);
            const data = try formatModelDataJson(arena, provider_name.*, live.model_display.*);
            try coding.modes.writeRpcResponse(io, req.id, "set_model", true, data);
            continue;
        }
        if (std.mem.eql(u8, req.method, "cycle_model")) {
            const current = live.model_display.* orelse "mock";
            const next = nextKnownModel(current);
            if (next) |n| {
                // Rebuild client when provider changes (provider/id form)
                const combined = try std.fmt.allocPrint(arena, "{s}/{s}", .{ n.provider.name(), n.id });
                try coding.live_state.applyModel(live, combined);
                provider_name.* = n.provider.name();
                const data = try std.fmt.allocPrint(arena,
                    \\{{"model":{{"id":{s},"provider":{s},"display":{s}}}
                , .{
                    try jsonString(arena, n.id),
                    try jsonString(arena, n.provider.name()),
                    try jsonString(arena, n.display),
                });
                try coding.modes.writeRpcResponse(io, req.id, "cycle_model", true, data);
            } else {
                try coding.modes.writeRpcResponse(io, req.id, "cycle_model", true, "null");
            }
            continue;
        }
        if (std.mem.eql(u8, req.method, "set_thinking_level")) {
            const level = req.thinking_level orelse {
                try coding.modes.writeRpcResponse(io, req.id, "set_thinking_level", false, "{\"error\":\"thinkingLevel required\"}");
                continue;
            };
            const level_owned = try arena.dupe(u8, level);
            try coding.live_state.applyThinking(live, level_owned);
            const data = try std.fmt.allocPrint(arena, "{{\"thinkingLevel\":{s}}}", .{try jsonString(arena, level)});
            try coding.modes.writeRpcResponse(io, req.id, "set_thinking_level", true, data);
            continue;
        }
        if (std.mem.eql(u8, req.method, "get_state")) {
            const model_id = live.model_display.* orelse "";
            const prov = provider_name.* orelse "";
            const thinking = live.thinking orelse "";
            const pending = steer_queue.items.len + follow_up_queue.items.len;
            const streaming = agent_busy.load(.acquire);
            const data = try std.fmt.allocPrint(arena,
                \\{{"sessionId":{s},"sessionName":{s},"messageCount":{d},"pendingMessageCount":{d},"isStreaming":{s},"isCompacting":false,"thinkingLevel":{s},"model":{{"id":{s},"provider":{s}}},"sessionFile":{s},"steerQueue":{d},"followUpQueue":{d}}}
            , .{
                try jsonString(arena, sess.id),
                try jsonString(arena, sess.name),
                sess.entries.items.len,
                pending,
                if (streaming) "true" else "false",
                try jsonString(arena, thinking),
                try jsonString(arena, model_id),
                try jsonString(arena, prov),
                try jsonString(arena, session_path orelse ""),
                steer_queue.items.len,
                follow_up_queue.items.len,
            });
            try coding.modes.writeRpcResponse(io, req.id, "get_state", true, data);
            continue;
        }
        if (std.mem.eql(u8, req.method, "get_messages")) {
            const data = try formatSessionMessagesJson(arena, sess);
            try coding.modes.writeRpcResponse(io, req.id, "get_messages", true, data);
            continue;
        }
        if (std.mem.eql(u8, req.method, "compact")) {
            const live_client: ai.ModelClient = if (use_mock) mock_storage.?.client() else client_pool.client;
            try agent.compaction.compact(sess, .{
                .keep_recent = agent_cfg.compact_keep_recent,
                .client = live_client,
            });
            try coding.modes.writeRpcResponse(io, req.id, "compact", true, null);
            if (session_path) |sp| {
                if (!no_session) try sess.save(io, sp);
            }
            continue;
        }
        if (std.mem.eql(u8, req.method, "get_tree") or std.mem.eql(u8, req.method, "get_entries")) {
            const tree = try sess.treeSummary(gpa);
            defer gpa.free(tree);
            var aw: std.Io.Writer.Allocating = .init(arena);
            try aw.writer.writeAll("{\"tree\":");
            try std.json.Stringify.value(tree, .{}, &aw.writer);
            try aw.writer.writeAll(",\"tipId\":");
            try std.json.Stringify.value(sess.lastEntryId() orelse "", .{}, &aw.writer);
            try aw.writer.writeAll(",\"messageCount\":");
            try aw.writer.print("{d}", .{sess.entries.items.len});
            try aw.writer.writeAll("}");
            try coding.modes.writeRpcResponse(io, req.id, req.method, true, aw.written());
            continue;
        }
        if (std.mem.eql(u8, req.method, "set_session_name")) {
            const name = req.params_prompt orelse req.model_id orelse "";
            try sess.setName(name);
            const data = try std.fmt.allocPrint(arena, "{{\"name\":{s}}}", .{try jsonString(arena, name)});
            try coding.modes.writeRpcResponse(io, req.id, "set_session_name", true, data);
            continue;
        }
        if (std.mem.eql(u8, req.method, "export_html") or std.mem.eql(u8, req.method, "export")) {
            const path = req.params_prompt orelse "session.html";
            const html = try coding.export_html.exportHtml(gpa, sess);
            defer gpa.free(html);
            std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = html }) catch {
                try coding.modes.writeRpcResponse(io, req.id, "export_html", false, "{\"error\":\"write failed\"}");
                continue;
            };
            const data = try std.fmt.allocPrint(arena, "{{\"path\":{s}}}", .{try jsonString(arena, path)});
            try coding.modes.writeRpcResponse(io, req.id, "export_html", true, data);
            continue;
        }
        if (std.mem.eql(u8, req.method, "fork") or std.mem.eql(u8, req.method, "clone")) {
            const new_id = try agent.session.generateSessionId(gpa);
            defer gpa.free(new_id);
            var forked = try sess.fork(gpa, new_id);
            const path = if (session_path) |_| blk: {
                // sibling file next to current if we have a dir
                const dir = if (session_path) |sp| std.fs.path.dirname(sp) orelse "." else ".";
                break :blk try agent.session.newSessionPath(gpa, dir, new_id);
            } else null;
            defer if (path) |p| gpa.free(p);
            if (path) |p| {
                try forked.save(io, p);
            }
            // Replace live session with fork
            sess.deinit();
            sess.* = forked;
            const data = try std.fmt.allocPrint(arena, "{{\"sessionId\":{s},\"path\":{s}}}", .{
                try jsonString(arena, new_id),
                try jsonString(arena, path orelse ""),
            });
            try coding.modes.writeRpcResponse(io, req.id, req.method, true, data);
            continue;
        }
        if (std.mem.eql(u8, req.method, "get_commands")) {
            const cmds =
                \\{"commands":["prompt","abort","steer","follow_up","ping","quit","get_state","get_messages","get_available_models","set_model","cycle_model","set_thinking_level","compact","get_tree","set_session_name","export_html","fork","clone","new_session","get_commands"]}
            ;
            try coding.modes.writeRpcResponse(io, req.id, "get_commands", true, cmds);
            continue;
        }
        if (std.mem.eql(u8, req.method, "prompt")) {
            const prompt = req.params_prompt orelse "";
            abort_flag = false;
            try coding.modes.writeRpcResponse(io, req.id, req.method, true, null);

            // Run agent on background thread; main loop continues draining inbox for abort/steer.
            const RunCtx = struct {
                gpa: std.mem.Allocator,
                io: Io,
                cwd: []const u8,
                client: ai.ModelClient,
                sess: *agent.session.Session,
                agent_cfg: agent.AgentConfig,
                prompt: []const u8,
                session_id: []const u8,
                busy: *std.atomic.Value(bool),
                err: ?anyerror = null,
            };
            const rctx = try gpa.create(RunCtx);
            const live_client: ai.ModelClient = if (use_mock) mock_storage.?.client() else client_pool.client;
            rctx.* = .{
                .gpa = gpa,
                .io = io,
                .cwd = cwd,
                .client = live_client,
                .sess = sess,
                .agent_cfg = agent_cfg.*,
                .prompt = try gpa.dupe(u8, prompt),
                .session_id = sess.id,
                .busy = &agent_busy,
            };
            agent_busy.store(true, .release);
            const agent_thread = try std.Thread.spawn(.{}, struct {
                fn run(ctx: *RunCtx) void {
                    defer {
                        ctx.gpa.free(ctx.prompt);
                        ctx.busy.store(false, .release);
                        ctx.gpa.destroy(ctx);
                    }
                    var emitter = coding.modes.RpcEventEmitter.init(ctx.io);
                    emitter.json.session_id = ctx.session_id;
                    emitter.json.cwd = ctx.cwd;
                    emitter.json.emitted_header = true;
                    var result = agent.run(ctx.gpa, ctx.io, ctx.cwd, ctx.client, ctx.sess, ctx.prompt, ctx.agent_cfg, coding.modes.RpcEventEmitter.onEvent, &emitter) catch {
                        return;
                    };
                    result.deinit(ctx.gpa);
                }
            }.run, .{rctx});
            // Detach: main continues reading inbox; next non-concurrent command waits via agent_busy
            agent_thread.detach();
            // Spin until idle so sequential RPC scripts still work (quit after prompt completes)
            while (agent_busy.load(.acquire)) {
                // Process any concurrent lines that arrived
                inbox.mutex.lockUncancelable(io);
                while (inbox.lines.items.len > 0) {
                    const cl = inbox.lines.orderedRemove(0);
                    inbox.mutex.unlock(io);
                    defer gpa.free(cl);
                    const t2 = std.mem.trim(u8, cl, " \t\r");
                    if (t2.len == 0) {
                        inbox.mutex.lockUncancelable(io);
                        continue;
                    }
                    var req2 = coding.modes.parseRpcLine(gpa, t2) catch {
                        inbox.mutex.lockUncancelable(io);
                        continue;
                    };
                    defer coding.modes.freeRpcRequest(gpa, &req2);
                    if (std.mem.eql(u8, req2.method, "abort")) {
                        abort_flag = true;
                        coding.modes.writeRpcResponse(io, req2.id, "abort", true, null) catch {};
                    } else if (std.mem.eql(u8, req2.method, "steer")) {
                        const p = req2.params_prompt orelse "";
                        steer_queue.append(gpa, gpa.dupe(u8, p) catch "") catch {};
                        coding.modes.writeRpcResponse(io, req2.id, "steer", true, null) catch {};
                    } else if (std.mem.eql(u8, req2.method, "follow_up")) {
                        const p = req2.params_prompt orelse "";
                        follow_up_queue.append(gpa, gpa.dupe(u8, p) catch "") catch {};
                        coding.modes.writeRpcResponse(io, req2.id, "follow_up", true, null) catch {};
                    } else if (std.mem.eql(u8, req2.method, "ping")) {
                        coding.modes.writeRpcResponse(io, req2.id, "ping", true, "\"pong\"") catch {};
                    } else if (std.mem.eql(u8, req2.method, "quit") or std.mem.eql(u8, req2.method, "exit")) {
                        // Re-queue quit for after busy
                        if (gpa.dupe(u8, cl)) |owned| {
                            inbox.mutex.lockUncancelable(io);
                            inbox.lines.insert(gpa, 0, owned) catch {};
                            inbox.mutex.unlock(io);
                        } else |_| {}
                        // wait for agent then outer loop handles quit
                        while (agent_busy.load(.acquire)) {
                            const st: std.Io.Timeout = .{ .duration = .{ .raw = .fromMilliseconds(20), .clock = .real } };
                            st.sleep(io) catch {};
                        }
                        break;
                    } else {
                        // re-queue for after busy
                        if (gpa.dupe(u8, cl)) |owned| {
                            inbox.mutex.lockUncancelable(io);
                            inbox.lines.append(gpa, owned) catch {};
                            inbox.mutex.unlock(io);
                        } else |_| {}
                    }
                    inbox.mutex.lockUncancelable(io);
                }
                inbox.mutex.unlock(io);
                if (!agent_busy.load(.acquire)) break;
                const st: std.Io.Timeout = .{ .duration = .{ .raw = .fromMilliseconds(20), .clock = .real } };
                st.sleep(io) catch {};
            }
            if (session_path) |sp| {
                if (!no_session) try sess.save(io, sp);
            }
            continue;
        }
        try coding.modes.writeRpcResponse(io, req.id, req.method, false, "{\"error\":\"unknown command\"}");
    }
}

fn formatAvailableModelsJson(arena: std.mem.Allocator) ![]const u8 {
    var aw: std.Io.Writer.Allocating = .init(arena);
    try aw.writer.writeAll("{\"models\":[");
    for (ai.providers.known_models, 0..) |m, i| {
        if (i > 0) try aw.writer.writeAll(",");
        try aw.writer.writeAll("{\"id\":");
        try std.json.Stringify.value(m.id, .{}, &aw.writer);
        try aw.writer.writeAll(",\"provider\":");
        try std.json.Stringify.value(m.provider.name(), .{}, &aw.writer);
        try aw.writer.writeAll(",\"display\":");
        try std.json.Stringify.value(m.display, .{}, &aw.writer);
        try aw.writer.writeAll("}");
    }
    try aw.writer.writeAll("]}");
    return aw.written();
}

fn formatModelDataJson(arena: std.mem.Allocator, provider: ?[]const u8, model: ?[]const u8) ![]const u8 {
    return try std.fmt.allocPrint(arena,
        \\{{"id":{s},"provider":{s}}}
    , .{
        try jsonString(arena, model orelse ""),
        try jsonString(arena, provider orelse ""),
    });
}

fn nextKnownModel(current_id: []const u8) ?ai.providers.ModelInfo {
    const models = ai.providers.known_models;
    var idx: ?usize = null;
    for (models, 0..) |m, i| {
        if (std.mem.eql(u8, m.id, current_id)) {
            idx = i;
            break;
        }
    }
    if (idx) |i| {
        if (models.len <= 1) return null;
        return models[(i + 1) % models.len];
    }
    // Unknown current — start at first
    if (models.len == 0) return null;
    return models[0];
}

fn formatSessionMessagesJson(arena: std.mem.Allocator, sess: *const agent.session.Session) ![]const u8 {
    var aw: std.Io.Writer.Allocating = .init(arena);
    try aw.writer.writeAll("{\"messages\":[");
    for (sess.entries.items, 0..) |e, i| {
        if (i > 0) try aw.writer.writeAll(",");
        try aw.writer.writeAll("{\"role\":");
        try std.json.Stringify.value(e.role, .{}, &aw.writer);
        try aw.writer.writeAll(",\"content\":");
        try std.json.Stringify.value(e.content, .{}, &aw.writer);
        if (e.meta.provider.len > 0) {
            try aw.writer.writeAll(",\"provider\":");
            try std.json.Stringify.value(e.meta.provider, .{}, &aw.writer);
        }
        if (e.meta.model.len > 0) {
            try aw.writer.writeAll(",\"model\":");
            try std.json.Stringify.value(e.meta.model, .{}, &aw.writer);
        }
        if (e.meta.stop_reason.len > 0) {
            try aw.writer.writeAll(",\"stopReason\":");
            try std.json.Stringify.value(e.meta.stop_reason, .{}, &aw.writer);
        }
        try aw.writer.writeAll("}");
    }
    try aw.writer.writeAll("]}");
    return aw.written();
}

fn jsonString(arena: std.mem.Allocator, s: []const u8) ![]const u8 {
    var aw: std.Io.Writer.Allocating = .init(arena);
    try std.json.Stringify.value(s, .{}, &aw.writer);
    return aw.written();
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

/// Monorepo C surfaces: serve, mcp, eval, oauth, theme, index.
fn runSurfaceCommand(
    gpa: std.mem.Allocator,
    io: Io,
    environ: *const std.process.Environ.Map,
    arena: std.mem.Allocator,
    cmd: []const u8,
    cmd_args: []const []const u8,
) !void {
    if (std.mem.eql(u8, cmd, "serve")) {
        var host: []const u8 = "127.0.0.1";
        var port: u16 = 3141;
        var token: []const u8 = "";
        var i: usize = 0;
        while (i < cmd_args.len) : (i += 1) {
            if (std.mem.eql(u8, cmd_args[i], "--port") and i + 1 < cmd_args.len) {
                i += 1;
                port = std.fmt.parseInt(u16, cmd_args[i], 10) catch 3141;
            } else if (std.mem.eql(u8, cmd_args[i], "--host") and i + 1 < cmd_args.len) {
                i += 1;
                host = cmd_args[i];
            } else if (std.mem.eql(u8, cmd_args[i], "--token") and i + 1 < cmd_args.len) {
                i += 1;
                token = cmd_args[i];
            }
        }
        var srv = pi_zig.server.Server{
            .gpa = gpa,
            .io = io,
            .config = .{ .host = host, .port = port, .auth_token = token },
        };
        const msg = try std.fmt.allocPrint(arena, "pi serve listening on http://{s}:{d}/rpc (POST JSON-RPC lines)", .{ host, port });
        try tui.render.printLine(io, msg);
        try srv.serveLoop();
        return;
    }

    if (std.mem.eql(u8, cmd, "mcp")) {
        if (cmd_args.len == 0) {
            try tui.render.printLine(io, "usage: pi mcp <server-command> [args...]");
            std.process.exit(2);
        }
        var client = pi_zig.mcp.McpClient{ .gpa = gpa, .io = io };
        defer client.deinit();
        client.connect(cmd_args) catch |err| {
            const m = try std.fmt.allocPrint(arena, "mcp connect failed: {s}", .{@errorName(err)});
            try tui.render.printLine(io, m);
            std.process.exit(2);
        };
        client.listTools() catch |err| {
            const m = try std.fmt.allocPrint(arena, "mcp tools/list failed: {s}", .{@errorName(err)});
            try tui.render.printLine(io, m);
            std.process.exit(2);
        };
        if (client.tools.items.len == 0) {
            try tui.render.printLine(io, "(no MCP tools reported)");
        } else {
            for (client.tools.items) |t| {
                const line = try std.fmt.allocPrint(arena, "{s}\t{s}", .{ t.name, t.description });
                try tui.render.printLine(io, line);
            }
        }
        return;
    }

    if (std.mem.eql(u8, cmd, "eval")) {
        var script_path: ?[]const u8 = null;
        var expect: []const u8 = "ok";
        var prompt_parts: std.ArrayList([]const u8) = .empty;
        defer prompt_parts.deinit(arena);
        var i: usize = 0;
        while (i < cmd_args.len) : (i += 1) {
            if (std.mem.eql(u8, cmd_args[i], "--script") and i + 1 < cmd_args.len) {
                i += 1;
                script_path = cmd_args[i];
            } else if (std.mem.eql(u8, cmd_args[i], "--expect") and i + 1 < cmd_args.len) {
                i += 1;
                expect = cmd_args[i];
            } else {
                try prompt_parts.append(arena, cmd_args[i]);
            }
        }
        const sp = script_path orelse {
            try tui.render.printLine(io, "usage: pi eval --script mock.json --expect TEXT [prompt]");
            std.process.exit(2);
        };
        const raw = try std.Io.Dir.cwd().readFileAlloc(io, sp, gpa, .limited(4 * 1024 * 1024));
        defer gpa.free(raw);
        const prompt = if (prompt_parts.items.len > 0) try joinMessages(arena, prompt_parts.items) else "eval";
        const cwd = try std.process.currentPathAlloc(io, arena);
        var result = try pi_zig.evals.runCase(gpa, io, cwd, .{
            .name = "cli",
            .prompt = prompt,
            .expect_contains = expect,
        }, raw);
        defer result.deinit(gpa);
        const line = try std.fmt.allocPrint(arena, "eval {s}: {s}", .{ if (result.passed) "PASS" else "FAIL", result.detail });
        try tui.render.printLine(io, line);
        if (!result.passed) std.process.exit(1);
        return;
    }

    if (std.mem.eql(u8, cmd, "oauth")) {
        if (cmd_args.len < 2 or !std.mem.eql(u8, cmd_args[0], "parse-device")) {
            try tui.render.printLine(io, "usage: pi oauth parse-device <json-file>");
            std.process.exit(2);
        }
        const raw = try std.Io.Dir.cwd().readFileAlloc(io, cmd_args[1], gpa, .limited(256 * 1024));
        defer gpa.free(raw);
        var dc = try pi_zig.auth.parseDeviceCodeResponse(gpa, raw);
        defer dc.deinit(gpa);
        const line = try std.fmt.allocPrint(arena, "user_code={s}\nverification_uri={s}\nexpires_in={d}", .{
            dc.user_code, dc.verification_uri, dc.expires_in,
        });
        try tui.render.printLine(io, line);
        return;
    }

    if (std.mem.eql(u8, cmd, "theme")) {
        if (cmd_args.len > 0 and std.mem.eql(u8, cmd_args[0], "list")) {
            const list = try pi_zig.themes.product.listPalettes(gpa);
            defer gpa.free(list);
            try tui.render.writeAll(io, list);
            const sum = try std.fmt.allocPrint(arena, "\n# palette_count={d}\n", .{pi_zig.themes.product.paletteCount()});
            try tui.render.writeAll(io, sum);
            return;
        }
        if (cmd_args.len == 0) {
            try tui.render.printLine(io, "usage: pi theme <theme.json> | pi theme list");
            std.process.exit(2);
        }
        var th = try pi_zig.themes.loadFile(gpa, io, cmd_args[0]);
        defer th.deinit(gpa);
        const sample = try pi_zig.themes.wrap(th.accent_sgr, th.name, arena);
        try tui.render.printLine(io, sample);
        return;
    }

    if (std.mem.eql(u8, cmd, "index")) {
        const cwd = try std.process.currentPathAlloc(io, arena);
        const session_dir = if (cmd_args.len > 0) cmd_args[0] else try config.sessionDirForCwd(arena, environ, cwd, null);
        const index_path = try std.fs.path.join(arena, &.{ session_dir, "index.jsonl" });
        var idx = try pi_zig.storage.SessionIndex.open(gpa, io, index_path);
        defer idx.deinit();
        const sessions = try agent.session.listSessions(gpa, io, session_dir);
        defer {
            for (sessions) |*s| {
                var mut = s.*;
                mut.deinit(gpa);
            }
            gpa.free(sessions);
        }
        for (sessions) |s| {
            try idx.upsert(s.id, s.path, s.id, 0, "");
        }
        try idx.save();
        // Product path: also emit storage schema DDL from all schema shards
        const sql = try pi_zig.storage.product.allCreateSql(gpa);
        defer gpa.free(sql);
        const schema_path = try std.fs.path.join(arena, &.{ session_dir, "schema_all.sql" });
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = schema_path, .data = sql });
        const msg = try std.fmt.allocPrint(arena, "indexed {d} session(s) -> {s}; schema tables={d} -> {s}", .{
            sessions.len, index_path, pi_zig.storage.product.tableCount(), schema_path,
        });
        try tui.render.printLine(io, msg);
        return;
    }

    // --- monorepo product surfaces (consume all package shards) ---
    if (std.mem.eql(u8, cmd, "tui-demo")) {
        const demo = try pi_zig.tui.product.layoutDemo(gpa, 80, 24);
        defer gpa.free(demo);
        try tui.render.writeAll(io, demo);
        const rows = try pi_zig.tui.product.paintDiffSample(gpa, io);
        const sum = try std.fmt.allocPrint(arena, "# tui_widget_shards={d} diff_rows={d}\n", .{ pi_zig.tui.product.widgetShardCount(), rows });
        try tui.render.writeAll(io, sum);
        return;
    }
    if (std.mem.eql(u8, cmd, "skills-list")) {
        const list = try pi_zig.coding_agent.product.listSkills(gpa);
        defer gpa.free(list);
        try tui.render.writeAll(io, list);
        const sum = try std.fmt.allocPrint(arena, "# skill_count={d}\n", .{pi_zig.coding_agent.product.skillCount()});
        try tui.render.writeAll(io, sum);
        return;
    }
    if (std.mem.eql(u8, cmd, "llama-list")) {
        const list = try pi_zig.llama.product.listLocalModels(gpa);
        defer gpa.free(list);
        try tui.render.writeAll(io, list);
        const sum = try std.fmt.allocPrint(arena, "# local_models={d}\n", .{pi_zig.llama.product.modelCount()});
        try tui.render.writeAll(io, sum);
        return;
    }
    if (std.mem.eql(u8, cmd, "routes")) {
        const json = try pi_zig.server.routes_all.listAllRoutesJson(gpa);
        defer gpa.free(json);
        try tui.render.writeAll(io, json);
        const sum = try std.fmt.allocPrint(arena, "\n# route_count={d}\n", .{pi_zig.server.routes_all.routeCount()});
        try tui.render.writeAll(io, sum);
        return;
    }
    if (std.mem.eql(u8, cmd, "ext-list")) {
        const list = try pi_zig.extensions.product.listExtensionNames(gpa);
        defer gpa.free(list);
        try tui.render.writeAll(io, list);
        const sum = try std.fmt.allocPrint(arena, "# extensions={d}\n", .{pi_zig.extensions.product.extensionCount()});
        try tui.render.writeAll(io, sum);
        return;
    }
    if (std.mem.eql(u8, cmd, "schema-sql")) {
        const sql = try pi_zig.storage.product.allCreateSql(gpa);
        defer gpa.free(sql);
        try tui.render.writeAll(io, sql);
        return;
    }
    if (std.mem.eql(u8, cmd, "auth-list")) {
        const list = try pi_zig.auth.product.listProviders(gpa);
        defer gpa.free(list);
        try tui.render.writeAll(io, list);
        return;
    }
    if (std.mem.eql(u8, cmd, "cases")) {
        const list = try pi_zig.evals.product.listCases(gpa);
        defer gpa.free(list);
        try tui.render.writeAll(io, list);
        const sum = try std.fmt.allocPrint(arena, "# cases={d}\n", .{pi_zig.evals.product.totalCases()});
        try tui.render.writeAll(io, sum);
        return;
    }
    if (std.mem.eql(u8, cmd, "protocol-ping")) {
        const env = try pi_zig.protocol.product.encodePing(gpa);
        defer gpa.free(env);
        try tui.render.printLine(io, env);
        const disp = try pi_zig.protocol.product.dispatchAny(gpa, "ext_msg_0_0", "{}");
        if (disp) |d| {
            defer gpa.free(d);
            try tui.render.printLine(io, d);
        }
        const disp2 = try pi_zig.protocol.product.dispatchAny(gpa, "ext_msg_114_0", "{}");
        if (disp2) |d| {
            defer gpa.free(d);
            try tui.render.printLine(io, d);
        }
        return;
    }
    if (std.mem.eql(u8, cmd, "surface")) {
        // One-shot summary that touches every package product facade
        const cat = ai.catalog_index.totalCount();
        const tools_n = agent.tools_extended.totalCount();
        const routes_n = pi_zig.server.routes_all.routeCount();
        const mcp_ok = pi_zig.mcp.methods_all.isKnownMethod("ext/method_14_0");
        const skills_n = pi_zig.coding_agent.product.skillCount();
        const pal_n = pi_zig.themes.product.paletteCount();
        const cases_n = pi_zig.evals.product.totalCases();
        const llama_n = pi_zig.llama.product.modelCount();
        const tables_n = pi_zig.storage.product.tableCount();
        const ext_n = pi_zig.extensions.product.extensionCount();
        const line = try std.fmt.allocPrint(arena,
            \\surface catalog={d} tools={d} routes={d} mcp14={s} skills={d} palettes={d} cases={d} llama={d} tables={d} extensions={d}
        , .{
            cat, tools_n, routes_n, if (mcp_ok) "yes" else "no", skills_n, pal_n, cases_n, llama_n, tables_n, ext_n,
        });
        try tui.render.printLine(io, line);
        return;
    }

    const unknown = try std.fmt.allocPrint(arena, "unknown command: {s}", .{cmd});
    try tui.render.printLine(io, unknown);
    std.process.exit(2);
}

fn listModels(io: Io, query: ?[]const u8) !void {
    // Bootstrap curated list (always first)
    for (ai.providers.known_models) |m| {
        if (query) |q| {
            if (std.mem.indexOf(u8, m.id, q) == null and std.mem.indexOf(u8, m.display, q) == null) continue;
        }
        var buf: [256]u8 = undefined;
        const line = try std.fmt.bufPrint(&buf, "{s}/{s}\t{s}", .{ m.provider.name(), m.id, m.display });
        try tui.render.printLine(io, line);
    }
    // Full monorepo catalog surface (4000 models across catalog shards) — product path
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();
    const listed = try ai.catalog_index.listModels(gpa, query);
    defer gpa.free(listed);
    for (listed) |m| {
        var buf: [512]u8 = undefined;
        const line = try std.fmt.bufPrint(&buf, "{s}\t{s}\tctx={d}\ttools={s}\tfamily={s}", .{
            m.id,
            m.display,
            m.context_window,
            if (m.supports_tools) "yes" else "no",
            m.family,
        });
        try tui.render.printLine(io, line);
    }
    var sum_buf: [128]u8 = undefined;
    const sum = try std.fmt.bufPrint(&sum_buf, "# catalog_total={d} listed={d}", .{ ai.catalog_index.totalCount(), listed.len });
    try tui.render.printLine(io, sum);
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

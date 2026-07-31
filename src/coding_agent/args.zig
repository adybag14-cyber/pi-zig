//! Full CLI arg parse matching upstream flags surface.
const std = @import("std");

pub const Mode = enum { text, json, rpc };

pub const Args = struct {
    help: bool = false,
    version: bool = false,
    print: bool = false,
    mode: Mode = .text,
    provider: ?[]const u8 = null,
    model: ?[]const u8 = null,
    api_key: ?[]const u8 = null,
    base_url: ?[]const u8 = null,
    system_prompt: ?[]const u8 = null,
    append_system_prompt: std.ArrayList([]const u8) = .empty,
    thinking: ?[]const u8 = null,
    continue_session: bool = false,
    resume_session: bool = false,
    name: ?[]const u8 = null,
    no_session: bool = false,
    session: ?[]const u8 = null,
    session_dir: ?[]const u8 = null,
    fork: ?[]const u8 = null,
    tools: ?[]const []const u8 = null,
    exclude_tools: ?[]const []const u8 = null,
    no_tools: bool = false,
    no_builtin_tools: bool = false,
    export_path: ?[]const u8 = null,
    no_skills: bool = false,
    skills: std.ArrayList([]const u8) = .empty,
    prompt_templates: std.ArrayList([]const u8) = .empty,
    no_prompt_templates: bool = false,
    no_context_files: bool = false,
    list_models: bool = false,
    list_models_query: ?[]const u8 = null,
    offline: bool = false,
    verbose: bool = false,
    approve: ?bool = null,
    mock_script: ?[]const u8 = null,
    file_args: std.ArrayList([]const u8) = .empty,
    messages: std.ArrayList([]const u8) = .empty,
    /// Subcommand: install | list | remove | null
    command: ?[]const u8 = null,
    command_args: std.ArrayList([]const u8) = .empty,
};

pub fn parseArgs(arena: std.mem.Allocator, raw_args: []const []const u8) !Args {
    var result: Args = .{};
    // skip argv[0]
    var i: usize = if (raw_args.len > 0) 1 else 0;

    // Detect package / monorepo C subcommands early
    if (i < raw_args.len) {
        const c = raw_args[i];
        if (std.mem.eql(u8, c, "install") or std.mem.eql(u8, c, "list") or
            std.mem.eql(u8, c, "remove") or std.mem.eql(u8, c, "uninstall") or
            std.mem.eql(u8, c, "serve") or std.mem.eql(u8, c, "mcp") or
            std.mem.eql(u8, c, "eval") or std.mem.eql(u8, c, "oauth") or
            std.mem.eql(u8, c, "theme") or std.mem.eql(u8, c, "index") or
            std.mem.eql(u8, c, "surface") or std.mem.eql(u8, c, "tui-demo") or
            std.mem.eql(u8, c, "skills-list") or std.mem.eql(u8, c, "llama-list") or
            std.mem.eql(u8, c, "routes") or std.mem.eql(u8, c, "ext-list") or
            std.mem.eql(u8, c, "schema-sql") or std.mem.eql(u8, c, "auth-list") or
            std.mem.eql(u8, c, "cases") or std.mem.eql(u8, c, "protocol-ping"))
        {
            result.command = c;
            i += 1;
            while (i < raw_args.len) : (i += 1) {
                try result.command_args.append(arena, raw_args[i]);
            }
            return result;
        }
    }

    while (i < raw_args.len) : (i += 1) {
        const arg = raw_args[i];

        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            result.help = true;
        } else if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
            result.version = true;
        } else if (std.mem.eql(u8, arg, "--mode")) {
            i += 1;
            if (i >= raw_args.len) return error.MissingArg;
            if (std.mem.eql(u8, raw_args[i], "text")) result.mode = .text else if (std.mem.eql(u8, raw_args[i], "json")) result.mode = .json else if (std.mem.eql(u8, raw_args[i], "rpc")) result.mode = .rpc;
        } else if (std.mem.eql(u8, arg, "--continue") or std.mem.eql(u8, arg, "-c")) {
            result.continue_session = true;
        } else if (std.mem.eql(u8, arg, "--resume") or std.mem.eql(u8, arg, "-r")) {
            result.resume_session = true;
        } else if (std.mem.eql(u8, arg, "--provider")) {
            i += 1;
            if (i >= raw_args.len) return error.MissingArg;
            result.provider = raw_args[i];
        } else if (std.mem.eql(u8, arg, "--model")) {
            i += 1;
            if (i >= raw_args.len) return error.MissingArg;
            result.model = raw_args[i];
        } else if (std.mem.eql(u8, arg, "--api-key")) {
            i += 1;
            if (i >= raw_args.len) return error.MissingArg;
            result.api_key = raw_args[i];
        } else if (std.mem.eql(u8, arg, "--base-url")) {
            i += 1;
            if (i >= raw_args.len) return error.MissingArg;
            result.base_url = raw_args[i];
        } else if (std.mem.eql(u8, arg, "--system-prompt")) {
            i += 1;
            if (i >= raw_args.len) return error.MissingArg;
            result.system_prompt = raw_args[i];
        } else if (std.mem.eql(u8, arg, "--append-system-prompt")) {
            i += 1;
            if (i >= raw_args.len) return error.MissingArg;
            try result.append_system_prompt.append(arena, raw_args[i]);
        } else if (std.mem.eql(u8, arg, "--name") or std.mem.eql(u8, arg, "-n")) {
            i += 1;
            if (i >= raw_args.len) return error.MissingArg;
            result.name = raw_args[i];
        } else if (std.mem.eql(u8, arg, "--no-session")) {
            result.no_session = true;
        } else if (std.mem.eql(u8, arg, "--session")) {
            i += 1;
            if (i >= raw_args.len) return error.MissingArg;
            result.session = raw_args[i];
        } else if (std.mem.eql(u8, arg, "--session-dir")) {
            i += 1;
            if (i >= raw_args.len) return error.MissingArg;
            result.session_dir = raw_args[i];
        } else if (std.mem.eql(u8, arg, "--fork")) {
            i += 1;
            if (i >= raw_args.len) return error.MissingArg;
            result.fork = raw_args[i];
        } else if (std.mem.eql(u8, arg, "--no-tools") or std.mem.eql(u8, arg, "-nt")) {
            result.no_tools = true;
        } else if (std.mem.eql(u8, arg, "--no-builtin-tools") or std.mem.eql(u8, arg, "-nbt")) {
            result.no_builtin_tools = true;
            result.no_tools = true;
        } else if (std.mem.eql(u8, arg, "--tools") or std.mem.eql(u8, arg, "-t")) {
            i += 1;
            if (i >= raw_args.len) return error.MissingArg;
            result.tools = try splitCsv(arena, raw_args[i]);
        } else if (std.mem.eql(u8, arg, "--exclude-tools") or std.mem.eql(u8, arg, "-xt")) {
            i += 1;
            if (i >= raw_args.len) return error.MissingArg;
            result.exclude_tools = try splitCsv(arena, raw_args[i]);
        } else if (std.mem.eql(u8, arg, "--thinking")) {
            i += 1;
            if (i >= raw_args.len) return error.MissingArg;
            result.thinking = raw_args[i];
        } else if (std.mem.eql(u8, arg, "--print") or std.mem.eql(u8, arg, "-p")) {
            result.print = true;
            // optional next message if not a flag
            if (i + 1 < raw_args.len) {
                const next = raw_args[i + 1];
                if (!std.mem.startsWith(u8, next, "-") and !std.mem.startsWith(u8, next, "@")) {
                    try result.messages.append(arena, next);
                    i += 1;
                }
            }
        } else if (std.mem.eql(u8, arg, "--export")) {
            i += 1;
            if (i >= raw_args.len) return error.MissingArg;
            result.export_path = raw_args[i];
        } else if (std.mem.eql(u8, arg, "--skill")) {
            i += 1;
            if (i >= raw_args.len) return error.MissingArg;
            try result.skills.append(arena, raw_args[i]);
        } else if (std.mem.eql(u8, arg, "--prompt-template")) {
            i += 1;
            if (i >= raw_args.len) return error.MissingArg;
            try result.prompt_templates.append(arena, raw_args[i]);
        } else if (std.mem.eql(u8, arg, "--no-skills") or std.mem.eql(u8, arg, "-ns")) {
            result.no_skills = true;
        } else if (std.mem.eql(u8, arg, "--no-prompt-templates") or std.mem.eql(u8, arg, "-np")) {
            result.no_prompt_templates = true;
        } else if (std.mem.eql(u8, arg, "--no-context-files") or std.mem.eql(u8, arg, "-nc")) {
            result.no_context_files = true;
        } else if (std.mem.eql(u8, arg, "--list-models")) {
            if (i + 1 < raw_args.len and !std.mem.startsWith(u8, raw_args[i + 1], "-") and !std.mem.startsWith(u8, raw_args[i + 1], "@")) {
                result.list_models_query = raw_args[i + 1];
                i += 1;
            }
            result.list_models = true;
        } else if (std.mem.eql(u8, arg, "--verbose")) {
            result.verbose = true;
        } else if (std.mem.eql(u8, arg, "--approve") or std.mem.eql(u8, arg, "-a")) {
            result.approve = true;
        } else if (std.mem.eql(u8, arg, "--no-approve") or std.mem.eql(u8, arg, "-na")) {
            result.approve = false;
        } else if (std.mem.eql(u8, arg, "--offline")) {
            result.offline = true;
        } else if (std.mem.eql(u8, arg, "--mock-script")) {
            i += 1;
            if (i >= raw_args.len) return error.MissingArg;
            result.mock_script = raw_args[i];
        } else if (std.mem.startsWith(u8, arg, "--mock-script=")) {
            result.mock_script = arg["--mock-script=".len..];
        } else if (std.mem.startsWith(u8, arg, "@")) {
            try result.file_args.append(arena, arg[1..]);
        } else if (std.mem.startsWith(u8, arg, "-")) {
            // unknown flag — ignore for forward compat
        } else {
            try result.messages.append(arena, arg);
        }
    }
    return result;
}

fn splitCsv(arena: std.mem.Allocator, s: []const u8) ![]const []const u8 {
    var list: std.ArrayList([]const u8) = .empty;
    var it = std.mem.splitScalar(u8, s, ',');
    while (it.next()) |part| {
        const t = std.mem.trim(u8, part, " \t");
        if (t.len > 0) try list.append(arena, t);
    }
    return try list.toOwnedSlice(arena);
}

pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\pi - AI coding assistant (Zig rewrite of earendil-works/pi)
        \\
        \\Usage:
        \\  pi [options] [@files...] [messages...]
        \\  pi install path:./local-pkg
        \\  pi list | remove <name>
        \\  pi serve [--port N] [--host H] [--token T]
        \\  pi mcp <command...>        Spawn MCP server and list tools
        \\  pi eval --script mock.json --expect TEXT [prompt...]
        \\  pi oauth parse-device <json-file>
        \\  pi theme <theme.json>
        \\  pi index [session-dir]     Rebuild session index store
        \\
        \\Options:
        \\  -h, --help                 Show help
        \\  -v, --version              Show version
        \\  --provider <name>          openai | anthropic | google | mock | groq | ollama | xai | …
        \\  --model <id>               Model id
        \\  --api-key <key>            API key (or env vars)
        \\  --base-url <url>           Provider base URL (openai-compat gateways)
        \\  --system-prompt <text>     Replace system prompt
        \\  --append-system-prompt <t> Append to system prompt (repeatable)
        \\  --mode text|json|rpc       Output mode
        \\  -p, --print                Non-interactive one-shot
        \\  -c, --continue             Continue most recent session
        \\  -r, --resume               List/resume sessions
        \\  --session <path|id>        Session file or id
        \\  --session-dir <dir>        Session storage directory
        \\  --fork <path|id>           Fork session into new file
        \\  --no-session               Do not persist session
        \\  -n, --name <name>          Session name
        \\  -t, --tools <list>         Comma-separated tool allowlist
        \\  -xt, --exclude-tools <l>   Comma-separated exclude list
        \\  -nt, --no-tools            Disable all tools
        \\  -nbt, --no-builtin-tools   Disable built-in tools (same as --no-tools)
        \\  --thinking <level>         off|low|medium|high|xhigh (system + API budgets)
        \\  --export <path.html>       Export session to HTML
        \\  --skill <name>             Enable skill by name (repeatable filter)
        \\  --no-skills                Disable skill discovery
        \\  --prompt-template <name>   Load prompt template
        \\  --no-prompt-templates      Disable prompt templates
        \\  -nc, --no-context-files    Skip AGENTS.md / CLAUDE.md
        \\  --list-models [query]      List known models (40+ catalog)
        \\  --verbose                  Verbose tool output
        \\  --offline                  Require --mock-script / PI_MOCK_SCRIPT
        \\  -a, --approve              Trust project-local .pi resources
        \\  -na, --no-approve          Ignore project-local .pi resources
        \\  --mock-script <file>       Scripted mock model JSON
        \\  @file                      Include file contents in prompt
        \\
        \\Env:
        \\  OPENAI_API_KEY, ANTHROPIC_API_KEY, GOOGLE_API_KEY, GEMINI_API_KEY,
        \\  PI_API_KEY, PI_MODEL, PI_PROVIDER, OPENAI_BASE_URL, PI_MOCK_SCRIPT,
        \\  PI_AGENT_DIR, PI_SESSION_DIR, GROQ_API_KEY, OPENROUTER_API_KEY, XAI_API_KEY
        \\
        \\Interactive slash commands:
        \\  /help /quit /exit /session /new /name /model /compact /export
        \\  /import /fork /clone /tree /reload /hotkeys /changelog /copy
        \\  /login /logout /settings /resume
        \\
    );
}

test "parse print and tools" {
    const arena = std.testing.allocator;
    const raw = [_][]const u8{ "pi", "-p", "--tools", "read,write", "--mock-script", "m.json", "hello" };
    // messages list uses arena appends that need free - use a real arena
    var aimpl: std.heap.ArenaAllocator = .init(arena);
    defer aimpl.deinit();
    const a = aimpl.allocator();
    const args = try parseArgs(a, &raw);
    try std.testing.expect(args.print);
    try std.testing.expectEqualStrings("m.json", args.mock_script.?);
    try std.testing.expect(args.tools != null);
    try std.testing.expectEqual(@as(usize, 2), args.tools.?.len);
    try std.testing.expectEqualStrings("hello", args.messages.items[0]);
}

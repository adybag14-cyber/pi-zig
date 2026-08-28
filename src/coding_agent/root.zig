//! Coding-agent CLI, resources, settings, sessions and modes.
const std = @import("std");
pub const args = @import("args.zig");
pub const context = @import("context.zig");
pub const skills = @import("skills.zig");
pub const prompts = @import("prompts.zig");
pub const path_utils = @import("path_utils.zig");
pub const file_processor = @import("file_processor.zig");
pub const clipboard = @import("clipboard.zig");
pub const inline_files = @import("inline_files.zig");
pub const initial_message = @import("initial_message.zig");
pub const repl_completion = @import("repl_completion.zig");
pub const settings = @import("settings.zig");
pub const update = @import("update.zig");
pub const slash = @import("slash.zig");
pub const live_state = @import("live_state.zig");
pub const model_resolver = @import("model_resolver.zig");
pub const config_value = @import("config_value.zig");
pub const models_file = @import("models_file.zig");
pub const modes = @import("modes.zig");
pub const export_html = @import("export_html.zig");
pub const packages = @import("packages.zig");
pub const package_source = @import("package_source.zig");
pub const package_resources = @import("package_resources.zig");
pub const top_level_resources = @import("top_level_resources.zig");
pub const package_config = @import("package_config.zig");
pub const package_config_tui = @import("package_config_tui.zig");
pub const tree_tui = @import("tree_tui.zig");
pub const model_tui = @import("model_tui.zig");
pub const settings_tui = @import("settings_tui.zig");
pub const session_tui = @import("session_tui.zig");
pub const system_prompt = @import("system_prompt.zig");
pub const project_environment = @import("project_environment.zig");
pub const effective_catalog = @import("effective_catalog.zig");
pub const radius_catalog = @import("radius_catalog.zig");
pub const radius_models_store = @import("radius_models_store.zig");
pub const radius_cached_catalogs = @import("radius_cached_catalogs.zig");
pub const radius_refresh = @import("radius_refresh.zig");
pub const runtime_config = @import("runtime_config.zig");
pub const auth_commands = @import("auth_commands.zig");
pub const auth_tui = @import("auth_tui.zig");
pub const auth_flow_tui = @import("auth_flow_tui.zig");
pub const rpc_data = @import("rpc_data.zig");
pub const rpc_bash = @import("rpc_bash.zig");
pub const rpc_queue = @import("rpc_queue.zig");
pub const remote_transcript = @import("remote_transcript.zig");
pub const remote_session = @import("remote_session.zig");
pub const remote_cli = @import("remote_cli.zig");
pub const session_commands = @import("session_commands.zig");
pub const migrations = @import("migrations.zig");
test {
    std.testing.refAllDecls(@This());
}

pub const trust = @import("trust.zig");

pub const copilot_catalog_filter = @import("copilot_catalog_filter.zig");

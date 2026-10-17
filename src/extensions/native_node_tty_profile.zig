//! Explicit actual frontend profile. No default Engine/worker activation.
//! Callers retain their Bootstrap and obtain the SAME canonical provider/net
//! from canonical.acquire(actual Engine, streams, process). Frontend.install
//! owns the reviewed public/private assembly, event and publication boundary.
const dependencies = @import("native_node_tty_dependencies.zig");
const composition = @import("native_node_tty_frontend_assembly.zig");
pub const Bootstrap = composition.Bootstrap;
pub const canonical = dependencies.canonical;
pub const Frontend = composition.FrontendAssembly(dependencies.Socket, dependencies.Hub, dependencies.Scheduler, dependencies.Wake, dependencies.ClosePool);
pub const Builtins = Frontend.Builtins;

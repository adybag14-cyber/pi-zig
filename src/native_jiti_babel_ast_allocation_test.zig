//! Prepared ownership control only. No allocation baseline or pass is claimed.
//! C parser allocations are outside this GPA test; actual VM allocator/fatal
//! controls and all original30 observations require separate granted execution.
const std=@import("std");
const syntax=@import("extensions/native_jiti_babel_syntax.zig");
const modules=@import("extensions/native_jiti_babel_modules.zig");
const generator=@import("extensions/native_jiti_babel_generator.zig");
fn lifecycle(gpa:std.mem.Allocator)!void{
    const programs=[_] []const u8{
        "import main from './owned.cjs';export default function run(){return main}",
        "import * as ns from './owned.cjs';export const value=ns.value;",
        "export let value=3;",
        "enum Level{Low,High};export const value=Level.High;",
        "@first @factory() export class Decorated{}",
        "using owned=open();export const value=1;",
    };
    for(programs)|input|{
        const prepared=try syntax.prepare(gpa,input,true);defer prepared.deinit(gpa);
        const code=try modules.lower(gpa,prepared.source,.{.typescript=true,.resource=prepared.resource});defer gpa.free(code);
        const formatted=try generator.pretty(gpa,code);defer gpa.free(formatted);
    }
}
test "native Babel AST GPA lifecycle preserves all original failing indices"{
    try std.testing.checkAllAllocationFailures(std.testing.allocator,lifecycle,.{});
}

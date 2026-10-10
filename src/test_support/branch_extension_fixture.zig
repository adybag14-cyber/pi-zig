//! Original user-authored extension input for the branch-policy fixture.
pub const source =
    \\export default function(pi) {
    \\  pi.on("session_before_tree", async (event, ctx) => {
    \\    if (!event.signal || event.signal !== ctx.signal) throw new Error("tree signal identity missing");
    \\    if (event.preparation.userWantsSummary) {
    \\      if (event.preparation.customInstructions !== "focus-166") throw new Error("custom tree focus missing");
    \\      return {
    \\        summary: {
    \\          summary: "extension branch summary 166",
    \\          details: { source: "branch-policy-166", instructions: event.preparation.customInstructions },
    \\          usage: {
    \\            input: 31, output: 32, cacheRead: 33, cacheWrite: 34, totalTokens: 130,
    \\            cost: { input: 0.31, output: 0.32, cacheRead: 0.33, cacheWrite: 0.34, total: 1.30 }
    \\          }
    \\        },
    \\        label: "branch-label-166"
    \\      };
    \\    }
    \\    pi.appendEntry("skip-prompt-tree-166", { userWantsSummary: false });
    \\  });
    \\  pi.on("session_tree", async (event) => {
    \\    pi.appendEntry("after-tree-166", {
    \\      fromExtension: event.fromExtension,
    \\      hasSummary: Boolean(event.summaryEntry)
    \\    });
    \\  });
    \\}
    \\
;

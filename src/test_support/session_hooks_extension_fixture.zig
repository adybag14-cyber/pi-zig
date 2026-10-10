//! Original user-authored input for compaction/cancel/tree lifecycle checks.
pub const source =
    \\export default function(pi) {
    \\  pi.on("session_before_compact", async (event, ctx) => {
    \\    if (event.type !== "session_before_compact") throw new Error("compact event type missing");
    \\    if (!event.signal || event.signal !== ctx.signal) throw new Error("compact signal identity missing");
    \\    if (!Array.isArray(event.branchEntries) || event.branchEntries.length < 8) throw new Error("compact branch incomplete");
    \\    if (!Array.isArray(event.preparation.messagesToSummarize)) throw new Error("compact messages missing");
    \\    if (event.customInstructions === "cancel-164") {
    \\      pi.appendEntry("cancel-compact-164", { reason: event.reason, instructions: event.customInstructions });
    \\      pi.setSessionName("cancel-hooked-164");
    \\      return { cancel: true };
    \\    }
    \\    return {
    \\      compaction: {
    \\        summary: "extension compact summary 164",
    \\        firstKeptEntryId: event.preparation.firstKeptEntryId,
    \\        tokensBefore: event.preparation.tokensBefore,
    \\        details: { source: "extension-164", instructions: event.customInstructions, reason: event.reason },
    \\        usage: {
    \\          input: 11,
    \\          output: 12,
    \\          cacheRead: 13,
    \\          cacheWrite: 14,
    \\          totalTokens: 50,
    \\          cost: { input: 0.11, output: 0.12, cacheRead: 0.13, cacheWrite: 0.14, total: 0.50 }
    \\        }
    \\      }
    \\    };
    \\  });
    \\
    \\  pi.on("session_compact", async (event) => {
    \\    if (event.type !== "session_compact") throw new Error("compact after type missing");
    \\    if (event.compactionEntry.summary !== "extension compact summary 164") throw new Error("compact summary mismatch");
    \\    if (event.fromExtension !== true || event.reason !== "manual" || event.willRetry !== false) throw new Error("compact metadata mismatch");
    \\    pi.appendEntry("after-compact-164", { fromExtension: event.fromExtension, reason: event.reason });
    \\    pi.setSessionName("compact-hooked-164");
    \\  });
    \\
    \\  pi.on("session_before_tree", async (event, ctx) => {
    \\    if (event.type !== "session_before_tree") throw new Error("tree event type missing");
    \\    if (!event.signal || event.signal !== ctx.signal) throw new Error("tree signal identity missing");
    \\    if (event.preparation.userWantsSummary !== true) throw new Error("tree summary flag missing");
    \\    if (!Array.isArray(event.preparation.entriesToSummarize) || event.preparation.entriesToSummarize.length === 0) throw new Error("tree entries missing");
    \\    return {
    \\      summary: {
    \\        summary: "extension tree summary 164",
    \\        details: { source: "tree-extension-164", instructions: event.preparation.customInstructions },
    \\        usage: {
    \\          input: 21,
    \\          output: 22,
    \\          cacheRead: 23,
    \\          cacheWrite: 24,
    \\          totalTokens: 90,
    \\          cost: { input: 0.21, output: 0.22, cacheRead: 0.23, cacheWrite: 0.24, total: 0.90 }
    \\        }
    \\      },
    \\      label: "tree-label-164"
    \\    };
    \\  });
    \\
    \\  pi.on("session_tree", async (event) => {
    \\    if (event.type !== "session_tree") throw new Error("tree after type missing");
    \\    if (!event.summaryEntry || event.summaryEntry.summary !== "extension tree summary 164") throw new Error("tree summary mismatch");
    \\    if (event.fromExtension !== true) throw new Error("tree extension marker missing");
    \\    pi.appendEntry("after-tree-164", { fromExtension: event.fromExtension, oldLeafId: event.oldLeafId });
    \\    pi.setSessionName("tree-hooked-164");
    \\  });
    \\}
    \\
;

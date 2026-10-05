//! User-authored extension input retained from the original behavior fixture.
//! This string is test input; all fixture driving and assertions are Zig.
pub const source =
    \\export default function(pi) {
    \\  pi.on("session_before_compact", async (event, ctx) => {
    \\    const p = event.preparation;
    \\    if (!event.signal || event.signal !== ctx.signal) throw new Error("signal mismatch");
    \\    if (p.settings.enabled !== true || p.settings.reserveTokens !== 123 || p.settings.keepRecentTokens !== 20) {
    \\      throw new Error(`settings mismatch: ${JSON.stringify(p.settings)}`);
    \\    }
    \\    if (p.isSplitTurn !== true) throw new Error(`expected split turn: ${JSON.stringify(p)}`);
    \\    if (!Array.isArray(p.messagesToSummarize) || p.messagesToSummarize.length !== 4) {
    \\      throw new Error(`history mismatch: ${p.messagesToSummarize?.length}`);
    \\    }
    \\    if (!Array.isArray(p.turnPrefixMessages) || p.turnPrefixMessages.length !== 1 || p.turnPrefixMessages[0].role !== "user") {
    \\      throw new Error(`prefix mismatch: ${JSON.stringify(p.turnPrefixMessages)}`);
    \\    }
    \\    if (!p.fileOps || p.fileOps.read.length !== 0 || p.fileOps.written.length !== 0 || p.fileOps.edited.length !== 0) {
    \\      throw new Error(`file ops mismatch: ${JSON.stringify(p.fileOps)}`);
    \\    }
    \\    pi.appendEntry("policy-before-165", {
    \\      messages: p.messagesToSummarize.length,
    \\      prefix: p.turnPrefixMessages.length,
    \\      split: p.isSplitTurn,
    \\      reserveTokens: p.settings.reserveTokens,
    \\      keepRecentTokens: p.settings.keepRecentTokens,
    \\    });
    \\    return { compaction: {
    \\      summary: "token budget summary 165",
    \\      firstKeptEntryId: p.firstKeptEntryId,
    \\      tokensBefore: p.tokensBefore,
    \\      details: {
    \\        splitTurn: p.isSplitTurn,
    \\        summarizedMessages: p.messagesToSummarize.length,
    \\        prefixMessages: p.turnPrefixMessages.length,
    \\        reserveTokens: p.settings.reserveTokens,
    \\        keepRecentTokens: p.settings.keepRecentTokens,
    \\      }
    \\    }};
    \\  });
    \\
    \\  pi.on("session_compact", async (event) => {
    \\    if (event.compactionEntry.summary !== "token budget summary 165" || event.fromExtension !== true) {
    \\      throw new Error("after compact mismatch");
    \\    }
    \\    pi.appendEntry("policy-after-165", { reason: event.reason, fromExtension: event.fromExtension });
    \\    pi.setSessionName("token-budget-165");
    \\  });
    \\}
    \\
;

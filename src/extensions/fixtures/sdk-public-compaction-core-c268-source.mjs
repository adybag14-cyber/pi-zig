// Actual c268 compaction.ts bodies with TypeScript annotations erased.
// The sole imported projection function is the actual captured Source body.
(function (sessionEntryToContextMessages) {
"use strict";
const DEFAULT_COMPACTION_SETTINGS = { enabled: true, reserveTokens: 16384, keepRecentTokens: 20000 };
function calculateContextTokens(usage) {
    return usage.totalTokens || usage.input + usage.output + usage.cacheRead + usage.cacheWrite;
}
function getAssistantUsage(msg) {
    if (msg.role === "assistant" && "usage" in msg) {
        const assistantMsg = msg;
        if (
            assistantMsg.stopReason !== "aborted" &&
            assistantMsg.stopReason !== "error" &&
            assistantMsg.usage &&
            calculateContextTokens(assistantMsg.usage) > 0
        ) {
            return assistantMsg.usage;
        }
    }
    return undefined;
}
function getLastAssistantUsage(entries) {
    for (let i = entries.length - 1; i >= 0; i--) {
        const entry = entries[i];
        if (entry.type === "message") {
            const usage = getAssistantUsage(entry.message);
            if (usage) return usage;
        }
    }
    return undefined;
}
function shouldCompact(contextTokens, contextWindow, settings) {
    if (!settings.enabled) return false;
    return contextTokens > contextWindow - settings.reserveTokens;
}
const ESTIMATED_IMAGE_CHARS = 4800;
function estimateTextAndImageContentChars(content) {
    if (typeof content === "string") {
        return content.length;
    }
    let chars = 0;
    for (const block of content) {
        if (block.type === "text" && block.text) {
            chars += block.text.length;
        } else if (block.type === "image") {
            chars += ESTIMATED_IMAGE_CHARS;
        }
    }
    return chars;
}
function estimateTokens(message) {
    let chars = 0;
    switch (message.role) {
        case "system": {
            const system = message;
            chars = estimateTextAndImageContentChars(system.content);
            if (system.sections) {
                for (const section of Object.values(system.sections)) {
                    if (section) chars += section.length;
                }
            }
            if (system.toolsAdded) chars += JSON.stringify(system.toolsAdded).length;
            return Math.ceil(chars / 4);
        }
        case "user": {
            chars = estimateTextAndImageContentChars(message.content);
            return Math.ceil(chars / 4);
        }
        case "assistant": {
            const assistant = message;
            for (const block of assistant.content) {
                if (block.type === "text") {
                    chars += block.text.length;
                } else if (block.type === "thinking") {
                    chars += block.thinking.length;
                } else if (block.type === "toolCall") {
                    chars += block.name.length + JSON.stringify(block.arguments).length;
                }
            }
            return Math.ceil(chars / 4);
        }
        case "custom":
        case "toolResult": {
            chars = estimateTextAndImageContentChars(message.content);
            return Math.ceil(chars / 4);
        }
        case "bashExecution": {
            chars = message.command.length + message.output.length;
            return Math.ceil(chars / 4);
        }
        case "branchSummary":
        case "compactionSummary": {
            chars = message.summary.length;
            return Math.ceil(chars / 4);
        }
    }
    return 0;
}
function isCutPointMessage(message) {
    switch (message.role) {
        case "user":
        case "assistant":
        case "bashExecution":
        case "custom":
        case "branchSummary":
        case "compactionSummary":
            return true;
        case "toolResult":
            return false;
    }
    return false;
}
function isTurnStartMessage(message) {
    switch (message.role) {
        case "user":
        case "bashExecution":
        case "custom":
        case "branchSummary":
        case "compactionSummary":
            return true;
        case "assistant":
        case "toolResult":
            return false;
    }
    return false;
}
function isTurnStartEntry(entry) {
    if (entry.type === "compaction") {
        return false;
    }
    return sessionEntryToContextMessages(entry).some(isTurnStartMessage);
}
function findValidCutPoints(entries, startIndex, endIndex) {
    const cutPoints = [];
    for (let i = startIndex; i < endIndex; i++) {
        const entry = entries[i];
        if (entry.type === "compaction") {
            continue;
        }
        if (sessionEntryToContextMessages(entry).some(isCutPointMessage)) {
            cutPoints.push(i);
        }
    }
    return cutPoints;
}
function findTurnStartIndex(entries, entryIndex, startIndex) {
    for (let i = entryIndex; i >= startIndex; i--) {
        if (isTurnStartEntry(entries[i])) {
            return i;
        }
    }
    return -1;
}
function findCutPoint(entries, startIndex, endIndex, keepRecentTokens) {
    const cutPoints = findValidCutPoints(entries, startIndex, endIndex);
    if (cutPoints.length === 0) {
        return { firstKeptEntryIndex: startIndex, turnStartIndex: -1, isSplitTurn: false };
    }
    let accumulatedTokens = 0;
    let cutIndex = cutPoints[0];
    for (let i = endIndex - 1; i >= startIndex; i--) {
        const entry = entries[i];
        const messageTokens = sessionEntryToContextMessages(entry).reduce(
            (sum, message) => sum + estimateTokens(message),
            0,
        );
        if (messageTokens === 0) continue;
        accumulatedTokens += messageTokens;
        if (accumulatedTokens >= keepRecentTokens) {
            cutIndex = cutPoints.find((candidate) => candidate >= i) ?? cutPoints[cutPoints.length - 1];
            break;
        }
    }
    while (cutIndex > startIndex) {
        const prevEntry = entries[cutIndex - 1];
        if (prevEntry.type === "compaction" || sessionEntryToContextMessages(prevEntry).length > 0) {
            break;
        }
        cutIndex--;
    }
    const cutEntry = entries[cutIndex];
    const startsTurn = isTurnStartEntry(cutEntry);
    const turnStartIndex = startsTurn ? -1 : findTurnStartIndex(entries, cutIndex, startIndex);
    return {
        firstKeptEntryIndex: cutIndex,
        turnStartIndex,
        isSplitTurn: !startsTurn && turnStartIndex !== -1,
    };
}
return { calculateContextTokens, getLastAssistantUsage, shouldCompact, findTurnStartIndex,
    findCutPoint, estimateTokens, DEFAULT_COMPACTION_SETTINGS };
})

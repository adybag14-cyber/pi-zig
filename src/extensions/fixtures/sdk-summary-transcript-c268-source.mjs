// Exact accepted/c268 normalization bodies; module export keywords removed.
(function(){"use strict";
function createInitialSystemMessage(systemPrompt, tools) {
    const hasSystemPrompt = systemPrompt !== undefined && systemPrompt.length > 0;
    const hasTools = tools !== undefined && tools.length > 0;
    if (!hasSystemPrompt && !hasTools)
        return undefined;
    return {
        role: "system",
        content: systemPrompt ?? "",
        ...(hasTools ? { toolsAdded: tools } : {}),
        timestamp: 0,
    };
}
/**
 * Fold `Context.systemPrompt` and `Context.tools` into a leading system message.
 * This is the only entry point that produces a {@link TranscriptContext}; every
 * provider-facing function expects the result.
 */
function normalizeContext(context) {
    const initialMessage = createInitialSystemMessage(context.systemPrompt, context.tools);
    const messages = initialMessage ? [initialMessage, ...context.messages] : context.messages;
    return { messages };
}
return {createInitialSystemMessage, normalizeContext};
})

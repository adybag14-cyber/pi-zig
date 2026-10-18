// Actual c268 ai/utils/text.ts and compaction/utils.ts selected bodies.
// TypeScript annotations are erased; the imported contentText binding is fixed.
(function () {
"use strict";
function contentText(content, separator = "\n") {
    if (typeof content === "string") return content;
    return content.filter((block) => block.type === "text").map((block) => block.text).join(separator);
}
const TOOL_RESULT_MAX_CHARS = 2000;
function truncateForSummary(text, maxChars) {
    if (text.length <= maxChars) return text;
    const truncatedChars = text.length - maxChars;
    return `${text.slice(0, maxChars)}\n\n[... ${truncatedChars} more characters truncated]`;
}
function serializeConversation(messages) {
    const parts = [];
    for (const msg of messages) {
        if (msg.role === "user") {
            const content = contentText(msg.content, "");
            if (content) parts.push(`[User]: ${content}`);
        } else if (msg.role === "assistant") {
            const toolCalls = [];
            for (const block of msg.content) {
                if (block.type === "toolCall") {
                    const args = block.arguments;
                    const argsStr = Object.entries(args).map(([k, v]) => `${k}=${JSON.stringify(v)}`).join(", ");
                    toolCalls.push(`${block.name}(${argsStr})`);
                }
            }
            if (msg.content.some((block) => block.type === "text")) {
                parts.push(`[Assistant]: ${contentText(msg.content)}`);
            }
            if (toolCalls.length > 0) {
                parts.push(`[Assistant tool calls]: ${toolCalls.join("; ")}`);
            }
        } else if (msg.role === "toolResult") {
            const content = contentText(msg.content, "");
            if (content) {
                parts.push(`[Tool result]: ${truncateForSummary(content, TOOL_RESULT_MAX_CHARS)}`);
            }
        }
    }
    return parts.join("\n\n");
}
function getSummarizationFailure(response, label) {
    if (response.stopReason === "error") {
        return `${label} failed: ${response.errorMessage || "Unknown error"}`;
    }
    if (response.stopReason === "length") {
        return `${label} failed: generation hit the token cap and the summary is incomplete`;
    }
    return undefined;
}
return {contentText,serializeConversation,getSummarizationFailure};
})

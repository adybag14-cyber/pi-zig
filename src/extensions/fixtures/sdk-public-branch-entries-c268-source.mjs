// Exact c268 selected branch bodies and their real private Source helper bodies.
(function () {
"use strict";
function createFileOps() {
	return {
		read: new Set(),
		written: new Set(),
		edited: new Set(),
	};
}

/**
 * Extract file operations from tool calls in an assistant message, or from the nested calls
 * recorded on a tool result.
 */
function extractFileOpsFromMessage(message, fileOps) {
	if (message.role === "toolResult") {
		// Calls made from codemode scripts are recorded on the script's result.
		for (const call of message.nestedCalls?.calls ?? []) addFileOp(call.name, call.arguments, fileOps);
		return;
	}
	if (message.role !== "assistant") return;
	if (!("content" in message) || !Array.isArray(message.content)) return;

	for (const block of message.content) {
		if (typeof block !== "object" || block === null) continue;
		if (!("type" in block) || block.type !== "toolCall") continue;
		if (!("arguments" in block) || !("name" in block)) continue;
		addFileOp(block.name, block.arguments, fileOps);
	}
}

function addFileOp(toolName, args, fileOps) {
	const path = typeof args?.path === "string" ? args.path : undefined;
	if (!path) return;
	switch (toolName) {
		case "read":
			fileOps.read.add(path);
			break;
		case "write":
			fileOps.written.add(path);
			break;
		case "edit":
			fileOps.edited.add(path);
			break;
	}
}

/**
 * Compute final file lists from file operations.
 * Returns readFiles (files only read, not modified) and modifiedFiles.
 */
function computeFileLists(fileOps) {
	const modified = new Set([...fileOps.edited, ...fileOps.written]);
	const readOnly = [...fileOps.read].filter((f) => !modified.has(f)).sort();
	const modifiedFiles = [...modified].sort();
	return { readFiles: readOnly, modifiedFiles };
}

/**
 * Format file operations as XML tags for summary.
 */
function formatFileOperations(readFiles, modifiedFiles) {
	const sections = [];
	if (readFiles.length > 0) {
		sections.push(`<read-files>\n${readFiles.join("\n")}\n</read-files>`);
	}
	if (modifiedFiles.length > 0) {
		sections.push(`<modified-files>\n${modifiedFiles.join("\n")}\n</modified-files>`);
	}
	if (sections.length === 0) return "";
	return `\n\n${sections.join("\n\n")}`;
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

function createBranchSummaryMessage(summary, fromId, timestamp) {
	return {
		role: "branchSummary",
		summary,
		fromId,
		timestamp: new Date(timestamp).getTime(),
	};
}

function createCompactionSummaryMessage(summary, tokensBefore, timestamp) {
	return {
		role: "compactionSummary",
		summary: summary,
		tokensBefore,
		timestamp: new Date(timestamp).getTime(),
	};
}

/** Convert CustomMessageEntry to AgentMessage format */
function createCustomMessage(customType, content, display, details, timestamp) {
	return {
		role: "custom",
		customType,
		content,
		display,
		details,
		timestamp: new Date(timestamp).getTime(),
	};
}
function collectEntriesForBranchSummary(session, oldLeafId, targetId) {
	// If no old position, nothing to summarize
	if (!oldLeafId) {
		return { entries: [], commonAncestorId: null };
	}

	// Find common ancestor (deepest node that's on both paths)
	const oldPath = new Set(session.getBranch(oldLeafId).map((e) => e.id));
	const targetPath = session.getBranch(targetId);

	// targetPath is root-first, so iterate backwards to find deepest common ancestor
	let commonAncestorId = null;
	for (let i = targetPath.length - 1; i >= 0; i--) {
		if (oldPath.has(targetPath[i].id)) {
			commonAncestorId = targetPath[i].id;
			break;
		}
	}

	// Collect entries from old leaf back to common ancestor
	const entries = [];
	let current = oldLeafId;

	while (current && current !== commonAncestorId) {
		const entry = session.getEntry(current);
		if (!entry) break;
		entries.push(entry);
		current = entry.parentId;
	}

	// Reverse to get chronological order
	entries.reverse();

	return { entries, commonAncestorId };
}

// ============================================================================
// Entry to Message Conversion
// ============================================================================

/**
 * Extract AgentMessage from a session entry.
 * Similar to getMessageFromEntry in compaction.ts but also handles compaction entries.
 */
function getMessageFromEntry(entry) {
	switch (entry.type) {
		case "message":
			// Skip tool results - context is in assistant's tool call
			if (entry.message.role === "toolResult") return undefined;
			return entry.message;

		case "custom_message":
			return createCustomMessage(entry.customType, entry.content, entry.display, entry.details, entry.timestamp);

		case "branch_summary":
			return createBranchSummaryMessage(entry.summary, entry.fromId, entry.timestamp);

		case "compaction":
			return createCompactionSummaryMessage(entry.summary, entry.tokensBefore, entry.timestamp);

		// These don't contribute to conversation content
		case "thinking_level_change":
		case "model_change":
		case "custom":
		case "label":
		case "session_info":
			return undefined;
	}
}

/**
 * Prepare entries for summarization with token budget.
 *
 * Walks entries from NEWEST to OLDEST, adding messages until we hit the token budget.
 * This ensures we keep the most recent context when the branch is too long.
 *
 * Also collects file operations from:
 * - Tool calls in assistant messages
 * - Existing branch_summary entries' details (for cumulative tracking)
 *
 * @param entries - Entries in chronological order
 * @param tokenBudget - Maximum tokens to include (0 = no limit)
 */
function prepareBranchEntries(entries, tokenBudget = 0) {
	const messages = [];
	const fileOps = createFileOps();
	let totalTokens = 0;

	// First pass: collect file ops from ALL entries (even if they don't fit in token budget)
	// This ensures we capture cumulative file tracking from nested branch summaries
	// Only extract from pi-generated summaries (fromHook !== true), not extension-generated ones
	for (const entry of entries) {
		if (entry.type === "branch_summary" && !entry.fromHook && entry.details) {
			const details = entry.details;
			if (Array.isArray(details.readFiles)) {
				for (const f of details.readFiles) fileOps.read.add(f);
			}
			if (Array.isArray(details.modifiedFiles)) {
				// Modified files go into both edited and written for proper deduplication
				for (const f of details.modifiedFiles) {
					fileOps.edited.add(f);
				}
			}
		}
	}

	// Second pass: walk from newest to oldest, adding messages until token budget
	for (let i = entries.length - 1; i >= 0; i--) {
		const entry = entries[i];
		const message = getMessageFromEntry(entry);
		if (!message) continue;

		// Extract file ops from assistant messages (tool calls)
		extractFileOpsFromMessage(message, fileOps);

		const tokens = estimateTokens(message);

		// Check budget before adding
		if (tokenBudget > 0 && totalTokens + tokens > tokenBudget) {
			// If this is a summary entry, try to fit it anyway as it's important context
			if (entry.type === "compaction" || entry.type === "branch_summary") {
				if (totalTokens < tokenBudget * 0.9) {
					messages.unshift(message);
					totalTokens += tokens;
				}
			}
			// Stop - we've hit the budget
			break;
		}

		messages.unshift(message);
		totalTokens += tokens;
	}

	return { messages, fileOps, totalTokens };
}
return { collectEntriesForBranchSummary, prepareBranchEntries };
})

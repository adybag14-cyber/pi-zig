// Exact c268 branch constants and generateBranchSummary body; only TypeScript annotations erased.
(function (collectEntriesForBranchSummary, prepareBranchEntries, convertToLlm, serializeConversation, normalizeContext, completeSummarization, getSummarizationFailure, contentText, computeFileLists, formatFileOperations) {
"use strict";
const SUMMARIZATION_SYSTEM_PROMPT = "You are a context summarization assistant. Your task is to read a conversation between a user and an AI assistant, then produce a structured summary following the exact format specified.\n\nDo NOT continue the conversation. Do NOT respond to any questions in the conversation. ONLY output the structured summary.";
const BRANCH_SUMMARY_PREAMBLE = `The user explored a different conversation branch before returning here.
Summary of that exploration:

`;

const BRANCH_SUMMARY_PROMPT = `Create a structured summary of this conversation branch for context when returning later.

Use this EXACT format:

## Goal
[What was the user trying to accomplish in this branch?]

## Constraints & Preferences
- [Any constraints, preferences, or requirements mentioned]
- [Or "(none)" if none were mentioned]

## Progress
### Done
- [x] [Completed tasks/changes]

### In Progress
- [ ] [Work that was started but not finished]

### Blocked
- [Issues preventing progress, if any]

## Key Decisions
- **[Decision]**: [Brief rationale]

## Next Steps
1. [What should happen next to continue this work]

Keep each section concise. Preserve exact file paths, function names, and error messages.`;

async function generateBranchSummary(entries, options) {
	const {
		model,
		apiKey,
		headers,
		env,
		signal,
		customInstructions,
		replaceInstructions,
		reserveTokens = 16384,
		streamFn,
		retry,
		callbacks,
	} = options;

	// Token budget = context window minus reserved space for prompt + response
	const contextWindow = model.contextWindow || 128000;
	const tokenBudget = contextWindow - reserveTokens;

	const { messages, fileOps } = prepareBranchEntries(entries, tokenBudget);

	if (messages.length === 0) {
		return { summary: "No content to summarize" };
	}

	// Transform to LLM-compatible messages, then serialize to text
	// Serialization prevents the model from treating it as a conversation to continue
	const llmMessages = convertToLlm(messages);
	const conversationText = serializeConversation(llmMessages);

	// Build prompt
	let instructions;
	if (replaceInstructions && customInstructions) {
		instructions = customInstructions;
	} else if (customInstructions) {
		instructions = `${BRANCH_SUMMARY_PROMPT}\n\nAdditional focus: ${customInstructions}`;
	} else {
		instructions = BRANCH_SUMMARY_PROMPT;
	}
	const promptText = `<conversation>\n${conversationText}\n</conversation>\n\n${instructions}`;

	const summarizationMessages = [
		{
			role: "user",
			content: [{ type: "text", text: promptText }],
			timestamp: Date.now(),
		},
	];

	// Call LLM for summarization. Prefer the session stream function so SDK
	// request behavior (timeouts, retries, attribution headers) stays consistent
	// without running through agent state/events. Retried via completeSummarization
	// so transient stream drops reuse the configured retry policy.
	const context = normalizeContext({ systemPrompt: SUMMARIZATION_SYSTEM_PROMPT, messages: summarizationMessages });
	const requestOptions = { apiKey, headers, env, signal };
	const response = await completeSummarization(model, context, requestOptions, streamFn, retry, callbacks);

	// Check if aborted or errored
	if (response.stopReason === "aborted") {
		return { aborted: true };
	}
	const failure = getSummarizationFailure(response, "Branch summarization");
	if (failure) {
		return { error: failure };
	}
	if (response.content.some((block) => block.type === "toolCall")) {
		return { error: "Branch summarization attempted to call a tool" };
	}

	let summary = contentText(response.content);

	// Prepend preamble to provide context about the branch summary
	summary = BRANCH_SUMMARY_PREAMBLE + summary;

	// Compute file lists and append to summary
	const { readFiles, modifiedFiles } = computeFileLists(fileOps);
	summary += formatFileOperations(readFiles, modifiedFiles);

	return {
		summary: summary || "No summary generated",
		usage: response.usage,
		readFiles,
		modifiedFiles,
	};
}

return {collectEntriesForBranchSummary,prepareBranchEntries,generateBranchSummary};
})

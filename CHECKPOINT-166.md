# Pi Zig checkpoint 166

Evidence base: the uploaded Pi coding-agent **0.84.1** source, uploaded Zig checkpoint 165, and the supplied native Zig **0.16.0** toolchain.

Checkpoint 166 continues the native rewrite by closing the remaining settings and preparation gap in branch summarization. Branch navigation now uses the active model's context window, the original `branchSummary.reserveTokens` and `branchSummary.skipPrompt` settings, newest-first token selection, cumulative file-operation metadata, the canonical summary prompt, and a real interactive summary-choice flow.

## Original branch-summary settings

The native settings model now parses, independently merges, formats, and transactionally reloads:

```json
{
  "branchSummary": {
    "reserveTokens": 16384,
    "skipPrompt": false
  }
}
```

Camel-case, snake-case, and historical flat aliases are accepted. Effective values propagate through startup, trusted-project settings, `ProjectEnvironment`, the live agent configuration, model switching, slash-command execution, and transactional `/reload`.

`reserveTokens` defaults to **16,384**. `skipPrompt` defaults to **false**.

## Active-model token budget

The old branch-summary byte caps are removed from the production path. Branch preparation now computes:

```text
tokenBudget = activeModel.contextWindow - branchSummary.reserveTokens
```

A model with no declared context window uses the original 128,000-token fallback. Entry selection walks the abandoned branch from newest to oldest, preserving chronological order in the final request and retaining the most recent useful context when the branch exceeds the budget.

The native policy matches the supplied original implementation in these important cases:

- tool-result entries are omitted from the serialized branch material because their context is represented by the assistant tool call;
- compaction and branch-summary entries remain eligible as high-value context;
- a summary that crosses the budget can still be retained when less than 90% of the budget has been used;
- a zero effective budget is treated as no limit, matching the original `prepareBranchEntries(..., 0)` contract;
- file operations are collected before and during newest-first selection, including the first assistant entry that crosses the request budget.

## Cumulative file-operation tracking

Branch summaries now carry deterministic file metadata through repeated navigation.

The implementation extracts:

- `read` paths from native assistant tool calls;
- `written` paths from `write` calls;
- `edited` paths from `edit` calls;
- prior `readFiles` and `modifiedFiles` from Pi-generated nested branch summaries.

Extension-generated summaries are not treated as authoritative cumulative file-operation records. Modified paths are removed from the final read-only list, both lists are sorted, and the resulting metadata is persisted in the durable branch-summary `details` object.

The generated summary also appends the original-style `<read-files>` and `<modified-files>` sections so a later branch summary can preserve file context even when older conversational text falls outside the token budget.

## Canonical model request

The native model-backed branch summarizer now uses:

- the original context-summarization system prompt;
- chronological serialized conversation material;
- the original structured branch-summary prompt;
- optional appended `Additional focus:` instructions;
- complete replacement instructions when explicitly requested;
- the existing settings-driven summarization retry engine and durable usage/cost metadata.

Assistant thinking, assistant text, tool calls, custom messages, bash executions, compaction summaries, and nested branch summaries receive explicit serialized roles rather than being presented as an ordinary conversation that the model might continue.

## Interactive `/tree` summary choice

For plain interactive navigation, `/tree <entryId>` now asks the user to choose:

```text
No summary
Summarize
Custom prompt
Cancel
```

The dialog uses the native line editor when available and retains a plain-input fallback. Choosing a custom prompt collects an additional focus string and passes it through the existing `session_before_tree` extension lifecycle.

When `branchSummary.skipPrompt` is true, the dialog is suppressed and plain `/tree` defaults to navigation without a summary, matching the original setting. Explicit `--summary` remains deterministic for scripts, tests, and RPC-style automation and does not invoke the dialog.

## Preserved extension lifecycle

Checkpoint 166 retains checkpoint 164's native `session_before_tree` and `session_tree` contracts. The richer native preparation is visible to the same extension boundary, and extension replacements continue to preserve:

- `fromHook`;
- structured details;
- usage and cost;
- labels;
- immediate ordered side effects;
- append-only JSONL persistence.

## Real executable validation

A persistent RPC process created four real turns. The same session was then opened through a real pseudo-terminal.

The first interactive navigation verified:

```text
branch_summary_reserve_tokens=77
branch_summary_skip_prompt=false
interactive summary dialog visible
custom focus accepted: focus-166
extension summary persisted
fromHook=true
usage total=130
label=branch-label-166
```

The settings file was then changed to `skipPrompt=true`, and a second pseudo-terminal process reopened the same session. Plain `/tree` navigated without showing the summary dialog and without appending a second branch summary.

```text
RPC exit:                                  0
First interactive exit:                    0
Second interactive exit:                   0
Combined stderr:                           0 bytes
```

## Complete validation

```text
Direct all-package root tests:             894/894 passed
Direct skips/failures:                     0 / 0
Normal module process:                     887 passed, 7 isolated, 0 failed
SQLite repository process:                11/11 passed
SQLite CLI/schema process:                 8 passed, 6 isolated, 0 failed
Ordinary executable process:               9/9 passed
SQLite live-persistence process:           5/5 passed
SQLite-enabled executable process:         9/9 passed
Normal build-test graph:                   passed

Whole-tree Zig formatting:                 passed
Embedded Node bridge syntax:               passed
Python E2E fixture compilation:            passed
Git diff validation:                       passed
Real-source audit:                         passed
Synthetic source files:                    0

Static pi Debug build:                     passed
pi-sqlite Debug build:                     passed
pi-sqlite-live Debug build:                passed
```

The seven module-process isolates are intentional C-linked SQLite cases. Six execute in the dedicated SQLite repository process, and the CLI integration case executes in its dedicated linked process.

## Remaining parity boundary

Checkpoint 166 closes the documented branch-summary reserve-token and skip-prompt gap, replaces byte-size truncation with active-model token budgeting, and adds the real interactive choice path. Complete Pi 0.84.1 monorepo equivalence is still not asserted.

The highest-value remaining areas are:

1. Exact upstream token-estimation and prompt-length clamping nuances, including the branch summary's independent 2,048-token response cap.
2. Full tree progress indicators, cancellation controls, searchable selector, visualization, and retained fullscreen workflow.
3. Retry-policy propagation through OAuth, cloud-credential, catalog-refresh, and update-check bootstrap requests.
4. The complete package, model, login, settings, session, and tree fullscreen managers.
5. Complete npm, pnpm, and Bun workspace, lockfile, lifecycle-script, and platform behavior.
6. Arbitrary extension-owned retained component trees with asynchronous invalidation.
7. Function-valued provider transports and extension-owned OAuth/login callbacks.
8. Native server TLS and mutual TLS.
9. Automatic image resizing, EXIF-orientation normalization, and transcoding.
10. Remaining enterprise credential, telemetry, retry, and cross-language interoperability coverage.

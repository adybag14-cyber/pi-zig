# Pi Zig checkpoint 171

Checkpoint 171 continues the native Zig 0.16.0 rewrite from checkpoint 170 against the supplied original Pi 0.84.1 source. This pass closes the largest remaining ordinary interactive-settings gap: `/settings` is now a retained fullscreen editor whose changes are persisted atomically and applied to the running agent through the transactional reload system.

No generated or synthetic feature shards were added. The implementation consists of ordinary audited Zig source and one real pseudo-terminal Python fixture.

## Native fullscreen `/settings`

Interactive `/settings` now opens a retained alternate-screen selector rather than printing a static diagnostic block.

Implemented behavior includes:

- incremental case-insensitive fuzzy search over setting names, descriptions, native keys, and current values;
- Unicode-cell-safe retained rendering;
- Up, Down, Home, End, Page Up, and Page Down navigation;
- Left and Right value cycling;
- Enter or Space value selection;
- mouse-wheel movement and click selection;
- Escape clearing search before closing;
- Ctrl-C and Ctrl-D cancellation;
- buffered-input handoff from the owning interactive shell;
- deterministic raw-mode, alternate-screen, mouse, paste, cursor, and screen restoration;
- nested fullscreen operation when another retained shell already owns the alternate screen;
- inline persistence errors without discarding selector state.

The editor currently exposes 24 native settings spanning compaction, branch summaries, assistant retry, provider retry, transport deadlines, thinking, themes, delivery queues, startup behavior, tree filtering, telemetry, and project trust.

## Atomic settings transactions

Every selection is persisted immediately through the same advisory configuration lock used by package and resource mutations.

The transaction:

1. acquires the user-scope configuration lock;
2. reads the current global `settings.json`;
3. rejects malformed JSON or incompatible nested shapes rather than replacing them;
4. mutates one canonical upstream field;
5. removes only superseded legacy aliases;
6. preserves unrelated top-level and nested values;
7. writes through an atomic temporary file;
8. synchronizes and replaces the destination;
9. reloads and verifies the exact persisted value.

Canonical nested forms are retained for:

```text
compaction.enabled
compaction.reserveTokens
compaction.keepRecentTokens
branchSummary.reserveTokens
branchSummary.skipPrompt
retry.enabled
retry.maxRetries
retry.baseDelayMs
retry.provider.timeoutMs
retry.provider.maxRetries
retry.provider.maxRetryDelayMs
```

Global settings remain the editable source. Trusted project settings continue acting as read-only higher-precedence overrides, matching the original settings-manager ownership model.

## One transactional live reload

The selector may apply several atomic edits while remaining open. On close, the `/settings` command performs one transactional runtime reload.

That replacement updates the running agent’s:

- compaction and branch-summary policy;
- assistant and provider retry policy;
- provider request timeouts;
- Codex transport;
- default thinking level;
- maximum turn count;
- selected theme and theme registry state;
- active tool settings already handled by reload;
- steering queue mode;
- follow-up queue mode;
- bare `/tree` default filter;
- startup lifecycle settings and formatted `/settings` state.

Malformed replacement state retains the previous live runtime through the existing rollback path.

## Original delivery and interactive policy settings

Checkpoint 171 ports additional original settings that were previously either absent or hard-coded:

```json
{
  "steeringMode": "one-at-a-time" | "all",
  "followUpMode": "one-at-a-time" | "all",
  "quietStartup": true | false,
  "treeFilterMode": "default" | "no-tools" | "user-only" | "labeled-only" | "all"
}
```

They support canonical and snake-case compatibility spellings, independent global/project deep merge, formatted diagnostics, atomic persistence, startup application, and live reload.

The selected tree filter is shared with the existing fullscreen tree selector, so the next bare `/tree` invocation immediately reflects a settings-screen change.

## Startup lifecycle ownership correction

The pseudo-terminal validation exposed a pre-existing shutdown race unrelated to selector rendering: the anonymous install-report request used a detached thread that could outlive runtime-owned state and emit a Zig crash trace during clean process shutdown.

Checkpoint 171 corrects this boundary:

- install-report work is joinable rather than detached;
- its owned context uses process-safe storage;
- normal shutdown waits for bounded report completion;
- explicit `--offline` suppresses both version-check and install-report startup network work;
- environment-level offline behavior remains authoritative.

The real selector fixture now exits with zero stderr bytes, and the existing model/update lifecycle fixture remains green.

## Real executable validation

The final LLVM-backed Debug executable completed a real pseudo-terminal workflow that:

1. opened fullscreen `/settings`;
2. disabled automatic retry;
3. changed assistant retries from 4 to 5;
4. changed steering and follow-up delivery to `all`;
5. changed the default tree filter to `no-tools`;
6. enabled quiet startup;
7. closed the selector and observed one live reload;
8. completed a mock-provider turn;
9. opened bare `/tree` and observed the live `no-tools` filter;
10. restarted Pi and verified the normal startup header was suppressed.

Observed result:

```text
SETTINGS_SCREEN_E2E_171=PASS
fullscreen=True
retryEnabled=False
retryMaxRetries=5
nestedProviderPreserved=True
unrelatedSettingPreserved=True
liveReload=True
steeringMode=all
followUpMode=all
treeFilterMode=no-tools
liveTreeFilter=True
quietStartup=True
terminalRestored=True
exit=0
stderrBytes=0
```

The same final binary also passed the established fullscreen tree-control, model/update/managed-tool, and startup/live-session-resume fixtures with zero child-process stderr.

## Validation summary

```text
Supplied Zig compiler:                     0.16.0
Original Pi source:                        0.84.1
Native Zig source files:                   186
Native Zig logical lines:                  109,279
Named Zig test declarations:               934
Synthetic/generated source files:          0

Direct all-package process:                935/935 passed
Direct skipped/failed:                     0 / 0
Normal module process:                     928 passed / 7 isolated / 0 failed
SQLite repository process:                 11/11 passed
SQLite CLI/schema process:                 8 passed / 6 isolated / 0 failed
Ordinary executable process:               10/10 passed
SQLite live-persistence process:           5/5 passed
SQLite-enabled executable process:         10/10 passed
Build-test graph:                          13/13 steps succeeded

Whole-tree Zig formatting:                 passed
Git diff validation:                       passed
Embedded Node bridge syntax:               passed
Python E2E fixture compilation:             passed
Real-source audit:                         passed
Static pi Debug build:                     passed
pi-sqlite Debug build:                     passed
pi-sqlite-live Debug build:                passed
Settings PTY E2E:                          passed
Tree/model/session regression E2Es:        passed
```

The seven normal module-process isolates are deliberate C-linked SQLite cases. Six pass in the separately linked repository process and the SQLite CLI integration case passes in its dedicated process. The direct root closure explicitly links SQLite and libc and executes every case without skips.

## Remaining parity boundary

Checkpoint 171 materially closes the main fullscreen settings editor, atomic setting persistence, live delivery/tree policy application, quiet startup, and selector-related lifecycle ownership gap. Complete Pi 0.84.1 monorepo equivalence is still not claimed.

The largest remaining areas are:

1. The original settings screen’s remaining image, Markdown/Mermaid, cache-notice, editor, cursor, scrollbar, warning, TUI-mode, and automatic light/dark-theme controls.
2. Project-scope editing and visual indication of effective project overrides in the settings screen.
3. The complete fullscreen package install/update/remove and login/account managers.
4. Complete npm, pnpm, Yarn, and Bun workspace, lockfile, lifecycle-script, global-store, and platform behavior.
5. Arbitrary asynchronously invalidated extension-owned retained component trees.
6. Function-valued extension providers and extension-owned OAuth/login callbacks.
7. Native server TLS and mutual TLS.
8. Automatic image resizing, EXIF-orientation normalization, and transcoding.
9. Remaining enterprise credential, telemetry, update, retry, and cross-language interoperability breadth.

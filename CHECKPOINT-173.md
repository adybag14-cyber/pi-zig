# Pi Zig checkpoint 173

Checkpoint 173 continues the native Zig 0.16.0 rewrite from checkpoint 172 against the newly supplied original Pi 0.84.1 source. This pass closes the largest remaining settings-management gap: the original interactive settings surface is now represented by native typed settings, and the retained selector can edit global or trusted-project scope with explicit inheritance.

No generated or synthetic feature shards were added. The implementation is ordinary Zig source plus one real pseudo-terminal regression fixture.

## Expanded original settings model

The native settings layer now parses, independently deep-merges, formats, atomically persists, verifies, and transactionally reloads the original settings for:

- hidden reasoning blocks;
- prompt-cache miss notices;
- double-Escape action;
- terminal clear-on-shrink and OSC 9;4 progress;
- image auto-resize policy;
- editor and output padding;
- autocomplete row count;
- hardware cursor visibility;
- Markdown Mermaid mode;
- Anthropic extra-usage warning;
- regular/fullscreen TUI mode;
- fullscreen exit-output mode;
- fullscreen scrollbar policy.

Existing compaction, branch summary, retry, provider retry, model/thinking, theme, delivery, transport, media privacy, skill-command, lifecycle, trust and telemetry controls remain in the same selector. The global inventory contains 43 settings; trusted-project scope contains the 41 project-editable settings. Global-only install telemetry and default-project-trust controls are deliberately excluded from project scope.

Compatibility parsing accepts canonical camel-case and historical snake-case forms. Persistence writes the canonical original JSON shape and removes only superseded aliases.

## Trusted-project settings editing

The fullscreen `/settings` selector now supports two scopes:

```text
GLOBAL
PROJECT
```

Tab changes scope when the project is trusted. Project rows visibly distinguish:

```text
inherit → value
explicit value
```

Backspace or Delete with an empty search removes the selected project override, restoring inheritance. Empty nested objects are pruned without disturbing unrelated project configuration.

The entire read/modify/write/verify transaction remains under the existing advisory configuration lock. Malformed JSON or incompatible nested values fail without replacing the original file.

## Correct explicit-default overrides

Checkpoint 173 fixes a subtle deep-merge defect. `maxTurns` previously used its default value as a proxy for absence, which meant a project could not explicitly restore the upstream default of 16 over a global value such as 32.

The parser now retains presence separately from value. This works correctly:

```json
// global
{"maxTurns":32}

// trusted project
{"maxTurns":16}
```

The same explicitness model is used by project-state visualization and override clearing.

## Stable selector identity

Search-result rows are no longer tracked only by their numeric position. Clearing a search or reloading settings preserves the selected `EditableKey` when it remains visible.

This prevents a dangerous mismatch where a user selected one filtered setting, cleared the query, and Backspace/Delete acted on an unrelated row occupying the same index in the full inventory.

## Live behavioral wiring

Checkpoint 173 connects several newly ported controls to the running native shell:

- `terminal.showTerminalProgress` emits and clears OSC 9;4 around live agent work;
- `editorPaddingX` changes the interactive prompt/editor indentation immediately after reload;
- `outputPad` changes native assistant Markdown indentation immediately after reload;
- `terminal.showImages`, `terminal.imageWidthCells`, and hardware-cursor state remain part of the mutable render options;
- `tuiMode` is honored on process startup when no CLI override is present;
- project settings participate in the same transactional `/reload` as global settings.

The broader settings surface is now interoperably parsed, merged, displayed and persisted even where the simplified current Zig REPL does not yet have the original retained component required for complete visual behavior.

## Real pseudo-terminal validation

Two independent real PTY workflows passed against the final Debug executable.

The retained checkpoint-171 regression proves global settings editing, nested retry preservation, live reload, tree-filter application and terminal restoration.

The new project-scope fixture proves:

```text
PROJECT_SETTINGS_E2E_173=PASS
Project scope switching:                   passed
Project override clear and restoration:    passed
Global edit from the same selector:         passed
Explicit project maxTurns=16 over global 32:passed
Terminal progress after reload:             passed
Editor padding after reload:                1
Output padding after reload:                0
Fresh-process project fullscreen mode:      passed
Terminal restoration:                       passed
Combined stderr:                            0 bytes
```

## Validation closure

Completed gates:

```text
Focused settings/TUI/import graph:          165/165 passed
Legacy global settings PTY E2E:             passed
Project/global settings PTY E2E:            passed
Ordinary executable tests observed:         10/10 passed
SQLite repository tests:                    11/11 passed
SQLite CLI/schema process:                   8 passed, 6 intentional isolates
Whole-tree Zig formatting:                  passed
Python fixture compilation:                 passed
Git diff validation:                        passed
Real-source audit:                          passed
Synthetic source files:                     0
Static pi Debug build:                      passed
pi-sqlite Debug build:                      passed
Fresh SQLite init/integrity smoke:          passed
```

A cold direct all-package test artifact and the all-package module process in `zig build test` were attempted with the supplied Zig 0.16.0 compiler. Both exceeded their individual compile deadlines before producing an aggregate result and emitted no compiler diagnostic or failing test. Checkpoint 173 therefore does not claim an aggregate-root pass.

The optional complete `pi-sqlite-live` companion was also attempted with the non-LLVM backend. The deadline interrupted output creation and the incomplete file was rejected rather than published. The static Pi executable and SQLite administration companion are fully rebuilt from checkpoint 173 source.

## Remaining parity boundary

Checkpoint 173 closes native representation and global/project editing for the main original settings surface, plus live behavior for the settings supported by the current direct-rendering shell. Complete Pi 0.84.1 monorepo equivalence is still not claimed.

The largest remaining areas are:

1. Complete runtime behavior for retained-UI-only controls: clear-on-shrink, scrollbar policy, dynamic TUI switching, fullscreen transcript/resume-hint exit, autocomplete menus, cache notices, Mermaid rendering and full thinking-block presentation.
2. Automatic light/dark theme selection and theme preview submenus.
3. Automatic image resizing, EXIF orientation normalization and transcoding.
4. The complete fullscreen package install/update/remove and login/account managers.
5. Complete npm, pnpm, Yarn and Bun workspace, lockfile, lifecycle-script, global-store and platform behavior.
6. Arbitrary asynchronously invalidated extension-owned retained component trees.
7. Function-valued extension providers and extension-owned OAuth/login callbacks.
8. Native server TLS and mutual TLS.
9. Remaining enterprise credential, telemetry, update, retry and cross-language interoperability breadth.

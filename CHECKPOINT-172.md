# Pi Zig checkpoint 172

Checkpoint 172 continues the native Zig 0.16.0 rewrite from checkpoint 171 against the newly supplied original Pi 0.84.1 source. This pass ports the original media privacy/rendering controls and skill-command registration boundary as live, atomically persisted settings rather than display-only configuration.

No generated or synthetic feature shards were added. The implementation consists of ordinary Zig source plus a real loopback-provider/RPC Python fixture.

## Media privacy and rendering settings

The native settings system now parses, independently deep-merges, displays, edits, verifies, and transactionally reloads:

```json
{
  "terminal": {
    "showImages": true,
    "imageWidthCells": 60
  },
  "images": {
    "blockImages": false
  },
  "enableSkillCommands": true
}
```

Compatibility parsing also accepts snake-case spellings and the historical nested `skills.enableSkillCommands` form. Atomic persistence writes the canonical original shape while preserving unrelated settings and removing only superseded aliases.

The fullscreen `/settings` editor now includes:

- **Show images** — controls native and extension-rendered terminal images;
- **Image width** — selects 30, 40, 60, 80, 100, or 120 terminal cells;
- **Block provider images** — keeps images in durable session history but prevents them from reaching model providers;
- **Skill commands** — controls whether discovered skills are exposed as slash commands.

Defaults match the original implementation: images are shown, width is 60 cells, provider images are allowed, and skill commands are enabled.

## Defense-in-depth provider image blocking

`images.blockImages` is enforced at the final provider-context boundary, after extension context transforms and immediately before every model request.

When enabled, the native agent:

1. preserves the append-only session and its original images;
2. creates an owned request-only context projection;
3. removes legacy and ordered image payloads from user, assistant, and tool messages;
4. adds the original `Image reading is disabled.` placeholder where a user/tool message would otherwise become image-only;
5. fails closed if the privacy projection cannot be allocated.

Because filtering occurs after extension transforms, an extension cannot reintroduce an image after the setting has been applied. Image-free requests retain the original slice without allocation.

## Native and extension image rendering

`terminal.showImages` and `terminal.imageWidthCells` now affect the live interactive renderer.

- Native terminal rendering uses the selected image protocol and configured cell width when supported.
- Hidden or unsupported images render an explicit MIME/dimension fallback instead of silently disappearing.
- Extension custom renderers receive the live `showImages` value.
- Runtime reload updates both settings without restarting Pi.
- Legacy first-image fields and additional ordered images are rendered without duplicating the first image.

The privacy and display settings are deliberately separate: `showImages=false` affects local presentation, while `blockImages=true` affects what leaves the process for a model provider.

## Complete skill-command gating

`enableSkillCommands=false` now applies consistently across the native command surface:

- `/skill` and `/skill:*` do not execute or mutate the session;
- `/help` omits the skill-command hint;
- line-editor completion omits the built-in skill command and skill aliases;
- JSONL RPC `get_commands` omits discovered skills;
- live reload updates the RPC and interactive inventories immediately.

Skill resources remain available to project context according to the existing skill-selection policy; this setting controls only their command registration, matching the original Pi boundary.

## Real executable validation

A loopback OpenAI-compatible provider and persistent RPC process validated the final static executable:

```text
MEDIA_SKILL_SETTINGS_E2E_172=PASS
blockedProviderImage=True
blockedPlaceholder=True
blockedDurableImage=True
allowedProviderImage=True
allowedDurableImage=True
skillDisabledHidden=True
skillEnabledAfterReload=True
rpcReload=True
stderrBytes=0
```

The blocked run received no image data at the provider while the exact image MIME/base64 remained in JSONL. The allowed run received the image normally. The persistent RPC process hid the skill command, atomically changed the setting, reloaded, and exposed the skill without restarting.

## Validation closure

Completed source and executable gates:

```text
Agent/AI import graph:                     333/333 passed
Changed coding-agent/settings/TUI graph:   649/649 passed
SQLite repository process:                 11/11 passed
SQLite CLI/schema process:                  8 passed, 6 intentional isolates
Ordinary executable process:               10/10 passed
Focused new tests:                          6/6 passed
Whole-tree Zig formatting:                 passed
Python fixture compilation:                passed
Embedded Node bridge syntax:               passed
Real-source audit:                         passed
Synthetic source files:                    0
Static pi Debug build:                     passed
pi-sqlite Debug build:                     passed
Media/skill executable E2E:                passed
```

The cold monolithic all-package artifact and the complete SQLite-live companion were both attempted repeatedly. Zig 0.16.0 compilation exceeded the individual command deadlines without emitting a source or test failure. Checkpoint 172 therefore does **not** claim a fresh aggregate root pass or publish a mislabeled SQLite-live binary. The ordinary static Pi executable and SQLite administration companion are fully rebuilt from checkpoint 172 source.

## Remaining parity boundary

Checkpoint 172 closes the original media-privacy, terminal image-width/visibility, and skill-command registration settings. Complete Pi 0.84.1 monorepo equivalence is still not claimed.

The largest remaining areas are:

1. The rest of the original settings surface, including Markdown/Mermaid, cache notices, editor/cursor/scrollbar/warning controls, TUI mode, terminal progress, and automatic light/dark themes.
2. Project-scope settings editing and explicit effective-override visualization.
3. Automatic image resizing, EXIF-orientation normalization, and transcoding before provider submission.
4. The complete fullscreen package install/update/remove and login/account managers.
5. Complete npm, pnpm, Yarn, and Bun workspace, lockfile, lifecycle-script, global-store, and platform behavior.
6. Arbitrary asynchronously invalidated extension-owned retained component trees.
7. Function-valued extension providers and extension-owned OAuth/login callbacks.
8. Native server TLS and mutual TLS.
9. Remaining enterprise credential, telemetry, update, retry, and cross-language interoperability breadth.

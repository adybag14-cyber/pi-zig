# Pi 0.84.1 → Zig checkpoint 179 parity audit

## Closed in checkpoint 179

| Original behavior | Zig checkpoint 179 status |
|---|---|
| Provider-owned login screen after provider selection | Implemented as retained `auth_flow_tui` controller |
| Browser authorization link | OSC 8 hyperlink with sanitized visible URL |
| Automatic browser open with manual fallback | Implemented across native browser flows |
| Callback listener progress | Displayed without leaving fullscreen mode |
| Manual redirect/code entry | Available when Codex/Anthropic callback binding falls back to pending flow |
| Device verification URL and code | Retained visibly during polling |
| Login progress and elapsed time | Native spinner plus bounded progress history |
| Cancellation | Escape/Ctrl-C/Ctrl-D/EOF propagate through provider abort flags |
| Provider transport abort normalization | User-facing `Login cancelled.` rather than internal request error |
| Successful token persistence | Existing provider-specific durable credential writers retained |
| Live active-provider rebinding | Existing client-pool completion paths retained |
| Terminal ownership | Raw mode, alternate screen, mouse, paste, cursor, and buffered input restored |
| OpenAI Codex browser/device | Integrated |
| Anthropic browser | Integrated |
| OpenRouter browser | Integrated |
| GitHub Copilot device | Integrated |
| Kimi Coding device | Integrated |
| xAI device | Integrated |
| Radius browser/device/custom provider | Integrated |

## Qualified differences

- The original generic authentication interaction protocol can emit arbitrary provider prompt/select/info events. Checkpoint 179 provides the native UI primitives and covers all built-in flow shapes currently represented in the Zig runtime, but function-valued extension OAuth callbacks are not yet ported.
- Browser callback fallback to in-dialog manual input is available for Codex and Anthropic pending flows. OpenRouter and Radius still require a callback listener because their current native flow objects do not retain an equivalent independently completable pending state.
- Device polling displays elapsed time and progress, but provider modules do not yet expose every intermediate poll status as a structured UI event.

## Validation evidence

```text
Authentication/import graph:               102/102 passed
Login-filtered graph:                      19/19 passed
Executable tests:                         10/10 passed
SQLite repository tests:                  11/11 passed
SQLite CLI/schema:                         8 passed, 6 intentional isolates
Browser callback PTY:                     passed
Device cancellation PTY:                  passed
Staged selector regression:               passed
Live credential rebind regression:        passed
Combined child-process stderr:             0 bytes
Synthetic source files:                    0
```

## Highest-value remaining areas

1. Function-valued extension providers and extension-owned OAuth callbacks.
2. Generic provider prompt/select/manual-code event plumbing beyond built-in flows.
3. Fullscreen package and broader account administration.
4. Complete package-manager platform behavior.
5. Asynchronously invalidated extension component trees.
6. Native TLS/mTLS server transport.
7. Embedded image transformation.
8. Enterprise authentication and interoperability edge cases.

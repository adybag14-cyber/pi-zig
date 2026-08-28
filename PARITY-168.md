# Pi 0.84.1 → native Zig parity audit — checkpoint 168

Checkpoint 168 was compared directly with the uploaded Pi 0.84.1 source, especially:

- `packages/coding-agent/src/utils/management-http.ts`;
- OAuth implementations under `packages/ai/src/auth/oauth`;
- Radius configuration under `packages/ai/src/providers/radius-config.ts`;
- Google and AWS credential resolution under `packages/ai/src`;
- `packages/coding-agent/src/modes/interactive/components/tree-selector.ts`;
- native provider retry and proxy behavior already present in checkpoint 167.

## Closed in checkpoint 168

### Shared management/bootstrap networking

OAuth, credential, and catalog requests no longer maintain unrelated direct-fetch loops. A common native request path applies bounded retries, timeout, cancellation, response retry headers, response-size limits, proxy selection, and `NO_PROXY` matching.

### OAuth refresh and login propagation

OpenAI Codex, Anthropic, OpenRouter, Radius, xAI, Kimi Coding, and GitHub Copilot flows consume the same effective live policy in interactive, device, refresh, reload, and noninteractive auth-check paths.

### Cloud bootstrap propagation

Google ADC and AWS web-identity, STS, ECS/container, and IMDS credential requests consume the same bounded retry/deadline/cancellation contract. Metadata requests intentionally bypass user proxy configuration.

### Dynamic catalog propagation

Radius gateway configuration and GitHub Copilot catalog/policy requests now use the shared bootstrap policy rather than independent HTTP clients.

### Fuller original tree controls

The fullscreen session-tree selector gains original-style wrapped movement, search-clearing Escape, direct and reverse filters, label editing and timestamps, OSC 52 copy, mouse selection/scrolling, and hit-target wheel dispatch.

### Compact-context estimation

Tool schemas now use canonical compact JSON for token estimates, and assistant tool-call accounting excludes transport-only wrapper metadata. Compaction and active-context estimation share the same implementation.

## Real executable evidence

The ordinary `pi auth check` path demonstrated:

- HTTP 503 retry with `Retry-After-Ms` followed by success;
- atomic persistence of refreshed access and refresh tokens;
- explicit retry denial from `X-Should-Retry:false`;
- provider timeout pre-emption;
- settings-proxy absolute-form routing to a fake target host;
- `NO_PROXY` bypass of a configured trap proxy;
- zero stderr.

Two real pseudo-terminal runs confirmed both retained provider-backed branch navigation and the newly ported controls. The control run created a durable label, copied the selected assistant text through OSC 52, displayed label timestamps, switched to labeled-only filtering, exited cleanly, and produced zero stderr.

## Retained parity from earlier checkpoints

Checkpoint 168 preserves:

- append-only sessions, compaction, branch summaries, retry history, labels, usage, and cost;
- token-budget summarization and request-local no-cache summary calls;
- JavaScript/TypeScript extension execution, ordered actions, UI requests, custom renderers, providers, tools, packages, and live reload;
- package/resource management and trusted project scopes;
- native model transports, provider retry, proxying, remote protocol, SQLite companions, and retained TUI primitives;
- rich multimodal messages, terminal images, Markdown/LaTeX, Unicode cells, and terminal input protocols.

## Remaining highest-value gaps

1. Remaining update/report/download management traffic and its UI lifecycle.
2. Provider-specific enterprise OAuth/cloud/catalog edge cases not represented by the implemented native flows.
3. Complete original tree connector grammar, mouse actions, progress/cancellation, and help/edit overlays.
4. Remaining fullscreen package/model/login/settings/session managers.
5. Full npm/pnpm/Bun workspace, lifecycle, lockfile, and platform parity.
6. Arbitrary asynchronously invalidated extension component trees.
7. Function-valued extension providers and extension-owned OAuth/login callbacks.
8. Native server TLS and mutual TLS.
9. Automatic image normalization, resizing, orientation correction, and transcoding.
10. Enterprise credential, telemetry, update, retry, and cross-language interoperability breadth.

## Validation summary

```text
Direct exact-source root:                  913/913 passed
Normal module process:                     906 pass / 7 isolated / 0 fail
Build graph:                               13/13 succeeded
SQLite repository:                         11/11 passed
SQLite CLI/schema:                         8 pass / 6 isolated / 0 fail
Ordinary executable:                       9/9 passed
SQLite persistence:                        5/5 passed
SQLite-enabled executable:                 9/9 passed
Bootstrap-network executable E2E:          passed
Fullscreen-tree provider/PTY E2E:          passed
Tree controls PTY E2E:                     passed
Synthetic source files:                    0
```

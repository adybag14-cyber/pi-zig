# Native durable Registry, agent resolution and context

Source authority: Pi `1cedd32724abfcb0915f76cc61b6827e2c16dbad`, durable 1.1.0. The later reviewed `6fb2e7815167e6b19006fc526d1a5d0f5f998787` has no durable/Chord/environment source changes. The built original reference is external to this repository; fixture JavaScript is user input evaluated through QuickJS, while host behavior is implemented in Zig.

Implemented in this additive layer:

- Registry immutable publication snapshots, identity-preserving extension/tool/schema/task references, atomic candidate validation, replacement order, subscriptions and unsubscribe booleans. `createRegistry` remains withheld from public exports until all three real built-in workflows exist. Tests injecting built-in tokens are core publication tests; custom caller-registry fixtures execute actual custom tasks and do not qualify built-in workflows.
- Public identity helpers `defineExtension`, `defineTool`, `section`, `hook`, `wrapTool` and `wrapSection`.
- `AgentDoc`, `configure`, Conversation `configure`/`agent`, Harness `resolveAgent`, extension selection/filter ordering, tool/section composition, bound wrappers, failed/renamed target removal and reporting. Agent document changes stay rewindable through forks.
- Runtime `settings`, including mutable exported default policies, undefined merge behavior and passive access after an invocation ends. Runtime `agent` resolves once per phase using its admitted registry snapshot, with independently cancellable waits.
- Runtime hooks iterate selected handlers in extension order, bind each receiver, await user callbacks, report original failures, and propagate failures when aborted. Runtime environment construction uses committed `cwd`, the original call context, and the Harness read interface.
- Conversation and Runtime context derivation: committed cutoffs and fork visibility, newest head selection, edits, excluded assistant stop reasons, system-leading order, call-ordered tool results, synthetic missing results and source-specific freezing. Runtime cached views preserve nested entry/message/contribution identity through unchanged or appended ranges and rebuild contributions for edits/backward reads. Idle cache expiry is checked by the native owner pump after workers release the Session line; no JavaScript timer or host runtime is required.
- Document checkpoint predicates locate their final write by document identity after Harness write ordering, rather than a stale write index.

The source captures and expected transcripts are in the external evidence folder `pi-zig-update-evidence-20261003/env-completion-20261007`, named `durable-registry-agent-resolution-1ced-source-capture.mjs`, `durable-runtime-hooks-env-1ced-source-capture.mjs`, and `durable-context-view-1ced-source-capture.mjs`. Allocation-failure tests cover Registry admission and context derivation/shared values/freeze.

Remaining full durable work includes real executable Generation/Tool/Compaction workflows and public Registry construction; submission/conversation lifecycle conveniences; generic caller storage and Cloudflare executors; broader Chord behavior; and the remaining source error/crash/recovery matrix. This layer does not claim complete durable parity.

Builds use vendored static SQLite by default. An explicit `-Dsqlite-lib-dir` is an opt-in external-library path, and can create a dynamic dependency. Validation of this layer omits that flag; the Windows PE import audit confirms no `sqlite3.dll` import.

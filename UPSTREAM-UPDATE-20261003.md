# Active Pi upstream update

Status: in progress. This file does not certify parity or a release.

- Working branch: `update/pi-upstream-20261003`, based on pi-zig main
  `012e80ced763e8d8ac7e01f7331d32dad3ab468b`.
- Previous Pi baseline: `853a80d26c90a14c1886f0ebb8ffaae133ca2185`, version 0.84.4.
- Selected authority: earendil-works/pi main
  `4c6fb7cfe8c538a668726f6f8b3554098c39faee`, package version 1.0.1.
  It descends from and is newer than published GitHub release v1.0.0.
- Delta: 882 commits, including new model types/classifiers, codemode, MCP
  configuration/OAuth, providers/auth, agent-loop hooks, terminal behavior,
  and extraction of durable harness APIs into pi-durable.
- User-required toolchain: final Zig 0.16.0. No implicit upgrade.
- User-required implementation: Zig; direct C interoperability allowed.
  Retain upstream user-authored JavaScript/TypeScript extension compatibility
  through a directly linked C runtime, with native Zig host/bridge behavior.
- Official Windows Zig archive SHA-256:
  `68659eb5f1e4eb1437a722f1dd889c5a322c9954607f5edcf337bc3684a75a7e`.
- Upstream-pinned typed model catalog revision:
  `sha256-d28b6de6985826060b6e2ccf589d16800d9fdbc40681ae4c698421c92d2ff86f`.
  Its fetched bytes match the hash. 1,601 models, 42 providers; chat, image,
  and classifier operations.

Completed evidence:

- Unmodified Windows Debug build and full test graph pass with Zig 0.16.0
  and the existing SQLite 3.53.4 native library.
- Pinned minimal QuickJS-NG C sources at v0.17.0 /
  `6d46d07d04041b40f4f49eaa7fdebe44c314c699`, with license and file hashes.
- Added native Zig engine ownership, memory/stack limits, interruption,
  cancellation, promise jobs, exception handling, relative module loading and
  top-level await and native Zig callbacks. Seven dedicated engine tests pass
  through the direct C ABI with no Node process.
- Added C-parser-backed Zig transformation for erasable TypeScript input.
  Numeric/string enums and ordinary constructor parameter properties are also
  lowered with runtime behavior checked in the C engine. Six transformer tests
  plus the seven engine tests pass. Unsupported namespaces, decorators and
  uncommon parameter-property/super control flow remain explicit errors;
  the existing Node runtime has not been replaced yet.
- Full linked-C Windows Debug build and existing regression graph pass:
  21/21 aggregate steps; 1,035 module passes, 27 existing skips, zero failures;
  dedicated SQLite and executable roots pass; seven engine tests and thirteen
  combined engine/transformer tests pass.
- Native maintenance audit recognizes forbidden implementation languages and
  synthetic surfaces. Native vendor verification checks 107 pinned files with
  zero digest failures. The language audit remains expected to fail until the
  old bridge and scripts have been ported; no exemption hides those files.
- Native-foundation draft PR #1 passes hosted Windows, Ubuntu and macOS CI.
- Added model operation types with omitted-type chat compatibility, explicit
  unknown-type rejection, per-operation identity and chat-only legacy selectors.
- Added native System One request/answer projection and HTTP client: bool/noul,
  choice/score, direct and Completed Cloudflare envelopes, priced usage retained
  on malformed answers, owned response strings, case-insensitive header
  overrides/null suppression, aborts and provider retry policy. This does not
  yet certify classifier integration into the full model registry/codemode.
- Ported Pi 1's fullscreen default (explicit regular mode retained), leading
  whitespace slash completion and explicit-provider/model validation.
- The latest Windows regression graph passes after these operation/CLI changes.

Required outstanding work:

1. Native extension module loader and TypeScript input erasure, host bindings,
   persistent worker protocol, provider callbacks, UI/renderers, and adversarial
   lifecycle coverage. Replace the Node bridge only after compatibility passes.
2. Native Zig catalog importer/generator, typed model lookup, classifier/image
   operation routing, provider transports, auth and metadata changes.
3. Latest agent-loop hooks, durable APIs, MCP configuration/transports/OAuth,
   codemode and its bounded output/store/model/tool APIs.
4. Terminal, settings, selectors, completion, clipboard/image and render deltas.
5. Port Python and JavaScript repository tooling/fixtures to Zig and add an
   enforceable implementation-language audit without dropping behavior.
6. Full local regression graph, offline process/PTY/protocol gates, Windows /
   Linux / macOS CI, exact upstream coverage audit, version/provenance update,
   GitHub publication and terminal release verification.

Local task evidence is outside the repository at
`C:\Users\adyba\pi-zig-update-evidence-20261003`. Task process records include
PID, start time, executable, command line, exit status and separate output logs.

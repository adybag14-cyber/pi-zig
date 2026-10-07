# Active Pi upstream update

Status: in progress. This file does not certify parity or a release.

Checkpoint 198 reviews upstream `7fb59f995b0a1db552001a8577b234e4105d7179`
(Pi 1.0.4). The immutable catalog revision contains 1,631 models across
42 providers. The native AI update includes Decisions classifiers and images,
3.5-character UTF-16 context estimation, Bedrock GPT thinking profiles,
Mistral server diagnostics, and caller-overridable Codex application headers.

Native extension registrations now carry ordered registration and SDK selection
events. Owned activation state, model schemas, and acknowledgements commit
after allocation succeeds. Actual no-Node CLI cases cover defaults, exact
positive/negative selectors, caller order, hidden/deferred tools, and late
false/true/false replacements. Raw-provider fixtures validate and consume
unsolicited metadata records. Retained widgets preserve component ownership,
current geometry, replacement/disposal behavior, and original text wrapping.

The environment candidate includes remote capability adapters, concurrent file
workers with ordered writes, native Linux watches, portable polling, reconnect,
and owned local/remote FileSystem and ExecutionEnv bindings. A watch teardown
use-after-free is repaired and proved by a negative control and ordinary RPCs
after close. Tool execution duration is measured monotonically and preserved
through events, JSONL reload, cloning, and forks. The original source reproduces
DrvFS rename behavior; tests separately measure retained handles and path reads.

Four complete Debug/ReleaseSafe Windows/Linux graphs passed on 619 unchanged
compiled inputs. `verification/checkpoint-198` records exact receipts, source
hashes, and slice limits. Hosted macOS results remain separate. Production still
defaults to the legacy runtime; the JS host and native release guard remain
until complete SDK/UI/durable/MCP/codemode parity and final distribution checks.

The current environment candidate adds a native protocol-v1 daemon/client,
retained file handles, priority control replies, ordered command output,
heartbeat/session fencing and strict-key SSH deployment helpers. Independent
original-daemon captures cover retained reads/writes, cancellation, active
disconnect and detached Windows background lifetime. Actual private loopback
SSH proves detection, verified upload/start and unknown/changed key rejection.
`src/env/CONTRACT.md` records remaining worker-pool, watch, remote adapter and
distribution gaps. The daemon version follows the validated catalog pin.

The current composed candidate also admits first-registration tool catalogs,
collision-safe command aliases, native MCP stdio/HTTP/SSE session APIs and the
native `McpClient`/explicit `pi mcp --url` utility adapter. Persistent native
Editor/CustomEditor factories now own fullscreen editor rows, raw input,
submission, focus/modal handoff and draft restoration. Captured UI capabilities
retain their original owner lifetime across unrelated headless invocations.
The original modal-editor extension is stored as exact Zig string input with
a SHA-256 assertion; no standalone TypeScript implementation/fixture is added.
Native failure envelopes retain authoritative actions admitted before a throw,
and daemon client waits handle spurious timed-event wakes with fixed deadlines.
Final composed validation remains separate from each increment's focused proof.

- Working branch: `update/pi-upstream-20261003`, based on pi-zig main
  `012e80ced763e8d8ac7e01f7331d32dad3ab468b`.
- Previous Pi baseline: `853a80d26c90a14c1886f0ebb8ffaae133ca2185`, version 0.84.4.
- Selected authority: earendil-works/pi main
  `28dcce2ba45ce4a9efeb0f5b686f0be830fd89b9`, package version 1.0.4.
  It descends from and is newer than published GitHub release v1.0.3.
- Delta: 939 commits, including new model types/classifiers, codemode, MCP
  configuration/OAuth, providers/auth, agent-loop hooks, terminal behavior,
  and extraction of durable harness APIs into pi-durable.
  The refresh from initial target `4c6fb7cf` adds exactly one Nix workflow
  history-fetch fix and changes no runtime/package/catalog sources.
- The October 4 refresh to `20038712` adds five commits and published v1.0.2.
  Runtime changes are per-thinking-level sampling parameters and durable
  provider-session identity persistence; release/package versions also advance.
  Those runtime contracts are being reviewed and are not yet parity-certified.
- The evening refresh to `f5d20047` adds five more commits: cancellation-safe
  persistence of rotated OAuth tokens, Windows durable environment fixes, and
  bounded binary/directory readers and argv execution with stream information.
  These additional contracts remain tracked for native implementation.
- The later refresh to `1b094148` adds codemode survival after an install is
  updated or removed. Native codemode integration remains an outstanding port.
- The refresh to `1965a806` adds nine commits: durable filesystem watches,
  Windows polling/rename behavior and macOS startup handling, line scanning,
  windowed shell output with counted skips, progress intervals, and codemode
  image output to temporary files. These new runtime contracts remain pending.
- The latest refresh to `b2b5c42f` adds dead-terminal stdin handling and the
  corrected codemode MCP saved-image test expectation. The terminal change is
  being validated natively; codemode saved-image integration remains pending.
- The `6100fe5a` refresh adds canonical Azure/Foundry provider contracts
  and Home/End ownership changes. Native Azure transport/alias and Application
  component gates are implemented. Complete CLI fullscreen frontend wiring
  remains a separate pending integration.
- The October 5 midday refresh to `b78e6a90` adds eight commits, including
  published v1.0.3, a new catalog pin, multiline syntax-token colors, and
  pi-env SSH execution environments with verified packaged daemons. These
  additional contracts are tracked for native implementation; this refresh
  does not certify parity. The old6100 reference remains intact for prior gates.
- Current upstream source tar SHA-256:
  `a11ca75ccca5a5e5a359afc5b32102545c27709052e3a1e7643c14cb52c219bb`.
- User-required toolchain: final Zig 0.16.0. No implicit upgrade.
- User-required implementation: Zig; direct C interoperability allowed.
  Retain upstream user-authored JavaScript/TypeScript extension compatibility
  through a directly linked C runtime, with native Zig host/bridge behavior.
- Official Windows Zig archive SHA-256:
  `68659eb5f1e4eb1437a722f1dd889c5a322c9954607f5edcf337bc3684a75a7e`.
- Upstream-pinned typed model catalog revision:
  `sha256-c5d5070c7592ca8e27743e892a7eec1d6c883be8034f888735238cdfdb3ab70f`.
  Its fetched bytes match the hash. 1,621 models, 42 providers; 1,539 chat,59 image,
  and23 classifier operations. Native archive/package/catalog import and
  generated-catalog verification pass for this new pin.

Fresh integrated 6100 checkpoint validation:

- The final Azure/UI sources were frozen before validation. All 376 compilation
  and runtime-data inputs have the same before/after SHA-256 aggregate:
  `76c302ef5795f6ae3e1c0adf6b286b44e26185c7939286d9dc2b3843ab77c927`.
- The exact Windows graph `build test test-provider-contracts -j2 --summary all`
  passes 69/69 steps, 385 dedicated tests and five skips. The primary module
  runner passes 1,117 tests with 28 skips; failures are zero.
- Windows ReleaseSafe passes all seven build steps. An executable-only PATH,
  isolated agent/home/workspace and offline mock CLI run returns the expected
  result with zero stderr, without touching the user's installation or history.
- A fresh x64 Linux GNU ReleaseSafe candidate is built from those same inputs.
  Authentication screen (3 tests), OAuth dialog (5), bootstrap networking (5,
  including all five scenarios), and provider retry (7, including all seven
  scenarios and real RPC reload) pass through owned Ubuntu/PTY/pipe processes
  against that candidate and a freshly compiled native browser opener.
- Formatting, byte-exact catalog regeneration, all 107 pinned vendor digests and
  structural auditing pass. The language audit still rejects exactly 15 Python
  and five JavaScript files. One bytecode file created by the external baseline
  adapter was removed by its exact owned path; the audit itself was not weakened.
- Native `verify-release` rejects `IncompleteParityCheckpoint` as expected.
  Parity remains false and production discovery still uses the legacy backend.
- Fresh evidence is appended in
  `verification/checkpoint-189/checkpoint-6100-integration-20261005.json` and the
  three `checkpoint-6100-*-20261005.json` process reports. Earlier records remain
  immutable. Historical Windows/Linux/macOS CI passes published `c24fa85`
  (run 37240154150); it is not proof for this newer checkpoint.

Current b78e6a90 integration checkpoint:

- Pi1.0.3 catalog/changelog source is verified from the immutable archive and
  typed revision. Counts are1,539 chat,59 image and23 classifier models across
  42 providers. Catalog tests now compare the generated rows, identities,
  operation counts and provenance against source data instead of hardcoding a
  previous release's counts.
- The complete Debug graph passes105/105 steps on both Windows and Linux.
  Windows has459 dedicated passes and26 skips, plus1,148 primary-module passes
  and28 skips. Linux has625/625 dedicated passes, plus1,168 module passes and
  eight skips. All416 compilation/data inputs match the native Linux snapshot
  byte for byte. The same complete105-step graph also passes ReleaseSafe on
  both platforms, with the same pass/skip counts. Linux explicitly targets the
  host SQLite library's glibc2.35 ABI; generic older-ABI link failures are
  retained as environment evidence.
- Fifteen additional Python executable fixtures are replaced by Zig drivers,
  retaining their original behavior gates and independently captured baseline
  reports. Together with the four earlier replacements, this yields nineteen
  native CLI process fixtures. Native helper executables replace shell test
  stand-ins for browser opening, clipboard operations, package-manager calls
  and managed-tool execution. No Python scripts remain; five legacy JavaScript
  files still fail the strict language audit.
- Native EventStream/provider-stream ownership and ACK/cancel/replacement
  controls have real no-Node process proof. Native URL/URLSearchParams and
  strongly branded filesystem/CommonJS consumers have captured Node and
  allocation/GC evidence. URL IDN contextual/bidi tables remain incomplete;
  one Node24 hostless-pathname inconsistency is documented explicitly.
- The optimized TypeScript scanner now inherits an explicit create(void)
  prototype through a narrowly reviewed native ABI header. Optimization and
  function sanitization remain enabled; pinned vendor bytes are unchanged.
- The persistent Linux fullscreen frontend is exercised through actual PTY
  cells: branch history, streamed frames, anchors, editor ownership, key
  routing, modal handoff, reload, resize, abort/reuse and dead-terminal behavior.
  Startup and live editor padding now affect wrapping and cursor placement.
  Windows/macOS persistent frontend and native custom scenes remain separate
  integration work; component-only checks do not certify those platforms.
- Mandatory concurrency and cleanup replace owner-dependent eager async work
  in callback, reader, timeout/abort, tool-queue and mirror paths. One-CPU and
  unavailable-concurrency regressions cover real HTTP/SSE/WebSocket/provider
  callbacks and bounded progress queues. WebSocket HTTP ownership now stays at
  a stable heap address and releases the upgraded connection before teardown.
- The production extension backend remains the legacy Node bridge. Native
  custom component factories, complete TUI exports/renderers, newer durable
  and SSH environment APIs, codemode and final parity certification are still
  required. Release verification intentionally rejects this checkpoint.

Historical implementation evidence (preserved separately from the fresh gates):

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
- Ported prepareRequest/finishTurn hooks with event ordering, explicit end/one
  continuation, natural-queue deduplication and hard-error termination tests.
- Native module object exports, common schema constructors, tool/command/flag
  and hook registration/invocation, ordered action capture and stale-context
  rejection are implemented in Zig. More extension APIs remain to port.
- Native worker candidate runs inside the self-contained Pi executable. Its
  real process fixture loads typed sibling imports and exchanges ready, hook,
  tool and shutdown records with Node absent from PATH and zero stderr.
- Added native filesystem read/write/existence/directory/delete functions,
  typed-array views and non-destructive invalid-data checks. Additional Node
  compatibility APIs remain outstanding.
- Retired the JavaScript catalog generator after all 1,290 existing records
  compared equal and the native generator reproduced the existing file byte
  for byte. CI now uses the Zig generator and native vendor verification.
- The latest complete Windows regression graph passes with the native worker,
  schemas, filesystem and tooling artifacts included. Production extension
  discovery still uses the old bridge pending complete compatibility gates.
- Imported the exact pinned typed catalog with the native tool and recorded
  the exact upstream source archive digest (not a fabricated release digest).
  Native generated data includes 1,529 chat, 57 image and 15 classifier models.
  Legacy chat selectors and operation-specific lookup/routing stay separate.
- Updated current provider defaults including Meta, Codex GPT-6.1 Sol, Nemotron
  3 Ultra, Kimi K3 and Radius Balanced. Full current-catalog Windows regression
  graph and byte-exact native regeneration check pass.
- Ported MCP protocol negotiation (latest 2025-11-25 and supported older
  versions), persistent newline framing, numeric response correlation,
  notification separation and unsupported server-request replies. Paginated
  tool refreshes reject duplicate cursors and preserve prior tools on failure.
  The real native server/pipe fixture and ten structural/framing tests pass.
  Closure and truncated records produce errors instead of invented responses.
- Added native MCP OAuth token parsing, issuer validation and step-up scope
  retention. Credential key construction matches upstream's namespace plus
  canonical URL; full discovery, browser callback and storage remain to port.
- Retired the Python structural source audit while retaining its forbidden
  generated surface checks in Zig. The separate strict implementation-language
  audit still fails on remaining legacy Python/JavaScript files by design.
- Fixed the hosted Windows ReleaseSafe MinGW header translation issue at the
  C declaration import boundary. Local ReleaseSafe build passes; hosted
  confirmation of the new commit remains required.
- The current full Windows regression graph passes all 38 aggregate steps,
  including the real MCP fixture, generated catalog and linked native worker.
- MCP request deadlines now bound pipe writes/reads, cancel and join outstanding
  I/O, and close only the client-owned server on timeout. A real stalled-server
  fixture verifies handshake timeout and cleanup. Reconnection clears old input
  and protocol state; generated request IDs stay in JavaScript's exact range.
- Native filesystem promises provide actual C-engine Promise values, ordinary
  asynchronous settlement and catchable failures. Exclusive writes are retained;
  unsupported encodings/write flags fail before changing existing files.
- Native read-only extension context fields/methods project cloned session/model
  snapshots. Invocation tokens guard retained property getters and callbacks;
  expired contexts and later invocations cannot reuse old capabilities. The
  self-process fixture also verifies malformed-request recovery and context data.
- Replaced the upstream catalog/changelog import scripts with native commands.
  Changelog import reads immutable Git objects and accepts future major and
  prerelease package versions, instead of reading modified checkout files.
- Replaced the Python artifact inventory generator with native generation and
  verification. Independent SHA-256 checks match all 700 current source files;
  deliberate inventory tampering is rejected. The manifest records in-progress
  parity explicitly and distinguishes catalog/source-archive provenance.
- Hosted Windows, Linux and macOS CI pass commit `f3137b9` (typed catalog and
  base MCP contracts). The subsequent native host/tooling Windows graph passes
  all 38 steps. Additional host/tooling changes still require hosted checks.
- Vendor verification rejects entries outside each pinned digest inventory as
  well as changed/malformed digests. A deliberate extra C source file is rejected.
- Hosted Windows, Linux and macOS CI pass native host/tooling commit `0baa60e`.
  Build-only release workflow 37154545313 also passes all six x64/ARM64 targets
  on Windows, Linux and macOS. Six downloaded binary digests verify and the
  Windows x64 version smoke passes. These are candidates, not a parity release.
- Ported the llama.cpp classifier's labeled prompts, tokenization/template/
  completion endpoints, depth escalation, duplicate/split/missing-label errors,
  softmax, confidence and typed answers. Local endpoints accept omitted API
  credentials; outputs have no fabricated usage. JSON numeric-key order and
  very small positive temperatures are covered. Token reuse is currently scoped
  to a request; persistent cross-request label caching remains to integrate.
- Native loopback classifier tests exercise all seven HTTP records, real retry
  headers, timeout cleanup and completion-only response observation. The full
  Windows regression graph passes after these classifier changes.
- Native catalog import now requires the Git tar's embedded PAX commit and
  committed AI package version to match provenance before writing output.
- Native console logs stay on stderr outside the worker record stream. ESM
  default exports no longer add cyclic properties to builtin objects. Module
  registration allocation failures leave no hidden C module, and retry works.
- Native ESM dependency resolution handles nearest node_modules packages,
  extensionless typed input, directory entries, explicit/conditional exports,
  null blocks and wildcard specificity. A real worker loads a package and its
  relative imports with Node absent from PATH. Additional loader compatibility
  remains to implement before switching production discovery.
- Native TextEncoder handles UTF-8, unpaired surrogate replacement, typed-array
  views, complete-codepoint partial writes and receiver validation. The exact
  TypeBox 1.3.27 package from upstream's lockfile loads as external extension
  input through the C engine; its SHA-512 integrity matches. No library JS is
  added to repository implementation or distribution sources.
- Native schema validation now enforces real TypeBox tuple/record patterns,
  modern prefixItems, additionalProperties without a properties list, property
  names/counts, Unicode patterns and boolean schemas. The pinned C regexp
  interpreter has memory/interrupt bounds and receives terminated patterns.
  Broader schema/reference/format compatibility still needs review.
- Native package import aliases now support conditional targets, external
  dependencies, builtin modules, wildcard specificity and null blocks. Alias
  cycles and deeply nested conditions have explicit finite limits. Package
  self-references and aliases stop at the nearest package scope.
- Native file URL imports and percent-encoded path segments resolve to the
  same canonical file identity. Encoded separators and package target traversal
  fail explicitly. File URLs preserve Unicode, reserved characters, Windows
  drives and UNC paths. Search/fragment module identities remain unsupported.
- Native import metadata projects file URL, platform filename and directory;
  hosted extensions have `import.meta.main === false`, as imported plugins.
  Explicit standalone engine entrypoints can select true. Dependencies stay
  false. `import.meta.resolve` and further loader interoperability remain to port.
- Native `node:path` / `path` exports separate Windows/POSIX objects, normalize,
  join, resolve, relative, dirname, basename, extname, isAbsolute, parse, format
  and toNamespacedPath. 3,038 independently captured Node 24.14.0 results match,
  including device roots, UNC shares, drive-relative paths and colon prefixes.
  Per-drive environment CWDs and matchesGlob remain to port.
- Native `node:url` / `url` fileURLToPath handles string input, Unicode and
  explicit platform overrides. URL objects, pathToFileURL and the remaining
  general URL APIs are not yet implemented.
- The real native worker fixture verifies package/builtin aliases, encoded
  filenames, metadata and path/URL functions with Node absent from PATH. The
  complete Windows regression graph passes after these additions; see the
  retained native-module-path evidence for exact terminal jobs.
- Hosted macOS exposed the raw cwd sentinel being passed to its F_GETPATH
  lookup. Native path APIs now open/resolve/close a real owned directory handle.
  A fault-injection test rejects direct sentinel lookups and passes the new
  path. The failed 8b294bf CI checkpoint is retained; a new hosted run is required.
- Native CommonJS input runs through the C engine with Zig-owned require,
  conditional package exports, scoped filename/directory/module values and a
  shared mutable cache. Circular dependencies expose partial exports; JSON
  identity, module.exports replacement, deletion/reload and failed-load cleanup
  are covered by real processes. Typed .cts roots and ESM-to-CommonJS imports
  run with Node absent from PATH. `node:module.createRequire` accepts string
  absolute file paths and file URLs. No upstream CommonJS host source is embedded.
- CommonJS requiring ESM, full parent/children metadata, alternate resolution
  roots/global paths, exact static named-export detection and additional
  module APIs remain to implement. Unsupported require operations fail explicitly.
- Installed schema input retains precedence over native fallback modules for
  both import and require. Resolver fixtures verify both conditional branches;
  the exact external TypeBox 1.3.27 ESM package probe passes after the changes.
- Hosted Windows, Linux and macOS CI pass CommonJS/cwd checkpoint `3b17b97`
  (run 37197899160). This confirms the earlier Linux/macOS path lookup repair.
- Native Buffer values inherit Uint8Array, preserve shared ArrayBuffer slices,
  copy array/view input, and expose from/alloc/byteLength/concat/compare plus
  string/JSON/slice/copy/fill operations. UTF-8, UTF-16LE, Latin-1, ASCII, hex,
  base64 and base64url match 747 captured Node 24.14.0 encoding results.
  Captured strings use UTF-16 unit arrays to retain isolated surrogate cases.
- Native callbacks retain the original thrown value and its identity, including
  diagnostic conversion failures. Buffer mutations revalidate backing storage
  after user conversions, with real detachment tests. Failed Buffer registration
  cannot be silently treated as a completed install on retry.
- Synchronous and Promise filesystem reads return Buffer values for binary
  input and support the verified text/binary encodings. Write options are read
  before opening/truncating files. Getter failures preserve the original thrown
  value and existing file content. The real worker exercises Buffer reads with
  Node absent from PATH.
- Buffer numeric read/write/search APIs, Symbol.toPrimitive input conversion,
  complete SharedArrayBuffer behavior, remaining buffer module/web APIs and
  broader JSON boundary handling of isolated surrogates remain to port. Unsafe
  allocation functions currently return zero-initialized native storage.
- Hosted Windows, Linux and macOS CI pass Buffer checkpoint `893254e`
  (run 37200468839), including filesystem and exception ownership changes.
- Native event registration returns distinct, idempotent unsubscribe functions.
  Dispatch owns a snapshot so additions/removals during a callback affect the
  next event. Repeated registration of one function remains independently
  removable, and allocation failures leave no hidden hook registration.
- Read-only extension tool/command catalogs, effective settings, active tool
  names, session name and thinking level are copied; local queued changes are
  visible within the current callback. Tool overrides and source paths are
  preserved. The native process exercises these accessors without Node.
- Session-manager accessors add cloned leaf/entry/label lookup, explicit branch
  traversal and the upstream compaction-aware entry view, including exclusion
  of summarized system entries. Tree construction handles orphan/self roots,
  current labels/timestamps and chronological children without recursive
  construction. Cycles/duplicate IDs fail explicitly, and retained callbacks
  keep invocation-generation checks. Context cwd fallback also uses a real
  owned directory descriptor.
- Durable context-edit/provider transcript integration, UI/model registry/host request
  callbacks, provider/virtual-model/MCP registration and further SDK bindings
  remain outstanding; these read-only additions do not switch production.
- Native session `buildSessionProjection` retains source-entry provenance,
  applies the latest branch-local replacement/omission edits, normalizes missing
  message content, and carries model/thinking-level replay state. Only the newest
  retained compaction contributes its checkpoint/summary messages. Custom and
  branch-summary messages preserve their role and timestamp projections. Source
  entries and message metadata remain unchanged when content is replaced.
- Host DTO construction uses native C values rather than generated bridge
  source, preserves NaN timestamps and literal prototype/NUL property keys, and
  rejects excessively deep values explicitly. Durable edit storage and provider
  request replay still need integration before production uses the new path.

- Pi 1.0.2 sampling defaults now resolve after thinking-level clamping.
  Model defaults, per-level values, model overrides and request-local values
  merge by key. CLI/server reloads own the merged metadata independently, and
  extension providers receive effective stream options and per-level model data.
  Native catalog generation recognizes this field and rejects invalid levels.
  Real loopback HTTP tests inspect chat completions, Responses and Azure payloads;
  allocator fault injection checks parsing, runtime ownership and merge cleanup.
  The full Windows graph passes 52 steps, 1,094 module tests, 27 existing skips,
  and zero failures. Production Node discovery and full Pi parity remain pending.

- Stored extension OAuth refresh now has cancelable lock acquisition and
  re-checks current credentials under the lock. Once started, refresh uses an
  independent 15-second deadline and persists rotated credentials despite caller
  cancellation. Logout and concurrent refresh checks pass. Login/ordinary mutation
  cancellation behavior remains covered by its own regressions.
- Built-in Codex, Copilot, xAI, Anthropic, Kimi and Radius refresh hooks also finish
  independently of live request cancellation with a bounded HTTP attempt. A real
  Radius loopback test checks rotated-token persistence; a real extension worker
  checks late cancellation and subsequent reuse. The full Windows graph passes
  52 steps, 1,099 module tests, 27 existing skips and zero failures; ReleaseSafe
  passes. Shared stored-refresh locking for every built-in adapter remains pending.

- Native Buffer numeric reads/writes, 64-bit BigInt and Float/Double operations,
  endian variants, identity-preserving Uint aliases and byte swaps now execute
  through Zig/C. All 31,352 captured Node 24.14.0 cases across 62 numeric methods
  pass. Tests compare result values, error classes/codes and mutated bytes, and
  check actual detachment, exception identity, NaN, infinity and negative zero.
  The full Windows graph passes 52 steps, 1,099 module tests, 27 existing skips,
  and 224 dedicated tests; ReleaseSafe passes. Non-primitive BigInt coercion and
  further string comparison edge cases, Buffer.write/search and broader APIs
  remain outstanding.

- Native provider registration now encodes callable descriptors using the same
  parser as production. Closures retain nested/array receivers, named updates
  merge defined values, and object registrations replace the prior configuration.
  Callback IDs remain valid across safe-point handoff and are removed on unregister.
  Cycles, BigInt, throwing getters, allocation failures, inherited array indices,
  holes, self-unregister and nested action ordering have native coverage. A real
  TypeScript provider worker fixture exchanges nine records with Node absent.
  Signal-bearing requests remain explicit errors pending the native async protocol.
- Four Python source-text audits were retired in favor of
  `zig build test-provider-contracts`, which runs production adapter behavior,
  linked-C bindings and the real native process fixture. Nineteen Python PTY
  scripts and five JavaScript implementation/harness files still need migration.
  Full Windows Debug passes 52 steps, 1,100 module tests, 27 existing skips and
  233 dedicated tests; ReleaseSafe and the named provider suite pass.

- Native AbortController/AbortSignal classes now retain reason identity, enforce
  brands, manage once/capture/onabort listeners, and mark GC cycles. Listener
  errors are reported through C runtime jobs after abort returns. Active and
  pre-aborted signals now cross native provider request boundaries. Timeout and
  any composition use real signals and deduplicate repeated sources.
- Native timers, cleared intervals, callback arguments and microtasks now settle
  delayed Promise callbacks in the real worker without Node. Host waits have a
  configurable deadline. Allocation failures and callback errors have coverage.
  EventTarget/DOMException, concurrent input cancellation, idle timer pumping,
  Node timer handles and composed-signal weak cleanup remain outstanding.
  Full Windows graph plus provider suite passes 55 steps, 1,100 module tests,
  27 existing skips and 297 dedicated tests; ReleaseSafe passes. The native
  language audit correctly fails for 24 remaining files and verifies 107 vendor
  files with zero digest failures. Production discovery remains on the old bridge.

- Native Node timer handles now retain identity and ref/unref/hasRef state,
  support active refresh/close and numeric/string coercion, and are the callback
  receiver. Timer module aliases expose the same C-runtime functions.
  Promise timers preserve value identity and original cancellation causes for
  pre-aborted/live signals. Cancelled and failed-setup timers retire callbacks.
  Expired refresh, idle pumping and unref process liveness remain outstanding.
  Exact `1965a806` source passes 55 steps, 1,100 module tests, 27 existing skips
  and 300 dedicated tests; ReleaseSafe passes. Latest durable/watch/codemode
  contracts remain explicitly pending native integration.

- Native tool numeric parsing now checks finite i64 bounds before conversion
  and rejects millisecond timeout overflow before launching a process. Real
  read/shell regressions check extreme inputs and preserve file contents. The
  full graph/provider suite passes 55 steps, 1,101 module tests, 27 existing skips
  and 300 dedicated tests; ReleaseSafe passes.
- Build-only checkpoint `c1bf824` passes all six Windows/Linux/macOS x64/ARM64
  targets (run 37238345450). All downloaded SHA-256 digests and its Windows
  version smoke pass. These are candidates from that checkpoint, not the newer
  source head and not a published or parity-certified release.

Latest native integration (October 5, London):

- Expired timer refresh preserves the handle, arguments, callback receiver and
  ref state, allocates a new numeric ID atomically, and permits callback-time
  refresh. Closed handles cannot revive. Node comparisons, allocation failures,
  ID exhaustion/retry and callback/argument/handle GC cycles pass focused tests.
- BigInt Buffer writes now perform all four observable primitive conversions,
  compare integer strings without floating-point loss, preserve partial low-word
  writes and original thrown values, and handle detachment at each stage. All
  31,352 existing numeric oracle cases and new adversarial cases pass.
- Native TextDecoder supports UTF-8 and UTF-16LE/BE labels and their aliases,
  BOM handling, fatal decoding, streaming/flush state, detached genuine views,
  subclass prototypes and original exceptions. Ten focused tests cover 287
  scalar split positions, 4,096 deterministic Node oracle calls and allocator
  failures. Other WHATWG encodings remain unsupported and throw RangeError.
- TextEncoder now rejects nonprimitive encodeInto sources before inspecting
  destinations, returns zero counts for detached/out-of-bounds Uint8Array views,
  and preserves conversion exceptions and Node error codes. Captured Unicode
  capacity/count cases and allocation failure/retry tests pass.
- CI runs the native provider contract suite and exact artifact inventory
  verification. Git checkout attributes preserve inventory bytes across hosts.
  A real worker fixture checks streaming decoding and encoding counts with
  Node absent from PATH. Combined validation is recorded after integration.

October 5 native host checkpoint:

- The explicit native Runtime/Host backend discovers and invokes real extension
  workers with Node absent from their PATH. Tools, hooks and provider methods
  receive live signals; tool updates preserve call identity and invocation
  generations. The worker reads bounded input on a separate task and dispatches
  controls only on the C context's owner thread. Timeout/EOF/shutdown cleanup,
  worker reuse, stale controls and allocation failures have real process tests.
  Production discovery still selects the legacy backend while remaining UI,
  provider streams, custom components and lifecycle operations are ported.
- Native DOMException has legacy codes/constants, Error inheritance, constructor
  options/cause, original exceptions and GC ownership. Abort and timeout default
  reasons match Node. Native stack capture and internal JS_IsError branding are
  not claimed.
- Directory enumeration and native Dirent objects support string/Buffer output,
  sync and promise recursion, exact getter behavior, stable constructors and
  Node's differing symlink traversal modes. Windows real-directory, Unicode and
  junction records match Node, including self-cycle results. URL-object paths,
  some Buffer error metadata and further legacy encodings remain outstanding.
- Four Python executable fixtures were retired after native real-process gates:
  authentication screen (11 byte-identical report fields), OAuth dialog (nine
  byte-identical fields), bootstrap HTTP (all five scenarios), and provider retry
  (all seven scenarios including live RPC reload). The retry mock now emits
  Responses events for current upstream gpt-4o; original assertions are retained.
  Fifteen Python scripts and five JavaScript files remain.
- Exact source before the latest upstream refresh passes Windows Debug with
  67 build steps, 363 dedicated tests, five platform skips, 1,105 module tests,
  28 module skips and zero failures. ReleaseSafe passes. Linux fixtures used the
  separately recorded earlier candidate; the final source needs hosted matrix
  validation. Evidence: verification/checkpoint-189/native-host-integration-20261005.json.
- Publishing requires native verify-release metadata, matching version/tag and
  certified upstream identity, the source inventory, language audit and C vendor
  provenance. Candidate builds remain possible. The draft checkpoint correctly
  rejects release publication with IncompleteParityCheckpoint.
- Latest observed upstream is 6100fe5a8358709a26050b8da97ccd188ae93101, two commits
  beyond the prior pin: Azure Foundry Chat Completions and fullscreen Home/End
  routing. Its source archive, catalog and changelog are now pinned and verified.
  The reviewed Azure transform retains the immutable raw catalog digest, renames
  the provider to azure and adds the DeepSeek Chat Completions deployment row:
  1,602 models total, 1,530 chat, 57 image, 15 classifier and 42 providers.
- Azure aliases preserve old CLI/model references, scopes, configuration and
  stored credentials. Canonical writes and logout cover both credential names;
  failed runtime-key replacement preserves the previous key. A legacy models.json
  provider config applies once to the canonical catalog and keeps the DeepSeek
  model's Chat Completions API. Twelve focused integration tests and fourteen
  credential tests pass. Native endpoint/deployment, payload-hook, header,
  reasoning and Responses API-version tests pass in Debug and ReleaseSafe
  (27 focused tests each). The reviewed upstream config oracle also matches.
  Live cloud credentials and arbitrary WHATWG URL normalization are not claimed;
  the streaming entry point remains options-less.
- The native Application routes Home/End to the editor and Ctrl+Home/End to the
  primary transcript ScrollView. Real editor/scroll component tests cover custom
  mappings, overlay focus, repeat/release and navigation overlap: Windows 104
  pass/one platform skip and Linux 105 pass. Main's fullscreen CLI still needs a
  persistent Application/ScrollView frontend; CLI transcript routing is not
  certified by these component gates.
- Standard native UI request roundtrips, FIFO delivery, retained actions,
  headless fallbacks, original errors, stale-context and reply-generation fences,
  cancellation and human-dialog deadlines have real worker coverage. Prompt
  lifecycle hooks are deferred until the active runtime lock is released,
  retaining both hook order and action batches. The final focused UI run passes
  13 steps and 91 tests (eight runtime and 83 bindings). Native custom component
  factories and overlay rendering remain unsupported; host UI callbacks must
  cooperate with native I/O cancellation.

Required outstanding work:

1. Native extension module loader and TypeScript input erasure, host bindings,
   persistent worker protocol, provider callbacks, UI/renderers, and adversarial
   lifecycle coverage. Replace the Node bridge only after compatibility passes.
2. Remaining provider transport/auth/transcript changes and shared stored-refresh
   locking for built-in adapters. Catalog/importer and selected operation routes
   are already native; complete provider behavior still needs certification.
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

October 5 native provider raw protocol checkpoint:

- Zig drivers replace the provider-method and stream JavaScript drivers, retaining
  original user-authored extension inputs and complete behavior checks.
- Actual native workers run with Node absent; supplied stream cancellation reasons
  survive cleanup, including bounded hostile retirement with an original cause.
- Injected clock values verify human-wait budget suspension and exact ordinary
  timeout rearming. Actual process tests separately verify dialog concurrency.
- Complete Debug graphs pass 109/109 steps: Windows 467 passes/32 skips plus
  1,148 module passes/28 skips; Linux 639 dedicated and1,168 module passes/eight skips.
  Optimized runtime plus both raw targets pass Windows25/six skips and Linux31/31 See exact evidence:
  verification/checkpoint-189/native-provider-raw-budget-20261005.json.
- Three legacy JavaScript files remain; default-native and parity stay incomplete.

October 5 durable integration checkpoint:

- Native local ExecutionEnv/readers/filesystem/temp/shell/output-window/polling-watch
  and structured read/write/edit/bash operations are integrated. CLI read now
  selects bounded text ranges while preserving existing image handling.
- Independent data captures cover386 reads,17 edits,240 display/patch cases,
  plus decoder/scanner/output suites. Native Myers code retains its BSD notice.
- Windows noFollow opens use a synchronous final-reparse handle, preserving
  non-following regular-file checks and preventing Zig0.16 pending-read panics.
- Complete Debug and ReleaseSafe graphs pass115/115 steps on both platforms:
  Windows519 dedicated passes/35 skips and1184 module passes/30 skips;
  Linux694 dedicated passes and1206 module passes/eight skips.
- Watch support remains polling, reads use regular files, diff budgets are bounded,
  and a global mutation lock serializes paths. Storage/Session/Harness, typed-tool
  registration and language adapters remain separate work. Default-native and
  final parity remain uncertified. Exact evidence is in
  verification/checkpoint-189/durable-integration-native-20261005.json.

October 5 native UI/OAuth/model-publication integration checkpoint:

- Persistent frontend now runs on Windows, Linux and macOS. Actual native
  Windows/Linux CLI tests cover Unicode, streams/history, resize, modal/draft
  ownership, hidden/revealed overlays, closeACK, disposal and reload.
- Native custom factory promises, component/overlay ownership and pure control
  DTOs retain original errors and caller values until fenced close acknowledgment.
- Native OAuth callbacks/prompts and model publication preserve original config,
  update receiver/closure, live models, stale rejection, cancellation and reuse.
- The last two JS protocol drivers are replaced by Zig drivers with their original
  user-authored inputs; only the legacy host bridge remains as JS implementation.
- Production still defaults to legacy. PI_EXTENSION_BACKEND=native selects the
  actual selfworker and survives reload. Regular native custom ownership, advanced
  focus/mouse, renderers/retained factories and complete exports remain pending.
- Composed full Debug/ReleaseSafe evidence is recorded separately from the final
 123-step Windows Debug admission. A Linux optimized fixture hang and its exact
  owned-worker cleanup remain documented; transition-driven replay passes.
- The session clock uses Zig's typed C ABI and builds/runs with Linux musl.
  Latest upstreamb7dfc049 adds14runtime commits under separate review. This
  checkpoint is not final parity or a release; see the native UI integration JSON.

October 5 latest upstream refresh to b7dfc049:

- Fourteen commits afterb78 add environment deployment/liveness/Windows fixes,
  daemon native watch/output windows, durable growing-read/BOM/progress changes,
  MCP OAuth metadata/tool filtering, codemode resilience and HTTP2 cancellation retry.
- Release remains1.0.3; the main commit is newer than the published release.
- Catalog/changelog archive provenance is regenerated and checked natively.
- Pending-stream retry and native MCP registration-body application_type inference
  pass focused gates; the remaining14-commit runtime delta stays tracked for porting.
  This refresh does not certify final parity or a release.

## Latest source and native API increment

The selected October 5 source is 031b24aa at 18:39:50 UTC. Six commits
after b7df add pending MCP connection shutdown, explicit PowerShell tool execution,
hidden-tool prompt rules and indirect skill-reader hints, planning-document
removal, watch changelog clarification, and lazy SSH connection construction.
The native PowerShell tool and structured prompt API have actual upstream
captures and Windows/Linux validation. PowerShell registration remains explicit.
Structured prompt sections are exposed as a native API; the complete CLI
loadout/section-update adapter remains an outstanding integration. Native lazy
daemon/SSH transport is a separate active increment. Source pinning does not
certify that every selected-source runtime contract has been ported.

The 28dcce2 refresh selects package version 1.0.4 after the release commit and
Unreleased headers. It adds four commits after 031b24 and changes no runtime
files under ai, coding-agent, durable, env, mcp or tui. The SSH login-shell
test now supports zsh. GitHub releases/latest was still v1.0.3 at the recorded
check; package/main authority is newer. Native pi-env reports the generated
catalog version automatically. Native environment limits remain documented
in src/env/CONTRACT.md and are not implied complete by this provenance pin.

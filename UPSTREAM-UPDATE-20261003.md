# Active Pi upstream update

Status: in progress. This file does not certify parity or a release.

- Working branch: `update/pi-upstream-20261003`, based on pi-zig main
  `012e80ced763e8d8ac7e01f7331d32dad3ab468b`.
- Previous Pi baseline: `853a80d26c90a14c1886f0ebb8ffaae133ca2185`, version 0.84.4.
- Selected authority: earendil-works/pi main
  `f5d20047b3ad43d068a8eb61bd4e1f193bedbce6`, package version 1.0.2.
  It descends from and is newer than published GitHub release v1.0.0.
- Delta: 893 commits, including new model types/classifiers, codemode, MCP
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
- Current upstream source tar SHA-256:
  `38a6ed7cbe08cbd4f101df62a884b1eeb5d859adf892bf03d33b937ce8443a9b`.
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

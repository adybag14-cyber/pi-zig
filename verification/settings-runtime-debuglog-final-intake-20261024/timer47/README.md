# Original debuglog timer consumer

This packet implements the complete original `formatTime`, `time`, `timeEnd`, `timeLog`, private `timeLogImpl`, and `debugWithTimer` bodies from Node revision f657bb8ed86365ff3fdbe32e27563e778b41486a. It is a source-only successor of the separately accepted ordinary initialized debuglog packet. It does not publish an internal builtin or change the application backend.

## Private entry and real dependency boundary

`native_node_debuglog_timers.acquire(engine, Inputs)` requires two inputs:

* `debuglog_exports` is the exact private exports object already produced by `native_node_debuglog.acquire`. The successor authenticates it against the actual cached owner; a shape-compatible replacement fails before assembly.
* `trace_events` is the actual bootstrap-captured original `internalBinding('trace_events')` value. This consumer captures `getCategoryEnabledBuffer` and then `trace` once, in the original named-import order. It has no default trace input.

The actual ordinary owner supplies its captured process, inspect, format, SafeArrayIterator, private require, shared testEnabled cell, warning implementation and lazy utilColors cell. The existing genuine SafeMap producer must already be bootstrapped; this consumer refuses cold recapture from guest-mutated globals. A private per-Engine publication record preserves complete-owner identity and reentrant publication. The ordinary source prefix is byte-identical; four Zig-only handoffs are appended, plus their one private helper.

The original module assembly must acquire the ordinary producer and this timer producer at the original module-load capture point, before the original bootstrap invocation of initializeDebugEnv. That invocation must receive the actual initial NODE_DEBUG value. This packet neither performs that initialization nor chooses a disabled value. Later initializeDebugEnv calls operate on the same shared predicate seen by timer initialization.

## Implemented semantics

Formatting uses the actual VM comparison, division, remainder, template ToString and captured Number.toFixed, Number, Math.floor, String.split and String.padStart. It preserves repeated numeric coercion, Number receiver branding, nonfinite values, three-decimal formatting and the object-pattern index-zero/index-one assignment order. Four minimal clone-capture hunks add those missing pristine operations to the already accepted ordinary clone successor.

The direct timer functions retain default-argument timing, label coercion, live store method references, warnings, flag coercion, the two ordinary replaceAll calls, begin/end/instant phases, original id zero, timestamp argument shape and original callback arity. Begin trace precedes process.hrtime and storage. End logging precedes end trace and deletion; a missing label warns but still permits the original end trace/delete path. No host floating-point formatting or host elapsed-time surrogate is used.

debugWithTimer shares one actual SafeMap per uppercased set. It captures the original category and source cells, calls the mandatory init callback every time an original arrow runs, and returns the actual escaped internal functions. Those functions reread the enabled buffer's index zero using strict numeric comparison on every call. Debug and trace flags remain distinct; both-disabled skipping occurs at the original wrapper/internal boundaries only. Direct time still stores a timestamp when its own trace bit is disabled, as the original body does.

The logging path reads live process.pid for each emission, creates the ordinary colors options object before evaluating its value, uses the actual lazy colors owner and inspector, resolves the second live stderr/write reference before formatting, and protects extra-argument iteration with the actual SafeArrayIterator. Original statement scopes, parameter cells, Source frames and owned completions preserve callback reentry, abrupt failures, ignored-return retirement and the pid local through the write.

## Controls and validation status

The new root declares forty-seven focused controls. Most run the same observation against both the native source candidate and a test-only literal copy of the complete retained JavaScript body. The reference embeds all 11,702 original body bytes unchanged, with an explicit wrapper providing actual process/inspect/private require/SafeMap/ArrayIterator inputs and the controlled original private trace input.

The fixture uses the real Engine, process owner, private builtin require, full inspector, colors, InternalTTY, OS and SafeCollections. Its trace input and live process.hrtime overrides are explicitly controlled source-test inputs. They do not qualify a native trace binding, native clock, process bootstrap, or application runtime.

Controls cover callable shapes, threshold/coercion/brand behavior, primordial capture, split assignment order, live callee selection, begin/end/instant event ordering, flag cases, missing and duplicate labels, callback argument arity, abrupt failures, trace reentry, dynamic enabled-byte changes, shared categories, init retry/reentry, HTTP warnings, live pid/stderr ordering, real formatting/inspection, protected extra iteration, authentic assembly inputs, and native fatal/retirement boundaries.

No Zig parser, formatter, compiler, metadata query, test executable, Node process, source generator or candidate was executed in this lane. Controls are declarations and have not been run. Static accounting checks all selected bytes, direct imports, original authority, finite source/build inverses, the exact reference-body span and the additive patch.

## Genuine next suppliers

Current Main's installed process owner has no hrtime property. The original time/timeEnd/timeLog bodies intentionally perform ordinary live process.hrtime Gets and Calls. The private producer does not synthesize that property. The next bounded supplier is the original process_methods BindingData hrtimeBuffer plus uv_hrtime-backed native callbacks and the original per_thread.js hrtime/hrtimeBigInt wrappers. The retained native source specifies a three-element aliased Uint32Array, seconds high/low cells and nanoseconds, with the BigInt view over the same backing. Current TUI performance.now/awake-clock behavior cannot substitute for it.

Genuine native tracing controller, agent, clock and event C ABI drafts already exist in the modules worktree and are pinned as dependency evidence. They are not selected by this packet and are not admitted in Main. The original node_trace_events.cc GetCategoryEnabledBuffer returns a one-byte view over the real native category-enabled pointer. Its trace export comes from the original V8 extras binding. A private JavaScript event array, owned synthetic enabled buffer, local category registry, no-op trace, or performance.now clock would not supply those semantics.

Complete trace admission still needs the actual native binding/VM extras operation and process-wide tracing lifecycle: genuine initialization flags, Agent publication, controller/category ownership, writer/configuration, platform producers/observer and original teardown ordering. These inputs belong to process/bootstrap ownership, not to a per-Engine opportunistic Agent. The source trace draft and original bootstrap analysis remain explicit handoff evidence.

Once both providers exist, the original complete private debuglog module can be assembled and admitted; canonical Module debugWithTimer/wrapModuleLoad wiring can consume its real exports. This packet alone does not claim canonical Module, print/RPC startup, native application runtime, public loader parity or product qualification.

## Source composition

Preserve the accepted ordinary debuglog packet and its Root review. Select this packet's clone and debuglog successors only after that source prerequisite, retaining its SafeArrayIterator. New relative imports resolve to this packet, the accepted ordinary packet, or exact current Main bytes as recorded.

Apply only the exact timer build insertion to a future composed build. The standalone build projection uses current 35790e97 Main and must not replace a newer composed build. Keep the ordinary debuglog target's separate insertion when composing both packets. The timer artifact stem is explicitly native-node-debuglog-timers; the installed PDB retains the build system's test name.

All earlier packets remain immutable. This packet does not authorize execution, source intake, native grants or Main mutation.

## Immutable v2 corrections

The v1 packet and independent findings remain preserved. V2 applies one JS_ToObject operation to the split result before either object-pattern indexed Get, through the existing owned guest-operation boundary. The boxed result is reused for both properties. The literal reference now starts with the exact original 'use strict' directive; its 11,702-byte original body is unchanged. Two appended paired controls cover a primitive Number result whose indexed getters must share one wrapper, and nullish result rejection. The previous 45-control source remains an exact prefix. The build insertion changes only its displayed control count.

The exact Node f657bb8/V8 target observes Symbol.split on non-nullish primitive separators after prototype protector invalidation. Current QuickJS uses the newer object-only rule. V2 therefore requires the separately reviewed genuine target-compatibility C successor; it does not weaken the original split control or select a fake splitter. That compatibility change and its VM controls belong to their own packet. No VM change, compiler or candidate execution occurs in this timer packet.

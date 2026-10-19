# Actual Node options: native serialization tail and retained process

Status: source only. The new code and controls have not been compiled or executed. All assigned source reviews are closed and remain bounded to their stated slices.

## What this unit changes

The two native options bindings now execute their actual selected serialization tails after the original bootstrap throw. The former flag-only implementation returned immediately and skipped those allocations. GetCLIOptionsValues still sets the real serialized flag after its void THROW helper; GetEmbedderOptions leaves that flag unchanged. Both construct the actual output while the same caller-stable Node boundary owns the ordinary bootstrap reason.

The native tail reserves its names vector before its values vector, produces the selected values and names in the retained source order, and creates fresh intrinsic output objects. StringVector conversion creates each primitive string before the actual intrinsic Array. The consuming JS_NewArrayFrom receives owned duplicates made immediately before the call. Native vectors borrow roots held by the same Scope and release their charged storage at their actual native scope boundary. Fresh object fields use the direct own-property operation, so inherited setters and later replacements of public constructors do not participate.

A failed actual native vector or VM allocation is recorded before rollback. A new actual fatal may supersede the ordinary bootstrap reason through the existing C435 reducer; a successful tail leaves the original explicit reason selected. This continuation is confined to these native producers over primitive names and fresh intrinsic objects. It introduces no general permission to execute guest code with a pending exception.

The serializer's host and port names are retained during binding creation, matching the original cached Environment strings. They are consumed after the actual host conversion, without a new late name allocation.

## Native Maybe::Check dependency

The original bootstrap Error uses V8 Object::Set with kDontThrow for its code field. A normal failed assignment continues normally; an actual thrown setter makes the Maybe empty and reaches native termination. The binding now calls the shared native_node_check_failure.maybeCheck operation immediately when the raw flags-zero Set returns a negative status, before pending capture or operand retirement.

The shared adapter is Root-owned and is not part of this source commit. Its reviewed ABI is E4C368A322B65340D70C7F48153CA898ECF0290A47696823AA557876775E114E. Passing null diagnostics selects the original default report-disabled branch. The shared C implementation, logging metadata, transitive native link, and isolated fatal-process proof must be integrated and qualified by Root. This unit neither manufactures a guest fatal Error nor treats the native termination as ordinary caught DATA.

The retained native-check evidence distinguishes Maybe::Check's FATAL ERROR route from node::Assert's assertion formatting and from the corrupted-async-stack exit path. These packets document the shared dependency; this options binding invokes only Maybe::Check.

## The process binding is the original wrapper parameter

The original BuiltinLoader passes exports, require, module, process, internalBinding and primordials to the compiled builtin body. Consequently, the process identifier in internal/options is its retained wrapper parameter.

The private options owner now retains the genuine registered node:process default during creation. It continues to read that object's live env and emitWarning properties. Replacing the public global process property, installing a throwing global getter, or introducing a genuine global lexical process TDZ cannot change this already-bound parameter.

The Source fixture uses the same actual process import as an explicit wrapper parameter. It does not obtain process through a late global lookup. The observer controls mutate and restore properties on the actual retained object to test the real receiver and callee boundaries.

## Controls and review scope

The existing install-only build-native-node-options target and filter are retained. The root now declares 26 named controls; no metadata count or runtime result is claimed. Controls 21–26 are added. Earlier native fatal control 18 is corrected to observe retirement of the actual env receiver before the warning getter; the old global-process receiver oracle is withdrawn. Its new title states that real boundary.

| Slice | Evidence and status |
| --- | --- |
| Original parser/default/admission and unrelated controls | Earlier source-only receipts remain in verification/node-options-sourceonly-20261019 and the separate parser compiler correction. This unit does not change them. |
| Native vectors, intrinsic field construction, same-boundary continuation and controls 21–23 | VM Foundation closed on 6759503E and root 46F6D889. Those bodies are unchanged by the later cached-name, CHECK and process-wrapper deltas. |
| Selected serializer ordering, cached host/port names and control 24 | SDK Owners closed on BA47869F and the unchanged control 24. |
| Native CHECK consumer | Root closed the immediate negative-status cutpoint and ABI on 58BA66B1 against E4C368A3. Shared implementation and fatal-process proof are separate. |
| Retained process body, revised controls 13–18 and late-global control 25 | SDK Owners closed on 2277A980, observer B3E8BF8C, root 13123938 and Source fixture 24A4DD2C. |
| State/process-root lifecycle, actual Source wrapper/Fixture and lexical-TDZ control 26 | VM Foundation closed on 2277A980, root 13123938, Source 24A4DD2C and observer B3E8BF8C. |

The actual failure controls retain their reason or progress object before invocation. Postfailure assertions read only the retained record's known own primitive fields. Quotas and injection flags are restored before teardown, and the native Probe storage outlives the Engine and its finalizers. Flagged successful DATA, ordinary throws and actual fatal events remain distinct cases.

## Authority and version boundary

This unit follows the retained Node v24.14.0 options and builtin-wrapper sources at commit f657bb8ed86365ff3fdbe32e27563e778b41486a. Its native options.cc is C9D94CF1, internal/options.js is EE760715, and the complete successful native-tail continuation proof is retained in the prior options unit as EE76DEEB. The new wrapper packet pins full BuiltinLoader source 770E6687 and realm source 6B19B7E8.

The filesystem, URL, libuv and FileHandle units retain their separately stated Node v24.13.0 basis. This change does not merge those version claims. The selected option schema and explicitly supplied host feature defaults remain the same as the prior options owner.

## Intake and remaining work

The five changed production/control files, the original-wrapper packet, the exact shared-check evidence and this source record form the unit. No C vendor or shared native CHECK implementation is included. An untracked copy of the Root-owned Zig adapter in the development worktree is only a source prerequisite and must not be staged.

Root must apply the unit after any Main freeze closes, preserve the existing build graph, add the exact shared CHECK dependency through its one transitive native library, and freshly build/query this 26-control root. Native execution and original Node reference capture require their distinct Root grants. Full option-schema admission, original report-on-fatal-error behavior and the final public Module/ESM/TS graph remain separate production work.

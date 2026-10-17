# Genuine lexical metadata and dual origins — source only

This successor extends the actual compiler/probe implementation reviewed at
`430dac95b8213520cdd3e27ad388732c8ef96cab` and its one-argument Zig predicate
correction `5a2b27ac9785a163e64077293c431b54d6d513ba`. Its historical Git parent is
79ef; the exact 79ef-to-430 source correction was carried before this metadata
delta. No CJS, parser, C, Zig, metadata-query, Node, native, formatter or generator
execution has occurred here. Sixteen named metadata controls are prepared;
actual imported anonymous declarations and compiled metadata remain unknown.
The previous forty-three compiler controls remain present. This is not a full
Node/V8 compiler, code-cache, wrapSafe, loader or resource qualification claim.

The original scanner authority is official Node commit
`f657bb8ed86365ff3fdbe32e27563e778b41486a`, including its bundled V8 scanner.
`Scanner::TryToParseMagicComment` in scanner.cc and its real single-line lexer
event in scanner-inl.h define the grammar. The implementation runs only at the
actual QuickJS `//` lexer event when this private compiler scope is active:

* `#` or `@` must immediately follow the two slashes, followed by exactly one
  mandatory ECMAScript WhiteSpace code point; the name starts immediately after
  that code point. A second space gives an empty, unrecognized name.
* Exact `sourceURL` or `sourceMappingURL` must be followed immediately by `=`.
  WhiteSpace after `=` is skipped. One raw, nonwhite value is retained; only
  WhiteSpace may follow it on that line. Empty or junk-tailed recognized
  assignments clear their earlier value. Unknown/malformed pre-equals comments
  do not clear earlier metadata. Quotes, percent sequences and NUL are data.
* Strings, regexp bodies, template raw text, block and HTML comments do not
  invoke this event. Speculative parser backtracking cannot overwrite an event
  at a later physical source position. Each source-sized helper scan uses the
  existing actual opt-in compiler poll and current-pending policy.

No source text regular expression or secondary comment scanner supplies these
values. The private diagnostic holds borrowed source slices only while the API
owns its CString conversion. Successful outputs are genuine owned JS strings.

## Separate physical and logical origins

The retained V8 `CallSiteInfo::GetScriptName` returns Script.name;
`GetScriptNameOrSourceURL` returns Script.GetNameOrSourceURL. V8's host dynamic
import callback independently uses `referrer->name()`. Node module_wrap and
internal/modules/esm/utils forward that physical referrer to actual import.
Consequently changing QuickJS `b->filename` to sourceURL would redirect relative
imports and would conflate the two public CallSite accessors.

`JSFunctionDef.pi_source_url` and `JSFunctionBytecode.pi_source_url` instead own
an optional logical atom. Physical filename atoms and
`JS_GetScriptOrModuleName` are unchanged. One real parsed source's final logical
URL is duplicated into its actual nested function definitions, transferred into
their bytecode, and freed with the owning FD/FBC. The native AsyncFunction FBC
creator, ordinary compiler creator and bytecode reader initialize the field;
all read/failed-read paths retain the legacy NULL value. Closures share their
real bytecode owner; no borrowed input or native filename CString escapes.

Existing CallSite `getFileName` and `JS_ReadCapturedStackFrame` remain physical.
The captured record owns an additional logical `source_name`, exposed by
`getScriptNameOrSourceURL` and the additive no-guest-lookup
`JS_ReadCapturedStackFrameSourceName` accessor. Its allocation/clone/transfer,
mark and finalizer paths own it independently. Parser-error native capture uses
the live private source slice for the full logical JS value, while its existing
native-hook filename argument stays physical. Private pending reasons survive
field failure. Default formatted C backtraces use the logical name when present.
The actual Zig Node Error formatter still needs a separate reviewed caller
delta to consume the new logical accessor; this C packet does not claim that
formatter or wrapSafe integration has happened.

The public binary format/version and default serialized bytecode remain
unchanged. Serializing bytecode with a nonempty private logical atom explicitly
fails as unsupported before its function record is emitted. This is not V8
binary cache interoperability. Ordinary metadata-free bytecode is still tested
through real write/read/evaluate operations. Source-map URL is metadata output,
not a fabricated source-map parser/cache result.

## Actual compiler interfaces and ownership

`JS_PiCompileCJSFunctionInfo` uses the same real ordinary-function body parser,
fixed five parameters, semantic compiler and closure creation as the reviewed
raw compiler. `JS_PiCompileCommonJSScriptInfo` uses actual
GLOBAL|COMPILE_ONLY for the patched Module.wrap route, without body execution.
Both require distinct non-NULL output slots and an admitted capture-only native
Error owner. Any entry pending reason is left untouched. Failure leaves metadata
slots untouched, resets only the documented compiler category, and preserves
the exact owned current reason over FD/bytecode/value/CString cleanup. Success
transfers an owned sourceURL (logical when nonempty, otherwise the primitive
physical filename) and owned sourceMapURL (undefined only for an empty actual
lexer buffer). The old raw function compiler remains a real wrapper over this
same implementation; it collects metadata for actual frame semantics but does
not allocate unused JS output strings.

The new allocator mode 7 uses 128 real nested declarations so its measured
native backing-allocation sweep cannot silently claim every logical arena
allocation. At most 512 actually measured host events are tested in fresh VMs.
It checks untouched metadata slots on failure, exact produced reason identity,
no loading/body/jobs, returned URL/map on success, atom-count restoration after
result/reason/output release and GC, native backing-block retirement and healthy
reuse. The actual 10000-cadence pending-success interrupt sweep is independently
bounded to 128 observed callbacks. It never injects a PC, VM allocation count,
time or parser result. Existing raw regexp modes remain exactly 0 through 6.

## Prepared controls and remaining gates

The installed-only target `build-native-cjs-source-metadata` links the real C
fixture; it never runs tests. The sixteen controls cover actual metadata,
lexical exclusions, clearing/whitespace/raw Unicode/NUL, exact first pending
reason and unchanged outputs, patched real script/raw Promise completion,
nested frames/clone/GC, logical name versus physical relative import (two actual
C modules with different marker values), private serialization refusal/default
roundtrip and native allocator/cadence retirement.

`reference-node24-input.mjs` is an original-only future observer. It requires
explicitly granted expose-internals and fresh contained owned fixtures, uses
actual contextify, vm.Script, Module and physical files, and retains eighteen
rows without expected values. No original execution or expected output exists
in this packet. Official original captures are Root's separate authority gate.

The capture-only native Error owner, trusted nonreentrant interrupt callback,
live owning context and no guest formatting/reentry remain mandatory host
preconditions. Existing atomic native library/copy/retirement frontiers from the
430 review remain explicit. Future composition must narrowly apply this delta
to Root's newer C core; this worktree's older C file must never overwrite Main
or the repaired namespace/CallSite/receiver/AF compositions.

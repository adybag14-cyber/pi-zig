# Node24.14 TTY source unit, 2026-10-17

State: authored source only, not installed, compiled, AST checked, or executed.
Base: `65dc640634d6bb1ae3ed4fba8a6b17eb50ab83b7` in the isolated
`worktrees/node-tty-20261017` checkout. Root Main is untouched.

## Implemented unit

`native_node_tty_colors.zig` implements the actual internal/tty decision tree,
per-module warning and lazy OSRelease cache, strict FORCE_COLOR cases, ordered
CI own-property checks, TEAMCITY `in`, actual VM regex/string methods, ordinary
TERM_ENVS inherited-property reads, and lexical hasColors dispatch/arithmetic.
The methods ignore their receiver; a real call on WriteStream.prototype works
without opening a terminal. Captured bootstrap methods remain required inputs,
with a bootstrap capture API. A native validateInteger implementation delegates
to the actual captured Node error constructors. It does not substitute a generic
TypeError/RangeError message for Node's registered errors.

`native_node_tty.zig` creates the actual ordinary callable ReadStream and
WriteStream functions, constructor/prototype inheritance from canonical
net.Socket, actual fd shift/strict-validation order, native TTY allocation and
ctx checking, same-receiver live Socket.call, ReadStream options spread,
blocking/raw/window/resize methods, and lazily cached real readline delegation.
Methods have genuine bodies and shared color-function identities. Namespace is
the actual ordinary `{isatty, ReadStream, WriteStream}` object. The production
assembler must retain it once and build the real valueNamespace/default export.

`native_node_tty_values.zig` keeps all fallible guest operations local and
transfers a success-with-pending exception before later guest effects. Traced
callable captures retain private lexical objects; those objects are not public
module properties or guest-selected opaque-holder lookup paths.

## Actual remaining native integration

This commit does not claim that a tty_wrap binding exists. Constructors require
the genuine native TTY and isTTY functions and actual registered Node error
constructors. No undefined export, fs.WriteStream alias, dummy Duplex, fake fd,
worker stdout terminal, or always-false color method is supplied.

Filesystem's source-only canonical Socket adopter is separately authored at
`c1b478cd23190620bc1e304b23b7373a82bbda72` in `worktrees/child-process`.
Its Provider.addHandleAdopter accepts a fixed known JSClassID, traced owner,
native context and resolver. Resolver verifies Engine and canonical handle
identity, returns genuine endpoint Hooks; Socket retains the Hooks and performs
Duplex.call on the same receiver. Adopter rollback and teardown are its owner.
It remains an unreviewed/uncompiled external dependency of this unit.

Body owns the actual node:os release implementation using RtlGetVersion/uname.
Colors will call genuine require('os'), select release, invoke it unbound, split
the actual returned string with the bootstrap String.split and cache only after
success, exactly as Source. No OS version is invented or inferred from colors.

The next unit is the actual tty_wrap backend. It must distinguish explicit real
CRT descriptors from authenticated frontend terminal capabilities. Existing
native_process_streams.Bridge carries operations and dimensions, not a native
fd/handle identity, and cannot authorize treating framed worker stdout as one.
See NATIVE-BINDING-PROPOSAL.md. Root explicitly authorized continuing this unit
through that backend; this packet is an immutable review checkpoint, not a stop
at the required binding dependency.

## Authority and prepared controls

All source references under authority are exact official v24.14.0 downloads;
authority-manifest.json records URL, length and SHA256. tty.js/internal-tty.js
match the already retained Node builtin strings exactly after CRLF-to-LF
normalization. The original evidence JSON is unchanged. Source headers and the
complete Node LICENSE are retained; libuv source is authority, not executable
new C. Existing Source20/14 and proofs are untouched.

original-consumers.mjs contains original Node calls for the actual jiti optional
chain, metadata/inheritance, detached lexical calls, strict force levels,
integer validation, env getters/Proxies, inherited TERM keys, fd validation,
method order and resize/raw protocol. warning-and-cache.mjs requires a fresh
process and captures throwing-warning identity, warning retry/once and genuine
release lazy/cache behavior. These are capture-pending controls. No expected
value, golden, executable result, or original assertion has been created or
changed. Original-consumers opens no valid fd; actual console construction and
native adoption/retirement need a separate owned native-console fixture.

Future exact-head review gates must include native memory/GPA retirement,
fatal-allocation and pending-exception boundaries, poisoned late globals versus
captured primordials, real TTY/non-TTY descriptor cases, console mode ownership,
same canonical Socket receiver, actual IO completion/backpressure/cancellation,
and teardown after wake detachment. Runtime grants remain Root's separate action.

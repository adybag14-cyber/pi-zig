# mlly boundary and format successor — source only

This separately committed successor preserves historical54489dcd and4672e40d,
their manifests and original inputs. Root authorized the namespace-local real
callable adapter, including construction, after independent review identified
that a body-only callback guard cannot cover generic construction setup. No
shared Node callable, Engine, C/H, common loader, build or Main file changes.
No formatter/AST/compiler/Node/native/generator/capture job was run.

## Corrected boundaries

`native_mlly_function.zig` implements the same ordinary/arrow/method call and
construction behavior used by these consumed bindings. Its private native
state/captured values have an aggregate reservation, GC mark and finalizer.
One invocation generation covers both constructor setup and the body. Its exit
first takes a current pending VM reason, otherwise transfers the owned captured
reason, and frees any superseded diagnostic root. A fresh privately tagged
reason keeps its exact identity and becomes uncatchable. Direct OutOfMemory
without an existing completion creates one actual private Error and marks it
uncatchable. An already pending Error combined with direct OOM is retained and
marked rather than replaced. Arbitrary pending non-Error data combined with
direct OOM remains an explicit unsupported mixed host contract (the pinned C
mark only accepts Error objects); no name/message heuristic classifies it.

Ordinary and preexisting fatal flags are preserved. No ordinary duplicate stays
in captured_exception after a guest catches the callback completion. Scope
roots remain borrowed/owned as before; captures are duplicated into the adapter
and released once by its finalizer. The fresh-error helper temporarily owns a
duplicate capture; that duplicate is freed while the original owned reason is
retained for the final JS_Throw ownership transfer. The adapter covers only
mlly/URL/ufo functions created by this component. Pathe4672 remains unchanged.

Iterator throw-completion cleanup now snapshots generation separately before
the live return getter and before its call. Each failing boundary classifies
only its own fresh native reason. The enclosing close no longer applies the
loop-start generation to cleanup errors, so an older loop-born private tag
re-emitted as ordinary cleanup data is not promoted. Ordinary cleanup remains
suppressed by the primary throw; a fresh cleanup fatal still overrides an
ordinary primary, and an existing primary fatal keeps its identity. Normal
return-result validation and the prior abrupt-close suppression rules remain.

The finalization catch now captures global Object and its defineProperty callee
before creating the descriptor and evaluating String(resolved)/String(base).
The exact primary reference is `lib/resolve.js`233–253, especially249–250.

## Actual format dispatch

The former abbreviated file-format helper is replaced with the pinned
get-format.js policy. The null-prototype extension and protocol maps retain
real ordinary handler functions, a single shared HTTP/HTTPS handler and the
nonconstructible node method. Dispatch reads url.protocol, performs the actual
captured hasOwnProperty.call check, then calls the selected handler with its
map receiver and (url, context, true); unknown/falsy results become null.

The data MIME and file extension/package-type handlers are actual Source
bodies, including conditional MIME matching, post-decrement extension scanning,
the extensionless package-type rules and the unknown-extension TypeError path.
Legacy deprecation builds {parentURL:base.href} before dispatch. Primary lines:
get-format.js19–36 (extension map/MIME),48–72 (handler map/data),80–143
(extension/file/http),151–158 (dispatch). Unknown-extension message/base are
errors.js288–298. These are finite pinned Source changes, not inferred formats.

## Prepared, unrun controls

The frozen original51 input and five native controls are unchanged. New
`jiti-mlly-boundaries-4.2.input.mjs` has8 planned genuine original helper
observations: finalization descriptor order/raw identity after a controlled
failure following real Node URL conversion, then file/node/http/https/data-JS/
data-JSON/unknown protocol dispatch with actual URL getter traces. Its subject
must contain the actual pinned exported moduleResolve/get-format helper and
genuine Node URL/syncBuiltinESMExports bindings. It is not a new controller and
does not claim that the native Node named-export synchronization seam exists.
Original capture and native boundary probes are separate until that seam is
implemented; no synthetic synchronization callback is supplied.

`native_jiti_mlly_boundary_test.zig` adds13 native tests: direct OOM bypass,
pending-before-stale capture, pending Error plus direct OOM exact identity,
ordinary slot transfer, historical tagged data,
fresh tagged identity, pre-body new-target prototype failure, exhaustive GPA
through genuine new, ordinary/arrow/method receiver/descriptor/construction
shape, two historical close boundaries and two fresh fatal close boundaries.
Two additional entrypoints require complete actual imports for format dispatch
and descriptor order. The latter injects an ordinary failure only after calling
the real supplied Node file URL converter. It restores guest mutations only
after probe success; any prior failure exits to the fresh realm owner teardown.
Control callbacks are host error/allocation probes, not product collaborators.

All controls are authored/unrun. Both original51 and supplemental8 expected JSON
files remain absent. No generated native answers or edited historical evidence.
The old89 authority members and17 inert resolution fixtures remain byte-exact.
Full V8 internal-error stack/reflection, adversarial recursion, broad replacement
global/proxy behaviors, whole Node/crypto/platform parity, original capture,
native execution, and default loader selection remain unqualified.

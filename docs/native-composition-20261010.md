# Native composition qualification

The native follow-up branch composes focused Pi compatibility changes while the
complete native rewrite remains in progress. It is not a release or a parity
certification. Zig remains pinned to 0.16.0; the existing extension bridge remains
available pending the complete native lifecycle and application gates.

The latest reviewed upstream target is
`ea448f454af474f3e2fe9733b331e17b0662f5d6` (10 October 2026, 19:29 UTC).
The ownership-index, nested-call-document and `TaskRuntime.ownedTasks()` changes
in that revision still require integration. Its image, SDK and UI source files
are unchanged from the preceding image/SDK/UI comparison snapshot.

## CodeMode source directives

The source parser now follows ECMAScript whitespace, validates unsupported keys
before supported values, orders numeric object keys before ordinary keys, and
validates the output budget before the timeout regardless of JSON insertion
order. Syntactically valid overflowing JSON numbers reach option validation as
Infinity, matching `JSON.parse`; durable storage retains its existing strict
nonfinite-number rejection through its unchanged default parser entry point.

The `test-codemode-source` target passed on Windows and native Linux in Debug and
ReleaseSafe. It includes 88 complete actual-upstream source comparisons and the
existing source fixtures. Malformed-JSON diagnostic wording and public portable,
remote and Cloudflare CodeMode bindings remain separate unfinished work.

## SDK process streams

The integrated reference packet is
`b2f5ae63bf222abe4f94585794a279fc60672726`. It previously passed 12 focused tests
on Windows/Linux Debug/ReleaseSafe and all three hosted operating systems in
Debug. Root composition preserves its framed process transport, exact invocation
routing, opaque JSON result bytes including escaped lone UTF16 code units, and
EOF cleanup. Those earlier results qualify the packet's original source.

`SDK stdio composition diagnostics` separately validates the newly composed
source at the pushed head. It records that head, tree, exact compiler identity,
complete tracked input hashes, posthashes and executable digests. It deliberately
does not claim source equality with the earlier SDK implementation. Main's shared
physical input hub and complete SDK session parity remain unfinished.

## Native image codecs

Coding-agent image resize uses the exact Photon Node 0.3.4 translation. Durable's
optional image processor uses the separate exact Photon browser 0.3.3 translation.
Both compile directly from C using Zig; neither needs a JavaScript host or WASM
interpreter. Each module shares the bounded allocator and C trap boundary while
retaining its own codec artifact and upstream selection rules.

Image branch `ab25122c9da287270ecd9472ea20170162c98815` passed 15 focused tests on
Windows Debug/ReleaseSafe and all six hosted combinations of Windows, Linux and
macOS Debug/ReleaseSafe (run 38083044187). The suite includes original codec bytes,
20 coding-agent resize results, 38 Durable prepared-image results, 29 current
Durable metadata cases, orientation, exhaustive allocation failure cleanup, and
concurrent caller recovery. The application default image path, image factory
bindings, worker integration and complete application checks remain unfinished.

Keep the dependency licenses and known-component provenance with distributed
artifacts. The recorded known notices do not constitute a complete transitive
dependency SBOM.

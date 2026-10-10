# Native migration follow-up checkpoint, 10 October 2026

This is an unfinished development checkpoint. It is not a release or a full
parity certification. The existing extension backend selection remains in place.

The current upstream reference is `c5f5b3282d5e4203c085e59837ba17aeaf2829b5`,
newer than release v1.1.0. Compared with the previous reference, it adds portable
and remote codemode transports and rejects an OAuth response issuer when there
is no discovered issuer to compare it with. Upstream metadata and generated
artifact inventories must be regenerated after the complete composition passes
its required checks.

## Completed checks and their scope

- Checkpoint `de6d647` passed Windows Debug for the retained UI service,
  Markdown, project context, layout, and OAuth issuer targets: 62 tests and
  21 build steps. This includes the overlay service regression and 16 actual
  upstream issuer-validation cases. The separate HTTP authorization regression
  in `oauth_authorize.zig` still needs `test-mcp-runtime` or its focused
  `test-mcp-issuer-exchange` target.
- The ProcessTerminal pipe follow-on at `cdd0b38d7f41aa51789c62b7f13e17f5c4d45f8a`
  passed 42 tests in each of Windows Debug, Windows ReleaseSafe, Linux Debug,
  and Linux ReleaseSafe. Its 1,969 tracked source hashes matched after the runs.
  This checkpoint incorporates that four-file patch; the final composition
  still needs its own verification.
- The isolated singleton retained UI transport candidate at `04508ee` passed
  its genuine upstream retention, identity, rebinding, and idle-completion test
  using the actual native SDK executable in both Windows configurations. That
  candidate has not yet been integrated here or qualified on Linux.

## Open work

The codemode changes in `32aa424` are not yet compiled or qualified. They add
bounded promise-job draining, inline interrupt budgets, and upstream fixtures
for startup and terminal-result ordering. The new remote and Cloudflare APIs
remain open. Low interrupt budgets and orphan promise work must be checked
against the actual upstream fixtures before these changes can be certified.

The first isolated OS matrix passed the actual issuer-exchange test on all three
platforms and the bounded synchronous/promise-loop cases. Its finite tiny-budget
golden failed. Actual upstream instrumentation then located all four polls for
`return 1` inside the WASI JavaScript prelude. Native bindings implement that
setup in Zig/C, so their startup poll cost differs. Upstream documents polling
rate as dependent on code and machine; this quantitative backend difference is
retained in the evidence rather than reproduced with dummy polls or a JavaScript
host prelude. The follow-on enforces a real budget admission check before user
effects, compares finite semantics under ample budget, and checks tiny positive
budgets against actual cumulative native polls. Those follow-on changes still
need qualification.

Terminal value serialization is part of execution: getters and `toJSON` may
produce output/store writes or fail before the result is selected. Added upstream
fixtures cover those paths, undefined serialization, cyclic values, an infinite
serializer, and suppression of effects after the first terminal result. Native
error stacks preserve genuine native frames rather than inventing WASI frames.

Storage/context and dynamic receiver work, remaining SDK APIs and parent
terminal transport, TUI constructors/autocomplete/collation, native image
processing, full platform CI, and removal of the maintained JavaScript host
remain incomplete. Individual target successes do not certify those areas.

The previously published checkpoint's full hosted OS matrix failed. Its logs
identified linkage, filesystem-fixture, and UI lifecycle issues; those failures
must be resolved and the final source head checked again before merge or release.

The work branch has a separate, read-only diagnostic OS matrix for
`test-codemode-inline` and `test-mcp-issuer-exchange`. It preserves the exact
source/tree/toolchain receipt. It does not replace artifact-inventory,
provenance, allocation, full-suite, or release qualification.

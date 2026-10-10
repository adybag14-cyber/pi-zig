# SDK stdio diagnostic branch

This branch preserves implementation snapshot467 `a5432924d2b7855f0f56d51baf51046747c15d56` and proposed snapshot468 `5aec3b2dcd03455ac5596bbc957ef6e93e75488d`. The latter changes only the captured factory error return to an explicit error union and is not proven. This branch is a backup and diagnostic, not full Pi qualification or publication of a completed migration. Existing main, pull-request, release, and lifecycle workflows are unchanged.

The workflow runs only on pushes to `work/sdk-stdio-diagnostics-20261010`, with read-only repository contents permission, a separate concurrency group, pinned action commits and Zig 0.16.0. It is temporarily **tiny-only**: one Windows job, five-minute outer limit, one compiler task at a time, and 30-second per-test bounds. Exact external reproducer bytes, their hashes, head/tree/tool receipts, logs, and expected-negative/variant results are retained for 14 days. No heavy SDK target runs until the language pattern is reproduced or refuted.

The original workflow at `ccadc3aa67cbfc691c93b1e8f9e68217fba0a428` selected three targets for real installed SDK process pipes, authenticated framed worker startup, and the private stdio protocol. Its test processes receive a PATH containing the SDK binary directory; Node is used only to capture the original upstream reference and is not their runtime host.

The reference fixtures are actual Source `6fb2e7815167e6b19006fc526d1a5d0f5f998787` captures. The relevant AgentSession and terminal source files were checked against current42a authority. Fixtures preserve complete raw stdout/stderr and encode observations JSON as opaque base64 so isolated UTF-16 code units are retained exactly. No replacement-character substitution, key omission, or weaker Unicode comparison is allowed.

| Reference | Behavior | External capture SHA256 |
| --- | --- | --- |
| Source454 | Actual pipe metadata, Unicode keys, EOF, binary stdout and stderr | DEBB979C9EE940F85A611DBDF90AC03C2E08ED257C4CEB06C5B7394F0BDD05FA |
| Source455 | Global input/output after SDK disposal while the captured context rejects stale use | 345AF622345DE41CE6EB41A59E7921B361155A14F37CE411035BA863D00BDB98 |
| Source457 | Actual terminal extension factory; input callbacks run after factory return | C7C9A64FD495E77E4B89B6D40B37A65DB1FADECA9D5ACCF42443367F883F54E1 |
| Source460 | Pausing/stopping permits exit while the parent input pipe remains open | 700B75A58479E1DD8A70F987E6AD139E03B5238D79F1075035824D696E0F4D4E |

EOF prerequisite `3b4436e627f9ca16f437dad0068560bbef5e38d3` was qualified separately in all four Windows/Linux Debug/ReleaseSafe modes, 45/45 tests per mode, with unchanged posthashes. Its patch SHA256 is `E9BBDBB3C90951F064E6805705B55688345E0246A10A33AF3097AF9E9BB57AE1`; receipt SHA256 is `FA3A122353FF9E09F3BFFF1A4F82D115FB087D82A81A25B147EE541231786FB8`. This prerequisite proof does not qualify the SDK integration automatically.

Local snapshot465 compiled the real embedder and passed three actual SDK pipe tests plus two protocol tests. Its framed worker startup test failed with `JavaScriptExtensionClosed`; the worker termination cause is not established. Snapshot466 added framed termination diagnostics but encountered an error-set compilation failure. Snapshot467 made the worker owner's error union explicit; local admission was refused before launching a compiler because available RAM was below the guard. Hosted run38069694451 then reproduced the same compilation failure on467, with all2206 tracked posthashes unchanged. No new runtime cause was obtained.

The external reproducer compares the original expression-form `errdefer` plus bare error return with explicit error-union-cast and block-form variants. The original compilation failure is retained as an explicitly expected negative, rather than hidden. If the minimal original compiles, the verifier records a **refutation** and fails the diagnostic: the actual SDK catch/return context must be inspected before attributing any repair. Variant tests verify capture of the original error identity. Their success alone does not establish an SDK fix.

The first tiny run38070819902 reproduced the original negative and also found the same compilation failure in the block-form variant's bare return. A combined variants file could not execute its cast test because that block error prevented compilation. The current tiny workflow therefore builds filtered cast and block targets separately. It requires the original and block negative diagnostics explicitly, and requires the isolated cast test to pass and preserve the captured error identity. No heavy SDK build is enabled by this workflow change.

Remaining work includes the concrete framed worker fix, the SDK integration's complete four-mode qualification and ownership checks, genuine Main shared terminal input/output wiring, physical console behavior, and AgentSession prompt/queue/compaction parity. Full migration and all required CI publication remain incomplete.

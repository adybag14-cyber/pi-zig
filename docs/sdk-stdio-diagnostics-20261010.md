# SDK stdio diagnostic branch

This branch preserves implementation snapshot `a5432924d2b7855f0f56d51baf51046747c15d56` and adds only this document and its branch-scoped workflow. It is a backup and a Windows Debug diagnostic, not full Pi qualification or publication of a completed migration. Existing main, pull-request, release, and lifecycle workflows are unchanged.

The workflow runs only on pushes to `work/sdk-stdio-diagnostics-20261010`, with read-only repository contents permission, a separate concurrency group, pinned action commits, Zig 0.16.0, one build job, 120-second per-test bounds, and a 25-minute job limit. It records the pushed head/tree, implementation head, tool executable hash, complete tracked-input hashes before and after execution, the build log and result, and produced executable hashes. Artifacts are retained for 14 days.

The three selected targets exercise real installed SDK process pipes, authenticated framed worker startup, and the private stdio protocol. Test processes receive a PATH containing the SDK binary directory; Node is used only to capture the original upstream reference and is not their runtime host.

The reference fixtures are actual Source `6fb2e7815167e6b19006fc526d1a5d0f5f998787` captures. The relevant AgentSession and terminal source files were checked against current42a authority. Fixtures preserve complete raw stdout/stderr and encode observations JSON as opaque base64 so isolated UTF-16 code units are retained exactly. No replacement-character substitution, key omission, or weaker Unicode comparison is allowed.

| Reference | Behavior | External capture SHA256 |
| --- | --- | --- |
| Source454 | Actual pipe metadata, Unicode keys, EOF, binary stdout and stderr | DEBB979C9EE940F85A611DBDF90AC03C2E08ED257C4CEB06C5B7394F0BDD05FA |
| Source455 | Global input/output after SDK disposal while the captured context rejects stale use | 345AF622345DE41CE6EB41A59E7921B361155A14F37CE411035BA863D00BDB98 |
| Source457 | Actual terminal extension factory; input callbacks run after factory return | C7C9A64FD495E77E4B89B6D40B37A65DB1FADECA9D5ACCF42443367F883F54E1 |
| Source460 | Pausing/stopping permits exit while the parent input pipe remains open | 700B75A58479E1DD8A70F987E6AD139E03B5238D79F1075035824D696E0F4D4E |

EOF prerequisite `3b4436e627f9ca16f437dad0068560bbef5e38d3` was qualified separately in all four Windows/Linux Debug/ReleaseSafe modes, 45/45 tests per mode, with unchanged posthashes. Its patch SHA256 is `E9BBDBB3C90951F064E6805705B55688345E0246A10A33AF3097AF9E9BB57AE1`; receipt SHA256 is `FA3A122353FF9E09F3BFFF1A4F82D115FB087D82A81A25B147EE541231786FB8`. This prerequisite proof does not qualify the SDK integration automatically.

Local snapshot465 compiled the real embedder and passed three actual SDK pipe tests plus two protocol tests. Its framed worker startup test failed with `JavaScriptExtensionClosed`; the worker termination cause is not established. Snapshot466 added framed termination diagnostics but encountered an inferred error-set compilation failure. Snapshot467 makes the worker owner's error union explicit; local admission was refused before launching a compiler because available RAM was below the guard. The hosted run is intended to obtain the first exact terminal diagnostic from that unchanged implementation.

Remaining work includes the concrete framed worker fix, the SDK integration's complete four-mode qualification and ownership checks, genuine Main shared terminal input/output wiring, physical console behavior, and AgentSession prompt/queue/compaction parity. Full migration and all required CI publication remain incomplete.

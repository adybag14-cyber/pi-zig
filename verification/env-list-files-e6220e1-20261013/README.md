# Private Pi 1.2.0 Env candidate

Base: `76692817853747a62aaf8b3745cd839be6ff3cbb`.
Authority: unmodified Pi `e6220e1316f86af818a0ccbfe1c09d7e918b41cf`.
Implementation: native Zig 0.16.0, with the existing direct Windows C ABI calls.

The reference daemon was built separately from the exact upstream checkout with
its locked Cargo dependencies. Rust and TypeScript are reference implementations
only; neither runs native product operations. The source-manifest fixture binds
the production source files, the reference daemon's SHA-256 and all captured
fixture hashes. The observer inputs below are preserved test callers, not product
implementations. Their original external paths are intentionally retained.

The immutable captured cases comprise 20 ordinary walks/bounds/errors, 89 ignore
pattern walks (including invalid UTF-8 and malformed patterns), 6 additional
protocol default/error cases, and 6 Windows edge cases. The latter include real
junction loops and an explicit linked root, hidden attributes, one unpaired
UTF-16 surrogate and UTF-8 payload byte limits. File symlink creation was denied
by Windows in that reference capture; directory junctions succeeded.

The preceding local Debug snapshot passed 10 tests with 1 explicit Windows
symlink-privilege skip. It covered the first 20 walks, the initial 70 ignore
patterns, actual local/remote capabilities and old-daemon fallback, unchanged
directory paging, exhaustive allocation-failure ownership, and daemon cancellation
followed by complete 10,100-entry and bounded 5,000-entry requests. Its full source
and Zig tool-tree pre/post hash checks reported zero drift.

The first hosted candidate `181b363` retained its genuine negative outcomes: its
inventory test used a runtime test count as an array type, and textual brace
expansion promoted embedded `**` into a recursive wildcard. The repair allocates
the actual compiler inventory at runtime and emits its marker on a separate line.
The glob implementation now parses the locked globset token semantics and compiles
an acyclic native state graph. Alternatives keep their original wildcard tokens;
`foo/{**,deep}/a.txt` consequently leaves `foo/a.txt` visible, as the source does.
Matching uses a bottom-up table, including wildcard self loops, without recursive
calls for successive path bytes. All original captured expectations are unchanged.

The repaired local Debug and ReleaseSafe gates each passed the actual selected
listing inventory of 12 tests (11 passed, one explicit file-symlink privilege skip)
and the complete existing Env inventory of 105 tests (88 passed, 17 platform/tool
skips). The Windows junction/surrogate test executed successfully. Each mode's full
4,585-source / 19,546-tool-file pre/post check reported zero drift. The ReleaseSafe
log also passed the workflow's actual-inventory coverage validator. Final hosted
qualification of the repaired candidate remains separate from these local results.

`.github/workflows/native-env-list-files.yml` runs both the complete selected
listing suite and the existing native Env regression target on Windows, with the
pinned official Zig 0.16.0 executable, LLVM, one build job, the original 120-second
test guard and a verified-owned 300-second outer deadline. It freezes every tracked
input and the full installed tool tree, verifies the original fixture pins, checks
the compiler's selected test names against every intended test body, rejects all
unexpected skips, and uploads terminal process, coverage and post-hash receipts.

The candidate does not register a QuickJS Env guest module, activate a native
default, establish complete Pi parity, or qualify a release. Full guest Connection,
Env, reader and callback lifetime integration remains a separate follow-up.

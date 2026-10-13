Private original VisualLinePreview dependency
===========================================

The native body follows the unchanged e6220e1 `visual-truncate.ts`: it renders
through actual native Text, slices visual lines, clips the caller's hint,
preserves cached array identity at the same width, and invalidates both cache
fields. The constructor, ordinary field order, method metadata, live option
getters, and exact caller exception identity are part of the 23-case comparator.
No session factory, builtin renderer, or public SDK activation is added.

The genuine latest Source runs use Node24.14.0 with source conditions and the
explicit experimental TypeScript transform. The audited official workspace
export resolver maps dist to unchanged src files. Every run checks all 1,945
latest runtime files, all 31,064 reused original runtime/dependency files, all
1,774 Node/tool files, and the 53 actually observed modules. Repeat captures
match every raw row, descriptor, cache relation and property order without
normalization. The stricter negative caller rethrows unexpected errors unchanged
and still requires the exact intended marker; both original captures before and
after this change produce the same 23 rows. Prior negatives remain retained.

The full comparator plus GC and allocator probe passed in Debug and ReleaseSafe.
Each mode has eight disjoint complete ranges of the same 4,562-allocation
baseline. Every index is present exactly once; each trial executes all 23
original cases and metadata checks. All 16 invocations passed 11/11 selected
tests and 156/156 build steps, with identical full 4,624-file source manifests and
zero source/tool post drift. The collector checks the retained begin/complete
markers, exact range floors, native terminal owners and every index.

The allocator sweep found a genuine native Text boundary failure at index847:
UTF16 host allocation failure was converted to an untagged VM error. The separate
one-line commit 31bdb48 preserves the engine's existing private native allocation
identity. It changes no user exception or message-based classification. Both
full sweeps include the failing index and the stronger caller fixture.

ReleaseSafe compilation ran separately with an owned 1,320-second compile-only
bound. Every runtime partition retains outer300, test120 and host10000ms, default
LLVM and j1. Each local launch passed fresh16GiB admission and recorded exact PID,
executable hash, argv and UTC creation/terminal times. The compile-only step ran
no tests. Hosted qualification is pending; this packet proves Windows local
component behavior, GC and all host allocation indices.

`source-qualification.json` records the original capture owners, manifests,
body hashes and retained negatives. `allocation-partitions-qualification.json`
records all 16 native gates. `collect-allocation-partitions.mjs` only verifies
receipts and never substitutes a probe. The private build aliases are
`build-native-sdk-tool-visual-preview` and `test-native-sdk-tool-visual-preview`.
The qualification worktree also contained an unselected listing-renderer build
alias and uncompiled WIP; neither is included in this component slice. The
qualified implementation/test/caller/golden hashes match the committed bytes;
new receipt metadata is recorded after the terminal native post checks.

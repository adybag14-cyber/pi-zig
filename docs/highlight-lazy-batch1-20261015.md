# Actual lazy grammar batch 1, source-only

This isolated batch starts at qualified eager highlighter commit `733800b8b872d86c5766dc4a30cf44ae8d373254`. It adds four actual highlight.js 10.7.3 factory bodies in Zig: `dockerfile`, `makefile`, `protobuf`, and `ini`. Their `create` and `build` entry points use the existing native legacy-function adapter and highlighter Scope. Existing core, compiler, scanner, eager registration, and frontend modules are unchanged.

The authority is the installed highlight.js package under the immutable upstream dependency checkout, covered by the complete 31,064-file dependency manifest. Each original factory's path and digest is retained in `verification/highlight-lazy-batch1-20261015/original-inputs.json`. The authoritative package index contains 191 canonical factories, including 170 outside the existing eager set.

TOML belongs to the actual `ini` factory and its `toml` alias. The installed version has no separate `toml.js`, `graphql.js`, or `hcl.js` factory, and GraphQL/HCL are absent from the 191-factory index. This batch does not invent those factories or replace them with another language.

The new bodies retain Source object field order, shared mode identities, regular-expression versus string values, helper getter order, ordinary receiver calls, Makefile identifier addition/coercion, and the assignment to the live object returned by INI's `COMMENT` helper. INI's private regex concatenation uses the existing native regex helpers, retaining their live array and regular-expression property behavior.

The shared input fixture prepares 29 comparisons: factory metadata, complete raw grammar graphs and identities, live helper access, throwing getters, coercion and setter behavior, twelve scanner samples, actual aliases, and unsupported factory absence. The capture driver loads the genuine installed original factories and core. The first checkpoint created no expected JSON; expected output was subsequently captured from the original modules, as recorded below.

Native checks remain Zig formatting and Git whitespace only. This checkpoint is uncompiled and does not activate lazy loading or claim these languages are available through the application. Integration must retain the actual 191-factory index order, including re-registration of the 21 eager factories.

## Genuine Source29 capture

The granted Source job completed with exit 0, PID 58460, using pinned Node 24.14.0, 128 MiB heap, and a 300-second operation deadline. Its result contains all 29 cases. The four deliberately throwing helper-getter cases produced their intended TypeErrors; all twelve actual scanner samples returned highlighted output without `errorRaised`.

The original captured JSON SHA-256 is `17d9117f4f5f94de6fd2a25c9c2cf162d5cae40fd656fb35802021ba88b00cd3`. It was copied unchanged into the fixture. Complete post-verification found zero drift among 1,967 Source files, 31,064 dependency/runtime files, 1,774 Node tools, all caller controls, and the Source path inventory. The observed-module log establishes that the original installed core and grammar files were loaded; it does not substitute an adapted grammar.

The native comparator and `build-native-highlight-lazy-batch1` / `test-native-highlight-lazy-batch1` targets are prepared. Their compile and runtime phases have not run. The baseline remains explicitly `733800b8`; a later independent core allocation-failure repair is owned by the core lane and has not been copied into this branch. Source capture success is not native grammar qualification or full lazy-index completion.

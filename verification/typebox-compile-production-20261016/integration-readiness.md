# Actual TypeBox graph integration readiness

`src/extensions/native_typebox_production_graph.zig` now assembles the actual
owner-realm graph through `create(engine)`. It returns one cached shared object
with `Memory`, `Settings`, `Freeze`, mutable `Type`, real `Compiler`, and separate
provider `Schemas.model` / `Schemas.compat` namespaces. Partial and generic
operators retain the same Memory/Settings/Type graph. Actual Compiler supplies
Codec constructors before real provider schema constructor operations run.
Consumers that export Type as an ESM namespace must finish the mutable builder
before sealing its namespace; this helper does not install global aliases.

The standalone `src/native_typebox_compile_production_test.zig` contains two
native replay tests, each creating a fresh Engine with 10000ms host guest await:
all80 actual Compile/Code/Validator observations, and all52 actual provider
schema/Partial/Memory observations on the same assembled compiler graph.
No public Compile binding points at the private tool-validator.

The generic operators already matched published3ed99011 byte-for-byte before
integration: local equivalents58312d1a/c5708548/6afb03c5 preserve the published
8abc2a98/682c2acc/3ed99011 chain. Published proof successor3432c219 was retained
as local0ffdea2d. Its independent Source396 packet verifier passed after
integration. Published schema/Partial/Memory proof f144385a was retained as
local30e7a9f0. Its historical COMPILE-AUDIT file was retained to resolve the
modify/delete conflict; product source had no conflict or change in that step.

Source80 proof8fd7ce24 retains actual paused candidate3b7a6480's successful
reference run. Its independent packet verifier passed after both integrations.
The uncompressed original prehash is also preserved outside this checkout at
`C:/Users/adyba/tmp-typebox-compile-production-20261016/source80-original-prehash.json`;
the committed ZIP contains its complete original bytes.

Validation so far: Zig0.16 formatting checks and `git diff --check` pass. The
new graph and tests have **not** had semantic compilation or native execution.
No shared Engine, shared build, SDK, main, release or activation file changed.
No HOST_GPA, exhaustive C malloc, complete TypeBox, full Pi, or activation claim
follows. Native checker ownership/fault injection and the previously documented
arbitrary BuildResult source mutation / overridden join risks remain open.

# Actual synchronous argument slots for Module paths and classic realpath

This source unit consumes the canonical native synchronous argument owner from
`5d0781260997f4ab05b9ce01d2db64ab9f4c0f7c`. It does not change that owner,
the lexical Frame implementation, or linked QuickJS.

The Module callable adds an opt-in factory with a separate formal count. It
forwards the original arguments and call flags, keeps the canonical Node
operation boundary live, and uses the actual new-target realm Object prototype
for constructor receiver creation. Existing callback/factory callers retain
their interface.

The actual `Module._nodeModulePaths(from)` and classic `realpathSync(p, options)`
callbacks now assign their real selected formal slots. They no longer retain
duplicate parameter roots in a separate Frame. Original locals are installed
once and close through the shared native argument owner's two terminal hooks.
The previously reviewed reverse scan and classic walk/encoding algorithms are
unchanged.

## Dependencies and source review

- Canonical synchronous argument adapter: `native_sync_arguments.zig`,
  SHA-256 `3AC7413F4C367E6C4F8FE75C963F2ABDA2522EB5A9652152E0EE6D25F0F4F3F6`.
- Canonical lexical Frame:
  `E478B2D425EA729F4B63D3E6033AAB8AB1C463211E14A7139EE2F072CE2163D1`.
- ModuleCallable factory/entry source: VM foundation finite peer closed.
- Module paths, borrowed realpath activation and actual callbacks:
  SDK owners finite peer closed.
- New controls: VM foundation finite peer closed on Module declarations 25–26
  and classic realpath declarations 22–23, including the genuine Probe/Fixture.

## Declared controls

No build target or filter is changed. The existing install-only Module creation
target gains two declarations (24 to 26), and the existing install-only classic
realpath target gains two declarations (21 to 23).

Each pair uses the genuine existing owner/fixture and an actual sole C holder.
The normal control observes original argument retirement before the next live
property access. The fatal control records the actual producer reason and
checks retained own numeric progress fields for one initial operation and zero
later guest/catch visits. These are native owner controls; the existing
independent Node observers and authorities are unchanged.

This is source-only work. No compiler, metadata, Node reference, native test,
filesystem observation or runtime qualification was executed for this unit.

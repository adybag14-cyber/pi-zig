# Native model-scope warning wrapper

Source basis: `c248553d15282e1e8ad896382c78132b6a501dd9`.

This packet implements the complete original `resolveModelScope` wrapper in
`4954d76`'s coding-agent model resolver. The native function awaits the actual
diagnostics resolver, destructures its result once, emits each warning through
the actual consumed Chalk default and the live console binding, and returns the
original scoped-model value. It supplies a concrete dependency of Main's
`createRuntime` closure; it does not implement or publish that closure.

## Production changes

- A private cached owner captures the genuine CLI thinking binding, real
  `resolveModelScopeWithDiagnostics`, and real Chalk default. Cache publication
  follows successful construction; cold creation reentry is rejected.
- The async body uses one real Await, preserves thrown identity, original
  destructuring order, cached iterator next, abrupt IteratorClose and native
  fatal/cancellation handling.
- Expression subscopes retire the message coercion operand before the color
  call and the color callable before `console.warn`. The old draft retained
  both too long. Loop-head locals stay alive until their original replacement
  or terminal retirement.
- One additive C/header API, `JS_PiGetGlobalBinding(ctx, atom)`, forwards to the
  existing `JS_GetGlobalVar(ctx, atom, true)`. It preserves global lexical
  bindings, TDZ and missing-identifier ReferenceError semantics. The owner uses
  it only for the original unqualified `console` identifier. Existing VM
  algorithms, bytecode version and shared Zig global-property helper are
  unchanged.

## Controls and boundaries

The packet declares 44 named controls: 37 independent original/native
comparisons, three actual fatal/cancellation checks, and four cache/assembly
checks. Both comparison sides acquire genuine native imported owners. Twelve
cases exercise the real lower resolver with explicit caller-provided model
records. The remaining comparisons perturb a property of the actual resolver
namespace before wrapper capture to isolate result-destructuring and warning
semantics; those are controlled seam tests, not a physical ModelRuntime claim.

The original function fixture preserves its body byte-for-byte; only the
TypeScript signature and export marker are erased, and a strict control factory
captures the original imports. No JavaScript implementation is added to
production. No Node reference capture, compiler, test binary or native runtime
was executed while authoring this packet.

The install-only target is `build-native-sdk-model-scope-warning`; its explicit
Windows filename is `native-sdk-model-scope-warning.exe`. It uses the updated
QuickJS C source through the existing shared library builder.

## Static checks

The patch applies with `git apply --check` against clean Main c248553d.
Complete inverse checks recover the original C, header and build bytes.
Existing tracked source and test names remain intact. Metadata records exact
original authority, import/fixture resolutions and file hashes. These are
source checks; actual compiled metadata and runtime results remain null.

## Remaining application work

The actual cwd/trust-aware `createRuntime` closure must consume this callable
together with shared SettingsManager, trust resolver/store, runtime service
factory, settings diagnostics and the existing option/path helpers. Canonical
Module assembly and production entry wiring remain unfinished. The production
bridge stays selected until whole-application parity is established.

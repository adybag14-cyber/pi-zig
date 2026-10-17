# Canonical Node builtin alias proposal

Root explicitly authorized these isolated Engine hunks after the generic TTY
assembly review. The generic assembly closure at `edd289975db2dce3f511d6e546b9404559e70c8a`
does not cover this new unit. No Main/C/header/default-selection changes or
execution belong here.

The API `Engine.registerBuiltinAlias(bare, canonical)` maps an explicit bare
Node builtin to an already registered canonical `node:` C module. It requires
the exact suffix relationship, rejects path/invalid/conflicting inputs and alias
chains, and owns both strings. All allocation precedes map publication. No
second C module, mutable forwarder, ordinary fake namespace or JS host body is
created. Existing Source registration and value-module APIs reject shadowing
an admitted alias.

ESM normalization resolves the alias before consulting a project loader, as
existing registered Node builtins already do. `normalizeRequire` and direct
host `requireBuiltin` resolve the SAME canonical name and actual carrier.
`setSourceLoader` always refreshes alias-aware normalization, so replacing a
user loader cannot accidentally disable alias identity. Every unrelated input
still delegates to the existing user normalizer/require normalizer/load/input
paths with its original caller/base/name. There is no fragile loader wrapper,
borrowed wrapper-context lifetime or extra public alias namespace object.

When no user normalizer exists, alias support still needs a host normalizer.
The new native helper preserves the linked C engine's actual default algorithm
from `vendor/quickjs/quickjs.c:js_default_module_normalize_name`: names without
an initial dot stay unchanged; only leading `./` and `../` are reduced, using
the base's forward-slash directory and retaining `.`/`..` segment barriers.
It is not filesystem path resolution. Returned strings use the actual VM
allocator expected by `JSModuleNormalizeFunc`. Checked capacity arithmetic
rejects impossible size overflow instead of reproducing C integer overflow.
No C API addition is required.

The TTY assembler now publishes three canonical C modules plus three aliases.
Actual TTY/util/readline bare and prefixed ESM imports therefore resolve to the
same module/namespace, default carrier, constructors and functions. Publication
remains sticky after a real C-module/alias allocation failure. The existing
publication control counts both immutable canonical names and explicit aliases;
it does not count an alias as another native C module.

Root current Engine authority is exactly
`bfb33a2312c5dd75173ad0b8eb6f6ad111c4f78c`, blob
`e0724e9d6bce414173f1421eb100ea2b827df95a`, SHA256
`80BC71798070DF9855D87AD123F8543BF311B56837B355D902E1778F545BA422`.
Only unchanged map/deinit/builtin-normalizer/require seams were edited in the
older isolated tree. A separate private-index projection checks/applies those
exact hunks against Bfb, then reverses the canonical Bfb patch and proves its
whole tree equals the original Bfb tree. This preserves all current AF,
capture/producer, await, heap and other Engine code; no old whole-file copy is
an intake candidate.

Projection evidence:
`evidence/node-tty-alias-bfb-projection-sourceonly-20261017/projection.json`.
Prospective Bfb Engine SHA256:
`C04A16D26138C02D0162FF5D51D1DB3D68F5B06754873BAE9619567EADEEC875`.
Canonical Engine-only Bfb patch SHA256:
`3B76749A9FBA59D34535CFB2927728B9BF53C6EBD62917CD54785CC5D5C82A4B`.

Prepared controls, all UNRUN:

- Original Node24 `original-alias-identity.mjs` records actual import namespace,
  defaults, real createRequire and constructor identity. The actual typed
  assembly identity helper evaluates those exact original caller inputs through
  the linked runtime after real installation; expected captures remain absent.
- Actual installed TTY plus a controlled user Source fixture proves project
  normalization sees the original base/name once while builtin imports bypass
  it, then replacing the loader without a normalizer preserves aliases and
  direct host require identity. The user fixture is extension input, not a
  production host implementation or fake provider.
- A genuine current Error with observable native `toString` tests direct alias
  admission: exact reason, no map mutation, no formatting, balanced suppression.
- Fresh actual private TTY exports register one canonical C module; actual
  failing-GPA alias admission must publish nothing. Normal-GPA retry must
  resolve the same namespace and reject source-module shadowing. Failure
  positions are admitted separately by the eventual owner, not a runtime claim.

Independent alias source review and exact Bfb dependency composition remain
required. Root's native/runtime/ABI grants and frontend qualification are
separate. No compiler, Node, formatter, parser, AST or native job ran.

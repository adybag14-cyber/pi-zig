# Pathe finite source-review successor — unrun

Frozen954ad45c and pathe-source-manifest.json remain historical source-review
material. This successor corrects the independent finite findings without
changing the313 original input or five original native controls. The additional
six-observation original subject and its comparison test are separate files;
expected JSON for both subjects remains absent. Three namespace-local native
controls additionally cover cancellation/quota and primitive-close allocation.

Corrections:

- normalizeWindowsPath's /\\/g and dirname's /\/$/ are fresh literals at their
  actual call positions, after resolving replace. True module constants remain
  shared. Retained regexp mutation cannot affect a future inline literal.
- basename resolves slice before reading extension.length. Numeric unary-minus
  emulation preserves negative zero; unusual BigInt extension values remain
  explicitly unqualified, outside the actual jiti basename(path) call contract.
- normalizeString saves the left value, evaluates slice and RHS template string
  coercion first, then uses binary+ default left coercion, matching compound +=.
- Throw-completion IteratorClose gets/calls return and discards a normal result
  before any object-result validation, preserving the primary. Normal early
  return/destructuring still uses validating close. Trusted fatal policy remains:
  cleanup native allocation bypasses ordinary primary; already-fatal primary
  retains exact identity even if cleanup throws. Capture slots transfer ownership
  with null-before-free ordering.
- forIn checks the existing resource budget for every native key, including its
  growing seen-key lookup. No enumeration/proxy policy expansion is claimed.
- Controlled cancellation/quota marks its own created interruption reason
  uncatchable before checked capture. Namespace-local advance reproduces shared
  next/done/closed/value behavior with one fatal budget check before its error
  closure. All five pathe iterator-next sites use it; shared Iterator/C/Engine
  files remain unchanged. Ordinary guest lookalikes are never classified fatal.

The source review used official pathe2.0.3 published payload and ECMAScript
IteratorClose throw-completion ordering. Native failing-allocator control arms
only after iterator/method/primary preparation and requires primitive return
cleanup not to allocate a TypeError. Native cancellation and300-key quota
controls require uncatchable reasons; an ordinary interrupted lookalike remains
catchable. All controls are authored, not executed. No golden answers exist.

No formatter, AST, Node, eval, source generator, compiler or native job ran.
No Main, C, Engine, shared helper, build target or default registration changed.
Broader proxy/mutation/nonstandard-extension frontiers documented in the base
scope remain unqualified. The actual mlly URL/resolver task continues separately.

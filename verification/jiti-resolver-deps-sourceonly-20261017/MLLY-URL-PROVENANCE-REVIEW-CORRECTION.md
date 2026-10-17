# URL wrapper provenance review correction — source only

Independent review of frozen7b9a685f found one additional private trusted guard:
native_mlly_urls.exact still used its original broad invocation generation. Both
real public URL wrapper exports pass through that guard, so a live String.replace
operation entering a nested ordinary normal-close could be promoted there before
the complete callable exit consulted the new provenance floor.

This one product line now consults functions.trustedGeneration, like the three
other guarded paths. The7b9 checkpoint/manifest and all historical inputs remain
unchanged. No shared code, C/H, Engine or namespace selection changes.

An additional actual-import entrypoint verifyActualURLWrapperReentry constructs
the genuine native URL wrapper carrier with required actual Node URL bindings.
Its live String.replace hook enters the actual nested normal-close callback; the
ordinary profile checks exact older-loop reason and an empty captured slot for
both fileURLToPath/pathToFileURL. The later-fresh profile raises a new native
allocation after that ordinary boundary and checks fatal bypass/identity through
each complete public URL wrapper. Each of these four profiles requires its own
fresh realm. Only an entirely successful ordinary profile restores the guest
descriptor; earlier ordinary/fatal/OOM failure exits to realm teardown. No fake
successful Node conversion is supplied. There are21 test declarations and now4
actual-import entrypoint functions (the new one has four required profiles).

All controls remain authored/unrun. Original51, supplemental8 and new15 expected
files are absent. All89 primary files and17 fixture files remain byte-exact.
No Node/compiler/AST/native/formatter/generator/capture job was run.

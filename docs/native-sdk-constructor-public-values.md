# Ordinary native session constructor and public values

Implementation071d00ca64f0a68fc8b632d5e0ed300839c8a4e6 ports the ordinary
AgentSession declarations/configuration/constructor body, native bound event
handler, public getters and value methods, and constructor tool-name matcher.
The private constructor requires the original complete runtime-building and
transcript-restoration methods on its prototype; no successful stub or public
activation is installed.

Genuine latest upstream e6220e1 evidence covers66 own field descriptors observed
immediately before original `_buildRuntime` (the observer calls its body once),
43 public getter/route/tool-metadata scenarios, and27 tool-name matcher scenarios.
The public getters read actual ordinary fields, retain references, honor live
getters, and preserve VM arithmetic and original thrown identities. The event
regression retains28 original factory scenarios and16 original hook scenarios.

Windows Debug passed the four relevant artifacts: constructor10, values11,
events12 and matcher4 tests. The combined run also exercised the private loadout
and finished47/48, with only its fullSource55 allocation sweep exceeding120s.
That negative is retained; it is not a combined integration pass. The unchanged
loadout fixture is being qualified separately across every original allocation
failure index.

Windows ReleaseSafe passed all37 relevant tests. Compilation had its separate
1320s envelope; runtime retained120s per test,10000ms host awaits and300s outer.
Full4722-file source and19546-file compiler posthashes show zero drift. Binary
Git blob verification confirms every4722 committed source blob matches the
successful ReleaseSafe input bytes.

The cross-platform candidate workflow checks the same four artifacts and their
actual per-target completion counts in both modes on Windows/Linux/macOS. Those
hosted results are pending. Full runtime/registry/core binding, public factory,
remaining lifecycle methods and complete Pi parity are still required before
removing the implementation compatibility bridge.

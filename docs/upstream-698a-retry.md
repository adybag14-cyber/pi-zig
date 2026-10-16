# Upstream gateway retry update

Official Pi advanced from `4dd2b149d155d7369de16ea4dc77c84e9f5ffb24`
to `698a2d23b86a5045dd54554354a5e0cb7e466795` on 16 October 2026.
The one-commit delta changes the retry classifier, its regression tests and
the AI changelog. The retained source is under the project container's
`upstream/snapshots/698a2d23-20261016`.

The native VM classifier's embedded expression now includes the same four
additional alternatives in their original order. The typed Zig retry helper
also recognizes these gateway failures, with quota/billing exclusions still
checked first. Its optional separators consume at most one non-line-terminator
UTF-16 code unit, preserving the upstream regexp's distinction between a BMP
separator and an astral character. HTTP/2 permits exactly one optional slash.

The standalone Debug unit gate passed all ten tests, including the upstream
gateway examples and negative separator, line-terminator, astral and quota
controls. Its canonical owner recorded compile/runtime exit zero, exact
executable hashes and start times. Full inventories of all 19,546 compiler
files matched before and after, source/control drift was zero, and the final
native process census was empty. The short-lived runtime exited before the
CIM command-line query returned, so its live command-line field is null. This
ordinary unit result is not accepted as a full native differential proof.

The sealed packet is in `verification/upstream-698a-retry-20261016`.
It preserves raw receipts and logs, the exact tested source, build/driver,
compiler inventories and executable. It excludes disposable build caches.

The embedded VM classifier still needs its own genuine-source observations
and native replay. Historical 4dd Source273 observations and expected files
remain unchanged; this small standalone gate does not qualify the default
SDK/CLI, extension runtime, hosted profiles or release.

Upstream change: https://github.com/earendil-works/pi/commit/698a2d23b86a5045dd54554354a5e0cb7e466795

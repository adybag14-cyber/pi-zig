# Prospective reproduction tool closure (unreviewed, no execution)

The immutable historical 1,774-file tool manifest comprises global node.exe plus
the npm subtree. It does not seal every file in the global nodejs directory or
the Windows shell. Keep this authority boundary explicit. Full inventory checks
must enumerate the npm subtree and compare all its expected files/reparse points,
then check node.exe separately. Do not falsely require the entire nodejs parent
to contain only those historical files or silently absorb today's extras.

Root subsequently released additional original full Node authority:
`evidence/typebox-heap-scope-args-static-second49d-20261016-frozen.json`,
SHA35F1F2B0F12BF79C06B47AE2BA8C485EF10A7714BE3F129772E3BA1BBB97B927,
property node_complete (1,838 rows). Read-only manifest comparison confirmed all
1,774 older rows have identical paths/hashes, with64 additional launcher/Corepack
files. This separate authority does not rewrite the1774 manifest or restore the
runtime. Native tools.zig now provides a mandatory full1838 file/inventory check
for future admission. Actual1838 tool files were not rehashed during source
authoring; the helper remains uncompiled/unexecuted. Prefix selection still
requires the separately reviewed private resolver/wrapper decision below.

The original 19cb build:offline shell graph uses npm run, tsc, shx and node.
It builds chord/tui/telemetry/codemode/mcp, ai offline, durable/env/agent, then
coding-agent unbundled and its esbuild bundle. The bundle invokes esbuild's exact
staged native service. No npx invocation occurs in this graph. Original build
scripts, .bin shims, TypeScript, shx and esbuild bytes remain prebuild-manifest
inputs; do not regenerate or edit them for this owner.

Root allowed a separately reviewed prospective control-tool closure, without
claiming historical equality for shims absent from the old tool manifest.
Read-only current inspection found:

| File | SHA256 |
| --- | --- |
| C:\Program Files\nodejs\npm.cmd | 21B46C69AD6E2F231F02A9E120F4BA6C8E75FEF5A45637103002EAB99F888AB8 |
| C:\Program Files\nodejs\npx.cmd | 4DD3574F4396FC3B45C52B6AC80FD52BE2DD2660D2A153B4CC807DBBFEEFA7A0 |
| C:\Windows\System32\cmd.exe | 15CD209C995B7D3009C91CA40892D5B8F1FB162F3E5F10716642EA278E8E0D7B |

The installed npm.cmd invokes npm-prefix.js and can redirect npm-cli.js to a
prefix-dependent location. Hashing the shim alone does not constrain that
resolution. Proposed alternative, subject to source review: a contained private
PATH directory with byte-verified copied Node and only the minimal npm.cmd source
below, forwarding to the global pinned node.exe and npm-cli.js. Set the npm
script-shell and ComSpec to the separately reviewed absolute cmd.exe. Do not put
System32, Windows or the unrestricted global nodejs directory on PATH. Npm's
own staged .bin additions remain full original-manifest inputs. Deny npx and
unneeded tools by omitting them from that private directory.

```bat
@ECHO OFF
"C:\Program Files\nodejs\node.exe" "C:\Program Files\nodejs\node_modules\npm\bin\npm-cli.js" %*
```

This changes the prospective control environment; it does not establish original
shim byte identity. A bare `node` may resolve to the byte-identical private copy,
whereas process.execPath from the directly invoked pinned root Node stays global.
Record that distinction, inventory the private directory exactly and require full
original output hashes. Review npm/.bin resolution and actual child launch APIs
before acceptance. No private PATH directory, copied Node or installed wrapper
has been created by this source proposal. Root review remains required.

The concrete uninstalled forwarding source is npm.cmd.source in this leaf.
Native tools.zig checks the exact private two-file inventory, the separately
reviewed cmd.exe hash, original Node bytes, and a Root-reviewed wrapper hash.
The installer/composition is not implemented or admitted yet. This source file
is not on PATH and was never invoked.

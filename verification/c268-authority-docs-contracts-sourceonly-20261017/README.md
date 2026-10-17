# c268 source marker and pending native whole-tree contract

This narrow source preparation starts at Root
`bfb33a2312c5dd75173ad0b8eb6f6ad111c4f78c`. It updates the human-maintained
source target and current documentation to
`c268154ca1171c2f9eefe75d3d7372a68aada2d5`, with package version 1.3.0.
It does not create a generated contract, edit generated catalogs, execute an
upstream program, or certify the new native adapters or whole application.

## Authority and expected scope

The official retained comparison at
`evidence/upstream-c268-live-audit-20261017/compare.json` identifies one commit
after `8efd314fa3d3232ce197d8d7a6a5660530b9d83e`. The comparison names 25
files. This packet also contains freshly fetched, nontruncated official Git
trees by their actual tree object IDs: c268 tree
`b9004b99aceb672e8295412ee0e25f6b46063ed5` and 8efd tree
`1cf799825d6626bc9771518699091b165d51f2e3`. Their pinned record maps agree
with the earlier reviewed SQLite source audit.

The immediate delta contains 10 additions and 15 changes, no removals. It moves
the portable SQLite drivers/migration/schema interfaces into Chord, keeps
Durable compatibility reexports and storage wrappers, and changes package
exports, tests, documentation and the root TypeScript path map. The agent,
coding-agent and AI subtree identities remain unchanged. The actual moved Node
and Cloudflare algorithm bodies were compared in the retained shared SQLite
source packet; original source observations retain their own exact revisions.

The official c268 tree contains 1,941 tracked blobs. This is a read-only Git
metadata count, not output from a new native contract capture. The scheduled
workflow still selects `verification/upstream-contract/tree-97195ec3.json`,
whose 2,017 records predict a much larger delta: 107 added, 183 removed and
310 changed paths. `expected-delta.json` records the exact prospective path
sets and object/mode/kind identities. It is an audit input, NOT a generated
contract or an executed checker receipt. Reviewing only the immediate 25 paths
does not erase the older scheduled baseline's accumulated drift.

## Existing native machinery

- `tools/upstream_contract.zig` implements `capture` and `verify` without
  executing upstream JavaScript/TypeScript. Capture checks exact `git HEAD`,
  rejects dirty tracked source, obtains Git object format and parses native
  `git ls-tree -r -z HEAD`. The schema contains every tracked path, mode,
  object kind and object ID. It preserves path case and fails invalid input.
- `tools/maintenance.zig` exposes the actual commands
  `capture-upstream-contract <root> <expected-commit> <new-manifest>` and
  `verify-upstream-contract <root> <manifest>`. The former writes new bytes;
  the latter recaptures and compares complete maps plus commit/object format.
  Git subprocesses are bounded to 30 seconds, 32 MiB stdout and 8 KiB stderr.
- `build.zig` supplies the native `maintenance` executable step and the
  `test-upstream-contract` native test step. The tool is built with the pinned
  Zig 0.16.0 compiler. Its literal native tool-module closure and entry hashes
  are recorded in `generator-plan.json`; that finite list is not a substitute
  for Root's full compiler/process pre/post seals at execution time.
- `.github/workflows/upstream-contract.yml` runs that native test and checker.
  Its current 97195 manifest path remains unchanged in this preparation.

No accepted checkout or snapshot was advanced. At preparation time the shared
`upstream/pi` checkout is still at 4dd2b149 and lacks the c268 object; no clean
contained c268 snapshot exists. A separately authorized source acquisition must
create a NEW detached checkout at the exact c268 commit and preserve accepted
snapshots. The two API tree records are not a replacement for the actual clean
Git checkout required by the native tool.

## Exact future invocation, not executed

Root must first grant and seal the native tool build/run, create and independently
verify the complete clean c268 Git checkout, verify the compiler/Git executables
and exact native source head, and apply its usual owned-process/admission/
deadline/pre-post rules. Do not invoke these commands while the serial lease is
held. `generator-plan.json` records the executable pin and full arguments.

From the accepted isolated native source checkout, with `$zig` resolving to
`C:\Users\adyba\pi-zig\toolchain\zig-x86_64-windows-0.16.0\zig.exe` and
`$source` resolving to the NEW complete clean detached c268 checkout:

```powershell
& $zig build test-upstream-contract -Doptimize=Debug -j1 --summary all
& $zig build maintenance -Doptimize=Debug -j1 -- verify-upstream-contract $source verification/upstream-contract/tree-97195ec3.json
& $zig build maintenance -Doptimize=Debug -j1 -- capture-upstream-contract $source c268154ca1171c2f9eefe75d3d7372a68aada2d5 verification/upstream-contract/tree-c268154c.json
& $zig build maintenance -Doptimize=Debug -j1 -- verify-upstream-contract $source verification/upstream-contract/tree-c268154c.json
```

The old-baseline verification is an intentionally negative drift observation:
the predicted count is `upstream_files=1941 added=107 removed=183 changed=310`
followed by `UpstreamContractDrift`. Its actual terminal result and complete
path list must be retained and reviewed; this packet does not claim it passed.
The generator destination MUST be absent before capture so an old record cannot
be overwritten. Only actual native generator bytes become the new contract.
The new checker must then terminate successfully with zero additions/removals/
changes and exact c268 provenance. Actual inventories, hashes and terminal
process absence remain required. If observed counts or identities differ,
stop and investigate instead of editing generated output or expectations.

Only after that source/evidence review should a separate source change point
the workflow from `tree-97195ec3.json` to `tree-c268154c.json`. Do not select a
missing manifest, normalize old observations, weaken drift checks, or mark
behavioral compatibility on the basis of structural capture.

## Preserved qualification boundaries

The actual c268 Node/direct-C, Cloudflare and portable source units are reviewed
and intaken. Their original-source/native execution, real filesystem/storage/
ABI dependencies, combined graph, allocation/GC/teardown, default selection and
complete Pi parity remain separate gates. No such result is created here.
The ae7/FFA3 catalog and its source/archive digests stay unchanged. The c268
change does not alter the AI subtree, so it does not justify relabeling or
regenerating model catalog provenance. Native catalog/schema generators and
their checkers retain their own actual source requirements.

`tools/release.zig` still requires a complete parity-certified artifact manifest
and exact catalog/source identities. Changing the source target marker does
not satisfy or weaken that release guard. Historical fixtures, all 12 existing
whole-tree contracts and their qualification records remain unchanged.

No native tool, Node, generator, parser, formatter, compiler or runtime job ran.
No current native artifact metadata, source-capture result or generated c268
manifest exists as a result of this preparation. Main was not edited.

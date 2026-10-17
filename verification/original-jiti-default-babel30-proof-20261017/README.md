# Original Jiti default Babel30 raw authority

This packet preserves the actual original Jiti 2.7 default Babel/public Jiti
capture from `root-original-babel30-20261017-145214`. It contains thirty ordered
observations: twelve actual consumed function evaluations and eighteen compiler
frontier observations. The original package executed through Node v24.14.0;
no native candidate implementation or custom transform executed.

`original-output.json` is an immutable byte copy of the actual 33,061-byte
capture, SHA256
`96DA1A507001E61D539E067E99203B4F35BF982BEF64D8A3A7E152B350DC5C37`.
It is original authority for a future comparison. No native expected fixture
was generated. The archive also retains the exact original raw stdout copy.

The eighteen frontier rows contain original compiler results, including the
recorded Babel SyntaxErrors for `jsx` and `malformed-source-diagnostic`. They
were not evaluated and are not eighteen successful transformations. Full
generated code and actual evaluated function text remain in the raw JSON.
Observed behavior includes `live-named-import` returning `[1,1]`, and
`meta-resolve-real-builtin` returning the captured fixture-relative file URL
ending in `/fixtures/node:fs`. These observations are preserved verbatim.

## Contents and integrity

- `original-jiti-default-babel30-raw-proof-20261017.zip` contains 97 entries:
  complete actual run records and all 33 owned fixture files; all four full
  before/before-node/after-node/final seals; exact original caller and inputs;
  driver, stdin bootstrap, issued grant, Node owner and outer owner receipts,
  streams and absence records; original Node authority inventories; workspace
  resolver/layout controls; complete official 16-file Jiti package, including
  its license; independent raw and controller audits; and the prior D25 source
  negative packet.
- `public-manifest.json` lists each archive path, byte length and SHA256. It
  also pins the archive and separate original output.
- `package-verification.json` records two byte-identical ZIP writes and
  decompressed SHA256 verification of every entry in each write. Entry ordering
  is ordinal, timestamps are fixed at 1980-01-01, and external attributes are
  zero. Determinism is established for these two writes with the same payload
  and .NET implementation.

The archive SHA256 is
`862DE2B15FA5229D51AC60DCE46B6129B03557B20C3D56A8DF27F939C5661D7E`
and its size is 6,247,275 bytes. The independently accepted raw audit SHA256 is
`D7F1AE1AF872564F9AC1BAE0452BE4B4DE3B2B75176BE70D3A6B78200A6421F5`.

## Actual execution and authority boundary

The complete seals bind the clean source/control checkout
`9f4fc947e93eb9230eecd3f79838e69db3308976`: 10,965 source/tree files,
the original Node inventories of 1,774 and 1,838 files, all sixteen official
package files and sixteen control files. All four phases and the independent
current rehash had zero drift. Complete source and Node inventories are
included; whole source and Node installation payloads are excluded.

The exact actual driver is
`4C4F299DEC04B41820264F6151D3809B5C4F32F0515C5B72491B870E8AB9474C`.
Canonical CI owner `607BEDBB...B38285` launched actual Node PID 43192 with a
60-second deadline, 256 MiB V8 heap flag and ten-second pipe settlement. The
builtin bootstrap waited for the exact live-identity stdin fence before
importing the original caller. The outer `53E522C8...3D56B6B` owner launched
actual PowerShell PID 48756 with its independent 600-second deadline. Both
owners exited zero, stderr streams were empty, and full postseals and recorded
owned/global absence passed. The independent auditor did not run a new process
census. Fresh admission recorded 22,671,904 KiB free and no native candidates.
The heap flag and resource reserve do not establish an operating-system memory
cap.

The original `result.node_owner` empty-object-plus-receipt array quirk remains
unchanged. The scalar `node.json` is the authoritative Node owner record.
Original receipts retain historical absolute paths; moving these copies is
not a new run and this archive is not a directly runnable relocated collector.

The unchanged older D25 prospective packet is retained under
`controls/d25-source-negative/`. Its source-review finding was an incomplete
ambient Babel environment reset; it was not an executed failed capture. The
actual 4C4 successor changes only the child-process reset predicate to include
both `JITI_*` and `BABEL_*`. It retains the dedicated child guard, NullString
reset, absence verification and names-only environment record. No host
environment values were published or host environment mutated.

Node/PowerShell executable payloads, the Node installation, caches, PDBs,
objects, native executables and libraries are excluded. Their identity remains
in the original owner/inventory records; a local-only ledger records excluded
images and the retained repeat archive.

This intake is based on `65dc640634d6bb1ae3ed4fba8a6b17eb50ab83b7`
and adds only these five verification files. It does not change the frozen
source checkout, product code, prior observations or expected fixtures. This
packet qualifies the finite original authority capture. It does not establish
native runtime/API/default-loader behavior, complete Babel parity, Main
qualification or global runtime restoration. Packaging ran no Node, native,
compiler, AST, parser or generator job.

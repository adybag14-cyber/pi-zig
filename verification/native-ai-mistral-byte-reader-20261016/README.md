# Native Mistral reader and incremental byte proof checkpoints

These are scoped passing controls with explicitly preserved negatives. Full
Source30, full Source20, full Pi and public activation remain false.

* Product10f9d7bd2651819f8a7febf9f54d6105e42fca39: Debug compile and exact75
  metadata passed; runtime74/75 passed. The real loopback incremental-byte
  before-EOF gate passed. Strict original Source30 still fails at
  mistral-thinking-tools intermediate snapshots. Archive SHA256
  C3C0D2134C06F45F570F134F99FF32974518ED6EE86AC61E32065C0B55897DC2.
* Product28c434c288d57f17c92136f2aff0b82526a4e2ec adds only the explicit
  anyerror return type needed by the Source20 peer's Future declaration.
  Debug compile and exact9 metadata passed; runtime5/9 passed. Custom-fetch
  functional/getter/reader, retained GC and pending GC controls passed. Raw
  Google wire property order, strict wire/abort snapshots and the complete
  custom reader allocation graph remain negative. The original compile type
  failure is retained. Archive SHA256
  9D8E5E1964DA841DAAD10A9768E45742611B3E501DE3002552BF4BCDE71BC710.

Both archives contain the exact tested binary, candidate source blobs retrieved
from their tested Git heads, real metadata and logs, original B919 owner and
caller controls, full before/intermediate/post inventories and the independent
terminal absence record. Every archive payload was independently verified.
Run Verify-Proof.ps1 with -Archive to verify every retained payload.

The subsequent Google raw-wire source-only repair is not tested by these
artifacts. Its parts-before-role wire conversion preserves the original raw
body assertion and does not establish broader SDK part/schema conversion.

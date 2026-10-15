# Source100 and native collector checkpoint with one-shot negative

The tested code is exactly `eb74136ffd546cbc8787ef1358cb7112ec24714b`.
This is a scoped evidence checkpoint, not a complete one-shot qualification.
Original Source100 capture and its verbatim fixture are retained in the existing
`ai-one-shot-source100-20261015` directory. Source100 means80 provider/helper
observations plus20 separate image registry/dispatcher observations, pinned to
historical5ab. Newer ae7 catalog counts are not substituted into that fixture.

The first native compile on5b0c7fdf failed on four Zig0.16 shadowing declarations.
Its complete posthash passed. The second exact candidate compiled successfully
with157/157 build steps, owned Zig66576 exit0. Matching runtime owned Zig71400
completed with exit1: the body collector target passed5/5 runner tests, while
the one-shot target passed5 and crashed1. Runner totals include a module smoke
test per target; there are nine authored semantic tests across the two files.

The one-shot full80-control test crashed at QuickJS teardown asserting
`list_empty(&rt->gc_obj_list)`. Its complete native Source80 comparison therefore
remains unqualified. Other one-shot authored tests passed, including owned
native HTTP image success/error bodies above700KiB, repeated cookie headers,
image registry semantics, retained facade GC and pure helper host-GPA failures.
Those large-wire cases are owned native controls; the separate genuine
LargeImageSource2 capture has not run and is not inferred from Source100.

The collector's four authored controls passed: large/owned bytes and ArrayBuffer,
UTF8/BOM/EOF, chunk mutation, byte-event framing, wrong brands, original read
error identity, explicit byte limit, abort/cancel, pending GC roots and exhaustive
host-GPA setup/concatenation/decoding/continuation failures. The worker's separate
page allocator is outside that OOM injection scope. BodyUsed/clone/real readable
stream facade behavior belongs to the separate web Body owner and is not
qualified here.

All complete native posthashes passed: candidate6147, vendor1316, compiler19546,
controls9, historical Source1967, dependencies31064, Node1774 and84 absence
records. Frozen first/second runner bytes are retained separately so later
attempts cannot overwrite their historical control identities.

Source inspection found an owned retry-sleep promise omitted from a Scope;
follow-up source-only fixb0b97b2d is queued separately. This checkpoint retains
the tested code and negative evidence unchanged. Full one-shot APIs, full
factory/application parity and public activation remain false.

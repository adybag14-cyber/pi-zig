Separate Root-authorized followup to the reviewed native lstat seam. This
packet addresses the two concrete inherited shared metadata bugs reported
during lstat source review, without changing the historical lstat packet.
No compiler/native/Node/generator job is authorized or executed here.

Pinned Node24.14 libuv fs__stat_assign_statbuf computes Windows directory
permissions as 0666 or 0444, without execute bits. The existing native stat
helper added0111; the shared followup removes that extra bit calculation.
Source number and BigInt stat/lstat directory/file cases are prepared, with
actual mode values measured only by a later separately granted Node capture.

Pinned lib/internal/fs/utils.js imports BigInt from primordials and uses it
for BigIntStats._checkModeProperty. The underlying stats binding constructs
BigInt values independently of mutable guest globals. Node's primordial module
captures globalThis.BigInt before guest work. Engine already captures the
actual VM BigInt constructor during Engine.init before user execution and
retains it through deinit. Reusing that existing genuine intrinsic avoids
guest global lookup without a new Engine field, substitute callable or facade.

source-caller.mjs uses actual Node statSync/lstatSync and actual returned Stats
objects. It prepares throwing global BigInt getter and replaced-function cases,
existing Stats method calls, a real mode receiver getter and property coercion,
and raw reason identity. Both global mutations restore the original descriptor
in finally. No observer computes a native golden or copies a Stats algorithm.
Expected/observed files remain absent until Root's genuine capture admission.

Native followup controls must execute these same product routes with actual
metadata and shared Stats prototypes, retain raw getter reason identity, and
show no guest-global BigInt accesses. Exact source/native values, GC and fatal
completion remain unqualified until their separate grants. The old 899/57f/
912/719 packet history retains its truthful inherited-gap statements.

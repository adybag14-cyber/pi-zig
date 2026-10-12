# Complete bounded allocation failure coverage

The macOS Debug job for published `a3b96ad` hit the unchanged 120-second test
guard in four CodeMode allocation probes, the native worker-owner probe, and
the TuiAltScreen constructor probe. Their original test bodies and assertions
remain intact. The harness still uses `std.testing.FailingAllocator` over the
original `std.testing.allocator`, first runs the unlimited probe to measure its
allocation universe, then induces every assigned `fail_index`. Swallowed OOM,
nondeterministic allocation counts, leaked allocations, and original probe
assertion failures remain failures.

`PI_EXHAUSTIVE_ALLOCATION_SHARD` and `PI_EXHAUSTIVE_ALLOCATION_SHARDS` select a
contiguous partition. Without them, the default runs the entire original
universe. Existing CodeMode/TUI diagnostic environment variables and receipt
formats retain their meaning. Every new canonical receipt includes a measured
baseline, exact range header, and paired BEGIN/COMPLETE records for each
failure index; an unlimited baseline alone cannot satisfy coverage.

On macOS the existing eight platform groups divide 64 ranges. Group zero's
range zero is executed once by its ordinary Core/latest gates. Its dedicated
sweep runs ranges 1–7; the other groups each own eight ranges. The six selected
probe graphs carry 18 actual tests including imported controls, all retained.
Windows/Linux keep full unpartitioned Core/latest runs. Canonical range-zero
logs come from the actual Core/latest logs, never a duplicated dedicated run.

The native group checker requires all six graphs' baseline, range and ordered
per-index records. The final CI collector requires every global range, a fixed
baseline universe per graph, and the exact contiguous union from zero through
the final original failure index. Unit marker fixtures test this checker but
do not claim hosted execution. A preserved actual failed macOS timeout record
is a negative regression.

The 120-second test guards, 10-second host guards, original allocators and
Source assertions are unchanged. Inspection found QuickJS uses `-Og` for
Debug on every platform, ICU inherits its build mode, Photon explicitly uses
`-O1`, and native YAML uses ReleaseSafe/`-O1`. This patch changes none of those
flags and does not claim their optimization modes caused the observed timing.

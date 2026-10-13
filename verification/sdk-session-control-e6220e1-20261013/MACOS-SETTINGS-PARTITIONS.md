# macOS Debug settings allocation qualification

The first hosted control candidate at `40e2985ea2157e54db28f591b9f10c2fc7400111` passed all 12 session-control tests on macOS Debug, including the original 35 factory cases. Its separate legacy settings ownership allocation sweep exceeded the original 120-second test deadline. The failing job log is retained alongside this note.

The settings probe, file merge assertions, lock cleanup assertions, and failure allocator remain unchanged. The existing exhaustive allocation helper partitions the original allocation index universe into eight contiguous ranges on macOS Debug. Other five platform/mode combinations execute one complete range. Every partition reruns all 10 original settings tests, including an unlimited baseline, and retains the original 120-second test and 300-second invocation limits. The host await remains 10 seconds.

The workflow checks the baseline size, range boundaries, every begin/complete index in order, the terminal marker, and total coverage with no omissions or duplicates. Each invocation has an owned process receipt and bounded settlement. Separate compilation remains bounded at 1320 seconds per artifact. The larger overall job allowance accounts for sequential bounded invocations; it does not increase any test deadline.

This revision requires a new exact-head hosted run. Earlier component passes remain valid only for their recorded source bytes; the partition revision is not yet qualified by this note. The full session factory and full Pi migration remain incomplete.

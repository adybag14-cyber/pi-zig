# Native-only controls prepared for a later Root grant

These are input/acceptance specifications, not observations or passes. No fixture
was compiled or run. A future fixture binary must itself be created suspended,
assigned to the fresh unnamed job and verified before resume. No Node/npm is
needed to qualify the owner. All controls preserve unrelated sentinel processes.

| Input/control | Required result |
| --- | --- |
| Normal worker, child and grandchild | Root identities complete; kernel live/lifetime counts recorded; final zero; transient metadata coverage reported honestly. |
| Atomic JOB_LIST unsupported/nested creation deliberately rejected | Guest marker absent; creation failure retained; no two-step fallback, breakaway or retry. |
| Failure or supervisor death immediately around CreateProcess return | Successful worker creation is already job-associated; partial PI retained before probes; no abandoned suspended worker; zero/unknown reported honestly. |
| Identity reply completes after2seconds, before next poll | Timeout, never accepted as ready. |
| Attempt to start a closed/completed metadata request again | Explicit one-shot rejection, no stale result. |
| Zero-length WriteFile followed by owned-gate nonempty write | Capture rearms on zero and records later bytes; no fake EOF, workload sleep or fabricated event. |
| Stdout/stderr exact8MiB | Exactly bounded bytes retained, hashes/counts complete, normal retirement still required. |
| Stdout/stderr8MiB+1 | Explicit overflow negative; file never exceeds cap; fresh owned job only is stopped. |
| Pending read cancellation | Cancellation requested and actual completion observed before state release; otherwise unknown with state retained until exit. |
| Pending sink write/flush stalls | Timing loop remains responsive; bounded watchdog triggers owned retirement; no endless join/disposal. |
| First append after long idle | Receives a fresh persistence budget, not immediate stale-progress timeout. |
| Persistence record/queue/ledger bound exceeded | Negative; no truncated complete receipt or unbounded allocation. |
| Duplicate/reordered/incorrect-nonce ACK | Node stays suspended; owned retirement; no second launch. |
| Supervisor pulls wrong local handle | PID/creation/job binding fails; no privileged supervisor/job handle sent to worker. |
| Worker exits with grandchild retaining output handle | Root exit alone is insufficient; job member/accounting and pipe retirement determine result. |
| Dropped advisory completion message | Full kernel membership/accounting plus zero remain authority; no invented transient identity. |
| Observed cap violation | Negative with enforced limits and observed-only telemetry; no assertion that every recovered denial was seen. |
| Whole phase reaches D−10 in preflight/postseal | Normal work stops; one shared reserve ends at D, never D+10. |
| Retired worker/Node handles still retained | Record exit, release every owned/metadata duplicate, then require zero; no false absence while references block decrement. |
| Old grant/live prior lease PID/wrong controls | Reject before any workload launch. |
| Poisoned launcher environment | Worker/Node see only reviewed explicit environment and private prospective PATH. |
| Protected stage/extra tool/cache drift | Negative before Node; all readable independent final seals retained. |
| Output/link/absence drift after first positive comparison | Final asserted comparison makes the phase negative. |
| Broken or unplanned junction in absence path | Unknown/negative, not absent; only16checkedself-containedaliases may resolve. |
| Supervisor emergency exit | Last private job handle closes; never claim a zero-query receipt that was not completed. External Root check reports negative/unknown. |

Each later control receipt must bind source commit, compiler/binary SHA, exact
Root grant, process/job provenance, monotonic/UTC times, output and final accounting.
Keep every deliberate negative unchanged. A native control pass would qualify
only this verification tool; it would not establish recovered runtime authority.

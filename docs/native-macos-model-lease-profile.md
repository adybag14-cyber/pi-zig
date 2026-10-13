# Focused macOS hosted failure investigation

The shared integration at 5c45f3991550cff64b613f5751b6189f9172bdea failed
macOS Debug group 0 in job 115431224798 of run 38435196305.

The MCP test allowed a second OAuth directory lease to acquire. Its previous
150ms stale interval was shorter than a possible hosted scheduler delay. The
renewal test now holds a 2s lease for 2.3s, verifies unchanged inode, an advanced
filesystem mtime and a fresh heartbeat, then still requires the second acquire
to time out within the original 100ms wait. An unexpected successful contender
is explicitly closed before reporting the failed assertion. The product's
20s stale/5s heartbeat defaults, stale takeover checks, cancellation and owned
release behavior are unchanged. All existing MCP tests remain selected.

The CodeMode model test timed out in the independent four-slot case after its
first two cases completed. The case launches nine original classifier calls,
requires exactly four concurrent calls and verifies all original outputs, usage,
call outcomes and cleanup. Additional test-only timing marks record classifier
entry, exit and the existing 50ms gate release. The number of calls, Source
expectations and 10s whole-case await are unchanged. This is diagnosis, not a
claim that the runtime latency is repaired.

The focused workflow compiles MCP and model artifacts before a separate bounded
runtime check, runs all 76 MCP and 8 model tests in macOS Debug and ReleaseSafe,
and retains exact source/compiler prehash and posthash evidence. Its results
must be assessed before intaking a repair into the shared integration branch.

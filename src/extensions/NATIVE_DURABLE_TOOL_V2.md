# Native ToolTask v2 migration

Source authority is Pi commit `eba849739511223c51a62bbd7e3f1c00f99fb1d0`, whose built-in ToolTask is version 2. The native implementation stays on Zig 0.16.0 and uses the directly linked C extension runtime.

This packet provides native phase preparation, execution-intent commits, safe-replay clearing, cancellation and unsafe-recovery settlement, live-slot lookup and cleanup, final result projection, running output buffers, and adaptive progress scheduling. Suspended work retains VM values through native C function data; it retains no borrowed native stack or transaction mutex across an await.

Actual upstream execution supplies the comparison fixtures. The corpus covers 44 phase, intent and recovery traces; 18 final-result cases; 160 content-retention cases including lone UTF-16 surrogates; 240 streaming-output steps; and seven progress scheduling traces, including reentrant writes. Prior structured-output, nested-key and document fixtures remain in the test target. Final result construction and representative head/tail running-buffer paths receive exhaustive native allocator failure injection.

Output buffers retain original JavaScript UTF-16 chunks. Byte truncation uses TextEncoder-compatible surrogate replacement, while output that fits retains its original strings. Native TextDecoder performs streaming byte decoding. Truncation and cancellation keep upstream diagnostic ordering, partial details, nested summaries and small task receipts.

The native out-of-memory marker preserves private allocator error identity across Durable and TextDecoder callbacks. Guest exception values retain their ordinary identity; an error name or message does not grant native allocator classification.

This is a component migration, not complete ToolTask or Harness parity. Normal execution, nested admissions, execution API methods and progress publication still need to consume these primitives. Built-in GenerationTask and CompactionTask drivers are also unfinished. This packet installs no placeholder built-in task token, promotes no native default and removes no compatibility bridge. Four-configuration qualification applies only after the frozen packet receives terminal receipts for Windows and native Linux Debug and ReleaseSafe.

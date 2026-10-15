# First four lazy grammar Debug qualification

The frozen candidate `fed244fe58017fa539f999d1abb661875c5b0bd1`, with computational baseline `733800b8b872d86c5766dc4a30cf44ae8d373254`, passed the focused genuine Source29 comparison for Dockerfile, Makefile, Protocol Buffers, and INI/TOML. The later trusted-OOM core fix was not copied into this qualification.

Pinned Zig 0.16.0 compiled the focused Debug target with 155/155 successful steps. Compile PID 60916 completed with exit 0 at 2026-10-15T19:31:38.807222Z. The matching runtime PID 60648 completed with exit 0 at 19:34:08.254062Z, with 156/156 steps and 2/2 tests passing. All 29 rows match the retained genuine Source capture, including complete grammar graphs, helper calls, coercion/assignment probes, scanner behavior and aliases.

Both phases retained full 5,555-file candidate and 19,546-file pinned compiler manifests with zero drift. Controls also remained unchanged. The exact 47,531,520-byte test artifact was additionally frozen across the compile/runtime boundary with SHA256 `339cc06236b5103e114db0019645afa96fbaef6f880d1bf4d6dbc514652fb4cf`; the artifact and pair controls had zero drift after runtime. Final post-verification completed at 19:34:21.300706Z.

This qualifies only the focused Debug comparison. ReleaseSafe, exhaustive host allocation failures, the six other first-priority factories, later grammar batches, actual full 191-language import, frontend readiness integration, and full Pi parity remain unqualified. No public activation or compatibility-host removal occurred.

Exact launch owners, terminal process records, logs, admission, controls, zero-drift results and the matching artifact receipt are retained under `verification/highlight-lazy-first4-debug-qualified-20261015`. Large full candidate/compiler manifests remain at the exact external evidence paths recorded by those owners and receipts.

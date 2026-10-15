# Exact 1c22 component qualification

Candidate: `1c22a18117dcd1047e9c1fa8a6e8c94ef66362fb`, pinned Zig 0.16.0, Windows Debug/LLVM, one compilation job. The five owned component tests and one imported durable-storage test passed. This qualifies the observed Source30 functional terminal/payload/callback/auth/wire/event-shape components, 27 request cases, retained facade roots, guest exception identity and the complete native facade creation/missing-key host allocation graph on this profile.

This does not qualify full intermediate snapshots, the full providers, ADC, injectable fetch, SDK response classes, other build profiles, full Pi or complete factory/application parity. The strict full snapshot test remains unchanged in the full target; e554's genuine durationMs visibility timing failure remains preserved.

The component compile passed under owned Zig PID 50200, exit 0, completed 2026-10-15T19:55:41Z. Full between-phase inventories were unchanged. Fresh runtime admission was denied at 19:56:24Z (16595688KiB available; 16777216 KiB required), so the initial pair did not launch runtime. Its terminal posthash completed 19:56:55Z with zero drift. No threshold was lowered.

Root then explicitly re-reserved slot 3 for matching runtime only. The runtime-only wrapper verified the original frozen candidate inventory, prior compile PASS and zero-drift terminal receipt, all compile controls and the exact compiled executable. The artifact last-write timestamp is within the matching compile interval. It invoked that executable directly without a Zig/build process or source edit:

- Artifact: `.zig-cache/o/1635524a1e24730f35977181387a205b/test.exe`
- SHA256: `0214E2F94BD706194F8D2B43546959AA2107992D0E5A0C9BB9183F508B73A85D`
- Runtime owner PID 55240, exact argv `--seed=0`, exit 0, completed 19:59:56Z.
- Fresh admission: 18558736 KiB, no other native build roots, normal 16 GiB floor.
- Entire runtime was bounded 120s, a stricter bound than the 300s runtime upper limit and satisfying the 120s individual-test ceiling. Host awaits remained 10s.
- Terminal posthash 20:00:28Z: candidate6132/compiler19546/control13/Source1967/deps31064/Node1774/absent84, all zero drift.

The original Source30 fixture is unchanged. Method was not captured in that original Source packet; path/query, actual request body and functional captured headers are checked directly against Source, with origin rebinding only. The new followup controls capture method and are separate, unlaunched evidence at this checkpoint.

Exact raw receipts, logs, frozen candidate inventory and runner controls are retained here. There is no private/public release or activation claim.

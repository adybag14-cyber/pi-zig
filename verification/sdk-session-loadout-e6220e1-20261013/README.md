# Private AgentSession loadout and structured prompt qualification

The private native port executes the complete latest Source `_applyToolLoadout` and `_preparePromptAndToolLoadout` methods, their exposure and callable-tool collaborators, full structured prompt sections (including skills and documentation), and section diffing. All method bodies are Zig operating on live QuickJS values. Installation remains private.

The oracle is unchanged upstream `e6220e1316f86af818a0ccbfe1c09d7e918b41cf` (v1.2.0). Node 24 executes its TypeScript using `--conditions=source --experimental-transform-types` and an audited official dist-to-source export resolver. The capture creates 34 actual original factory instances and records 34 loadout/prepare scenarios, 12 section scenarios, 9 diff scenarios, and method/callback metadata. No Source class body was rewritten. The 1,902 original Source files plus 43 officially hydrated catalog files, all observed module mappings, 365 external lock records, 16 workspace mappings, and immutable reused runtime/tool manifests are recorded in `source-qualification.json` and its linked receipts.

The native fixture supplies an ordinary AgentSession prototype receiver with actual native Agent, ExtensionRunner and SessionManager collaborators. It explicitly rejects accidental model-stream invocation. This packet qualifies the complete private methods and their collaborators; full native AgentSession constructor/factory integration remains a separate gate.

Both Windows Debug and ReleaseSafe passed all 18 selected tests: 7 existing/native path tests including the new allocating-writer regression, and 11 loadout/import tests including strict Source55 replay, live callback/receiver collection and release, and the complete `std.testing.checkAllAllocationFailures` sweep of the full Source55 packet. Each injected allocation trial executes the entire fixture. There are no skipped allocation prefixes, sharding, shortened cases, or changed Source expectations. The path oracle retains all 3,038 original Node24 cases.

Only the seven explicitly named generated patch timestamp slots are bounded and removed from comparison copies; raw native and Source values remain in receipts. Each value must fall within its real run bounds. All other outputs, row identities, property order, hooks, errors and metadata compare exactly. Existing source/tool manifests remain intact.

The cold ReleaseSafe compile exceeded its original 300-second outer envelope and is retained as a negative. A separate explicitly bounded 1,320-second compile-only job completed, followed by the unchanged runtime gate: default LLVM, `-j1`, test timeout 120 seconds, host await 10,000 milliseconds and outer timeout 300 seconds. Both successful runtime jobs have complete terminal summaries, exact owned PID/UTC records, and full source/tool postchecks with zero drift.

Commands after compilation:

```text
zig build test-extension-path test-native-sdk-session-loadout -Doptimize=Debug -j1 --test-timeout 120s --summary all
zig build build-extension-path build-native-sdk-session-loadout -Doptimize=ReleaseSafe -j1 --test-timeout 120s --summary all
zig build test-extension-path test-native-sdk-session-loadout -Doptimize=ReleaseSafe -j1 --test-timeout 120s --summary all
```

These are Windows results. Hosted macOS/Linux and full public AgentSession factory activation are not claimed by this packet. Root owns intake and hosted qualification; this worktree has not been pushed.

# Anthropic and Bedrock Source5ab candidate

Authority: immutable upstream `5ab7fe74c400097b386662205cd93900695b8a71`, Zig 0.16.0, and whole native provider foundation `3f0cce9ad90ee9618d4216d9889f088f6a28f6de`.

The native Anthropic modules implement request construction, grouped tool results, error-image siblings, system/tool updates, historical effort markers, strict tools, SSE parsing, usage/signature/tool-argument decoding, and owner-thread asynchronous stream continuations. The Converse request modules produce actual JavaScript `Uint8Array` blobs, sanitize Documents, use model ID/name capability detection, preserve successful images, and relocate error images only for Claude.

The actual upstream public Anthropic `stream` and `streamSimple` APIs produced 25 observations through the pinned SDK and an owned loopback server using fixture credentials. The Source job passed with all 1,967 source, 31,064 dependency, and 1,774 Node/tool hashes unchanged; 84 historical absences and control hashes also remained unchanged. The raw capture and its driver/owner/posthash records are preserved under `verification/ai-anthropic5ab-20261015`; the fixture is `src/extensions/fixtures/ai-anthropic5ab.json`.

`build-native-ai-claude5ab` compiles the focused native target. `test-native-ai-claude5ab` exercises real Anthropic facade requests at the onPayload boundary against those Source observations, native image/tool/effort ownership, retained roots after collection, and host allocation failures. A passing Source capture does not establish native differential or runtime qualification.

Current qualification state: `public_activation=false`, `full_pi_qualified=false`. Native compile/runtime gates have not run on this candidate. The Anthropic workload-identity token exchange, SDK wire/error metadata, complete native Headers integration, and end-to-end stream differential/lifecycle checks still require completion. The separate Bedrock facade owner integrates the Converse converter with AWS credentials, binary event decoding, and provider results; the request converter alone does not qualify Bedrock transport.

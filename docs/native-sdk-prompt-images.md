# Native session prompt image normalization

Implementation da7559e70181a0bd2260f658cf8e65cf9e07c9bf ports upstream
AgentSession._normalizePromptImages through the linked native image processor.
It preserves empty/falsy inputs, live resize settings and model limits,
conversion hints, unsupported image handling, iterator closing and original
thrown values. Codec, iterator and receiver references remain rooted through
asynchronous work and collection.

The unchanged latest-upstream e6220e1 fixture contains 15 scenarios captured
through 15 genuine createAgentSession calls. The observer calls the original
installer once with unchanged arguments; it does not replace a constructor or
image processor body. Complete original source/runtime/compiler posthashes show
zero drift across 1945 source, 31064 installed runtime and 1774 Node files.

Windows Debug and ReleaseSafe each passed all 11 selected tests, including the
original functional comparison, explicit garbage collection and every native
allocation failure in the selected codec/iterator/session graph. Runtime keeps
120 seconds per test, 10000 ms host awaits and a 300 second outer limit. Cold
ReleaseSafe compilation used its separate 1320 second envelope.

All 4741 committed source blobs match the successful ReleaseSafe input bytes;
source and 19546 compiler file posthashes show zero drift. Receipts and the byte
proof are in verification/sdk-prompt-images-e6220e1-20261013.

The private candidate workflow runs the same artifact in both modes on Windows,
Linux and macOS. Hosted results remain pending. The complete session runtime,
public factory and remaining Pi behavior still need integration and validation;
this component does not activate the partial class or certify full Pi parity.

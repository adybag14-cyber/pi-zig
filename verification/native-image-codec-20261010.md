# Native image codec integration candidate

This work branch is an unfinished image dependency and Zig API candidate. It
does not switch the application's default image path or certify complete Pi
parity. Zig remains pinned to 0.16.0, with C used for the exact image algorithms.

External standalone checks passed the native codec's 24 original byte hashes,
its real Zig allocator failure sweep, two concurrent caller loops, malformed
input/resource/output recovery, 20 complete upstream resize results, and 16
pixel-orientation cases. The original byte goldens were captured at upstream
42a; the exact Photon artifact remains unchanged at c5. Resize and orientation
fixtures were captured directly against c5. The new automatic metadata reader,
high-level allocation sweep, repository build arrangement, strict floating-point
flags, and quiet unsupported-import errors still need their composed checks.

The separate six-job matrix checks Debug and ReleaseSafe on Windows, Linux and
macOS. It records source/tree/toolchain identity, verifies exact C inputs and
source hashes, and retains results and notices. Passing this target will qualify
the narrow codec candidate, not its future CLI, SDK, durable image capability,
worker isolation, or complete application integration.

The native API validates input/output bounds, owns a fresh protected C module
per operation, and returns Zig-owned copies. Its C-only trap boundary never
jumps across a Zig allocator callback. Resizing preserves upstream's candidate
order, generates every encoding before selection, and returns null when no
candidate fits. EXIF pixel transforms match actual upstream cases. The metadata
reader intentionally bounds malformed RIFF scans that cannot make progress.

The known-component notice bundle covers the identified crates, embedded Roboto
font, IJG JPEG code, NeuQuant, rasterizer, Rust and WABT notices. The artifact is
pinned; its complete original Rust dependency resolution has not been recovered.
See `vendor/photon-native/README.md` and `PROVENANCE-AUDIT.md` for the exact
provenance and remaining limitations. No complete SBOM claim is made.

The first repository matrix at `d4925b0` passed Linux Debug/ReleaseSafe,
macOS Debug/ReleaseSafe, and Windows Debug. Windows ReleaseSafe hit a Zig C
header translation error in unrelated internal CRT declarations. A minimal
allocator/result header now keeps trap and runtime types private to C.
At `1ba4fa0`, the corrected Windows ReleaseSafe target passed all nine tests
and 49 build steps, with all 1,775 source hashes unchanged. The public C ABI
layout and image algorithms are unchanged. The corrected head still needs
its complete hosted matrix. Thread-test failure cleanup also now joins each
probe exactly once.

# Pinned native image codec draft

This directory contains C translated from the exact published
`@silvia-odwyer/photon-node` 0.3.4 WebAssembly artifact. The build compiles C
directly with Zig 0.16.0; it does not load a WebAssembly interpreter, Rust,
Node, or JavaScript host code. Host allocation, pixel orientation, and resize
selection remain Zig code in `src/ai/photon_*.zig`.

The input artifact SHA-256 is
`10468181565c56004c867f3a4af96f89a0ef5a63a72f2b5fb12c1f1992a3615c`.
WABT 1.0.42 generated sixteen C translation units and two headers with module
name `pi_photon` and tail calls disabled. Its pinned commit is
`ff0ef7e0009402740c805a9744c09b05be063e48`.

The artifact's NPM git head is
`685f5b155b36c5611c08ca678bb78ddbab3edbac`. Its source manifest says Rust crate
0.3.3, which is distinct from the NPM artifact version 0.3.4. That source tree
does not contain a Cargo lockfile. The exact artifact, generated-file hashes,
known notices, and unresolved dependency-resolution limitations are recorded
in the accompanying provenance documentation; this is not a complete SBOM.

The WABT runtime files retain their original bytes and copyright headers.
Allocation macros are private to the three runtime compilation units. The C
guard keeps every `setjmp`/`longjmp` frame in C, and traps only after allocator
callbacks have returned normally. Each operation owns a fresh module, frees its
entire tracked allocation graph on success or failure, and returns a caller-owned
copy of output. Memory mapping, process-wide signal handlers, and Segue are
disabled. Explicit bounds checks and stack-depth checks remain enabled.

The small headless import implementation provides the required extern-reference
initialization. Unsupported browser DOM/error imports trap quietly; this narrow
codec API does not expose Photon DOM APIs. Unlike the external research probe,
these unsupported imports do not write diagnostics to application stderr.

`test-native-photon` is a separate validation target. The application's default
image-processing path has not yet been switched to this implementation. Platform
qualification, worker integration, source contract registration, and complete
application regression checks remain open.

## Notices

Retain `LICENSE-PHOTON.md`, `LICENSE-WABT`, and all files in `notices` when
redistributing this dependency. The bundle includes the embedded Roboto font,
Independent JPEG Group, NeuQuant, rasterizer, identified crate, and Rust notices.
In accordance with the included IJG terms:

**This software is based in part on the work of the Independent JPEG Group.**

The generated C is a translation of the published artifact; the allocation
boundary, headless imports, and Zig API are local additions. No claim is made
that the original Rust dependency graph has been completely reconstructed.

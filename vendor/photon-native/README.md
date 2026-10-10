# Pinned native image codecs

This directory contains C translated from the exact published
`@silvia-odwyer/photon-node` 0.3.4 WebAssembly artifact. The build compiles C
directly with Zig 0.16.0; it does not load a WebAssembly interpreter, Rust,
Node, or JavaScript host code. Host allocation, pixel orientation, and resize
selection remain Zig code in `src/ai/photon_*.zig`.

Durable uses the separate browser package `@silvia-odwyer/photon` 0.3.3.
Its exact artifact SHA-256 is
`06e9f6b245d53b488244e04dfe30e6731c029526101c6400e6490057fcfbdd04`.
The `photon_browser_*` translation uses module `pi_photon_browser`, sharing
the protected allocator and pinned WABT runtime with the Node 0.3.4 codec.
`src/durable/photon_images.zig` preserves Durable's lazy encoding order,
inclusive byte limits, optional capability, and unsigned EXIF offsets.
Its complete result fixtures were captured from actual upstream c5f5b328.
The production processor remains optional; its presence does not select it
for callers that omitted an image processor.

`PROVENANCE-BROWSER-033.json` independently records the browser artifact's
registry identity, producer section, embedded crate-version strings, and exact
Roboto font match. Its NPM git head, license bytes, 23 observed crate versions,
Rust producer, and embedded font match the Node artifact's known-notice bundle.
This comparison does not reconstruct the complete transitive dependency graph.

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

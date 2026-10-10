# Photon native C licensing and provenance audit

The known-component attribution packet is prepared, but dependency closure remains unresolved. This audit does not certify a complete SBOM or complete redistribution clearance. It made no product/vendor edits and ran no compiler. All original TUI work remains preserved.

## Exact input and translation authority

The input is published @silvia-odwyer/photon-node 0.3.4, Apache-2.0. The NPM archive was downloaded from its exact registry version and checked against both registry SHA512 integrity and SHA1. Its SHA256 is 5A23015C1CD2C38E3C492DD96929985247B92F52D2FF0FB948D29EDCA52BC50A. The contained 1,881,634-byte photon_rs_bg.wasm has SHA256 10468181565c56004c867f3a4af96f89a0ef5a63a72f2b5fb12c1f1992a3615c, equal to BOTH the actual reference6fb generation input and current upstreamc5 installed copy.

Registry gitHead685f5b155b36c5611c08ca678bb78ddbab3edbac resolves to a real complete GitHub tree. Its crate/Cargo.toml says photon-rs0.3.3; that Rust source version must remain distinct from the NPM package version0.3.4. Cargo.lock is not tracked in this tree. Its Photon license retains Copyright2023 Silvia O'Dwyer. No NOTICE-named file was found in the complete pinned Photon tree or exact NPM archive. The font license is a separate source asset which a basename-only LICENSE search would miss.

The retained owned generator receipt passed and invokes WABT wasm2c with --module-name=pi_photon --disable-tail-call --num-outputs=16. WABT release1.0.42 resolves to commitff0ef7e0009402740c805a9744c09b05be063e48. The locally used release archive SHA256 is 62F1EB2B51AA57CF0F0B8BA333BF2C72A049930AA9C5DE01DCAD271C4FE48C88, and actual wasm2c.exe SHA256 is 45EDCB1F2D5D775A4D0471E7C469F7019B4A75C0476E7C4E7C8CE255D5EF2D20. Eight actual runtime source/header/include files match that exact upstream commit after CRLF normalization; bytes of the local files and eighteen generated C/header files are recorded individually in PROVENANCE-AND-LICENSE-FINDINGS.json. A complete pinned WABT tree contains no NOTICE-named file. Preserve its Apache license and Copyright2018 WebAssembly Community Group participants source headers. The generator itself is a build tool; its attribution is recorded separately from runtime linkage.

The WASM producers section identifies rustc1.86.0-nightly (3f43b1a63 2025-01-03), walrus0.22.0, and wasm-bindgen0.2.95 (3a8da7cb8). Embedded /rustc/ source paths give the full Rust commit3f43b1a636738f41c48df073c5bcb97a97bf8459. Pinned Rust source licenses/COPYRIGHT and std/core/alloc/panic_abort manifests were fetched. This is a nightly compiler identity, not a claim of Rust1.86.0 stable. Producer metadata does not establish that the producer's implementation is itself linked into the codec.

Primary sources: [NPM exact package metadata](https://registry.npmjs.org/@silvia-odwyer%2fphoton-node/0.3.4), [pinned Photon manifest](https://raw.githubusercontent.com/silvia-odwyer/photon/685f5b155b36c5611c08ca678bb78ddbab3edbac/crate/Cargo.toml), [pinned Photon license](https://raw.githubusercontent.com/silvia-odwyer/photon/685f5b155b36c5611c08ca678bb78ddbab3edbac/LICENSE.md), [pinned WABT license](https://raw.githubusercontent.com/WebAssembly/wabt/ff0ef7e0009402740c805a9744c09b05be063e48/LICENSE).

## Additional notices established from actual bytes or primary source

Roboto-Regular.ttf is embedded as one exact complete171,676-byte sequence starting at WASM byte1,403,285. Its pinned font SHA256 is 79E851404657DAC2106B3D22AD256D47824A9A5765458EDB72C9102A45816D95. Pinned Photon text.rs contains include_bytes of this font. Its actual name-table records say Copyright2011 Google Inc. All Rights Reserved; Roboto is a trademark of Google; Apache License Version2.0. The source font license and exact name-table notices are included. Roboto-Black's full file bytes were not found; this does not prove absence of a transformed/subset form. [Pinned text source](https://raw.githubusercontent.com/silvia-odwyer/photon/685f5b155b36c5611c08ca678bb78ddbab3edbac/crate/src/text.rs), [pinned font license](https://raw.githubusercontent.com/silvia-odwyer/photon/685f5b155b36c5611c08ca678bb78ddbab3edbac/crate/fonts/Apache%20License.txt).

image0.24.9 src/codecs/jpeg/transform.rs includes an IJG libjpeg9a forward DCT translation with separate terms, beyond its Cargo MIT/Apache label. Executable documentation must state: “this software is based in part on the work of the Independent JPEG Group”. Source redistribution retains the full copyright/no-warranty notice and documents changes. The exact source header and original IJG jpeg9a README are included. Original IJG archive SHA256144AEEB75240241FBFAE3F1DDC86829525174BA04405EF9159884F241E112752. [Pinned image source](https://raw.githubusercontent.com/image-rs/image/2b513ae9a6ac306e752914f562e7d408f096ba3f/src/codecs/jpeg/transform.rs), [original IJG archive](https://www.ijg.org/files/jpegsr9a.zip).

color_quant1.1.0 contains the original NeuQuant Copyright1994 Anthony Dekker alongside Piston2014 modifications. Its source header requires the original copyright notice remain intact; the complete notice is included. ab_glyph_rasterizer0.1.5 raster.rs adds Google2015 and AlexButler2020 notices; those are also retained. These findings demonstrate why Cargo license fields alone do not establish the full notice set.

## Crates with embedded version evidence

All23 entries below have exact released crate archives downloaded from static.crates.io and verified against the exact crates.io version API checksum. Their primary license/copyright files are copied into redistribution-notices. Slash notation is retained as published metadata, without silently rewriting the license expression. Both offered license texts are retained where supplied.

| Crate | Version | Published license expression |
|---|---|---|
| ab_glyph_rasterizer | 0.1.5 | Apache-2.0 |
| base64 | 0.13.0 | MIT/Apache-2.0 |
| color_quant | 1.1.0 | MIT |
| console_error_panic_hook | 0.1.7 | Apache-2.0/MIT |
| dlmalloc | 0.2.7 | MIT/Apache-2.0 |
| fdeflate | 0.3.6 | MIT OR Apache-2.0 |
| flate2 | 1.0.34 | MIT OR Apache-2.0 |
| gif | 0.13.1 | MIT/Apache-2.0 |
| hashbrown | 0.15.2 | MIT OR Apache-2.0 |
| image | 0.24.9 | MIT OR Apache-2.0 |
| imageproc | 0.23.0 | MIT |
| jpeg-decoder | 0.3.1 | MIT OR Apache-2.0 |
| js-sys | 0.3.62 | MIT/Apache-2.0 |
| miniz_oxide | 0.8.0 | MIT OR Zlib OR Apache-2.0 |
| palette | 0.6.1 | MIT OR Apache-2.0 |
| png | 0.17.14 | MIT OR Apache-2.0 |
| rand_chacha | 0.2.2 | MIT OR Apache-2.0 |
| rand | 0.7.3 | MIT OR Apache-2.0 |
| rusttype | 0.9.2 | MIT / Apache-2.0 |
| tiff | 0.9.1 | MIT |
| ttf-parser | 0.6.2 | MIT OR Apache-2.0 |
| wasm-bindgen | 0.2.95 | MIT OR Apache-2.0 |
| weezl | 0.1.8 | MIT OR Apache-2.0 |

## Redistribution and vendoring requirements

Distribute the full applicable license texts and copyright notices with both source and binary artifacts. For Apache-covered material, retain source attributions, mark modified files prominently and reproduce any supplied applicable NOTICE content. The pinned Photon/WABT trees have no NOTICE-named file, but embedded source notices, font notices and IJG documentation requirements still apply. [Apache2 section4](https://www.apache.org/licenses/LICENSE-2.0).

Carry the IJG acknowledgement in shipped third-party documentation and the full original IJG notice/README in a source distribution. Preserve the NeuQuant and rasterizer notices, the Roboto attribution/license and WABT runtime headers. Keep crate-specific MIT permissions/copyright notices even when the original Photon NPM archive only contains its own Apache license. Do not replace all dependency attributions with one generic Apache text.

Every generated Photon C/header file currently starts only with the wasm2c generator marker. Before vendoring, add a prominent comment identifying the exact input WASM/package, generator version/commit, mechanical translation, applicable license/NOTICE location, and local changes. Describe the native host imports, allocation guards and configuration separately as project changes; preserve original authorship. Record hashes of original and modified files and the exact generation/configuration commands. This audit does not make those product edits.

A suggested packet contains the exact published WASM and verified registry metadata, pinned source manifest/license references, WABT runtime sources with their license/header provenance, generated-file hashes and recipe, adapters/change log, this notices folder, and an explicit unresolved dependency inventory. Only files actually selected for product redistribution belong in its final artifact inventory; test-only assets and documentation resources need not be represented as linked components.

## Remaining provenance gaps

The23 embedded strings are positive evidence, not a complete linkage map. The pinned Photon Cargo manifest has unresolved version ranges and no Cargo.lock. Released crate manifests expose101 dependency requirements across regular/build/target scopes; these are candidates, not101 proved compiled dependencies. Examples outside the23 strings include cfg-if, crc32fast, bytemuck, byteorder, num-traits, num, nalgebra, conv, itertools, rand_core, ppv-lite86, adler2, and Photon-declared serde/time/thiserror/perlin2d/instant/node-sys/web-sys. Enabled features and exact resolutions cannot be inferred solely from their declarations or from today's resolver. Candidate requirements are preserved in published-crate-dependency-requirements-candidates.json.

The pinned Rust std manifest also names runtime/build dependencies, including an exact compiler_builtins requirement. Rust std/core/alloc source licenses are known, but the target-specific transitive runtime notice closure has not been reconstructed. Rust COPYRIGHT includes compiler/tool/source-tree third parties; retaining it is conservative source attribution, not evidence that every named project is in this WASM. Photon docs/COPYRIGHT explicitly applies only to documentation resources and does not identify linked font/runtime dependencies.

To close redistribution qualification, obtain the original resolved build manifest/lockfile or an authoritative build SBOM from the publisher, or reproduce and prove an equivalent pinned source build with its resolved graph and all component-specific notices. Do not invent a historical Cargo.lock or label a modern re-resolution as the original build. Exact WASM-to-C regeneration is established independently of Rust-source reproducibility.

The prepared review packet is suitable for integrating the known notices and recording truthful provenance. It is not a substitute for resolving the remaining dependency/notice closure, and no complete-SBOM assertion should accompany it.
# Direct-C streaming codec dependency

Unmodified selected zlib 1.3.1 source and headers from the official repository:
https://github.com/madler/zlib/tree/v1.3.1

Annotated release tag `v1.3.1` resolves to source commit
`51b7f2abdade71cd9bb0e7a373ef2610ec6f9daf`.

The original license is retained in `LICENSE` and in the original source files.
Only the inflate/deflate/checksum implementation is compiled. The `Z_PREFIX`
build define gives the dependency its upstream-supported symbol namespace.
CompressionStream owns each incremental z_stream and supplies Engine allocator
callbacks, so codec memory participates in native allocation-failure accounting.
No source from this directory is evaluated as JavaScript.

This is an authored native candidate. Its byte output, error behavior, chunking,
platform header bytes and VM scheduling require genuine Node24 qualification.

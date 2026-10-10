# Pinned Unicode 17 grapheme data

These inputs come from the Unicode 17.0.0 Character Database, published by Unicode, Inc. The accompanying LICENSE.txt applies to the data. Unicode Text Segmentation revision 47 defines the extended grapheme rules used by ../utf16_graphemes.zig. This is a segmentation module; it does not replace the terminal-width tables.

Original locations:

- https://www.unicode.org/Public/17.0.0/ucd/auxiliary/GraphemeBreakProperty.txt
- https://www.unicode.org/Public/17.0.0/ucd/DerivedCoreProperties.txt
- https://www.unicode.org/Public/17.0.0/ucd/emoji/emoji-data.txt
- https://www.unicode.org/Public/17.0.0/ucd/auxiliary/GraphemeBreakTest.txt
- https://www.unicode.org/reports/tr29/tr29-47.html

Run the native Zig generator from the repository root:

```
zig run tools/unicode_graphemes.zig
zig run tools/unicode_graphemes.zig -- --check
```

The generator verifies SHA256 hashes before emitting generated_graphemes.zig, sorts ranges, rejects overlaps and checks the generated output byte for byte. The conformance test reads the original official GraphemeBreakTest.txt. The separate Source6fb fixture records Node 24.14.0 / ICU 78.2 / Unicode 17.0 / locale en-GB and compares every UTF16 cursor split in its captured grapheme examples.

The Input width projection additionally pins emoji-sequences.txt and emoji-zwj-sequences.txt from https://www.unicode.org/Public/17.0.0/emoji/. All 3,953 RGI emoji sequences were checked against Source's actual ICU 78.2 regex. The original Source utils and its get-east-asian-width 1.6.0 dependency were captured over all 0x110000 codepoints; the fixture records the package's source hashes and the included EAST-ASIAN-WIDTH-LICENSE.txt covers its derived width data. tools/unicode_width.zig verifies that capture's SHA256 and the raw emoji hashes before generating generated_width.zig. Run `zig run tools/unicode_width.zig -- --check` to verify the byte-exact projection. Native tests compare all codepoints and 9,104 original grapheme cases without requiring Node or ICU at runtime.

# Source word-engine data profile

This directory retains original ICU 78.2 word rules and all five dictionaries, including their complete copyright/license headers. LICENSE.txt is the ICU/Unicode license. Source locations are the release-78.2 tag of https://github.com/unicode-org/icu under icu4c/source/data/brkitr/. Native algorithm ports use no ICU or C++ runtime.

The authority runtime for Source6fb captures is Node 24.14.0, ICU 78.2, Unicode 17.0, locale en-GB. Its executable SHA256 and actual break-iterator resource table are recorded in ../fixtures/word-icu-capabilities-original-6fb.json. The data package contains cjdict, thaidict, burmesedict, laodict and khmerdict. Its selected Thai/Burmese LSTM resources are absent, with no ICU_DATA/NODE_ICU_DATA or data-directory override, so ICU takes its dictionary fallback. The upstream root.txt names those LSTM resources; its defaults alone do not establish the capabilities of the actual Node binary. An unqualified LSTM prototype and its failed Source comparison are preserved outside the repository in the task evidence directory.

The original Unicode 17 WordBreakProperty, WordBreakTest, Scripts, LineBreak and UnicodeData inputs are retained in ../unicode17 with the Unicode license. Actual Source captures retain every single-codepoint word tag, word boundaries/navigation examples, modifier/deletion snapshots and normalization results. Native generators verify pinned input hashes and emit deterministic tables/tries:

```
zig run tools/unicode_words.zig
zig run tools/unicode_words.zig -- --check
zig run tools/word_language_data.zig
zig run tools/word_language_data.zig -- --check
zig run tools/word_normalization_data.zig
zig run tools/word_normalization_data.zig -- --check
```

Generated dictionaries are little-endian read-only tries. UTF16 cursor offsets remain distinct from codepoint counts, including supplementary characters, isolated surrogates, negative cursors and positions past the end. CJK segmentation uses original dictionary costs, Katakana heuristics, native NFKC and original-position restoration. Southeast Asian segmentation uses the original lookahead, resynchronization, combining-mark and Thai-suffix rules. Dictionary engine breaks refine the original rule span without forcing new boundaries at mixed-script run edges.

# Unicode and pattern-state ordering amendment

This source-only successor corrects the independently reviewed native-path
transport bug in `4b95b416d9d965bca5c7f2a9917cd045501670e2`. That checkpoint
encoded each JavaScript UTF16 unit independently for native paths. A valid
astral pair therefore became six CESU8 bytes instead of the four canonical UTF8
bytes used by an actual POSIX filename, causing admitted literal and suffix
patterns or an astral cwd to miss existing files. This was a concrete blocker;
the previous implementation is not qualified.

`native_node_glob_path_codec.zig` now handles native paths separately from VM
code-unit transport. It combines valid high/low pairs into one scalar, emits
canonical UTF8 and rejects unpaired surrogates explicitly. All incoming pattern,
cwd and captured path-function results use it. Raw directory entry names are
validated before matching, caching, or metadata fallback. An invalid native
UTF8/WTF8 name raises `NodeGlobInvalidNativeNameUnsupported`; a lone surrogate
raises `NodeGlobLoneSurrogateUnsupported`. These are explicit unsupported
boundaries, never empty-directory or missing-file results. Native Windows names
containing unpaired surrogates and POSIX names containing invalid UTF8 remain
broader gaps. VM output reconstruction continues to produce the same UTF16
string values from valid canonical UTF8.

Pattern positions now retain original SafeSet insertion order in a small native
list alongside membership flags. Every transition appends only on first
insertion; traversal, first-position selection, symlink admission and cache
marking iterate that list. This preserves states such as `[0,2,1]` rather than
sorting them implicitly. The reviewer had identified the ordering difference
as a preventive closure because the source loop can return early on cache hits;
no concrete output discriminator had been claimed.

Eight separate original subject cases are prepared in
`src/extensions/fixtures/node24-glob-package-astral.input.json`: astral literal,
suffix, one/two question marks, cwd, absolute path, recursion, and the original
globstar/literal/globstar state shape. The existing original `.input.mjs` can run
these supplied cases with the same actual fs/Pi helper seams. No expected
answers, fixture execution or new replacement matcher are supplied.

The original 25-case input, eight broader-reference-only rows, original input
script, reference files, dependency core/AST and original source-only manifest
remain byte-identical. That historical manifest continues to describe the old
4b95 checkpoint; it is not relabeled as a seal of this successor. The separate
`unicode-amendment-manifest.json` binds the changed leaf, new codec, supplemental
input and this note to the unchanged historical pins.

All previous broader API/grammar/Dirent-prototype/resource limits remain in
effect. This changes no public installation/default selection, Engine, C,
filesystem metadata provider or shared helper. No Node, formatter, AST,
generator, compiler, native job or reference capture ran. Source review and
future behavioral qualification remain separate.

# Additive opt-in regexp compilation boundary

SOURCE DESIGN ADDENDUM, not an implementation or execution claim. The actual CJS/probe implementation is held unselected; its regexp capacity/poll frontier must close before source/runtime qualification. Root has the concrete findings. No libregexp edit is included in this addendum.

Actual pinned libregexp.c lre_compile calls stack checks but the timeout hook at the execution loop is not a compiler work budget. Its capture/group/register/range/bytecode capacity failures become only error_msg text. A caller cannot classify those as ordinary syntax versus operational limits without a producer channel. Reading that text or an Error property is prohibited. Existing lre_realloc and stack callbacks already give actual allocation/stack events, but are insufficient for these two frontiers.

Proposed additive native entry (internal C library ABI, no new JS function):

    typedef enum LRECompileLimit {
        LRE_LIMIT_CAPTURES, LRE_LIMIT_GROUP_SCOPES, LRE_LIMIT_REGISTERS,
        LRE_LIMIT_RANGES, LRE_LIMIT_BYTECODE
    } LRECompileLimit;
    typedef struct LRECompileOptions {
        int (*poll)(void *opaque);
        void (*capacity)(void *opaque, LRECompileLimit limit);
    } LRECompileOptions;
    uint8_t *lre_compile_with_options(int *plen, char *error_msg,
        int error_msg_size, const char *buf, size_t buf_len, int flags,
        void *opaque, const LRECompileOptions *borrowed_options);

The existing lre_compile signature/symbol remains and delegates to the same actual implementation with NULL options. Ordinary entries make no new interrupt/event callbacks. Options are a borrowed native stack scope carried only in REParseState/copies; no pointer or new option flag enters bytecode, returned strings, regex objects, jobs or serialization. Existing output ownership remains identical.

The new CJS scope selects this entry only while its borrowed compiler diagnostic record is active. poll calls the actual js_pi_compiler_poll over the same actual context; nonzero means the real current VM failure already exists and must survive native cleanup. capacity records only the actual producer's operational-limit event, with no allocation or JS call and no fatal classification. Existing actual allocator/stack/timeout callbacks retain their separate event provenance. QuickJS owns any actually pending failure before freeing native buffers/C strings; without a pending reason, an actual capacity report permits the actual existing SyntaxError production with diagnostic NONE, not an invented OOM or a guessed ordinary grammar category.

Required actual capacity sites: CAPTURE_COUNT_MAX capture allocation; GROUP_NAME_SCOPE_MAX disjunction scope; REGISTER_COUNT_MAX register analysis; the encoded range-count limit; the existing lre_bytecode_realloc signed-length ceiling. Keep their legacy error messages/results for NULL options. No error-string test chooses these events. Any additional parser/compiler hard limit discovered during the finite implementation audit must be explicitly inventoried before sealing.

Required opt-in polling sites: recursive parser entry and term/disjunction loops; character-class/Unicode-set string parsing; capture/name lookahead scans; bytecode scan/quantifier/register analysis; string-list hash/probe/union/intersection/emission loops. Every interruption path must release initialized native state without another VM producer or diagnostic conversion. Native cleanup/free loops do not introduce failing polls while a reason is being retired. Existing finite Unicode CharRange routines must be explicitly inventoried as atomic native operations or given an opt-in path; do not silently claim they have instruction-level cancellation.

The string-set rqsort path needs a separate opt-in checked native scratch vector and polled stable merge sort using its actual existing length/lexicographic comparator. A fallible qsort comparator cannot stop sorting at the first failure. Preserve the existing rqsort call and comparator under NULL options. Initialized scratch ownership and all failure exits must be reviewed before authoring/qualification closure.

Causal controls must use the actual CJS/probe entry points: a real flat capture-count overflow (not ModuleDef/FD field mutation) remains operational despite SyntaxError shape; ordinary invalid regexp remains completed syntax; actual native allocation/stack/poll failures retain the exact reason; Unicode string-set sort/cancellation and recovery/GC are real VM cases. All metadata counts and results remain unknown until Root separately grants execution. No Source expected is generated from the candidate.

Actual allocator NULL is not itself a VM exception. Existing optional string-buffer shrink and atom-hash growth can recover correctly without ever creating an error. The prepared measured-event control therefore accepts correct baseline recovery only when no actual captured failure was discarded, and validates actual ordinary syntax against its captured intrinsic SyntaxError prototype/identity. It does not invent a fatal/tag from NULL or change shared default allocator policy. LRE's explicitly designated nonzero allocation callback failure remains an operational compile event under the reviewed design; size-zero cleanup is never labeled OOM.

# Genuine Node formatter and Host error dependency

This source unit implements the retained Node v24.13.0 `format(...args)` body and its actual `formatWithOptionsInternal(undefined, args)` path. The actual inspector exports this function through the existing completed owner. The genuine file-URL Host error class already delegates to that same export.

## Why this unit is required

The retained V17 diagnostic failed the file-URL Host controls at indices 6 and 18. The existing Host class uses `File URL host must be "localhost" or empty on %s`, while the old formatter admitted only the FD error message. Its `RequiredAdditionalInspectFormatProfile` error displaced the required Host error. The original Host assertions remain unchanged.

The new body performs the original percent scan, argument selection, String/Number/parse conversions, JSON formatting, percent escaping, ignored style argument and trailing-argument formatting. It uses the genuine existing inspector/classifier/primitive formatters and actual option literals. Calls to `inspect` keep the existing inspector's explicit layout gates; this unit does not replace those dependencies.

## Native ownership

The outer function creates the actual rest Array before its first body statement. The inner formatter owns the original lexical slots and performs each observed expression through the shared Node operation boundary. The matching `%s`, `%d`, `%i` and `%f` case locals reset only on reentry to the corresponding case; the current linked compiler keeps their slots alive across case exit. `tempStr` and the final trailing value retain their original terminal lifetime.

The JSON path uses the actual captured JSON.stringify and canonical caught completion. Lazy circular calibration constructs the real self-reference with an actual property Set, retains the original error/cycle locals, completes the split expression before selecting its first item, and preserves the original thrown identity. Successful flagged/private values remain DATA. Actual fatal events bypass ordinary calibration and guest catch.

String, numeric, JSON and String-method imports are captured during the genuine early inspector bootstrap. A reflected formatting input retains those callables. The shared inspector's 13-root function ABI is unchanged. The separate color composition from commit `642f5136` remains present without alteration.

## Authored controls

The existing `build-native-node-inspect-entry` install-only target and `native actual inspect` filter now cover 37 declarations. The original 24 names and bodies remain; this unit appends 13 formatter controls.

| Declarations | Scope |
| --- | --- |
| 25–31 | Callable shape, Host/FD/percent/suffix paths, conversion hints and shared numeric defaults, actual inspection options, inherited real rest Array, captured primordials, JSON and ordinary identity |
| 32 | Fresh lazy calibration through actual assignment and first error line |
| 33–35 | Ordinary private DATA, successful flagged DATA, and actual fatal preemption |
| 36–37 | Real matching-case holder retirement before the next argument getter, including exact fatal identity and no later progress |

Eight ordinary observer functions also accept the genuine pinned Node `format` and `inspect` exports. The authored `node-source-observer.mjs` selects exactly one observer per fresh Node v24.13.0 process, so the original lazy circular-error cell starts empty for each capture. It verifies the retained authority and observer bytes. It has not been run.

## Provenance and review

The original source is the complete retained `verification/node-inspect-entry-sourceonly-20261018/authority/inspect.js`, SHA-256 `380AA09FAE68E3279D0FB2469A24D75931A8098C84354347BF7130A38852B597`. `source-projection.json` contains the exact selected original declarations and extraction positions. Node/V8 reference authority is kept distinct from linked-VM native lifetime controls.

SDK's assigned production and declarations 25–31, VM's rest/catch/create/ownership and declarations 32–37, and Root's capture entrypoint are finite source-peer closed. The manifest records the current pins and bounded review scope.

No compilation, raw metadata acceptance, Node reference capture, native execution or whole-app qualification is asserted. Public `formatWithOptions`, broader inspector layouts, and the rest of the CJS/public application graph remain separate work.

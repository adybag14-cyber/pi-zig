# Intrinsic untagged template evaluation

This separate compiler correction starts at activation-lease source commit
a123f0ce504ba88ba9d404c60d09d91de1d458e4 (QuickJS C SHA-256
4C7632FF7211511ABECC27D126C302A1F217521B92F6CE6A08DB58004AA88B5A).

## Language authority

The original application runs JavaScript under Node/V8. ECMAScript 2026
[13.2.8.6, Runtime Semantics: Evaluation](https://tc39.es/ecma262/2026/multipage/ecmascript-language-expressions.html#sec-template-literals-runtime-semantics-evaluation)
requires intrinsic ToString of each untagged substitution before evaluation of
the subsequent template spans, followed by intrinsic string concatenation.
Tagged substitution evaluation instead preserves the raw values.

The old linked QuickJS compiler fetched mutable String.prototype.concat from
the first cooked string, evaluated all substitutions, and finally called that
method. Its own deferred-conversion comment identifies the affected location.
Those observable lookup and conversion-order differences are compiler defects;
they are not authority for changing native application owners.

## Bounded compiler change

One real to_string opcode performs the actual JS_ToString operation and consumes
its input before a later expression can run. It uses the unchanged actual
pending-exception reducer before and after releasing the operand. A selected
first fatal survives later cleanup; a cleanup fatal preempts an ordinary throw.

Only untagged lowering emits this conversion. It concatenates known primitive
strings with the existing intrinsic string branch of OP_add. No global String
or mutable concat method is consulted. The existing tagged raw/cooked object,
raw substitution and template-site cache paths are unchanged.

The real opcode count rises from 252 to 253 and still fits the one-byte opcode.
BC_VERSION changes from 28 to 29 so previously serialized opcode layouts are
rejected. The current writer/reader round trip is exercised directly; an old
version discriminator must fail before opcode consumption.

## Authored controls and qualification

Install-only target: build-native-vm-template-literal.
Root: src/native_template_literal_test.zig.
Filter: VM template literal.
Authored named declarations: 18.

Actual literal programs cover poisoned String/concat, string-hint and fallback
conversion order, ordinary throws, Symbol rejection, cooked/empty/nested
strings, real Await boundaries, raw tagged values and their receiver, cached
frozen template objects, and tagged versus untagged invalid escapes. A real C
sole-holder probe checks retirement before the next expression and causal
ordinary/current-fatal precedence at conversion and cleanup. The final two
controls serialize actual compiler output, execute it after GC, and reject the
obsolete version.

The compiler production diff has an independent finite source review. Source
review and authored declaration counts are not compilation, metadata or
runtime acceptance. This vendor change requires Root's fresh controlled build,
independent actual-metadata audit and separately authorized runtime phases.
No author-side native or Node execution is claimed.

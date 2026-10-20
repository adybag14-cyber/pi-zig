# Actual VM OOM occurrence observation

Source-only unit based on consuming-operand commit f8a73a046683aab610c8a3b77c45938d2aaf5294. No build, metadata query, native runtime, Node, generator or formatter was executed for this unit.

## Operation and limits

The three C edits add one zero-initialized runtime counter, its allocation-free owner-thread getter, and one increment at the entry to the existing JS_ThrowOutOfMemory body. The header addition declares JS_PiOutOfMemoryOccurrence(JSRuntime*). The original report, compiler-diagnostic guard, recursive-report guard, exception construction and pending behavior are unchanged.

The counter counts actual report entries modulo 2^64, including a recursive attempt to report failure while creating the reporting Error. It is not a physical allocation-attempt counter or an Error provenance tag. A caller must snapshot it immediately around an admitted non-guest intrinsic and require that operation's actual failed result. A retained historical Error, a public fatal flag, a raw allocation failure that never enters JS_ThrowOutOfMemory, or an ordinary failed intrinsic is insufficient.

The selected source packet retains the original runtime calloc, OOM report, string allocation reporter and UTF16 length guard. The overlength control uses the actual JS_NewStringUTF16 API, which rejects the oversized length before reading the one-element input. It does not use JS_NewStringLen, whose UTF8 scan precedes the length rejection.

## Controls and ownership

The actual raw QuickJS root declares 13 controls. They cover successful allocations; direct and recursive reports; actual string, object, ArrayFrom, atom and shared-shape allocation failures; raw no-report malloc failure; ordinary RangeError; allocation-free observation with ordinary/fatal pending reasons; shared-runtime and separate-runtime histories; and historical Error DATA versus private execution termination. Consumed inputs and failed raw results have real owners before assertions. Heap limits are restored before inspection; native Probe storage survives all relevant runtime teardown.

SDK closed the complete four-edit production delta and controls 1-5, 7, 9-10. Modules closed Fixture/Probe/native retirement, controls 6, 8, 11-13, and the six-line install-only build seam. These are source reviews, with no transferred execution qualification.

## Intake

Apply production-delta.json's three C edits and one H edit by exact preimages after consuming25. Preserve all unrelated Main additions; do not replace Main C/H with donor files. Add the actual root, its evidence directory, and the six build lines from build-intake.json. The target is build-native-vm-oom-occurrence, filter VM OOM occurrence. Declared count is 13; actual native metadata remains unobserved.

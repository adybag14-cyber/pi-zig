# Proposed genuine AF consumer changes — not applied

The existing stream IIFE remains a genuine native AF. This proposal adds no async wrapper around an old flow, no JS adapter and no new Promise constructor. The C acquisition export alone is insufficient; the consumer's failure phases must match for-await.

Replace only the .response acquisition after decoder.start:

```zig
const iterable = try scope.get(owner, "sdkStream");
const iterator = try scope.own(try scope.engine.checked(
    c.JS_PiGetAsyncIterator(scope.engine.context, iterable),
));
try scope.put(owner, "iterator", iterator);
try scope.put(owner, "nextMethod", try scope.get(iterator, "next"));
// Do not enter the body/close region until result.value has been read.
try scope.put(owner, "iteratorActive", c.JS_NewBool(scope.engine.context, false));
try next(scope, owner);
```

next() must set iteratorActive=false before calling its retained nextMethod. Its synchronous call failure and rejected Await then leave the loop without outer AsyncIteratorClose. In .next, keep this flag false during object validation, done and value getters. On done=true, finish with no close. Only after obtaining nextValue successfully set iteratorActive=true and evaluate the provider hook. .chunk stays in that body region through decoder.push; calling next() leaves it again. This also avoids closing on a primitive next-result or throwing done/value getter, rather than treating all errors as loop-body errors.

For a body throw, fail() stores that original raw reason and clears the active flag once. The return getter, noncallable return, synchronous return call throw, rejected close await, and primitive close fulfillment all preserve that existing throw. Current return-getter replacement behavior must be corrected. A nullish return skips the await; an actual call returns an owned Await action and .closed applies the original failure. Trusted native OOM/uncatchable exceptions still escape through the separately qualified primitive/helper; they must not be normalized or suppressed as guest errors.

For normal break/return completion in the prepared generic consumer, the close getter/call/await errors instead propagate, and successful close fulfillment must be an object. The production OpenAI loop currently needs the body-throw path; the generic prepared controls cover both completion categories so their distinction is reviewable.

Acquisition failures leave no active iterator. Reading returned iterator.next is once per record, before the active body region. The C wrapper returns an actual async iterator unchanged or the engine's actual AsyncFromSync object; its internally retained sync next method and marked roots remain engine-owned. No subsequent per-iteration property lookup or extra Await is added for yielded values by the consumer. The actual engine wrapper performs sync value unwrapping; genuine async iterator values remain unwrapped.

The observed engine rejection-close omission remains a separate blocker. A consumer must not compensate with an unconditional outer close on next rejection: that would incorrectly close true async iterators and errors whose standard path does not close. Any repair belongs in the reviewed native AsyncFromSync continuation after genuine reference observations establish exact behavior.

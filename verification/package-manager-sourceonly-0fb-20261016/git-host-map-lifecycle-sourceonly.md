# Default-used LRU Map lifecycle successor

Source-only successor to cfb9adc01d6105d4633311e22d6d0e6fd1b21e16. Root
requested the actual Map lifecycle after the private native list was identified
as distinguishable through live Map.prototype hooks. Prior checkpoints and
all previous Source inputs/goldens remain unchanged.

The full GitHost factory now retains an actual VM Map. The default max=1000
lifecycle uses the original fixed numeric slot indices, actual filled VM
key/value arrays, Uint16 next/prev/free storage, and live get/set/delete/clear
method lookups/calls. has uses Map.get, not Map.has. Existing-key updates promote
and replace the value without a redundant Map.set. Eviction deletes the old
key before reusing its slot. List/value writes occur before Map.set; link/tail/
size changes occur after it, preserving reentry and partial writes when a hook
throws. All index values remain VM values with actual property-key/coercion
operations rather than narrowing a hook's return to an unsigned host index.

Undefined set performs the actual deletion path and still finishes with the
fromUrl cache.get. Last-entry deletion uses the Source reverse-index validity
walk (including its Map.get) and Map.clear before filling/resetting lists.
Native loop checks preserve interruption instead of silently truncating a
corrupted/reentrant list. Successful hit identity and max-1000 LRU ordering
remain part of the same used default lifecycle.

Short-lived helper scopes release their temporary roots at each actual helper
return. The new constructed instance's temporary argument ownership ends after
set returns or throws, before the final get hook runs. This does not retain an
otherwise removed instance across that later callback merely to simplify the
native ownership implementation.

The helper implements the actual default-used cache lifecycle. It does not
export a fabricated general LRUCache class, configurable TTL/disposal/fetch,
diagnostics subscription API or a broader lru-cache package replacement.
Those APIs are outside this used dependency packet; broader global/default-
option instrumentation and all runtime/allocator equivalence remain unqualified.

The separate original input git-host-map-lifecycle-0fb.input.mjs defines five
named cases: ordinary miss/hit/undefined, set throwing after its real write,
get reentry forcing an outer miss/update, undefined-result deletion of a
reentrant last entry, and max-1000 promotion/eviction/slot reuse. Its Map hooks
delegate to the actual original methods and record real calls/results; they
do not implement the cache. Each case must run in a fresh sealed process and
fresh native context. The separate prepared runner supplies caseId explicitly,
retaining the original parser/dependency checks and full observer/control seal
requirement. Neither runner nor input has executed, and expected output is absent.

Only source edits, reads, hashes and git diff checks were performed. No Node,
Source observer, Zig formatter/AST/compiler, native or C job ran. Engine,
shared SDK/Scope/class, Root, default selection and release are unchanged.

# Mutable native AsyncFunction formals

This source unit gives opted-in native async bodies the VM's actual argument slots. The concrete consumers are the three formal parameters of Node v24.13.0 `open` and the five of `read` in `lib/internal/fs/promises.js`: both bodies assign their parameters before their real I/O Await.

## Ownership

The existing native invocation now allocates and initializes `max(actual argc, formal_count)` slots when the factory explicitly opts in. Supplied values are duplicated once; missing slots start as the VM's runtime undefined value. The original supplied count is retained independently and remains available on every callback. The same expanded storage is marked and retired by the existing invocation owner.

`Arguments.get` borrows a declared slot. `take` consumes an owned incoming completion and uses the existing consuming store operation, publishing the replacement before retiring the previous value. Its failure path preserves actual pending/fatal selection and consumes the incoming owner even when entry is already blocked. The adapter and its C frame pointer are valid only during the current native callback; neither belongs in state, a closure, or a worker.

The existing terminal order is preserved: current argument slots retire before the terminal state-close hook and original locals, while adoption still observes them live. Arrow lexical this and the supplied call receiver keep the independently reviewed ownership from the parent revision.

Observable `Function.length` does not determine the number of formal slots. Default prologues initialize additional Source parameter-scope locals, and mutable captures need their genuine binding owner. Those are separate from this opt-in storage API.

## Exact lineage and controls

The parent is `d50cdef4f756ee6ae81bfe5987b33ff3a423e264`. The original eight C edits and their initial base are preserved in `c-owner-delta.json`; `rebased-c-owner-delta.json` records those exact edits on the corrected async retirement parent. The header and Zig factory/adapter have independent finite source peer closures.

Seventeen literal Source/native controls are retained in `src/native_async_arguments_test.zig`. They exercise supplied count versus declared formals and length, missing fourth/fifth assignments through two Awaits and GC, extra/zero-formal ownership, a real finalizer reading the replacement slot, actual private Await rejection data, final return adoption, gate abandonment, lexical versus supplied receivers, current-frame admission, consuming blocked stores, and actual native allocation failures before subsequent body/catch work. Native-only contract checks are explicit in their test bodies.

The new build step is `build-native-vm-async-arguments`, filtered by `VM async arguments`. It installs an artifact without running it. The manifest records declared names; actual imported metadata must be discovered from the exact artifact.

## Qualification status

Source authoring and review do not establish execution acceptance. This unit has not been compiled, queried, or run. Root controls the next source intake and fresh immutable-source qualification. The physical FileHandle owner, actual backing-storage lifetime during asynchronous reads, and bytecode stack/recursion equivalence remain distinct work.

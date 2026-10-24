# StreamBase JS dispatch — source-only handoff

Base: checksum-verified Main 65fac997. All work is in the assigned SDK worktree. No pre-existing donor/source file was overwritten; ten scoped SDK inputs retain their recorded SHA-256 values.

## Reviewable change

The exact stream-base-js-dispatch.patch contains five paths:

- New src/extensions/native_node_stream_js_dispatch.zig.
- New src/native_node_stream_js_dispatch_test.zig with thirteen named controls.
- Projected src/extensions/native_node_stream_base.zig.
- Projected src/extensions/native_node_file_handle_owner.zig.
- Projected build.zig.

The three projected files live beneath projected/; they are exact successors of current Main inputs, not the older SDK copies. The patch is intended for Root's Main integration after the current validation batch closes.

## Implemented behavior

The callback bodies preserve original StreamBase::JSMethod receiver handling and guard order: no native receiver returns undefined; a dead stream returns UV_EINVAL before argument CHECKs or trigger handling. Live dispatch scopes the actual Environment's default trigger id to its AsyncWrap id and restores the previous value on native error, JavaScript exception, nested invocation, and native stream destruction. It does not dereference the stream after invoking the method.

ReadStart/ReadStop enter the concrete FileHandle's existing native read owner. Shutdown invokes current Main's actual Shutdown implementation and retains the original object CHECK; UseUserBuffer invokes current Main's native CustomBuffer listener owner. No duplicate implementation or fallback success body was introduced.

GetFD has its own missing/dead guards and no trigger scope. Its original virtual default remains -1; FileHandle supplies its actual descriptor. Counter getters return JavaScript Numbers using the original uint64-to-double conversion, including rounding beyond 2^53, and continue to expose counters on a closed but still attached stream. Retired native receivers return zero counters.

Base's previously absent pure virtuals remain explicit dependencies until a real derived stream supplies them. The FileHandle adapters supply the actual existing owners.

## Focused source controls

The thirteen controls cover absent/wrong-brand receivers; genuine unattached instances; dead guard order; real descriptor access without GetAsyncWrap; Number rounding, closed counters and retired slots; physical read/stop completion with real byte counts; missing virtual dependencies; selected native failure; exact JavaScript thrown value identity; nested trigger restoration; native deletion during a method; actual CustomBuffer listener publication; and actual Shutdown request completion with closing-versus-dead behavior.

The projected build adds build-native-node-stream-js-dispatch, filter "native StreamBase JS dispatch", and the existing CustomBuffer native allocation C++ source. Its link/include closure matches current Main's CustomBuffer test root.

## Integration and remaining scope

Apply the patch against the recorded Main input hashes. Do not compile the older SDK donor graph with only the two new files: it lacks current Main's Shutdown/callback/registry/support changes. Root owns the exact merge, catalog registration, separate native admission and execution.

This slice deliberately does not publish a complete StreamBase prototype or FileHandle constructor. Original write methods, external_stream, full AddMethods/accessor installation and embedding bootstrap remain separate owners. ActualFileHandleCallbackTemplateRequired is unchanged. These sources therefore do not establish whole-application startup or production Node bridge removal.

Retained authority: verification/native-node-stream-base-sourceonly-20261020/authority/stream_base.cc.v24.13.txt, notably 151–173 (read, user buffer, shutdown), 487–489 (default fd), 626–650 (fd/counters) and 660–669 (JSMethod), plus its pinned header/inl files. The inputs-and-outputs.json manifest records exact hashes.

## Validation status

Performed: byte-hash checks before/after authoring, exact source-anchor replacement, relative-import resolution against the intended Main overlay, thirteen-control count, whitespace checks and exact patch generation.

Not performed: Zig parsing/semantic analysis, compile/link, native metadata, native runtime or terminal CHECK execution, Node reference capture, catalog changes or application startup. Every test remains unexecuted. The retained native CHECKs were not weakened or converted into recoverable test-only behavior.

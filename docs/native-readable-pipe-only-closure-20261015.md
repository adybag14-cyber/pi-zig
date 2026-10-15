This isolated source-only pipe closure starts from the clean typed public
composition429dd9c8. It adds real pipeTo/pipeThrough, native default controller
composition helpers, captured readable exports, qualified Writable8a and its
separate source-only db4110 host-failure retirement wrapper, plus native signal
listener add/remove helpers over the existing actual AbortSignal queue.

It has no static.from, native_readable_from_sync, native_async_generator import
or new C/header dependency beyond the previously reviewed live-view span API.
It is suitable for source review on the existing Body/Request/Fetch C baseline
without partially overriding a newer qualified AsyncGenerator interpreter.
Engine changes are the earlier readable root/free/class IDs plus only writable
root/free. No whole Engine, unrelated Env work, vendor or proof was copied.

The implementation acquires real reader/writer locks, marks actual disturbance,
uses writer readiness and actual writes, preserves final read/write ordering
against reader.closed, waits dynamically for the latest write during shutdown,
and invokes real close/abort/cancel algorithms. pipeThrough returns the genuine
pair readable after starting/handling that actual pipe. Native failure cleanup
settles real capabilities without Scope root allocation. No stream or worker
substitute is created.

Only static AST/fmt/diff checks have run. This is not public-stream, Request55,
Fetch39, pending pipe, native Signal, allocator or worker-retirement runtime
qualification. The admitted429d four-target NATIVE2 candidate remains a separate
frozen tree and contains none of these changes. Genuine pipe Source cases and
a matching native compile/runtime/GPA gate remain required.

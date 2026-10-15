# Native Response source checkpoint

This checkpoint authors the actual `Response` native JSClass facade against the
Node v24.14.0 bundled Undici 7.21.0 authority retained by the preceding Body176
source capture. It is source work, not a passing native qualification.

`src/extensions/native_web_response.zig` owns the Response class, constructor,
private response fields, descriptors, getters, clone facade, static methods and
native transport constructor. Each retained JS value is duplicated, marked and
freed by its native owner. It delegates extraction, disturbance, consumption and
stream cloning to `native_web_body.zig`; it does not implement a second Body or
stream graph.

The isolated source base is `eddc37aef1e17f69a198a495cd1919846b3b4286`. The reviewed
shared Body source checkpoint `76bc500da76a9fac8124af6301f69904f5ef1563` was intaken
as `75512991` before this Response work. That source includes the reviewed native
collector, text decoder and nonconstructible native arrow dependency.

The `web-response-node24.input.txt` fixture is a Response-only projection of the
genuine Body176 input. Its expected results remain in the original immutable
`web-body-node24.json` capture. The replay requires exactly 114 unique mapped
rows and compares complete rows in captured order, including actual engine error
messages. No golden has been generated from this native implementation and no
error has been rewritten to resemble Node.

The test bootstrap requires Env's actual `native_readable_stream.zig` public
graph. Its accepted exports are `install`, `isDisturbed`, `isErrored`,
`closeController` and `fromBytes`, using the engine and genuine JS values. It
roots the real constructor as the shared Body binding; native adapters invoke
the stream owner's actual state functions. The public stream graph is not yet
available in this source base, so neither semantic compilation nor the 114-row
replay has run. Pinned Zig 0.16.0 formatting and AST checks passed.

The transport seam is `fromTransport(engine, Transport)`, returning an owned,
genuine Response with immutable Headers. `Transport` borrows `body`, `status`,
`status_text`, `headers`, `url` and optional `redirected`. A genuine stream,
copied Uint8Array or null is supported by the shared source seam. Raw HTTP
iterators require the shared Body/fetch owner's actual stream adapter; current
Body source explicitly rejects async iterable extraction and multipart
encoding/parsing until those ports land.

Tests also exercise actual transport class identity, duplicate Set-Cookie
preservation, immutable original/clone headers, URL fragment removal, independent
cloned body consumption, body lock versus disturbance, real GC and five selected
native operation allocation failures. These tests are authored and unrun.

Build steps are `build-native-web-response-source`,
`test-native-web-response-source` and `test-native-web-response-oom`. Their native
jobs require Root's resource admission and the genuine stream dependency
checkpoint first.

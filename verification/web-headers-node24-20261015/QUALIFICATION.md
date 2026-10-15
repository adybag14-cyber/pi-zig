# Native Headers qualification boundary

Baseline: `3f0cce9ad90ee9618d4216d9889f088f6a28f6de`, isolated branch `pi-zig-web-headers-20261015`.

The genuine Source oracle is global Headers from `C:/Program Files/nodejs/node.exe`, Node v24.14.0 SHA256 `63c259c81e5d472b5f11c8d506070130cb04a1ecf84b80377a34ed6ec9048088`, bundled Undici 7.21.0. The complete actual bundled authority was extracted through `process.binding('natives')['internal/deps/undici/undici']`: 728836 bytes, SHA256 `c62030f1e505a4010d9972ecbf40155eddeb355f2a53a9f019a447214e1a9600`. Installed npm Undici is not substituted.

`web-headers-node24-source-first-20261015` terminated successfully, PID 64756, UTC 2026-10-15T18:07:00.8276126Z to 18:07:13.0353766Z. Its 189 unique cases and six actual GC calls are preserved byte for byte in `src/extensions/fixtures/web-headers-node24.json`. Fixture input SHA256 is `8f3be8d9c250eec0048331c461490704207b6e9375fb45c4d4e47ede9bc0b83b`. Complete before/after Source1967/runtime31064/Node-tools1774/absent84/candidate5954/control identities had zero drift. The capture used granted LIGHT6, 2 GiB admission, Node256MiB, 300-second owner.

Native code and comparison harness are authored; native compilation/runtime are pending a granted normal lane. `zig fmt`, `zig ast-check`, and `git diff --check` passed. No native parity, full Web APIs, platform matrix, main activation, release, or publication is claimed here.

`native_headers.install(engine)` installs one native constructor per engine idempotently. `native_headers.fromRecord(engine, init)` returns an owned, genuine Headers value using HeadersInit conversion, including iterables. A whole null init rejects; a null record field becomes the string `null`. Provider-specific nullable tombstones belong to provider buildHeaders. `isHeaders` checks actual native private storage, and `setGuard` supplies the internal none/request/response/immutable boundary for later Request/Response ownership.

Native runtime target replays all 189 genuine rows without projections or altered expected rows. It adds actual immutable guard/helper checks and selected allocation-failure offsets measured after true engine setup. The separate exhaustive full-engine OOM target is authored; selected operation failures cannot qualify full allocation ownership. Custom inspect delegates to the existing native default diagnostic formatter; general util.formatWithOptions options and arbitrary overridden intrinsics need separate broader comparison before a full Headers claim.

Request, Response, BodyMixin and global fetch are later phases. No empty Response or duck brand substitute is installed. Native HTTP onResponse metadata remains a plain record where Source expects a record; SDK request init and APIError headers need actual Headers. Shared native HTTP workers and Env byte-stream ownership are not edited by this lane.

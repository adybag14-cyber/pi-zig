# Reviewed mkdir source intake

Exact reviewed product authority:
f79b9caa01c9d6a2e14ffeda91a1485fda3d2a9d.

Only these two new product files are required from this branch:

| Path | SHA256 |
| --- | --- |
| src/extensions/native_node_fs_promises_mkdir.zig | DE72A89F60C4C5827472145820BB58779504DB46A5326B6EDEF6776E445A8C68 |
| src/extensions/native_node_fs_mkdir_exit.zig | ED8BD489E8BE42862A9F68AB409DE55410CA02616C22493B745E795D923E2C7D |

Independent Async source review receipt, authored by the reviewer and verified
read-only at C:/Users/adyba/pi-zig/evidence/fs-mkdir-f79-independent-async-source-review-20261017.json,
SHA256877E1B53BFE9A566197C4931FD03F03DE66960F3E683C90AABDF6E752784C52B.
This closes the finite worker/Hub ownership and local owned-exit findings. It
does not establish physical filesystem, cancellation, ABI or runtime equality.
All prepared controls remain UNRUN.

Do not copy this branch's Main147 shared Engine/Hub/VM/AF bytes over newer Root
authorities. Keep Root's genuine C3 AsyncFunction primitive and its independently
owned ordinary THROW/DATA/prebody prerequisites. This branch adds no shared
Engine, Hub or C/H implementation change.

The Root-only integration point is in node_fs's installation before either
fs/promises ESM module is registered/frozen, using the same promises object
already assigned to fs.promises:

```zig
try @import("native_node_fs_promises_mkdir.zig").install(engine, promises);
```

The convenience factory captures the actual Error.captureStackTrace binding at
trusted bootstrap. An embedding with an already captured primordial can instead
use createWithInputs(engine, .{ .error_capture_stack_trace = actual_capture })
and install that exact returned function on the actual shared namespace. A late
object-property replacement after named ESM exports freeze is not equivalent.

Google's genuine node-sqlite adapter consumes that exact namespace binding via
Inputs.mkdir. Its retained Source awaits mkdir(dirname(path), {recursive:true})
before creating DatabaseSync and skips mkdir/dirname for :memory:. No stub,
mkdirSync alias, alternate namespace or synthetic database path is needed.

Prepared controls and historical proof packets remain in this directory. The
physical original/native control requires separate empty retained fixture roots
and real binding installation. Root still owns all resource/ownership grants,
original Node capture and native execution admission. No expected output or
golden was generated, and this documentation-only intake note changes none of
the exact f79 product/control bytes.

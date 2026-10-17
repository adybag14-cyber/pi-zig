Actual jiti2.7 cache.ts/transform.ts source port, based on immutable primary
fd3bb289b75ed207edfb686d671ed50144f7e90f and Root675252b2. No executable,
Node/native/compiler/generator job is run or granted by this packet.

native_jiti_fs_cache.zig implements CACHE_VERSION="9", getCache(ctx,topts,get),
prepareCacheDir(ctx) and getCacheDir(ctx). create(engine,Inputs) returns owned
actual ordinary declarations named getCache/prepareCacheDir/getCacheDir with
lengths3/1/1. The prepare declaration retains the SAME real getCacheDir function
used by that module. Every input is an actual FS/os/pathe/utility function,
retained/traced through existing aggregate-charged native callables.

native_jiti_transform.zig implements actual transform(ctx,topts), ordinary
length2. Inputs.get_cache is the actual cache declaration above; Inputs.debug
is the actual shared utility import. Its nonconstructible zero-argument get
callback captures the real ctx/options/debug values. Source cache, transform
and frontend share their canonical declarations through the frontend owner's
once-linked module graph; no Engine/global/default selection is introduced.

The cache computes the real inline source hash suffix, path/name flags and
filesystem reads/writes in source order. Hits return stored suffixed code;
fresh transforms return raw code after storing code+suffix. __JITI_ERROR__
output is not stored. The outer transform applies its shebang prefix AFTER
getCache returns, preserving original cached bytes. Code/error/getter returns
are not coerced or normalized early; raw ordinary throws remain original.

prepareCacheDir preserves callee/assignment receiver order, recursive mkdir,
actual writability check, debug-before-disable catch order and fatal escape.
getCacheDir performs real nearby-node_modules resolution, then actual os.tmpdir
and live global process/env/cwd accesses. TMPDIR delete/recompute/restore is
exact source order; there is deliberately no invented finally restoration when
the second tmpdir call or a later restoration getter throws.

The transform hook is the actual ctx.opts.transform USER option, invoked with
its original opts receiver. Callee acquisition precedes transformOptions spread,
sourceMaps-derived babel fields, second transformOptions?.babel spread,
interopDefault and final top-level option spread. res.error is tested first,
read again only for debug, and res.code is read afterwards. An actual getter or
debug throw keeps the source's original completion and prevents later reads.

The reviewed API12a compiler is not substituted for this hook/default Babel:
its explicitly bounded source grammar, output formatting, source-map and error
contract are not the full Babel result contract. The actual public default
transformer/backend is a separate finite assembly/compiler dependency. This
packet neither supplies an identity transform nor executes a JS Babel host.

Genuine dependency ownership: models_refresh owns actual pathe functions and
is adding resolve/utils.filename; utility owner supplies actual debug/isWritable/
hash. Existing node:fs exports provide exists/mkdir/read/write, and the real
native_os_tmpdir export captures the original Node process/environment store.
Jiti hash requires actual MD5 by default and SHA256 when real FIPS mode is on;
the existing SHA256-only crypto profile cannot be silently relabeled as MD5.
Those input contracts are explicit, with Root coordinating missing owners.

source-caller.mjs is prepared genuine reference tooling. It requires the exact
admitted official jiti2.7 dist factory and invokes its REAL public transform
method with original owned custom-transform user options and real filesystem
objects. These user hooks test supported customization; they do not prove a
default compiler or act as substitute FS/hash/cache implementations. Explicit
tsconfigPaths:false avoids an unselected config dependency in this scope.
The caller's owned-start nonce/cwd/tmp fence is additional to, not a replacement
for, Root's separately reviewed capture controller and full process/resource/
permission/network/bytes inventory. Only owned dummy environment values may be
supplied by the cleared ProcessStartInfo; no host environment is enumerated.

The caller prepares23 real public observations: misses/hits/staleness/rebuild,
flags/option spread order, marker non-store, shebang cache ordering, raw code/
throw identity, debug getter order, real directory/write failures, nearby cache
selection and owned TMPDIR behavior. Direct source boundary and native fatal/GC
controls are also prepared. No expected, observed or new golden files exist.
Old Source48/39, API12a19/39, OpenAI58/52 and metadata proof bytes stay untouched.

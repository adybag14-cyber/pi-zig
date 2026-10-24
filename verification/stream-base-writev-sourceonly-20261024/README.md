# StreamBase Writev and bounded encoding — source-only packet

This packet implements the original private StreamBase::Writev callback and its missing native vector-encoding collaborators. It depends on the sealed Write20 and StringWrite18 packets. Every earlier donor, projection and packet remains unchanged. Main remains Root-owned at 65fac9975b25e9a5e4c00d7d7bca499aae1275c0.

## Selected files

Use source-intake.json as the authoritative selection. The three production owners are the v2 MaybeStackBuffer, v2 Stream string-bytes owner, and projected Writev owner. The selected controls are projected-v4/src/native_node_stream_writev_test.zig; earlier fixture/test drafts are preserved and unselected. The projected dispatcher and build are exact successors of StringWrite's selected files.

The real callback preserves fixed concrete Array count, strict-true all_buffers, both observable passes, Get/ToString/encoding order, native -1 plus the actual pending reason on ordinary failure, and the complete first-pass INT_MAX guard. Buffer::HasInstance in the retained Node version accepts all ArrayBufferViews, including DataView and non-Uint8 TypedArrays; proxies are not unwrapped.

The eight-encoding owner preserves ParseEncoding's primitive-only default, ASCII aliases and embedded NUL C-string behavior; source StorageSize formulas; bounded UTF8 replacement and pair clipping; low-byte ASCII/Latin1; whole UCS2 code units; and original base64/hex fallback behavior. The scalar nbytes decoder replaces the SIMD success optimization: valid SIMD-success inputs have the same decoded prefix, while all malformed, alphabet-mismatched, wide-low-byte and short-capacity cases follow the retained nbytes algorithm. This equivalence is a source reasoning result, not a captured native comparison.

Native temporaries preserve the 16-vector and 1024-code-unit/byte stack thresholds, actual charged heap ownership, one full-GC retry, and terminal native CHECK. ParseEncoding retains Utf8Value storage sizing; wide decoder paths retain TwoByteValue's copy and terminating code unit even for zero output capacity.

The callback retains real local values through Write and delegates to the existing genuine Write/TryWrite result, provider52 WriteWrap and shared listener owners. Positive backing storage moves only to a returned WriteWrap. Zero-byte inputs still enter original Write/DoWrite when no try shortcut completes them. Result native-pointer retirement precedes local backing retirement and vector retirement. No per-view asynchronous lease is invented.

## Controls and inspection

There are 32 declared positive controls. They cover primitive encoding parsing, bounded and malformed encodings, storage and charged temporary thresholds, ArrayBufferView breadth, strict flags, empty and odd arrays, repeated getters/coercions, changing second-pass values, fixed count, errors in both passes, retained views under GC, asynchronous and synchronous backing retirement, partial/full/error try-write, seventeen-vector heap storage, init-hook and error-setter pending reasons, real FileHandle ENOSYS, absent/dead guards and nested canonical dispatch.

Original invalid request/array/all-buffer brand, odd first-pass hex, arithmetic and terminal allocation CHECKs remain native process failures. These positive controls do not execute those terminal paths.

Static inspection verified 50 unique pins reached from the sealed StringWrite entry, 34 direct import resolutions, six selected targets, exact four dispatcher edit inverses, and the sole 1721-byte build insertion. No Zig parser, formatter, compiler, native metadata, test process, Node capture or production launch was executed.

## Integration

Apply this packet only after the exact StringWrite and Write prerequisites. Compose only build-addition.zig.txt into Root's accepted combined build; copying the standalone build would omit unrelated Module/application additions. The install-only target is build-native-node-stream-writev, executable native-node-stream-writev.exe, with the distinct filter native Stream vector write. It uses the same genuine FileHandle fixture and native owner dependencies as the accepted predecessor.

No new C ABI is added here. The inherited JS_PiBorrowFlatStringView C/header changes still require rebuilding the actual QuickJS library before native qualification; an older archive cannot qualify this packet.

The completed Writev body does not publish the complete StreamBase/AddMethods or FileHandle constructor. The genuine external_stream value owner and complete original publication wiring remain separate dependencies. Application startup still requires Root's Module/factory integration work; this source packet makes no startup or whole-port completion claim.

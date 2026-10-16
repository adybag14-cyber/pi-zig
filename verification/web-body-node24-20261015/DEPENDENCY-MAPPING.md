# Focused dependency gate from actual Source176 observations

Target pair: `build-native-web-body-dependencies`, `test-native-web-body-dependencies`. No grant or execution is implied by preparation. The target also replays original Headers189 and its existing helper/selected-OOM regression checks against the updated shared helpers.

Seventeen comparisons map unchanged genuine Source176 outputs to independent shared dependency behavior:

| Actual Source row | Native behavior compared |
| --- | --- |
| global descriptor Blob / File / FormData | The three genuine native global constructor descriptors |
| Response binary 6/text, arrayBuffer, bytes | Original Blob text and byte data, plus its MIME type; no Response claim |
| Response binary source mutation ownership | Shared BufferSource copying and caller mutation independence |
| Response text UTF8 replacement and BOM | Shared native decoding used by Blob text |
| Response FormData actual multipart roundtrip | Original FormData fields and actual File name/type/size/text only; multipart encoding/parsing is not tested by this mapping |
| Response init 3,4,5,14,18 | Actual WebIDL dictionary/ByteString/HeadersInit conversion errors |
| Response invalid header sequence conversion before invalid status | Conversion phase and caller-specific argument prefix |
| Response header ByteString conversion before invalid status | Early conversion error and original ByteString argument label |
| Response statusText Symbol | Actual ResponseInit ByteString Symbol error |

Additional native controls exercise genuine Blob/File private storage, inheritance and explicit unavailable-stream failure. Five selected allocation failures are measured after real dependency setup over one actual Blob/File/FormData operation. They do not claim full-engine or exhaustive allocation ownership. The complete176 expected packet is unchanged; this target does not delete or reinterpret the unimplemented Response/Request/multipart cases.

The separate copied `build-native-body-collect` / `test-native-body-collect` target retains the collector owner's independent large-byte, error/abort, UTF8 and GC controls. It does not qualify this lane's whole Body graph or any provider by itself.

# Private simdjson allocation successor

These two source files are the isolated allocator successor of Node v24.13.0's pinned simdjson 4.1.0 amalgamation at commit def0bdf8abee441cfcbf793a8dc24a6f3b899573.

The unchanged originals and their complete license are retained in ../simdjson. The source license remains the original simdjson license; this directory does not replace or relabel the original authority.

Only the selected ondemand parser's actual backend object and array allocation/deletion paths are redirected to src/extensions/native_simdjson_memory.{hpp,cpp}. The native memory owner charges every real allocation, including replacement overlap, and remains retained by each successful block until its own deallocation. Parser algorithms, allocation order and failure branches remain the original source.

The exact reversible edits, original and successor hashes, actual libc++ short-string proof, allocation inventory, and remaining wrapper admission requirement are recorded in verification/native-package-json-binding-sourceonly-20261020/simdjson-allocation-successor.json.

This is a source-only draft. No build, parser control, native execution, package-binding publication or complete allocation-coverage claim for unselected simdjson APIs is made.

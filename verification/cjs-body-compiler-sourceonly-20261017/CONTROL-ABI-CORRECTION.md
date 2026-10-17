# Prepared control ABI correction

SOURCE ONLY successor to immutable430dac95. AuthFailure's independent raw-adapter control review identified that the actual pinned C header declares bool JS_IsAsyncFunction(JSValueConst) with ONE value argument. The same wrong two-argument spelling also occurred once in this older unrun CJS control root. This successor corrects that call only; production C/H/LRE/inc, all43 control names/assertions and old source-review receipt remain unchanged. It does not turn the source closure into a compiler/runtime result. No compiler/parser/metadata/native jobs ran.

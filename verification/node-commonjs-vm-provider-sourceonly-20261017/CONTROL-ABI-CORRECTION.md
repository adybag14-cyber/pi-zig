# Raw adapter prepared-control correction

SOURCE ONLY successor to6c206489. Independent review of the immutable header identified the two prepared controls used an extra context argument for JS_IsAsyncFunction. Both now call the actual one-JSValue bool ABI. Product/ownership/ABI declarations and all four control names/assertions are unchanged; no parser/compiler/native job or metadata query ran. The original6c manifest remains historical. New inert primary scanner files are separate metadata-authoring inputs, excluded from this correction and its finite review.

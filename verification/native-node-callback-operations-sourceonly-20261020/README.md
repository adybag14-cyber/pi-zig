# Native callback assertion operations

This source unit provides actual native assertion/failed-Maybe dispatch and the corrupted-async-stack reporter adapter. It extends the callback Check enum with the ten real Read assertions required by the physical FSReq owner. All exits call the direct C owner already linked in Main; no guest Error or process event is substituted for a native terminal failure.

The SDK source peer closed the FS/Request/Binding mapping. Aggregate port identity/resource/size diagnostics remain explicitly labelled as port invariants. This unit does not yet install the complete Environment Operations table, admit the abort-on-uncaught option, or establish expected-exit runtime behavior. Those gates remain open. No source change was made to frozen Main during V18b.

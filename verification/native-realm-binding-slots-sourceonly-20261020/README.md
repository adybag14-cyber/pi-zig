# Separate native Realm slot for modules BindingData

This source-only prerequisite adds one native weak metadata slot for node::modules::BindingData to the existing Registry. It leaves the FS slot, the shared BaseEntry FIFO, AsyncWrap State, and existing constructor and reset algorithms unchanged.

The base is current Main `A5EF66E7B302998DB7C27E8EA2B7C1315F154286D3B284A5670358B6B5CF863A` (19,937 bytes). It already contains Root's three documentation placement corrections over the earlier DE347 file. The successor is `B53C4D0C1412BA496A267C03F58F8AB88CDA0288336098180D986C9D9FC0A04F` (20,128 bytes).

Exactly two edits add `modules_binding_data: ?WeakBindingSlot` and clear that slot before releasing its native weak entitlement during final Registry retirement. The Environment remains alive until after Registry storage and both weak slots retire. No JavaScript wrapper root is introduced.

The retained Node24.13 Realm-inl source uses a per-binding-type indexed weak store; its full SHA is EDAEF1C54760111714DE1C027073732D9571E5903064B1C8B807DC3514FE19D5. The exact selected source and complete two-edit forward/inverse evidence are in source-delta.json (5469132F9DA4515378428190A7F25408585C4A9CA2C00F1F68BD50D87CB353DF).

Root and Modules independently closed the complete Registry lifetime delta and exact reversal to Main. Actual modules BindingData construction, parser/cache ownership, target publication, controls, and public namespace assembly are separate Modules work. This prerequisite has no new build target. No compiler, native test, Node, generator, formatter, or AST execution was performed.

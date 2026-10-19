# Actual private property Set for Node internal bindings

This source unit provides the selected `markTransferMode` operation used by the
retained Node FileHandle implementation. Its key comes from the linked VM's
existing `JS_NewPrivateSymbol`, whose private atom kind is distinct from a
public JavaScript Symbol.

The retained V8 source creates the transfer key with `Private::New`. Keyed
private lookup uses the receiver's own storage and skips interceptors. A proxy
therefore owns its private slot on the wrapper itself, including after
revocation. An ordinary nonextensible receiver can receive a new private slot.
The selected source operation creates a nonenumerable, writable and
configurable property. The exact original source packets are retained under
`authority/`; their hashes and original locations are recorded in the manifest.

## Native ownership

`JS_PiSetPrivateProperty(ctx, receiver, private_symbol, value)` borrows the
receiver and key and consumes the value on every path. It returns 1 after a
successful assignment or -1 with the actual pending exception on failure.
Only an actual object and a key created as a private symbol are admitted.
There is no guest key coercion.

The operation looks directly at the receiver's own shape. It updates an
existing writable data property with the VM's publish-before-retire operation,
uses the genuine own setter when present, and preserves the VM's existing
own-property readonly, variable-reference and autoinitialization handling.
A missing slot is added directly with configurable and writable flags.
This does not traverse the prototype, call proxy traps, alter the receiver's
public extensibility, or redirect storage to a proxy target.

The selected production caller enters through its existing guarded native
callable with no pre-existing pending exception. This unit does not introduce
a separate pending-entry preservation contract, a public key map, or
additional private Get/Has ABI.

## Controls and validation boundary

The install-only target `build-native-vm-private-property` compiles
`src/native_vm_private_property_test.zig` with the `VM private property`
filter. The installed Windows artifact is `native-vm-private-property.exe`.

Nine declared controls use actual QuickJS objects, symbols, property
descriptors, proxy wrappers, ordinary exceptions and native class finalizers.
They cover unique hidden keys, inherited setters and readonly prototypes,
frozen public objects, proxy storage and revocation, exact replacement
retirement, invalid argument consumption without coercion, readonly own
slots, own setter identity and actual allocation failure without publication.
The allocation control changes the runtime's real allocation limit and
observes the consumed sentinel's genuine native finalizer.

The source review record is in `manifest.json`. Native compilation, complete
metadata discovery and separately granted runtime execution remain pending.
This unit alone does not qualify FileHandle, the public SDK or the application.

## Integration

The original draft packets are preserved as observations. Main must intake
only the literal C and header additions recorded in `draft-delta.json`,
preserving the subsequently integrated ArrayBuffer backing implementation
and all other current VM changes. The build contribution is exactly the
six additive lines in `control-draft.json`; the old donor build file must
not replace Main's current graph.

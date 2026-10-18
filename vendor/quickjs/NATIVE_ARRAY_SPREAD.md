# Native array spread, constructor apply, and rest operands

These additive native entry points expose existing operations from the linked
QuickJS-NG interpreter. The VM algorithms remain unchanged.

The source baseline is quickjs.c SHA-256
BCDF923F343846EFDA4305EDA2C7C1D8F44908A27296D5C50A97506E06B2A8BC
and quickjs.h SHA-256
0DBC21D3205747FB9620CAEFEB1AE3FE8D2F78F1793157C06E2FA4F2F18CB556.
Removing only the three wrapper definitions and three header declarations
reproduces those baseline source bytes.

## Ownership and execution

- JS_PiArrayAppend(ctx, target, position, iterable) borrows both VM operands and
  invokes the actual js_append_enumerate operation used by OP_append. Its local
  three-value stack is borrowed; it does not duplicate or consume the operands.
  The non-null uint32 cursor uses the same INT-tagged bits as the opcode,
  including the existing unsigned wraparound. The operation preserves both
  Symbol.iterator lookups, the VM fast-array path, and the original abrupt
  IteratorClose policy. A negative result preserves partial target mutations
  and leaves the caller's cursor unchanged. A successful pending-free result
  commits the new cursor. Existing pending reasons prevent guest execution.

- JS_PiCallConstructorArray(ctx, constructor, new_target, argument_array)
  borrows all three operands and returns one owned outcome. The array is the
  completed internal argument operand. The bridge calls the unchanged
  js_function_apply constructor case used by OP_apply. Existing
  build_arg_list, JS_MAX_LOCAL_VARS, VM allocation, JS_CallConstructor2 and
  free_arg_list retain their actual order and behavior. No global Reflect,
  function wrapper, host argument buffer, or replacement argument cap is used.

- JS_PiCreateRestArray(ctx, count, argv) accepts a valid native invocation's
  nonnegative argument count and borrowed argument values. It invokes the
  actual js_create_array used by OP_rest and returns an owned array containing
  the VM's duplicates. It does not iterate argv or read the global Array
  constructor. JS_NewArrayFrom has a different, consuming ownership contract
  and is not used for this borrowed operand.

Append and constructor apply can run guest code. Native consumers must finish
them through their actual guest-operation and owned-completion boundaries.
The rest producer is a direct non-guest allocation and uses the caller's
existing raw-allocation provenance handling before any subsequent cleanup.
No broad allocation-generation inference is valid across append or apply.

## Controls and qualification

src/native_vm_array_append_test.zig contains fourteen authored controls.
They compare literal spread/rest/super operations in this linked C runtime;
exercise dense, sparse, Unicode and Set values; observe the double iterator
probe and next receiver; distinguish next acquisition from next/done/value
failures; and check first-reason IteratorClose, partial target mutation,
uint32 cursor bits, pending entry, ordinary private DATA, actual native fatal
events, and fatal iterator retirement before cursor publication.

Constructor controls exercise a real derived new.target with a changed rest
iterator, the VM's actual 65535 argument cap, constructor abrupt identity, and
argument-list retirement. Rest controls verify borrowed values survive until
the returned array retires and that mutable global Array/iterator properties
are not consulted, including the empty case.

build-native-vm-array-append installs this test artifact without executing it;
its filter is "VM array append". Source review and authored controls do not
establish compilation or runtime acceptance. This vendor delta requires fresh
qualification and must not reuse the closed BCDF diagnostic cache lineage.

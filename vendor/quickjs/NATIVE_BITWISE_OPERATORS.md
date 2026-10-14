# Native bitwise operator boundary

`JS_PiBinaryOperator` retains operations 0 through 9 unchanged. Operations
10 (and), 11 (or), 12 (left shift), and 13 (signed right shift) duplicate the
borrowed operands and invoke the same `js_binary_logic_slow` implementation
used by guest bytecode. The original VM handles Number and BigInt conversion,
mixed-type rejection, negative and oversized shifts, and exception identity.
No parser, bytecode, global numeric function, or public Promise behavior changes.

The native UUIDv7 implementation needs these operators to preserve upstream
observable BigInt and Number conversions. Its tests use caller-owned clock and
random dependencies and do not qualify the complete global Crypto host.

The binary operator regression exercises all fourteen operations against
guest-language expressions, including coercion order and mixed BigInt inputs.
The added UUID owner tests check retained state and allocation cleanup. Passing
those tests establishes their stated scope; it does not establish full Pi parity.

The explicit `JS_PiBigIntNode` host entry point uses original number-hint
primitive conversion and original BigInt construction. It supplies the observed
Node null/undefined TypeError messages without modifying the original global
BigInt or interpreter conversion function. The opt-in Zig host installer retains
the original static functions and prototype property descriptors. It is not
installed in inner VMs. Other V8 error-message differences remain separate work.

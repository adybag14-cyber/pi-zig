# Pinned Zig0.16 captured-errdefer return typing

The actual d9be compile progressed beyond its explicitly typed capture returns,
but reported bare dynamic errors from js.typeError, a caught allocator error,
and Socket function factories. The earlier annotation-only5372 negative remains
unchanged. This successor inventories the whole affected pattern, rather than
only the next source line reported for each function.

Primary authority: the pinned compiler's lib/std/zig/AstGen.zig SHA256
2B3ABDFF84C015C3760993F1693BA5C8F10A128D4FA83D6A850E682C4A3DFBBC.
Its return lowering at approximately8008-8112 gives literal return error.Foo a
separate error-value path. Runtime call/identifier operands are potentially
error-valued; with a capturing errdefer, the generated failure branch extracts
err_union_code from that operand before addRet. A bare error-set operand is not
an error union at that extraction point. The function's declared return type
alone did not materialize the required operand union in the actual5372 failure.

The affected modules now make every PRODUCTION dynamic error-set return in a
capturing-errdefer scope an explicit anyerror!actualPayload expression: five
Socket typeError branches and submitWrite's native failure, acquireInner's caught
allocator error, invoke's TypeError and createKind's four capture branches.
The existing12d9be capture coercions remain. Literal error returns already use
the dedicated compiler path; successful values and existing error-union calls
are unchanged. The two remaining bare dynamic-error forms in these files are
outside capturing-errdefer scopes: acquire's NativeInvocation catch and an
unselected test callback without errdefer. Shared capture/Scope/Engine are not
changed, nor are callback calls/order/cleanup/ownership or19actual assertions.

This is a source trace plus observed compiler diagnostics, not a new compiler
execution or general compiler qualification. Root's next exact-source compile
remains mandatory; more independently observed diagnostics may still exist.

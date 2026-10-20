//! Actual native V8 Global-equivalent cells selected for AliasedBuffer.
//! The VM owns the weak target link. These cells neither create public WeakRefs
//! nor keep a weak target alive merely because Get was called. Every cell must
//! be released on the owner thread before its actual JSRuntime is destroyed.
//! The concrete JSNativeGlobal C unit is a separately reviewed dependency.
const a = @import("native_node_argument_values.zig");
const c = a.c;
const Scope = a.Scope;

pub const Global = struct {
    cell: ?*c.JSNativeGlobal = null,

    /// Creation allocates the one stable cell and retains the real object.
    /// The original AliasedBuffer Global construction occurs at this point.
    pub fn create(s: *Scope, value: c.JSValue) !Global {
        const generation = try s.beforeAllocation();
        const raw = c.JS_PiNewNativeGlobal(s.engine.context, value);
        var result: Global = .{ .cell = raw };
        s.boundary.checkPendingSince(generation) catch |err| {
            // Attach before checking, so even an owned success accompanied by
            // actual pending cannot strand the native Global entitlement.
            result.release(s);
            return err;
        };
        if (raw == null) return error.OutOfMemory;
        return result;
    }
    pub fn makeWeak(self: *Global, s: *Scope) !void {
        try s.pending();
        const raw = self.cell orelse return error.ActualNativeGlobalRequired;
        // The weak link was reserved by create; this transition allocates no
        // new cell and publishes the weak state before the strong root drops.
        c.JS_PiNativeGlobalSetWeak(raw);
        try s.pending();
    }
    /// Scope-borrowed Local value. The empty cell produces actual undefined;
    /// it does not resurrect a collected view or enter JS kept-object state.
    pub fn get(self: *Global, s: *Scope) !c.JSValue {
        try s.pending();
        const raw = self.cell orelse return c.pi_js_undefined();
        return s.checked(c.JS_PiNativeGlobalGet(raw));
    }
    pub fn release(self: *Global, s: *Scope) void {
        const raw = self.cell orelse return;
        self.cell = null;
        // Canonical pending reduction also covers a strong target's real
        // finalizer. Detach the native ticket before either retirement path.
        var nothing = c.pi_js_undefined();
        s.boundary.release(&nothing);
        c.JS_PiFreeNativeGlobal(raw);
        s.boundary.release(&nothing);
    }
};

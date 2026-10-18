//! CJS-local owned completion. Captured diagnostics are DATA; actual pending
//! and independently retained Bfb invocation producers alone establish fatality.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
pub const Boundary = struct {
    engine: *v.em.Engine,
    generation: u64,
    previous: ?c.JSValue,
    reason: ?c.JSValue = null,
    fatal: bool = false,
    invocation: v.em.Engine.NativeInvocation = .{},
    finished: bool = false,
    pub fn begin(engine: *v.em.Engine) Boundary {
        const previous=engine.captured_exception;engine.captured_exception=null;
        engine.native_exception_diagnostics_suppressed+=1;
        // Returned INACTIVE by value. No pointer into this temporary escapes.
        return .{.engine=engine,.generation=engine.native_allocation_generation,.previous=previous};
    }
    pub fn start(self:*Boundary)void{
        if(!self.finished and !self.invocation.active)self.engine.enterNativeInvocation(&self.invocation);
    }
    pub fn checkCurrent(self:*Boundary)!void{
        self.start();_=self.engine.nativeCallbackResult(c.pi_js_undefined());
        if(c.JS_HasException(self.engine.context))return self.rejectOwned(c.pi_js_undefined());
    }
    fn select(self:*Boundary,value:c.JSValue,fatal:bool)void{
        if(self.reason)|previous|{
            if(!self.fatal and fatal){self.reason=value;self.fatal=true;var old=previous;self.release(&old);}
            else {var old=value;self.release(&old);}
        }else{self.reason=value;self.fatal=fatal;}
    }
    fn observe(self:*Boundary,boundary:?u64)void{
        self.start();
        // This surfaces the independently recorded actual producer. A newly
        // captured PromiseResult cannot publish into NativeInvocation.first.
        if(!self.fatal)_=self.engine.nativeCallbackResult(c.pi_js_undefined());
        while(c.JS_HasException(self.engine.context)){
            const value=c.JS_GetException(self.engine.context);
            if(boundary)|generation|{
                const tag=c.pi_js_native_allocation_error_generation(value);const distance=tag-%generation;
                if(tag!=0 and distance!=0 and distance<=self.engine.native_allocation_generation-%generation){
                    c.JS_SetUncatchableError(self.engine.context,value);
                    // Owned actual pending event, qualified against this
                    // operation/free snapshot; record it before any release.
                    _=self.engine.checked(c.JS_Throw(self.engine.context,c.JS_DupValue(self.engine.context,value))) catch {};
                }
            }
            self.select(value,c.JS_IsUncatchableError(value));
        }
    }
    /// Only an explicit escaping JS completion calls this. A diagnostic may
    /// supply an ordinary thrown value, but its flag/tag is never fatal proof.
    pub fn escaping(self:*Boundary)void{
        self.observe(self.generation);
        if(self.reason==null)if(self.engine.captured_exception)|value|{
            self.engine.captured_exception=null;self.reason=value;self.fatal=false;
        };
    }
    pub fn own(self:*Boundary,scope:*v.Scope,value:c.JSValue)!c.JSValue{
        self.start();
        _=self.engine.nativeCallbackResult(c.pi_js_undefined());
        if(c.JS_HasException(self.engine.context))return self.rejectOwned(value);
        if(scope.inline_count<scope.inline_values.len){scope.inline_values[scope.inline_count]=value;scope.inline_count+=1;return value;}
        scope.values.append(self.engine.gpa,value) catch |err|{var old=value;self.release(&old);return err;};return value;
    }
    pub fn release(self:*Boundary,slot:*c.JSValue)void{
        self.start();const value=slot.*;slot.*=c.pi_js_undefined();
        const diagnostic=self.engine.captured_exception;self.engine.captured_exception=null;
        self.observe(self.generation);
        const generation=self.engine.native_allocation_generation;
        self.engine.freeValue(value);
        self.observe(generation);
        if(diagnostic)|prior|{
            // Every captured-only value remains DATA, including a new capture
            // made by awaitValueOnly(alreadyRejectedFlaggedPromise) in a free.
            // Retire collisions without looking at their bit or private tag.
            while(self.engine.captured_exception)|next|{
                self.engine.captured_exception=null;var old=next;self.release(&old);
            }
            self.engine.captured_exception=prior;
        }
    }
    pub fn rejectOwned(self:*Boundary,value:c.JSValue)anyerror{var owned=value;self.release(&owned);return error.JavaScriptException;}
    fn failureRoots(self:*Boundary,values:[]c.JSValue)void{
        for(values)|*value|self.release(value);
        while(self.engine.captured_exception)|value|{self.engine.captured_exception=null;var old=value;self.release(&old);}
        if(self.previous)|value|{self.previous=null;var old=value;self.release(&old);}
    }
    /// Retire native ownership without popping/materializing the completion.
    /// Args owner rollback uses this SAME stable frame before finishRetired.
    pub fn retire(self:*Boundary,host_error:?anyerror,scope:*v.Scope,values:[]c.JSValue)void{
        self.start();self.observe(self.generation);
        if(host_error==error.JavaScriptException and self.reason==null)self.escaping();
        const count=scope.inline_count;scope.inline_count=0;for(scope.inline_values[0..count])|*value|self.release(value);
        const dynamic=scope.values.items;scope.values.items=dynamic[0..0];for(dynamic)|*value|self.release(value);
        const generation=self.engine.native_allocation_generation;scope.values.deinit(self.engine.gpa);self.observe(generation);
        if(host_error==error.OutOfMemory and !self.fatal){_=self.engine.throwNativeOutOfMemoryFatal();self.observe(null);}
        if(host_error!=null or self.reason!=null)self.failureRoots(values)
        else if(self.engine.captured_exception==null){self.engine.captured_exception=self.previous;self.previous=null;}
        else if(self.previous)|value|{self.previous=null;var old=value;self.release(&old);};
        if(host_error!=null or self.reason!=null)self.failureRoots(values);
    }
    pub fn failed(self:*Boundary,host_error:?anyerror)bool{self.observe(null);return host_error!=null or self.reason!=null;}
    pub fn finishRetired(self:*Boundary,host_error:?anyerror,values:[]c.JSValue)!void{
        defer self.engine.native_exception_diagnostics_suppressed-=1;
        self.observe(null);
        if(host_error!=null or self.reason!=null)self.failureRoots(values);
        // Pop at the caller-stable address before returning any completion.
        self.finished=true;
        const result=self.engine.leaveNativeInvocation(&self.invocation,c.pi_js_undefined());
        self.engine.freeValue(result); // Undefined/exception sentinel only.
        self.observe(null); // finished prevents relinking the dead frame.
        if(host_error!=null or self.reason!=null)self.failureRoots(values);
        if(self.reason)|value|{
            self.reason=null;
            if(self.fatal)c.JS_SetUncatchableError(self.engine.context,value)
            else c.JS_ClearUncatchableError(self.engine.context,value);
            _=self.engine.checked(c.JS_Throw(self.engine.context,value)) catch |err|return err;
            return error.ActualCommonJSBoundaryThrowDidNotFail;
        }
        if(host_error)|err|return err;
    }
    pub fn finishMany(self:*Boundary,host_error:?anyerror,scope:*v.Scope,values:[]c.JSValue)!void{self.retire(host_error,scope,values);return self.finishRetired(host_error,values);}
    pub fn finish(self:*Boundary,completion:anyerror!c.JSValue,scope:*v.Scope)!c.JSValue{
        var values=[_]c.JSValue{c.pi_js_undefined()};var host_error:?anyerror=null;
        if(completion)|value|values[0]=value else |err|host_error=err;
        try self.finishMany(host_error,scope,&values);return values[0];
    }
};

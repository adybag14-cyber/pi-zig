//! CJS-local owned completion. Captured diagnostics are DATA; actual pending
//! and independently retained Bfb invocation producers alone establish fatality.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
pub const Boundary = struct {
    engine: *v.em.Engine,
    previous: ?c.JSValue,
    reason: ?c.JSValue = null,
    reason_pending: bool = false,
    fatal: bool = false, // Cached generic classification; private events are dynamic.
    terminated: bool = false, // Historical actual private unwind; not reason classification.
    invocation: v.em.Engine.NativeInvocation = .{},
    finished: bool = false,
    pub fn begin(engine: *v.em.Engine) Boundary {
        const previous=engine.captured_exception;engine.captured_exception=null;
        engine.native_exception_diagnostics_suppressed+=1;
        // Returned INACTIVE by value. No pointer into this temporary escapes.
        return .{.engine=engine,.previous=previous,.terminated=engine.nativeTerminationObserved()};
    }
    fn observeHistory(self:*Boundary)void{
        self.terminated=self.terminated or self.invocation.terminated or self.engine.nativeTerminationObserved();
    }
    pub fn start(self:*Boundary)void{
        if(!self.finished and !self.invocation.active)self.engine.enterNativeInvocation(&self.invocation);
        self.observeHistory();
    }
    pub fn checkCurrent(self:*Boundary)!void{
        return self.checkPendingSince(null);
    }
    /// A snapshot belongs only to a proven non-guest allocation, never a JS
    /// getter/call/coercion or entire body. Evaluate operands BEFORE this point.
    pub fn beforeAllocation(self:*Boundary)!u64{
        try self.checkCurrent();return self.engine.native_allocation_generation;
    }
    pub fn checkPendingSince(self:*Boundary,generation:?u64)!void{
        self.start();_=self.engine.nativeCallbackResult(c.pi_js_undefined());
        if(c.JS_HasException(self.engine.context)){
            self.observe(generation);return self.completionError();
        }
        self.observeHistory();
        if(self.terminated)return error.ExecutionTerminated;
    }
    fn isTermination(self:*const Boundary)bool{
        return self.reason_pending and self.reason!=null and c.JS_PiIsExecutionTermination(self.reason.?);
    }
    pub fn isFatal(self:*const Boundary)bool{
        return self.fatal or (self.isTermination() and
            c.JS_PiNativePendingPriority(c.JS_GetRuntime(self.engine.context),self.reason.?)>0);
    }
    fn completionError(self:*const Boundary)anyerror{
        return if(self.terminated or self.isTermination()) error.ExecutionTerminated else error.JavaScriptException;
    }
    fn select(self:*Boundary,value:c.JSValue,fatal:bool)void{
        if(c.JS_PiIsExecutionTermination(value)){
            self.terminated=true;
            if(self.engine.native_fatal_invocation!=null and !self.engine.nativeTerminationObserved()){
                // Actual paired token only: observe active-owner history
                // before cleanup even when a generic first reason is cached.
                // Existing drain consumes this once; no request is polled.
                _=c.JS_PiThrowNativePending(self.engine.context,c.JS_DupValue(self.engine.context,value),fatal);
                self.engine.releaseNativeValue(c.pi_js_undefined());
            }
        }
        // Both fields come from one actual pending take. A primitive carries
        // no Error bit; captured diagnostics never enter this policy channel.
        if(self.reason)|previous|{
            const replace=if(self.reason_pending)
                c.JS_PiNativePendingReplaceClassified(c.JS_GetRuntime(self.engine.context),previous,self.fatal,value,fatal)
            else fatal or (c.JS_PiIsExecutionTermination(value) and
                c.JS_PiNativePendingPriority(c.JS_GetRuntime(self.engine.context),value)>0);
            if(replace){self.reason=value;self.reason_pending=true;self.fatal=fatal;var old=previous;self.release(&old);}
            else {var old=value;self.release(&old);}
        }else{self.reason=value;self.reason_pending=true;self.fatal=fatal;}
    }
    fn observe(self:*Boundary,boundary:?u64)void{
        self.start();
        // This surfaces the independently recorded actual producer. A newly
        // captured PromiseResult cannot publish into NativeInvocation.first.
        if(!self.isFatal()){
            if(self.finished)self.engine.releaseNativeValue(c.pi_js_undefined())
            else _=self.engine.nativeCallbackResult(c.pi_js_undefined());
        }
        self.observeHistory();
        while(c.JS_HasException(self.engine.context)){
            var fatal:bool=false;
            const value=c.JS_PiGetExceptionWithFatal(self.engine.context,&fatal);
            if(boundary)|generation|{
                const tag=c.pi_js_native_allocation_error_generation(value);const distance=tag-%generation;
                if(tag!=0 and distance!=0 and distance<=self.engine.native_allocation_generation-%generation){
                    c.JS_SetUncatchableError(self.engine.context,value);fatal=true;
                    // Owned actual pending event, qualified against this
                    // operation/free snapshot; record it before any release.
                    _=self.engine.checked(c.JS_PiThrowNativePending(self.engine.context,c.JS_DupValue(self.engine.context,value),true)) catch {};
                }
            }
            self.select(value,fatal);
            self.observeHistory();
        }
    }
    /// Only an explicit escaping JS completion calls this. A diagnostic may
    /// supply an ordinary thrown value, but its flag/tag is never fatal proof.
    pub fn escaping(self:*Boundary)void{
        self.observe(null);
        if(self.reason==null)if(self.engine.captured_exception)|value|{
            self.engine.captured_exception=null;self.reason=value;self.reason_pending=false;self.fatal=false;
        };
    }
    pub fn own(self:*Boundary,scope:*v.Scope,value:c.JSValue)!c.JSValue{
        self.start();
        _=self.engine.nativeCallbackResult(c.pi_js_undefined());
        self.observeHistory();
        if(self.terminated or c.JS_HasException(self.engine.context))return self.rejectOwned(value);
        if(scope.inline_count<scope.inline_values.len){scope.inline_values[scope.inline_count]=value;scope.inline_count+=1;return value;}
        scope.values.append(self.engine.gpa,value) catch |err|{
            // This allocator failure precedes incoming-root retirement. Publish
            // its real event before a sole carrier can run a later finalizer.
            if(err==error.OutOfMemory){_=self.engine.throwNativeOutOfMemoryFatal();self.observe(null);}
            var old=value;self.release(&old);return err;
        };return value;
    }
    pub fn release(self:*Boundary,slot:*c.JSValue)void{
        self.start();const value=slot.*;slot.*=c.pi_js_undefined();
        const diagnostic=self.engine.captured_exception;self.engine.captured_exception=null;
        self.observe(null);
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
    pub fn rejectOwned(self:*Boundary,value:c.JSValue)anyerror{var owned=value;self.release(&owned);return self.completionError();}
    fn failureRoots(self:*Boundary,values:[]c.JSValue)void{
        for(values)|*value|self.release(value);
        while(self.engine.captured_exception)|value|{self.engine.captured_exception=null;var old=value;self.release(&old);}
        if(self.previous)|value|{self.previous=null;var old=value;self.release(&old);}
    }
    /// Retire native ownership without popping/materializing the completion.
    /// Args owner rollback uses this SAME stable frame before finishRetired.
    pub fn retire(self:*Boundary,host_error:?anyerror,scope:*v.Scope,values:[]c.JSValue)void{
        self.start();self.observe(null);
        if(host_error) |err| { if(err==error.ExecutionTerminated)self.terminated=true; }
        if(host_error) |err| { if(err==error.JavaScriptException and self.reason==null)self.escaping(); }
        // A trusted direct host allocation failure precedes root retirement.
        if(host_error) |err| { if(err==error.OutOfMemory and !self.isFatal()){_=self.engine.throwNativeOutOfMemoryFatal();self.observe(null);} }
        const count=scope.inline_count;scope.inline_count=0;for(scope.inline_values[0..count])|*value|self.release(value);
        const dynamic=scope.values.items;scope.values.items=dynamic[0..0];for(dynamic)|*value|self.release(value);
        const generation=self.engine.native_allocation_generation;scope.values.deinit(self.engine.gpa);self.observe(generation);
        if(host_error!=null or self.reason!=null or self.terminated)self.failureRoots(values)
        else if(self.engine.captured_exception==null){self.engine.captured_exception=self.previous;self.previous=null;}
        else if(self.previous)|value|{self.previous=null;var old=value;self.release(&old);}
        if(host_error!=null or self.reason!=null or self.terminated)self.failureRoots(values);
    }
    pub fn failed(self:*Boundary,host_error:?anyerror)bool{self.observe(null);return host_error!=null or self.reason!=null or self.terminated;}
    fn finishRetiredOwned(self:*Boundary,host_error:?anyerror,values:[]c.JSValue,comptime callback:bool)!?c.JSValue{
        defer self.engine.native_exception_diagnostics_suppressed-=1;
        self.observe(null);
        if(host_error!=null or self.reason!=null or self.terminated)self.failureRoots(values);
        // Pop at the caller-stable address before returning any completion.
        self.finished=true;
        const leave_result=self.engine.leaveNativeInvocation(&self.invocation,c.pi_js_undefined());
        self.engine.freeValue(leave_result); // Undefined/exception sentinel only.
        self.observe(null); // finished prevents relinking the dead frame.
        if(host_error!=null or self.reason!=null or self.terminated)self.failureRoots(values);
        if(self.reason)|value|{
            const termination=self.isTermination();
            const actual_pending=self.reason_pending;
            const fatal=self.fatal;
            self.reason=null;self.reason_pending=false;self.fatal=false;
            if(actual_pending and !termination and fatal)
                c.JS_SetUncatchableError(self.engine.context,value);
            const result=if(actual_pending)
                c.JS_PiThrowNativePending(self.engine.context,value,fatal)
            else c.JS_PiThrowExceptionData(self.engine.context,value);
            // A terminal C callback publishes the genuine owned event after
            // pop. Host checked completion intentionally converts it to DATA.
            if(self.terminated)return error.ExecutionTerminated;
            if(callback)return result;
            _=self.engine.checked(result) catch |err|return err;
            return error.ActualCommonJSBoundaryThrowDidNotFail;
        }
        if(self.terminated)return error.ExecutionTerminated;
        if(host_error)|err|return err;
        return null;
    }
    pub fn finishRetired(self:*Boundary,host_error:?anyerror,values:[]c.JSValue)!void{
        _=try self.finishRetiredOwned(host_error,values,false);
    }
    pub fn finishMany(self:*Boundary,host_error:?anyerror,scope:*v.Scope,values:[]c.JSValue)!void{self.retire(host_error,scope,values);return self.finishRetired(host_error,values);}
    /// Host propagation of an actual pending event. Unlike diagnostic finish,
    /// this never checked-captures the selected tuple after the final pop.
    /// Historical private unwind forbids subsequent source settlement even
    /// when cancellation lets an ordinary cleanup event win selection.
    pub fn finishRetiredPending(self:*Boundary,host_error:?anyerror,values:[]c.JSValue)!void{
        const host_terminated=if(host_error)|err|err==error.ExecutionTerminated else false;
        const result=self.finishRetiredOwned(host_error,values,true) catch |err| {
            if(self.terminated or host_terminated)return error.ExecutionTerminated;
            return err;
        };
        if(self.terminated or host_terminated)return error.ExecutionTerminated;
        if(result!=null)return error.JavaScriptException;
    }
    pub fn finishManyPending(self:*Boundary,host_error:?anyerror,scope:*v.Scope,values:[]c.JSValue)!void{
        self.retire(host_error,scope,values);
        return self.finishRetiredPending(host_error,values);
    }
    pub fn finish(self:*Boundary,completion:anyerror!c.JSValue,scope:*v.Scope)!c.JSValue{
        var values=[_]c.JSValue{c.pi_js_undefined()};var host_error:?anyerror=null;
        if(completion)|value|values[0]=value else |err|host_error=err;
        try self.finishMany(host_error,scope,&values);return values[0];
    }
    /// Use only at the real C callback return, never for a host checked value.
    /// All temporary roots retire and the invocation pops before publication.
    pub fn finishCallback(self:*Boundary,completion:anyerror!c.JSValue,scope:*v.Scope)!c.JSValue{
        var values=[_]c.JSValue{c.pi_js_undefined()};var host_error:?anyerror=null;
        if(completion)|value|values[0]=value else |err|host_error=err;
        self.retire(host_error,scope,&values);
        if(try self.finishRetiredOwned(host_error,&values,true))|result|return result;
        return values[0];
    }
};

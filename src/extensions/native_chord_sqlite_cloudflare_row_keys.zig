//! Source for-in row keys, with leaf-local pending checks and trusted budget.
//! Uses the existing source-for-in snapshot/live-presence policy; it does not
//! substitute Object.keys, omit inherited columns, or enumerate symbols.
const std=@import("std");
const h=@import("native_chord_sqlite_cloudflare_values.zig");
const c=h.c;
pub const Iterator=struct{
    engine:*h.v.em.Engine,source:c.JSValue,seen:std.AutoHashMapUnmanaged(c.JSAtom,void)=.empty,keys:std.ArrayList(c.JSAtom)=.empty,position:usize=0,steps:usize=0,
    pub fn init(engine:*h.v.em.Engine,input:c.JSValue)!Iterator{
        var self:Iterator=.{.engine=engine,.source=c.pi_js_undefined()};errdefer self.deinit();if(c.JS_IsNull(input)or c.JS_IsUndefined(input))return self;
        self.source=try h.current(engine,try engine.checked(c.JS_ToObject(engine.context,input)));var current=c.JS_DupValue(engine.context,self.source);defer engine.freeValue(current);
        while(!c.JS_IsNull(current)){
            try self.tick();var names:[*c]c.JSPropertyEnum=null;var count:u32=0;const proxy=c.JS_IsProxy(current);
            if(c.JS_GetOwnPropertyNames(engine.context,&names,&count,current,c.JS_GPN_STRING_MASK|(if(proxy)@as(c_int,0)else c.JS_GPN_SET_ENUM))<0)return h.v.js.capture(engine);defer c.JS_FreePropertyEnum(engine.context,names,count);try h.pending(engine);
            for(names[0..count])|entry|{
                try self.tick();const atom=c.JS_DupAtom(engine.context,entry.atom);const slot=self.seen.getOrPut(engine.gpa,atom) catch|err|{c.JS_FreeAtom(engine.context,atom);return err;};
                if(slot.found_existing)c.JS_FreeAtom(engine.context,atom)else if(proxy or entry.is_enumerable)try self.keys.append(engine.gpa,atom);
            }
            const parent=try h.current(engine,try engine.checked(c.JS_GetPrototype(engine.context,current)));engine.freeValue(current);current=parent;
        }
        return self;
    }
    pub fn deinit(self:*Iterator)void{
        var atoms=self.seen.keyIterator();while(atoms.next())|atom|c.JS_FreeAtom(self.engine.context,atom.*);self.keys.deinit(self.engine.gpa);self.seen.deinit(self.engine.gpa);self.engine.freeValue(self.source);
    }
    pub fn next(self:*Iterator)!?c.JSValue{
        try self.tick();while(self.position<self.keys.items.len){const atom=self.keys.items[self.position];self.position+=1;if(try self.present(atom))return try h.current(self.engine,try self.engine.checked(c.JS_AtomToValue(self.engine.context,atom)));}return null;
    }
    fn present(self:*Iterator,atom:c.JSAtom)!bool{
        var proxy=false;var current=c.JS_DupValue(self.engine.context,self.source);defer self.engine.freeValue(current);
        while(!c.JS_IsNull(current)){
            try self.tick();if(c.JS_IsProxy(current))proxy=true;var descriptor:c.JSPropertyDescriptor=undefined;const found=c.JS_GetOwnProperty(self.engine.context,&descriptor,current,atom);if(found<0)return h.v.js.capture(self.engine);
            if(found!=0){defer self.engine.freeValue(descriptor.value);defer self.engine.freeValue(descriptor.getter);defer self.engine.freeValue(descriptor.setter);try h.pending(self.engine);return !proxy or descriptor.flags&c.JS_PROP_ENUMERABLE!=0;}
            try h.pending(self.engine);const parent=try h.current(self.engine,try self.engine.checked(c.JS_GetPrototype(self.engine.context,current)));self.engine.freeValue(current);current=parent;
        }
        return false;
    }
    fn tick(self:*Iterator)!void{self.steps+|=1;try @import("native_jiti_budget.zig").check(self.engine,self.steps);}
};

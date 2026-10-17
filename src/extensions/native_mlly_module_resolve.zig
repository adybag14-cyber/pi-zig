//! Actual import-meta-resolve4.2.0 moduleResolve/package lookup and physical
//! finalization. This is the bundled clone, not a Node24 resolver alias.
const m = @import("native_mlly_values.zig");
const e = @import("native_mlly_errors.zig");
const reader = @import("native_mlly_package_reader.zig");
const targets = @import("native_mlly_package_targets.zig");
const c = m.c;
const Scope = m.Scope;
const Policy = targets.Policy(Resolver);
fn yes(s:*Scope,value:c.JSValue,method:[*:0]const u8,arg:c.JSValue) !bool { return s.truthy(try s.invoke(value,method,&.{arg})); }
fn slice(s:*Scope,value:c.JSValue,start:i64,end:?i64) !c.JSValue { return s.invoke(value,"slice",if(end)|last|&.{m.integer(s,start),m.integer(s,last)} else &.{m.integer(s,start)}); }
fn character(s:*Scope,value:c.JSValue,index:i64,text:[]const u8) !bool { return m.equal(s,try m.at(s,value,m.integer(s,index)),text); }
fn ownStringDescriptor(s:*Scope,target:c.JSValue,name:[]const u8,source:c.JSValue) !void {
    const object=try s.global("Object"); const define=try s.get(object,"defineProperty"); const descriptor=try s.object();
    const value=try s.call(try s.global("String"),c.pi_js_undefined(),&.{source});
    try m.define(s,descriptor,"value",value); _=try s.call(define,object,&.{target,try s.text(name),descriptor});
}
pub const Resolver=struct {
    context:m.Context,
    steps:usize=0,
    pub fn moduleResolve(self:*Resolver,s:*Scope,specifier:c.JSValue,base:c.JSValue,conditions_input:c.JSValue,preserve_symlinks:bool) anyerror!c.JSValue {
        const generation=s.engine.native_allocation_generation;
        return self.moduleBody(s,specifier,base,conditions_input,preserve_symlinks) catch |err| return m.exact(s.engine,err,generation);
    }
    fn moduleBody(self:*Resolver,s:*Scope,specifier:c.JSValue,base:c.JSValue,conditions_input:c.JSValue,preserve:bool) anyerror!c.JSValue {
        try m.budget(s.engine,&self.steps);
        const conditions=if(c.JS_IsUndefined(conditions_input))try self.context.get(s,"defaultConditions") else conditions_input;
        const protocol=try s.get(base,"protocol");
        const remote=try m.equal(s,protocol,"data:") or try m.equal(s,protocol,"http:") or try m.equal(s,protocol,"https:");
        const generation=s.engine.native_allocation_generation;
        const resolved=if(try relative(s,specifier)) self.context.url(s,specifier,base) catch |err| {
            const cause=try m.caught(s,err,generation);
            const failure=try e.create(self.context,s,.ERR_UNSUPPORTED_RESOLVE_REQUEST,&.{specifier,base}); try s.set(failure,"cause",cause);
            return m.throwReason(s.engine,failure);
        } else if(try m.equal(s,protocol,"file:") and try character(s,specifier,0,"#")) try self.importsResolve(s,specifier,base,conditions) else self.context.url(s,specifier,null) catch |err| blk: {
            const cause=try m.caught(s,err,generation);
            if(remote and !try yes(s,try self.context.get(s,"builtinModules"),"includes",specifier)) {
                const failure=try e.create(self.context,s,.ERR_UNSUPPORTED_RESOLVE_REQUEST,&.{specifier,base}); try s.set(failure,"cause",cause);
                return m.throwReason(s.engine,failure);
            }
            break :blk try self.packageResolve(s,specifier,base,conditions);
        };
        if(!try m.equal(s,try s.get(resolved,"protocol"),"file:"))return resolved;
        return self.finalize(s,resolved,base,preserve);
    }
    pub fn tryStat(self:*Resolver,s:*Scope,path:c.JSValue) anyerror!c.JSValue {
        const generation=s.engine.native_allocation_generation;
        return s.call(try self.context.get(s,"statSync"),c.pi_js_undefined(),&.{path}) catch |err| {
            _=try m.caught(s,err,generation); return c.pi_js_undefined();
        };
    }
    pub fn finalize(self:*Resolver,s:*Scope,input:c.JSValue,base:c.JSValue,preserve:bool) anyerror!c.JSValue {
        const generation=s.engine.native_allocation_generation;
        return self.finalizeBody(s,input,base,preserve) catch |err| return m.exact(s.engine,err,generation);
    }
    fn finalizeBody(self:*Resolver,s:*Scope,input:c.JSValue,base:c.JSValue,preserve:bool) anyerror!c.JSValue {
        const context=self.context; var resolved=input;
        const separator_regex=try context.get(s,"encodedSeparator"); const separator_exec=try s.get(separator_regex,"exec");
        if(!c.JS_IsNull(try s.call(separator_exec,separator_regex,&.{try s.get(resolved,"pathname")}))) {
            const failure=try e.create(context,s,.ERR_INVALID_MODULE_SPECIFIER,&.{try s.get(resolved,"pathname"),try s.text("must not include encoded \"/\" or \"\\\" characters"),try context.file(s,base)});
            return m.throwReason(s.engine,failure);
        }
        const generation=s.engine.native_allocation_generation;
        const file_path=context.file(s,resolved) catch |err| {
            const cause=try m.caught(s,err,generation);
            try ownStringDescriptor(s,cause,"input",resolved);
            try ownStringDescriptor(s,cause,"module",base);
            return m.throwReason(s.engine,cause);
        };
        // Preserve the clone's actual slice(-1), including its trailing-slash
        // behavior. This is not a spelling correction of the upstream algorithm.
        const stats=try self.tryStat(s,if(try yes(s,file_path,"endsWith",try s.text("/")))try slice(s,file_path,-1,null) else file_path);
        if(s.truthy(stats) and s.truthy(try s.invoke(stats,"isDirectory",&.{}))) {
            const failure=try e.create(context,s,.ERR_UNSUPPORTED_DIR_IMPORT,&.{file_path,try context.file(s,base)});
            try s.set(failure,"url",try s.call(try s.global("String"),c.pi_js_undefined(),&.{resolved})); return m.throwReason(s.engine,failure);
        }
        if(!s.truthy(stats) or !s.truthy(try s.invoke(stats,"isFile",&.{}))) {
            const failure=try e.create(context,s,.ERR_MODULE_NOT_FOUND,&.{if(s.truthy(file_path))file_path else try s.get(resolved,"pathname"),if(s.truthy(base))try context.file(s,base) else base,c.pi_js_bool(s.engine.context, 1)});
            try s.set(failure,"url",try s.call(try s.global("String"),c.pi_js_undefined(),&.{resolved})); return m.throwReason(s.engine,failure);
        }
        if(!preserve) {
            const real=try s.call(try context.get(s,"realpathSync"),c.pi_js_undefined(),&.{file_path});
            const search=try s.get(resolved,"search"); const hash=try s.get(resolved,"hash");
            const separator=try s.get(try context.get(s,"path"),"sep");
            resolved=try context.fileURL(s,try s.concat(real,try s.text(if(try yes(s,file_path,"endsWith",separator))"/" else "")));
            try s.set(resolved,"search",search); try s.set(resolved,"hash",hash);
        }
        return resolved;
    }
    pub fn importsResolve(self:*Resolver,s:*Scope,name:c.JSValue,base:c.JSValue,conditions:c.JSValue) anyerror!c.JSValue {
        const generation=s.engine.native_allocation_generation;
        return self.importsBody(s,name,base,conditions) catch |err| return m.exact(s.engine,err,generation);
    }
    fn importsBody(self:*Resolver,s:*Scope,name:c.JSValue,base:c.JSValue,conditions:c.JSValue) anyerror!c.JSValue {
        const context=self.context;
        if(try m.equal(s,name,"#") or try yes(s,name,"startsWith",try s.text("#/")) or try yes(s,name,"endsWith",try s.text("/"))) {
            return m.throwReason(s.engine,try e.create(context,s,.ERR_INVALID_MODULE_SPECIFIER,&.{name,try s.text("is not a valid internal imports specifier name"),try context.file(s,base)}));
        }
        var package_url=c.pi_js_undefined();
        const config=try reader.getPackageScopeConfig(context,s,base);
        if(s.truthy(try s.get(config,"exists"))) {
            package_url=try context.fileURL(s,try s.get(config,"pjsonPath")); const imports=try s.get(config,"imports");
            if(s.truthy(imports)) {
                if(try context.own(s,imports,name) and !try yes(s,name,"includes",try s.text("*"))) {
                    const value=try Policy.target(self,s,.{.package_url=package_url,.target=try m.at(s,imports,name),.subpath=try s.text(""),.match=name,.base=base,.conditions=conditions,.internal=true});
                    if(!m.v.nullish(value))return value;
                } else {
                    const best=try Policy.bestMatch(self,s,imports,name,true,package_url,base);
                    if(s.truthy(best.key)) {
                        const value=try Policy.target(self,s,.{.package_url=package_url,.target=try m.at(s,imports,best.key),.subpath=best.subpath,.match=best.key,.base=base,.conditions=conditions,.pattern=true,.internal=true});
                        if(!m.v.nullish(value))return value;
                    }
                }
            }
        }
        const package_path=if(s.truthy(package_url))try context.file(s,try context.url(s,try s.text("."),package_url)) else package_url;
        return m.throwReason(s.engine,try e.create(context,s,.ERR_PACKAGE_IMPORT_NOT_DEFINED,&.{name,package_path,try context.file(s,base)}));
    }
    pub fn packageResolve(self:*Resolver,s:*Scope,specifier:c.JSValue,base:c.JSValue,conditions:c.JSValue) anyerror!c.JSValue {
        const generation=s.engine.native_allocation_generation;
        return self.packageBody(s,specifier,base,conditions) catch |err| return m.exact(s.engine,err,generation);
    }
    fn packageBody(self:*Resolver,s:*Scope,specifier:c.JSValue,base:c.JSValue,conditions:c.JSValue) anyerror!c.JSValue {
        const context=self.context; try m.budget(s.engine,&self.steps);
        if(try yes(s,try context.get(s,"builtinModules"),"includes",specifier)) {
            const constructor=try s.global("URL"); return context.constructURL(s,constructor,&.{try s.concat(try s.text("node:"),specifier)});
        }
        var separator=try s.invoke(specifier,"indexOf",&.{try s.text("/")}); var valid=true; var scoped=false;
        if(try character(s,specifier,0,"@")) {
            scoped=true;
            if(s.equal(separator,m.integer(s,-1)) or s.equal(try s.get(specifier,"length"),m.integer(s,0)))valid=false else {
                const next_index=try s.get(specifier,"indexOf"); separator=try s.call(next_index,specifier,&.{try s.text("/"),try m.binary(s,0,separator,m.integer(s,1))});
            }
        }
        const package_name=if(s.equal(separator,m.integer(s,-1)))specifier else try s.invoke(specifier,"slice",&.{m.integer(s,0),separator});
        if(try context.regexExec(s,"invalidPackageName",package_name))valid=false;
        if(!valid)return m.throwReason(s.engine,try e.create(context,s,.ERR_INVALID_MODULE_SPECIFIER,&.{specifier,try s.text("is not a valid package name"),try context.file(s,base)}));
        const subpath=try s.concat(try s.text("."),if(s.equal(separator,m.integer(s,-1)))try s.text("") else try s.invoke(specifier,"slice",&.{separator}));
        const config=try reader.getPackageScopeConfig(context,s,base);
        if(s.truthy(try s.get(config,"exists"))) {
            const package_url=try context.fileURL(s,try s.get(config,"pjsonPath"));
            if(s.equal(try s.get(config,"name"),package_name) and !c.JS_IsUndefined(try s.get(config,"exports")) and !c.JS_IsNull(try s.get(config,"exports")))return Policy.exportsResolve(self,s,package_url,subpath,config,base,conditions);
        }
        const constructor=try s.global("URL");
        var package_url=c.JS_DupValue(s.engine.context,try context.constructURL(s,constructor,&.{try e.template(s,&.{try s.text("./node_modules/"),package_name,try s.text("/package.json")}),base})); defer s.engine.freeValue(package_url);
        var package_path=c.JS_DupValue(s.engine.context,try context.file(s,package_url)); defer s.engine.freeValue(package_path);
        while(true) {
            try m.budget(s.engine,&self.steps);
            var step:Scope=.{.engine=s.engine}; defer step.deinit();
            const stats=try self.tryStat(&step,try slice(&step,package_path,0,-13));
            if(!step.truthy(stats) or !step.truthy(try step.invoke(stats,"isDirectory",&.{}))) {
                const url_constructor=try step.global("URL");
                const next_url=try context.constructURL(&step,url_constructor,&.{try e.template(&step,&.{try step.text(if(scoped)"../../../../node_modules/" else "../../../node_modules/"),package_name,try step.text("/package.json")}),package_url});
                const next_path=try context.file(&step,next_url);
                const same=step.equal(try step.get(next_path,"length"),try step.get(package_path,"length"));
                const previous_url=package_url; const previous_path=package_path;
                package_url=c.JS_DupValue(s.engine.context,next_url); package_path=c.JS_DupValue(s.engine.context,next_path);
                s.engine.freeValue(previous_url); s.engine.freeValue(previous_path);
                if(same)break; continue;
            }
            const found=try reader.read(context,&step,package_path,base,specifier);
            const result=if(!c.JS_IsUndefined(try step.get(found,"exports")) and !c.JS_IsNull(try step.get(found,"exports")))try Policy.exportsResolve(self,&step,package_url,subpath,found,base,conditions) else if(try m.equal(&step,subpath,"."))try self.legacyMain(&step,package_url,found,base) else try context.url(&step,subpath,package_url);
            return s.own(c.JS_DupValue(s.engine.context,result));
        }
        return m.throwReason(s.engine,try e.create(context,s,.ERR_MODULE_NOT_FOUND,&.{package_name,try context.file(s,base),c.pi_js_bool(s.engine.context, 0)}));
    }
    fn fileExists(self:*Resolver,s:*Scope,url:c.JSValue) !bool {
        const function=try self.context.get(s,"statSync"); const options=try s.object(); try m.define(s,options,"throwIfNoEntry",c.pi_js_bool(s.engine.context, 0));
        const stats=try s.call(function,c.pi_js_undefined(),&.{url,options});
        const is_file=if(s.truthy(stats))try s.invoke(stats,"isFile",&.{}) else c.pi_js_undefined(); return if(m.v.nullish(is_file))false else s.truthy(is_file);
    }
    fn legacyMain(self:*Resolver,s:*Scope,package_url:c.JSValue,config:c.JSValue,base:c.JSValue) anyerror!c.JSValue {
        if(!c.JS_IsUndefined(try s.get(config,"main"))) {
            const constructor=try s.global("URL"); const direct=try self.context.constructURL(s,constructor,&.{try s.get(config,"main"),package_url});
            if(try self.fileExists(s,direct))return direct;
            const tries=try m.array(s,&.{
                try e.template(s,&.{try s.text("./"),try s.get(config,"main"),try s.text(".js")}),try e.template(s,&.{try s.text("./"),try s.get(config,"main"),try s.text(".json")}),try e.template(s,&.{try s.text("./"),try s.get(config,"main"),try s.text(".node")}),
                try e.template(s,&.{try s.text("./"),try s.get(config,"main"),try s.text("/index.js")}),try e.template(s,&.{try s.text("./"),try s.get(config,"main"),try s.text("/index.json")}),try e.template(s,&.{try s.text("./"),try s.get(config,"main"),try s.text("/index.node")})});
            if(try self.legacyTries(s,tries,package_url))|guess| {try self.emitLegacy(s,guess,package_url,base,try s.get(config,"main"));return guess;}
        }
        const tries=try m.array(s,&.{try s.text("./index.js"),try s.text("./index.json"),try s.text("./index.node")});
        if(try self.legacyTries(s,tries,package_url))|guess| {try self.emitLegacy(s,guess,package_url,base,try s.get(config,"main"));return guess;}
        const path=try self.context.file(s,try self.context.url(s,try s.text("."),package_url));
        return m.throwReason(s.engine,try e.create(self.context,s,.ERR_MODULE_NOT_FOUND,&.{path,try self.context.file(s,base)}));
    }
    fn legacyTries(self:*Resolver,s:*Scope,tries:c.JSValue,package_url:c.JSValue) anyerror!?c.JSValue {
        var i:i64=0;
        while(s.truthy(try m.binary(s,4,m.integer(s,i),try s.get(tries,"length")))) : (i+=1) {
            try m.budget(s.engine,&self.steps); var step:Scope=.{.engine=s.engine}; defer step.deinit();
            const constructor=try step.global("URL"); const guess=try self.context.constructURL(&step,constructor,&.{try m.at(&step,tries,m.integer(&step,i)),package_url});
            if(try self.fileExists(&step,guess))return try s.own(c.JS_DupValue(s.engine.context,guess));
        }
        return null;
    }
    fn emitLegacy(self:*Resolver,s:*Scope,url:c.JSValue,package_url:c.JSValue,base:c.JSValue,main:c.JSValue) anyerror!void {
        const context=self.context; const process=try context.get(s,"process"); if(s.truthy(try s.get(process,"noDeprecation")))return;
        // The Source constructs this context before format dispatch.
        const format_context=try s.object();try m.define(s,format_context,"parentURL",try s.get(base,"href"));
        const format=try @import("native_mlly_format.zig").defaultGetFormatWithoutErrors(context,s,url,format_context);
        if(!try m.equal(s,format,"module"))return;
        const url_path=try context.file(s,try s.get(url,"href")); const package_path=try context.file(s,try context.url(s,try s.text("."),package_url)); const base_path=try context.file(s,base);
        if(!s.truthy(main)) {
            const emit=try s.get(process,"emitWarning");
            const text=try e.template(s,&.{try s.text("No \"main\" or \"exports\" field defined in the package.json for "),package_path,try s.text(" resolving the main entry point \""),try s.invoke(url_path,"slice",&.{try s.get(package_path,"length")}),try s.text("\", imported from "),base_path,try s.text(".\nDefault \"index\" lookups for the main are deprecated for ES modules.")});
            _=try s.call(emit,process,&.{text,try s.text("DeprecationWarning"),try s.text("DEP0151")});
        } else if(!s.equal(try s.invoke(try context.get(s,"path"),"resolve",&.{package_path,main}),url_path)) {
            const emit=try s.get(process,"emitWarning");
            const text=try e.template(s,&.{try s.text("Package "),package_path,try s.text(" has a \"main\" field set to \""),main,try s.text("\", excluding the full filename and extension to the resolved file at \""),try s.invoke(url_path,"slice",&.{try s.get(package_path,"length")}),try s.text("\", imported from "),base_path,try s.text(".\n Automatic extension resolution of the \"main\" field is deprecated for ES modules.")});
            _=try s.call(emit,process,&.{text,try s.text("DeprecationWarning"),try s.text("DEP0151")});
        }
    }
};
fn relative(s:*Scope,specifier:c.JSValue) !bool {
    if(try m.equal(s,specifier,""))return false; if(try character(s,specifier,0,"/"))return true;
    if(try character(s,specifier,0,".")) {
        if(s.equal(try s.get(specifier,"length"),m.integer(s,1)) or try character(s,specifier,1,"/"))return true;
        if(try character(s,specifier,1,".") and (s.equal(try s.get(specifier,"length"),m.integer(s,2)) or try character(s,specifier,2,"/")))return true;
    }
    return false;
}

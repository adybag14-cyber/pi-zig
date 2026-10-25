import json, hashlib, re, difflib, subprocess
from pathlib import Path
base=Path(r"C:\Users\adyba\pi-zig\worktrees\sdk-owners-resume-20261018\verification\sdk-model-scope-warning-sourceonly-20261025")
main=Path(r"C:\Users\adyba\pi-zig\main")
old=base.with_name("sdk-model-scope-warning-sourceonly-20261024")
up=Path(r"C:\Users\adyba\pi-zig\upstream\snapshots\4954d76-20261015\packages\coding-agent\src\core\model-resolver.ts")
head=subprocess.check_output(["git","rev-parse","HEAD"],cwd=main,text=True).strip()
assert head=="c248553d15282e1e8ad896382c78132b6a501dd9",head
def read(p): return p.read_bytes()
def write(relative,data):
    p=base/relative;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data);return p
def pin(p):
    b=read(p);return {"path":str(p),"bytes":len(b),"sha256":hashlib.sha256(b).hexdigest().upper()}
authority=read(old/"authority/resolve-model-scope-original.ts")
assert authority.decode("utf-8") in up.read_text(encoding="utf-8")
write("authority/resolve-model-scope-original.ts",authority)
sig=b"export async function resolveModelScope(\n\tpatterns: string[],\n\tmodelRuntime: ModelRuntime,\n\toptions?: AuthOperationOptions,\n): Promise<ScopedModel[]> {"
assert authority.count(sig)==1
erased=authority.replace(sig,b"async function resolveModelScope(patterns, modelRuntime, options) {",1)
fixture=b'(function(resolveModelScopeWithDiagnostics, chalk) {\n"use strict";\n'+erased+b"return resolveModelScope;\n})\n"
write("projected/src/extensions/fixtures/sdk-model-scope-warning-4954-source.mjs",fixture)
old_c=read(main/"vendor/quickjs/quickjs.c")
old_h=read(main/"vendor/quickjs/quickjs.h")
marker=b"/* construct a reference to a global variable */"
assert old_c.count(marker)==1
c_add=b"""/* Native source bodies use the same lexical/TDZ/global identifier lookup
   as the interpreter's OP_get_var, without compiling an eval shim. */
JSValue JS_PiGetGlobalBinding(JSContext *ctx, JSAtom prop)
{
    return JS_GetGlobalVar(ctx, prop, true);
}

"""
assert b"JS_PiGetGlobalBinding" not in old_c+old_h
new_c=old_c.replace(marker,c_add+marker,1)
h_anchor=b"JS_EXTERN JSValue JS_GetGlobalObject(JSContext *ctx);"
assert old_h.count(h_anchor)==1
h_add=b"\n/* Exact OP_get_var lookup for native source bodies; prop remains borrowed. */\nJS_EXTERN JSValue JS_PiGetGlobalBinding(JSContext *ctx, JSAtom prop);"
new_h=old_h.replace(h_anchor,h_anchor+h_add,1)
write("projected/vendor/quickjs/quickjs.c",new_c)
write("projected/vendor/quickjs/quickjs.h",new_h)
assert new_c.replace(c_add,b"",1)==old_c
assert new_h.replace(h_add,b"",1)==old_h
start=old_c.index(b"static JSValue JS_GetGlobalVar(")
stop=old_c.index(marker,start)
write("authority/quickjs-global-identifier-original.c.txt",old_c[start:stop])
opcode=old_c.index(b"val = JS_GetGlobalVar(ctx, atom, opcode - OP_get_var_undef);")
write("authority/quickjs-global-identifier-opcode.txt",old_c[opcode-230:opcode+230])
# Only own static authoring under the assigned packet; no native compilation.
old_build=read(main/"build.zig")
add=read(base/"build-addition.txt")
anchor=b"    const main_runtime_helpers_tests = b.addTest(.{"
assert old_build.count(anchor)==1
new_build=old_build.replace(anchor,add+anchor,1)
write("projected/build.zig",new_build)
assert new_build.replace(add,b"",1)==old_build
write("original-fixture-inverse.json",json.dumps({
 "source":pin(up),"retained":pin(base/"authority/resolve-model-scope-original.ts"),
 "fixture":pin(base/"projected/src/extensions/fixtures/sdk-model-scope-warning-4954-source.mjs"),
 "erasure":{"before":sig.decode(),"after":"async function resolveModelScope(patterns, modelRuntime, options) {"},
 "function_body_exact":erased[erased.index(b"{")+1:]==authority[authority.index(b"{")+1:],
 "wrapper_added_only_for_control_capture":True,"original_executed":False},indent=2).encode()+b"\n")
write("native-helper-inverse.json",json.dumps({
 "c_before":pin(main/"vendor/quickjs/quickjs.c"),"c_after":pin(base/"projected/vendor/quickjs/quickjs.c"),
 "h_before":pin(main/"vendor/quickjs/quickjs.h"),"h_after":pin(base/"projected/vendor/quickjs/quickjs.h"),
 "c_exact_addition":c_add.decode(),"header_exact_addition":h_add.decode(),
 "both_complete_inverse_checks":True,"new_C_ABI":"JS_PiGetGlobalBinding(ctx, borrowed atom)",
 "lookup_semantics":"forward actual JS_GetGlobalVar(ctx, atom, true)",
 "existing_function_bodies_changed":False,"bytecode_version_changed":False,
 "existing_equivalent_export_found":False,"native_execution":False},indent=2).encode()+b"\n")
write("build-inverse.json",json.dumps({
 "before":pin(main/"build.zig"),"after":pin(base/"projected/build.zig"),
 "addition":pin(base/"build-addition.txt"),"insertion_before":anchor.decode(),
 "exact_inverse":True,"install_only":True,"run_step_added":False,
 "step":"build-native-sdk-model-scope-warning","artifact_windows":"native-sdk-model-scope-warning.exe",
 "filter":"native model scope warning"},indent=2).encode()+b"\n")
paths=[
 "src/extensions/native_sdk_model_scope_warning.zig",
 "src/native_sdk_model_scope_warning_test.zig",
 "src/extensions/fixtures/sdk-model-scope-warning-observer.mjs",
 "src/extensions/fixtures/sdk-model-scope-warning-4954-source.mjs",
 "vendor/quickjs/quickjs.c","vendor/quickjs/quickjs.h","build.zig"
]
patch=[]
for relative in paths:
    before=read(main/relative).decode("utf-8") if (main/relative).is_file() else ""
    after=read(base/"projected"/relative).decode("utf-8")
    patch.extend(difflib.unified_diff(before.splitlines(keepends=True),after.splitlines(keepends=True),
        fromfile="a/"+relative if before else "/dev/null",tofile="b/"+relative))
write("model-scope-warning.patch","".join(patch).encode())
checked=subprocess.run(["git","apply","--check",str(base/"model-scope-warning.patch")],cwd=main,text=True,capture_output=True)
assert checked.returncode==0,(checked.stdout,checked.stderr)
write("git-apply-check.json",json.dumps({"head":head,"exit_code":checked.returncode,"stdout":checked.stdout,
 "stderr":checked.stderr,"applied":False,"Main_modified":False},indent=2).encode()+b"\n")
print(json.dumps({"status":"source_authoring_only","head":head,"paths":paths,"patch":pin(base/"model-scope-warning.patch"),"git_apply_check":checked.returncode}))

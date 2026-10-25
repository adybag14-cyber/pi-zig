# Root-specific source-only authorization 2026-10-25.
# Writes only this isolated packet; no native build, Node, runtime, or Main edits.
from pathlib import Path, PurePosixPath
from datetime import datetime, timezone
import hashlib, json, re, difflib, subprocess
ROOT=Path(r"C:\Users\adyba\pi-zig")
MAIN=ROOT/"main"
P=Path(__file__).parent
HEAD="c248553d15282e1e8ad896382c78132b6a501dd9"
def pin(path):
    b=path.read_bytes()
    return dict(path=str(path),bytes=len(b),sha256=hashlib.sha256(b).hexdigest().upper())
def write(path,data):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_bytes(data if isinstance(data,bytes) else data.encode("utf-8"))
    return pin(path)
def jsonfile(name,obj):
    return write(P/name,json.dumps(obj,indent=2)+"\n")
assert subprocess.check_output(["git","-C",str(MAIN),"rev-parse","HEAD"],text=True).strip()==HEAD
loader=MAIN/"verification/node-module-constructor-sourceonly-20261016/authority/lib__internal__modules__cjs__loader.js.txt"
util=loader.parent/"lib__internal__util.js.txt"
assert pin(loader)["sha256"]=="2AB4659A8EED5728545CF4393994CB58387AC0693F20F8DFCD095C8D006D21EB"
assert pin(util)["sha256"]=="A6A3FED1D2DE1050CB8B119A2D792246E37ABDEA4099D90D6994D894F506C429"
spec=[("timer-declarations.js",loader,218,221),("lazy-declaration.js",loader,224,224),("wrap-module-load.js",loader,238,259),("get-lazy.js",util,813,823)]
parts={}; extracts=[]
for name,src,first,last in spec:
    raw=b"".join(src.read_bytes().splitlines(keepends=True)[first-1:last])
    target=P/"authority"/name
    write(target,raw); parts[name]=raw
    assert target.read_bytes()==raw
    extracts.append(dict(source=pin(src),first_line=first,last_line=last,extracted=pin(target),exact_raw_slice=True))
prefix=b'"use strict";\nglobalThis.makeOriginalModuleLoad = function(debugWithTimer, tracingChannel) {\nconst Module = actualWrapModule;\n'
body=b"\n".join([parts["get-lazy.js"],parts["timer-declarations.js"],parts["lazy-declaration.js"],parts["wrap-module-load.js"]])
suffix=b"\nreturn wrapModuleLoad;\n};\n"
fixture=write(P/"projected/src/extensions/fixtures/node-commonjs-wrap-load-original.js",prefix+body+suffix)
assert parts["wrap-module-load.js"].rstrip().endswith(b"}")
assert (P/"projected/src/extensions/fixtures/node-commonjs-wrap-load-original.js").read_bytes()[len(prefix):-len(suffix)]==body
extraction=jsonfile("authority/extraction.json",dict(original_loader=pin(loader),original_util=pin(util),extracts=extracts,fixture=fixture,body_bytes_preserved=True,only_test_factory_wrapper_added=True,syntax_boundary="Complete wrapModuleLoad closes on loader line 259; complete getLazy closes on util line 823."))
observer=P/"projected/src/extensions/fixtures/node-commonjs-wrap-load-controls.js"
text=observer.read_bytes().decode()
old='return [2,11,12,18,22,24].includes(scenario) ? true : scenario===29 ? {truthy:true} : false'
new='return scenario===22 ? loads===0 : [2,11,12,18,24].includes(scenario) ? true : scenario===29 ? {truthy:true} : false'
assert text.count(old)==1
text=text.replace(old,new)
old='  if(scenario===20 && actual.outcomes[0][1]!=="ReferenceError")throw Error("initializer TDZ absent");\n'
new=old+'  if(scenario===22 && (actual.loads!==2 || actual.events.filter(e=>e[0]==="trace").length!==1 || actual.events.filter(e=>e[0]==="subscribers").length!==2))throw Error("subscriber path transition absent");\n'
assert text.count(old)==1
write(observer,text.replace(old,new))
# Canonical LF for newly authored native/test sources; authority slices above retain raw bytes.
for rel in ["src/extensions/native_node_commonjs_wrap_load.zig","src/native_node_commonjs_wrap_load_test.zig"]:
    path=P/"projected"/rel
    write(path,path.read_bytes().replace(b"\r\n",b"\n"))
build=(MAIN/"build.zig").read_bytes()
assert hashlib.sha256(build).hexdigest().upper()=="37815BF647A0F94D4ECEB30AA6FB95FCA63ED26C1E5CB95EEDD519C32B5358D1"
pos=build.index(b"        const commonjs_watch = b.addTest")
start=build.rfind(b"    if (native_node_network != null) {\n",0,pos)
end=build.index(b"    if (native_node_network != null) {\n",pos)
block=build[start:end]
assert block.count(b"const commonjs_watch =")==1
addition=block.replace(b"commonjs_watch",b"commonjs_wrap_load").replace(b"commonjs-watch",b"commonjs-wrap-load").replace(b"CommonJS watch",b"CommonJS wrap load").replace(b"eleven actual",b"thirty-two actual")
assert b"watch" not in addition
write(P/"original/build.zig",build)
build_addition=write(P/"build-addition.txt",addition)
write(P/"projected/build.zig",build[:end]+addition+build[end:])
assert (P/"projected/build.zig").read_bytes().replace(addition,b"",1)==build
build_inverse=jsonfile("build-inverse.json",dict(baseline=pin(P/"original/build.zig"),candidate=pin(P/"projected/build.zig"),addition=build_addition,offset=end,exact_raw_inverse=True,existing_target_source=pin(MAIN/"src/native_node_commonjs_watch_test.zig"),changes="One added install-only native test target; copied existing canonical CommonJS watch linkage."))
rels=["build.zig","src/extensions/native_node_commonjs_wrap_load.zig","src/native_node_commonjs_wrap_load_test.zig","src/extensions/fixtures/node-commonjs-wrap-load-original.js","src/extensions/fixtures/node-commonjs-wrap-load-controls.js"]
changes=[]; patches=[]; resolutions=[]; packages=[]
for rel in rels:
    before=(MAIN/rel).read_bytes() if (MAIN/rel).exists() else b""
    after=(P/"projected"/rel).read_bytes()
    exists=(MAIN/rel).exists()
    if rel!="build.zig": assert not exists
    changes.append(dict(destination_relative_path=rel,operation="replace" if exists else "add",baseline=pin(MAIN/rel) if exists else None,candidate=pin(P/"projected"/rel)))
    patches.extend(difflib.unified_diff(before.decode().splitlines(keepends=True),after.decode().splitlines(keepends=True),fromfile="a/"+rel if exists else "/dev/null",tofile="b/"+rel,n=3))
    if rel.endswith(".zig") and rel!="build.zig":
        for kind,literal in re.findall(r'@(import|embedFile)\("([^"]+)"\)',after.decode()):
            if kind=="import" and not literal.endswith(".zig"):
                packages.append(dict(source=rel,kind=kind,literal=literal));continue
            r=(PurePosixPath(rel).parent/literal).as_posix()
            selected=P/"projected"/r if (P/"projected"/r).exists() else MAIN/r
            assert selected.is_file(),(rel,literal)
            resolutions.append(dict(source=rel,kind=kind,literal=literal,resolved_relative_path=r,selected=pin(selected)))
patch=write(P/"wrap-module-load.patch","".join(patches))
check=subprocess.run(["git","-C",str(MAIN),"apply","--check","--",patch["path"]],capture_output=True,text=True)
apply_result=jsonfile("git-apply-check.json",dict(head=HEAD,exit_code=check.returncode,stdout=check.stdout,stderr=check.stderr,read_only=True))
assert check.returncode==0,check.stderr
names=re.findall(r'^test "([^"]+)"',(P/"projected/src/native_node_commonjs_wrap_load_test.zig").read_text(),re.M)
assert len(names)==32 and len(set(names))==32
readme=write(P/"README.md",'''# Original CommonJS wrapModuleLoad owner

This source candidate ports the retained Node loader timer cells, getLazy module.require channel, and complete wrapModuleLoad declaration against the genuine canonical Module constructor.

The native owner preserves independent template coercions, callback-updated lexical timer cells including TDZ, successful-only lazy caching and reentry, subscribed and unsubscribed dispatch, exact receivers and arguments, null-prototype trace context, lookup order, ordinary throw identity, and finally precedence. The current canonical assembler must supply the real debugWithTimer and tracingChannel declarations. This packet does not publish a partial node:module or diagnostics_channel namespace.

The 32 declared tests compare the original retained source and this native consumer in the same linked VM. Observable test inputs expose consumer ordering and ownership. They are not production replacements for the tracing/timer producers. The constructor is the genuine canonical Module owner. A subscriber control changes from traced to direct across two calls.

Original loader lines 218–221, 224, and 238–259 and util lines 813–823 are retained byte-for-byte. Only the test factory wrapper is new. The original closing brace at loader line 259 is included; no original source bodies are rewritten.

The projected build file adds one install-only target copied from the current CommonJS watch link setup. Removing the recorded insertion reconstructs the complete c248553d baseline. Existing Main files are untouched. The patch has passed git apply --check against that exact head.

No native compiler, test executable, Node capture, whole application, or public module assembly has run for this packet. Declared controls are not actual metadata or passing runtime tests. Runtime qualification and real producer/assembler wiring remain required.
''')
static=jsonfile("static-checks.json",dict(source_basis_head=HEAD,original_raw_slices=4,complete_wrapper_end_line=259,declared_tests=32,unique_names=True,direct_imports_resolved=len(resolutions),package_imports=packages,raw_build_inverse=True,git_apply_check=apply_result,native_execution=False,Main_modified=False))
entry=dict(schema=1,created_utc=datetime.now(timezone.utc).isoformat(),status="source_candidate_complete_original_wrapModuleLoad_unexecuted",scope="Original timer cells, lazy channel, wrapModuleLoad consumer against genuine Module; actual declarations required from canonical assembler.",source_basis_head=HEAD,changes=changes,patch=patch,readme=readme,original_fixture_inverses=extraction,static_checks=static,retained_authorities=[pin(loader),pin(util)],build_addition=build_addition,build_inverse=build_inverse,direct_import_resolutions=resolutions,standard_package_imports=packages,controls=dict(declared_count=32,original_comparison_count=32,names=names,actual_metadata_count=None,runtime_result=None),git_apply_check=apply_result,remaining_integration=["Root and independent exact source acceptance","compiled metadata and strict runtime on final integrated head","genuine debugWithTimer and complete canonical tracingChannel suppliers","canonical Module assembler and production worker entry"],not_executed=["native compiler","native runtime","Node capture","original function fixture","whole application"],claims=dict(native_execution=False,candidate_executed=False,runtime_qualification=False,product_qualification=False,Main_modified=False,public_Module_published=False))
entry_pin=jsonfile("source-intake.json",entry)
print(json.dumps(dict(entry=entry_pin,patch=patch,changes=len(changes),declared_tests=len(names),fixture=fixture,build_inverse=True,apply_check=check.returncode,Main_modified=False)))

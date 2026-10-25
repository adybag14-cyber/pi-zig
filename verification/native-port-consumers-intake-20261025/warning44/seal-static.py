import json,hashlib,re,difflib,posixpath,subprocess
from pathlib import Path
from datetime import datetime,timezone
base=Path(r"C:\Users\adyba\pi-zig\worktrees\sdk-owners-resume-20261018\verification\sdk-model-scope-warning-sourceonly-20261025")
main=Path(r"C:\Users\adyba\pi-zig\main")
old=base.with_name("sdk-model-scope-warning-sourceonly-20261024")
def read(p): return p.read_bytes()
def pin(p):
    b=read(p);return {"path":str(p),"bytes":len(b),"sha256":hashlib.sha256(b).hexdigest().upper()}
def write(relative,obj):
    p=base/relative;p.parent.mkdir(parents=True,exist_ok=True)
    p.write_text(json.dumps(obj,indent=2)+"\n",encoding="utf-8",newline="\n");return p
head=subprocess.check_output(["git","rev-parse","HEAD"],cwd=main,text=True).strip()
assert head=="c248553d15282e1e8ad896382c78132b6a501dd9"
status=subprocess.check_output(["git","status","--porcelain"],cwd=main,text=True)
assert status=="",status
paths=sorted(str(p.relative_to(base/"projected")).replace("\\","/") for p in (base/"projected").rglob("*") if p.is_file())
assert len(paths)==7,paths
changes=[]
for relative in paths:
    baseline=main/relative
    if baseline.is_file():
        destination=base/"original"/relative;destination.parent.mkdir(parents=True,exist_ok=True)
        destination.write_bytes(read(baseline))
        before=pin(destination)
    else:before=None
    changes.append({"destination_relative_path":relative,"operation":"replace" if before else "add",
        "baseline":before,"candidate":pin(base/"projected"/relative)})
imports=[];packages=[]
for relative in paths:
    if not relative.endswith(".zig") or relative=="build.zig":continue
    source=(base/"projected"/relative).read_text(encoding="utf-8")
    for kind,literal in re.findall(r'@(import|embedFile)\("([^"]+)"\)',source):
        if kind=="import" and not literal.endswith(".zig"):
            assert literal in ["std"],literal
            packages.append({"source":relative,"kind":kind,"literal":literal});continue
        resolved=posixpath.normpath(posixpath.join(posixpath.dirname(relative),literal))
        projected=base/"projected"/resolved
        selected=projected if projected.is_file() else main/resolved
        assert selected.is_file(),(relative,literal,selected)
        imports.append({"source":relative,"kind":kind,"literal":literal,
            "resolved_relative_path":resolved,"selected":pin(selected)})
tests=(base/"projected/src/native_sdk_model_scope_warning_test.zig").read_text(encoding="utf-8")
names=re.findall(r'^test "([^"]+)"',tests,re.M)
both=re.findall(r'try both\("([^"]+)"\)',tests)
assert len(names)==44 and len(set(names))==44
assert len(both)==37 and len(set(both))==37
assert all(n.startswith("native model scope warning ") for n in names)
owner=(base/"projected/src/extensions/native_sdk_model_scope_warning.zig").read_text(encoding="utf-8")
assert "JS_Eval" not in owner and "eval(" not in owner
assert owner.count("JS_PiGetGlobalBinding")==1
assert "try consoleBinding(s)" in owner
assert owner.count("const console = try v.global")==0
assert owner.count(".awaited =")==1
assert owner.count("createResumableWithClose")==1
old_owner=(old/"projected/src/extensions/native_sdk_model_scope_warning.zig").read_text(encoding="utf-8")
old_start=old_owner.index("fn warning(");old_end=old_owner.index("fn diagnosticsLoop(")
new_start=owner.index("fn messageString(");new_end=owner.index("fn diagnosticsLoop(")
assert owner[:new_start]==old_owner[:old_start]
assert owner[new_end:]==old_owner[old_end:]
source_inverse=write("source-inverse.json",{
 "old_draft":pin(old/"projected/src/extensions/native_sdk_model_scope_warning.zig"),
 "selected_owner":pin(base/"projected/src/extensions/native_sdk_model_scope_warning.zig"),
 "changed_region_before":old_owner[old_start:old_end],
 "changed_region_after":owner[new_start:new_end],
 "complete_single_region_inverse":True,
 "changes":["nested coercion/color expression retirement","exact VM global identifier lookup"],
 "original_async_body_and_cache_code_unchanged":True})
up=Path(r"C:\Users\adyba\pi-zig\upstream\snapshots\4954d76-20261015\packages\coding-agent\src\core\model-resolver.ts")
c268=main/"verification/sdk-owners-resume-20261018/model-resolver.c268.ts.txt"
old_authority=c268.read_text(encoding="utf-8")
new_authority=up.read_text(encoding="utf-8")
a=old_authority.index("export async function resolveModelScopeWithDiagnostics(")
b=new_authority.index("export async function resolveModelScopeWithDiagnostics(")
a_end=old_authority.index("export interface ResolveCliModelResult",a)
b_end=new_authority.index("export interface ResolveCliModelResult",b)
assert old_authority[a:a_end]==new_authority[b:b_end]
delta="".join(difflib.unified_diff(old_authority.splitlines(True),new_authority.splitlines(True),fromfile="c268",tofile="4954"))
comparison=write("original-version-comparison.json",{
 "c268":pin(c268),"selected4954":pin(up),"whole_original_diff":delta,
 "diagnostics_wrapper_and_warning_wrapper_exact_between_versions":True,
 "model_default_successor_already_integrated_at_base":pin(main/"src/extensions/native_sdk_factory_model.zig"),
 "native_lower_resolver":pin(main/"src/extensions/native_sdk_public_model_resolver.zig"),
 "native_lower_scope":pin(main/"src/extensions/native_sdk_public_model_scope.zig"),
 "runtime_requalification_required":True})
static=write("static-checks.json",{
 "source_basis_head":head,"Main_clean":True,"projected_paths":paths,
 "all_direct_imports_and_embeds_resolved":True,"named_declarations":len(names),
 "unique_named_declarations":len(set(names)),"source_native_comparisons":len(both),
 "single_actual_await":True,"production_eval_absent":True,"native_execution":False,
 "source_generator_executed":False,"own_static_authoring_script_executed":True,
 "compiler_or_runtime_metadata":None})
retained=[
up,c268,base/"authority/resolve-model-scope-original.ts",
base/"authority/quickjs-global-identifier-original.c.txt",
base/"authority/quickjs-global-identifier-opcode.txt",
main/"src/extensions/native_sdk_factory_model.zig",
main/"src/extensions/native_sdk_public_model_resolver.zig",
main/"src/extensions/native_sdk_public_model_scope.zig",
main/"src/extensions/native_sdk_chalk.zig",
main/"src/extensions/native_sdk_guest_operation.zig",
main/"src/extensions/native_public_values.zig",
main/"src/extensions/native_public_lexical_frame.zig",
main/"src/native_sdk_initial_model_retirement_controls.zig",
main/"src/extensions/native_sdk_application_bootstrap.zig",
main/"src/extensions/native_sdk_main_runtime_helpers.zig"]
entry={
 "schema":1,"created_utc":datetime.now(timezone.utc).isoformat(),
 "status":"source_candidate_complete_original_model_scope_warning_unexecuted",
 "scope":"Complete original resolveModelScope warning wrapper and exact global-identifier primitive; no Main runtimeFactory/public namespace",
 "source_basis_head":head,"changes":changes,"patch":pin(base/"model-scope-warning.patch"),
 "readme":pin(base/"README.md"),"source_inverses":pin(source_inverse),
 "original_fixture_inverses":pin(base/"original-fixture-inverse.json"),
 "native_helper_inverse":pin(base/"native-helper-inverse.json"),
 "static_checks":pin(static),"original_version_comparison":pin(comparison),
 "retained_authorities":[pin(p) for p in retained],
 "build_addition":pin(base/"build-addition.txt"),"build_inverse":pin(base/"build-inverse.json"),
 "direct_import_resolutions":imports,"standard_package_imports":packages,
 "controls":{"declared_count":44,"original_comparison_count":37,"fatal_or_cancel_count":3,
  "cache_or_assembly_count":4,"names":names,"actual_metadata_count":None,"runtime_result":None},
 "git_apply_check":pin(base/"git-apply-check.json"),
 "remaining_integration":["Root exact source acceptance and fresh C-library build","compiled metadata and strict runtime on final integrated head",
  "original createRuntime assembly consumes this callable","canonical Module and production worker entry wiring"],
 "not_executed":["native compiler","native runtime","Node reference capture","original function fixture","production source generator","whole application"],
 "claims":{"native_execution":False,"candidate_executed":False,"runtime_qualification":False,
 "product_qualification":False,"new_C_ABI":True,"Main_modified":False,
 "public_Main_published":False,"runtimeFactory_complete":False}}
entry_path=write("source-intake.json",entry)
print(json.dumps({"status":"source_packet_sealed_unexecuted","entry":pin(entry_path),
 "patch":pin(base/"model-scope-warning.patch"),"controls":len(names),"direct_imports":len(imports),
 "new_source_build_paths":len(paths),"Main_clean":True}))

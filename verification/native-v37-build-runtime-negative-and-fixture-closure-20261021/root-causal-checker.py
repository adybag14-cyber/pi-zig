from pathlib import Path
import hashlib,json
root=Path(r"C:\Users\adyba\pi-zig");sdk=root/"worktrees/sdk-owners-resume-20261018/verification/v37-file-handle-runtime-fixtures-sourceonly-20261021";mod=root/"worktrees/modules-io-resume-20261018/verification/v37-file-handle-runtime-fixtures-peer-20261021"
def sha(b):return hashlib.sha256(b).hexdigest().upper()
seen={}
def check(p):
 b=Path(p["path"]).read_bytes();assert len(b)==p["bytes"] and sha(b)==p["sha256"].upper(),p
 seen[str(Path(p["path"])).casefold()]={"path":p["path"],"bytes":len(b),"sha256":sha(b)}
 return b
cp={"path":str(sdk/"causal-proof.json"),"bytes":83979,"sha256":"39DF95F9780D1A663A6CAC9542B1F7656AAD5EE6CDCCD4761219142295E81C5D"}
mp={"path":str(mod/"source-audit.json"),"bytes":101785,"sha256":"74591C1609D2A07397D44585C0BD92C1BEDB406AC9663AFF77161D4449CA9512"}
c=json.loads(check(cp));m=json.loads(check(mp))
sources={r["key"]:r for r in c["input_pins"]}
for row in c["input_pins"]:check(row)
for row in m["inputs"]:check(row)
for r in c["installed_SDK_authority_snapshots"]:assert check(r["installed_original"])==check(r["immutable_snapshot"])
for e in c["exact_excerpts"]:
 b=check(sources[e["source_key"]]);x=b"".join(b.splitlines(keepends=True)[e["first_line"]-1:e["last_line"]])
 assert len(x)==e["bytes"] and sha(x)==e["sha256"] and x.decode()==e["text"],e["source_key"]
for e in m["source_ranges"]:
 b=Path(e["path"]).read_bytes();assert sha(b)==e["file_sha256"];x=b"".join(b.splitlines(keepends=True)[e["first_line"]-1:e["last_line"]])
 assert len(x)==e["bytes"] and sha(x)==e["sha256"] and x.decode()==e["text"]
assert c["declared_control_count"]==m["declared_controls"]==58
assert len(c["file_checks"])==m["exact_files"]==2 and m["exact_edits"]==8
assert m["main_clean_before_and_after"] and m["all_inputs_rehashed_at_end"]
assert m["pe_imports"]["binary_executed"] is False
assert m["pe_imports"]["selected"]=={"_close":"api-ms-win-crt-stdio-l1-1-0.dll","_set_invalid_parameter_handler":"api-ms-win-crt-runtime-l1-1-0.dll"}
assert m["future_actual_metadata"] is None
print(json.dumps({"distinct_current_pins":len(seen),"source_proof":cp,"independent_proof":mp,"SDK_excerpts_verified":len(c["exact_excerpts"]),"peer_source_ranges_verified":len(m["source_ranges"]),"source_pins":list(seen.values()),"SDK_excerpt_index":[{"i":i,"key":e["source_key"],"first":e["first_line"],"last":e["last_line"],"bytes":e["bytes"]}for i,e in enumerate(c["exact_excerpts"])],"peer_only_ranges":[{"i":i,"path":e["path"],"first":e["first_line"],"last":e["last_line"],"bytes":e["bytes"]} for i,e in enumerate(m["source_ranges"]) if i>=41],"PE":m["pe_imports"]}))

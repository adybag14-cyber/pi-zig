import pathlib,json,hashlib,ast,re
root=pathlib.Path(r"C:\Users\adyba\pi-zig")
own=root/"worktrees/modules-io-resume-20261018";packet=own/"verification/native-node-tracing-platform-sourceonly-20261020";vendor=own/"vendor/node-v24.13.0/abseil-cpp"
h=lambda b:hashlib.sha256(b).hexdigest().upper()
verified={}
def pin(v):
 p=pathlib.Path(v["path"]);b=p.read_bytes();assert h(b)==v["sha256"].upper(),str(p)
 if "bytes" in v: assert len(b)==v["bytes"],str(p)
 verified[str(p)]=h(b);return b
mraw=(vendor/"SOURCE-MANIFEST.json").read_bytes();assert h(mraw)=="0B91065B9E2B4F79929FF2245DE802AF87C01BEB2F572B274491343DC1C94706"
m=json.loads(mraw);gyp=ast.literal_eval(pin(m["original_gyp"]).decode());members=[x.removeprefix("<(ABSEIL_ROOT)/") for x in gyp["targets"][0]["sources"]]
assert len(members)==349
acq={};normalized=[]
for v in m["acquisition_receipts"]:
 receipt=json.loads(pin(v))
 for a in receipt["records"]:
  if not a.get("ok"):continue
  name=a["relative_path"]
  prefix="vendor/node-v24.13.0/abseil-cpp/"
  if name.startswith(prefix):
   assert pathlib.Path(v["path"]).name=="closure-000-004-attempt1.json"
   normalized.append(name);name=name[len(prefix):]
  acq[(name,a["sha256"].upper())]=a
allfiles={}
for f in m["files"]:
 p=vendor/f["path"];b=p.read_bytes();assert h(b)==f["sha256"] and len(b)==f["bytes"],str(p)
 assert (f["path"],f["sha256"]) in acq,f["path"]
 a=acq[(f["path"],f["sha256"])];assert a["url"]==f["url"] and a["bytes"]==f["bytes"]
 assert a["url"].startswith("https://raw.githubusercontent.com/nodejs/node/def0bdf8abee441cfcbf793a8dc24a6f3b899573/")
 allfiles[f["path"]]=b
assert len(allfiles)==353 and len(normalized)==3
assert set(allfiles)==set(members)|set(m["additional_literal_headers"])|{"LICENSE"}
proofraw=(packet/"abseil-source-graph-proof.json").read_bytes()
assert h(proofraw)=="E30A058AFE090EC9D59458E01FB9136CE945777397E349ABA670793A48259EB0"
proof=json.loads(proofraw);recipe=pin(proof["recipe"]).decode()
cpp=[x for x in members if x.endswith(".cc")]
actual=re.findall(r'^\s*"(absl/[^"]+\.cc)",\s*$',recipe,re.M)
assert cpp==actual and len(cpp)==110
edges=[];unresolved=[]
pattern=re.compile(r'^[ \t]*#[ \t]*include[ \t]*([<"])([^>"]+)[>"]',re.M)
comment=re.compile(r'/\*.*?\*/|//[^\n]*',re.S)
for rel,b in sorted(allfiles.items()):
 if rel=="LICENSE":continue
 clean=comment.sub(lambda x: "".join("\n" if c=="\n" else " " for c in x.group()),b.decode())
 for x in pattern.finditer(clean):
  inc=x.group(2);line=clean.count("\n",0,x.start())+1
  if inc.startswith("absl/"):
   edges.append({"source":rel,"line":line,"include":inc})
   if inc not in allfiles:unresolved.append((rel,inc))
  elif x.group(1)=='"' and not (vendor/pathlib.Path(rel).parent/inc).is_file():
   unresolved.append((rel,inc))
assert len(edges)==1420,(len(edges),len(proof["edges"]))
assert edges==proof["edges"],"graph row difference"
assert not unresolved,unresolved
selectionraw=(packet/"toolchain-and-sdk-selection-proof.json").read_bytes()
assert h(selectionraw)=="D63D4FFDB34668088EF82F9261416ED590D3C90BE7935628E94D5AAAFC06DE33"
selection=json.loads(selectionraw);excerpts=0
for source in selection["sources"]:
 b=pin(source);lines=b.decode().splitlines()
 for e in source.get("excerpts",[]):
  for row in e["lines"]:assert lines[row["line"]-1]==row["text"],(source["path"],row["line"])
  excerpts+=1
raw=(packet/"build-composition/proposal.json").read_bytes()
assert h(raw)=="39CD6DFEB20FD08C0A8F4899647195E9DEA7DEF968C0DF291BEE05BFB4FB4856"
d=json.loads(raw);a=pin(d["build_original"]);b=pin(d["build_projected"]);e=d["edit"];i=e["byte_offset"];s=e["insert"].encode()
assert len(s)==1188 and a[:i]+s+a[i:]==b and b[:i]+b[i+len(s):]==a
assert a==(root/"main/build.zig").read_bytes()
print(json.dumps({"abseil_files_hashed_and_bound_to_successful_original_receipts":len(allfiles),"acquisition_receipts_hashed":len(m["acquisition_receipts"]),"exact_closure_prefix_normalizations":normalized,"exact_original_gyp_members":len(members),"exact_original_cpp_order":len(cpp),"complete_literal_edges_recomputed":len(edges),"unresolved_includes":unresolved,"toolchain_source_pins_hashed":len(selection["sources"]),"excerpt_ranges_verified":excerpts,"build_single_insertion_forward_inverse":True,"main_build_bytes_unchanged":True,"no_compiler_or_preprocessor_or_writes":True},indent=2))

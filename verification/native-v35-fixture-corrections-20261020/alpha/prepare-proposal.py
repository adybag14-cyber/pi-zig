"""Finite source-only alpha-renaming proposal. No compiler, formatter, project generator or native execution.
The prefix before FINAL OUTPUT PHASE reads inputs and constructs candidate bytes in memory.
The final phase creates only new evidence files under this packet; live source files are never written.
"""
from pathlib import Path
import re,json,hashlib,subprocess,difflib
B=Path(r"C:\Users\adyba\pi-zig")
M=B/"main"
W=B/"worktrees/sdk-owners-resume-20261018"
D=W/"verification/v35-file-handle-fixture-shadowing-sourceonly-20261020"
HEAD="79c19fc30c886e85b71aca75d1a025397db04fec"
REL="src/native_node_file_handle_owner_test_support.zig"
NEG=B/"evidence/root-native-foundation-fresh-v35-new4-buildquery-20261020-223254/groups/native-node-file-handle-owner"
CAT=B/"evidence/combined-native-batch-v35-new4-prepared-20261020/groups.json"
DOC=B/"toolchain/zig-x86_64-windows-0.16.0/doc/langref.html"
def sha(b): return hashlib.sha256(b).hexdigest().upper()
def jp(o): return (json.dumps(o,indent=2,ensure_ascii=True)+"\n").encode()
def row(p,b=None):
 p=Path(p);b=p.read_bytes() if b is None else b
 return {"path":str(p),"bytes":len(b),"sha256":sha(b)}
def git(*args):return subprocess.check_output(["git",*args],cwd=M)
assert git("rev-parse","HEAD").decode().strip()==HEAD
assert git("status","--porcelain")==b""
original=(M/REL).read_bytes()
assert len(original)==32558 and sha(original)=="8E1205EAFD05CB18C6FD984258A1D153AE3E6262103EE0E13934FBB54FCC2E60"
raw=git("show",HEAD+":"+REL)
assert raw==original
sdk_before=(W/REL).read_bytes()
assert sdk_before==original
stderr=(NEG/"compile.stderr.log").read_bytes()
compile_bytes=(NEG/"compile.json").read_bytes()
assert len(stderr)==24890 and sha(stderr)=="9EBCCA812674DE30F512015FD2FB696D9DDA97F0D81CF617D4E4B3825BC5D25D"
assert sha(compile_bytes)=="8FA9761496EB7C1F63F918B554FC488F76331AE9760B40F9181C3802A404E904"
terminal=json.loads(compile_bytes)
assert terminal["status"]=="failed" and terminal["exit_code"]==1
assert terminal["pid"]==68180 and terminal["created_utc"]=="2026-10-20T22:33:50.6644500Z"
assert terminal["completed_utc"]=="2026-10-20T22:39:18.9309873+00:00"
assert terminal["timeout_seconds"]==1320
assert b"compile test Debug native 10 errors" in stderr
diagnostic_re=rb"src\\native_node_file_handle_owner_test_support\.zig:(\d+):(\d+): error: ([^\r\n]+)\r?\n.*?\r?\nsrc\\native_node_file_handle_owner_test_support\.zig:(\d+):(\d+): note: declared here"
diagnostics=[]
for m in re.finditer(diagnostic_re,stderr,re.S):
 diagnostics.append({"line":int(m[1]),"column":int(m[2]),"message":m[3].decode(),
 "declaration_line":int(m[4]),"declaration_column":int(m[5]),"verbatim":m[0].decode()})
assert [(r["line"],r["declaration_line"]) for r in diagnostics]==[
 (304,483),(328,504),(383,483),(390,483),(512,483),(569,296),(581,361),(591,483),(610,483),(652,664)]
# Byte lexer for this finite ASCII Zig file. Strings, characters, comments,
# multiline string lines, whitespace and all punctuation stay separate from identifiers.
lex=re.compile(rb'(?P<comment>//[^\r\n]*)|(?P<multiline>\\\\[^\r\n]*)|(?P<escaped_identifier>@"(?:\\.|[^"\\])*")|(?P<string>"(?:\\.|[^"\\])*")|(?P<char>\'(?:\\.|[^\'\\])*\')|(?P<identifier>[A-Za-z_][A-Za-z_0-9]*)|(?P<number>[0-9][A-Za-z_0-9.]*)|(?P<space>\s+)|(?P<punct>.)',re.S)
def tokens(b):
 result=list(lex.finditer(b))
 assert b"".join(m[0] for m in result)==b
 return result
old_tokens=tokens(original)
rules=[
 ("Fixture.init",304,"value","bootstrap_result",[304,305],2),
 ("Fixture.bootstrap",328,"global","global_object",[328,329,341],3),
 ("Fixture.create.offset",383,"value","offset_value",[383],2),
 ("Fixture.create.length",384,"value","length_value",[384],2),
 ("Fixture.createArgs",390,"value","constructor_result",[390,391],2),
 ("Fixture.expose",512,"value","exposed_value",[512,519],2),
 ("Fixture.installInitRecorder",569,"init","init_hook",[569,570,573],3),
 ("Fixture.stopIo",581,"registry","actual_registry",[581],2),
 ("Fixture.drop",591,"value","owned_value",[591],2),
 ("Fixture.deinit.caught",610,"value","caught_value",[610],2),
 ("File.init",652,"status","open_status",[652,655,656],3),
]
edits=[];groups=[]
for group,binding_line,before,after,lines,expected in rules:
 chosen=[]
 for i,m in enumerate(old_tokens):
  line=original.count(b"\n",0,m.start())+1
  if m.lastgroup!="identifier" or m[0]!=before.encode() or line not in lines:continue
  previous=next((old_tokens[j][0] for j in range(i-1,-1,-1) if old_tokens[j].lastgroup not in ("space","comment")),b"")
  if previous==b".":continue
  column=m.start()-original.rfind(b"\n",0,m.start())
  chosen.append({"binding":group,"old_offset":m.start(),"before":before,"after":after,
                 "line":line,"column":column,"token_index":i})
 assert len(chosen)==expected,(group,chosen)
 edits.extend(chosen)
 groups.append({"binding":group,"binding_line":binding_line,"before":before,"after":after,
 "source_lines":lines,"changed_identifier_tokens":expected,
 "compiler_reported":binding_line!=384,
 "purpose":"Rename only this local binding and its references; preserve enclosing declarations and operations."})
edits.sort(key=lambda x:x["old_offset"])
assert len(edits)==25 and len({e["old_offset"] for e in edits})==25
candidate=original
for e in reversed(edits):
 o=e["old_offset"];b=e["before"].encode()
 assert candidate[o:o+len(b)]==b
 candidate=candidate[:o]+e["after"].encode()+candidate[o+len(b):]
delta=0
for e in edits:
 e["new_offset"]=e["old_offset"]+delta
 delta+=len(e["after"])-len(e["before"])
inverse=candidate
for e in reversed(edits):
 o=e["new_offset"];b=e["after"].encode()
 assert inverse[o:o+len(b)]==b
 inverse=inverse[:o]+e["before"].encode()+inverse[o+len(b):]
assert inverse==original
new_tokens=tokens(candidate)
assert len(old_tokens)==len(new_tokens)
changed=[]
for i,(a,b) in enumerate(zip(old_tokens,new_tokens)):
 assert a.lastgroup==b.lastgroup
 if a[0]!=b[0]:
  assert a.lastgroup=="identifier"
  e=next(e for e in edits if e["token_index"]==i)
  assert a[0]==e["before"].encode() and b[0]==e["after"].encode()
  changed.append(i)
assert len(changed)==25
assert b"".join(m[0] for m in old_tokens if m.lastgroup!="identifier")==b"".join(m[0] for m in new_tokens if m.lastgroup!="identifier")
assert original.count(b"\n")==candidate.count(b"\n") and original.count(b"\r")==candidate.count(b"\r")
def declarations(b):
 return re.findall(rb"\b(?:pub\s+)?fn\s+([A-Za-z_][A-Za-z_0-9]*)\s*\(",b)
assert declarations(original)==declarations(candidate)
def public(b):
 return re.findall(rb"\bpub\s+(?:fn|const|var)\s+([A-Za-z_][A-Za-z_0-9]*)",b)
assert public(original)==public(candidate)
imp=rb'@import\s*\(\s*"([^"]+)"\s*\)'
emb=rb'@embedFile\s*\(\s*"([^"]+)"\s*\)'
assert re.findall(imp,original)==re.findall(imp,candidate)
assert re.findall(emb,original)==re.findall(emb,candidate)
assert re.findall(rb'^\s*test\s+"([^"]+)"',original,re.M)==re.findall(rb'^\s*test\s+"([^"]+)"',candidate,re.M)==[]
# Whole-file lexically admitted identifiers matching the conflicting names
# are enumerated below; no blanket text replacement or field-label rename.
remaining={}
for container,start,end in [("Fixture",296,630),("File",638,683)]:
 methods=set(re.findall(rb"^    (?:pub )?fn ([A-Za-z_][A-Za-z_0-9]*)",b"\n".join(candidate.splitlines()[start-1:end]),re.M))
 sig=[m for m in new_tokens if m.lastgroup not in ("space","comment")]
 bindings=[]
 for i,m in enumerate(sig):
  line=candidate.count(b"\n",0,m.start())+1
  if not start<=line<=end or m.lastgroup!="identifier" or m[0] not in methods:continue
  prev=sig[i-1][0] if i else b""
  if prev in (b"const",b"var",b"|"):
   bindings.append({"line":line,"name":m[0].decode(),"prefix":prev.decode()})
 assert bindings==[],(container,bindings)
 remaining[container]={"container_function_names":sorted(x.decode() for x in methods),
 "same_name_const_var_or_capture_bindings_after":bindings,
 "scope":"Finite lexical const/var/capture check, not a compiler or general semantic validator."}
catalog=CAT.read_bytes()
assert sha(catalog)=="B5DDAB29463DC9EEF28A795F702F605AEC013B21236975B857AE66C25A8CD7FA"
matrix=json.loads(catalog)
selected=matrix["groups"][-4:]
assert [g["name"] for g in selected]==["native-node-file-handle-owner","native-node-fs-before-hook-continuation","native-vm-error-constructor-name","native-node-file-handle-transfer"]
expected=[(18,710,243),(3,710,243),(24,1,0),(13,711,243)]
named={"catalog_tool":"tools/catalog.zig","native_icu_api":"src/extensions/icu/native_icu_api.zig"}
cache={REL:original}
def data(rel):
 if rel not in cache:cache[rel]=(M/rel).read_bytes()
 return cache[rel]
def graph(root,projected):
 modules=set();embeds=set();edges=[];external=set();todo=[root]
 while todo:
  rel=todo.pop()
  if rel in modules:continue
  modules.add(rel)
  b=candidate if projected and rel==REL else data(rel)
  for kind,pattern in [("import",imp),("embed",emb)]:
   for m in re.finditer(pattern,b):
    literal=m[1].decode()
    if kind=="import" and not literal.endswith(".zig"):
     if literal not in named:external.add(literal);continue
     dest=named[literal]
    else:
     p=((M/rel).parent/literal).resolve()
     assert p.is_relative_to(M.resolve()) and p.is_file(),p
     dest=p.relative_to(M.resolve()).as_posix()
    edges.append({"from":rel,"kind":kind,"literal":literal,"to":dest})
    if kind=="import":todo.append(dest)
    else:embeds.add(dest);data(dest)
 assert external<=set(["std","builtin"])
 return {"modules":sorted(modules),"embeds":sorted(embeds),"edges":sorted(edges,key=lambda e:(e["from"],e["kind"],e["literal"],e["to"])),"external":sorted(external)}
graphs=[]
for g,(n,nm,ne) in zip(selected,expected):
 before_graph=graph(g["source_root"],False)
 after_graph=graph(g["source_root"],True)
 assert before_graph==after_graph
 assert len(before_graph["modules"])==nm and len(before_graph["embeds"])==ne
 names=re.findall(rb'^test "([^"]+)"',data(g["source_root"]),re.M)
 required=[Path(g["source_root"]).stem+".test."+x.decode() for x in names]
 assert required==g["required_named"] and len(names)==n
 for p in g["source_pins"]:
  assert sha(data(p["path"]))==p["sha256"],p["path"]
 graphs.append({"group":g["name"],"source_root":g["source_root"],"root_pin":row(M/g["source_root"],data(g["source_root"])),
 "declared_controls":n,"required_named":required,"allowed_anonymous":g["allowed_anonymous"],
 "modules":nm,"embeds":ne,"edges":len(before_graph["edges"]),
 "topology_sha256":sha(jp(before_graph)),"complete_before_after_topology_equal":True,
 "fixture_reachable":REL in before_graph["modules"]})
assert sum(g["declared_controls"] for g in graphs)==58
build=(M/"build.zig").read_bytes()
assert sha(build)=="4746B7E154B4F6A3441A387A7A3C66FEE7B1CDC75652C13D0969CC4160451D55"
doc=DOC.read_bytes()
assert sha(doc)=="095DAA2D9F1262FB8BC00AFBB44D386F20363FD930E400BF703A8BC4255A4FFD"
doclines=doc.splitlines(keepends=True)
excerpts=[]
for lo,hi in [(1940,1946),(5477,5501)]:
 b=b"".join(doclines[lo-1:hi])
 excerpts.append({"authority":row(DOC,doc),"first_line":lo,"last_line":hi,"bytes":len(b),"sha256":sha(b),"text":b.decode()})
patch="".join(difflib.unified_diff(original.decode().splitlines(keepends=True),candidate.decode().splitlines(keepends=True),
 fromfile="a/"+REL,tofile="b/"+REL)).encode()
inputs=[row(M/r,b) for r,b in sorted(cache.items())]
assert (M/REL).read_bytes()==original and (W/REL).read_bytes()==sdk_before
assert (M/"build.zig").read_bytes()==build
assert CAT.read_bytes()==catalog and (NEG/"compile.stderr.log").read_bytes()==stderr
assert git("rev-parse","HEAD").decode().strip()==HEAD and git("status","--porcelain")==b""
proof={
 "schema":"pi-zig-v35-fixture-shadowing-token-proof-v1","head":HEAD,
 "input":row(M/REL,original),"raw_git_preimage":{"head":HEAD,"path":REL,"bytes":len(raw),"sha256":sha(raw),"checkout_equal":True},
 "projected":row(D/"projected"/REL,candidate),
 "identifier_bindings":groups,"identifier_token_edits":edits,
 "identifier_token_changes":25,"bindings_renamed":11,"compiler_errors_preserved":diagnostics,
 "unreported_adjacent_binding":{"line":384,"reason":"Same Fixture.value shadow in the immediately adjacent length capture; direct source finding, not an extra reported compiler error."},
 "complete_forward_and_inverse_exact":True,"all_other_tokens_and_whitespace_exact":True,
 "all_nonidentifier_bytes_sha256":sha(b"".join(m[0] for m in old_tokens if m.lastgroup!="identifier")),
 "function_declaration_names":[x.decode() for x in declarations(original)],
 "public_declaration_names":[x.decode() for x in public(original)],
 "public_function_types_unchanged":"Only the expose parameter spelling changes; token kinds, type tokens, punctuation and all function declaration names are identical.",
 "all_literals_comments_fields_imports_embeds_assertions_unchanged":True,
 "finite_remaining_container_check":remaining,
 "graphs":graphs,"source_declarations_total":58,"future_actual_metadata":None,
 "current_inputs":len(inputs),"input_inventory_sha256":sha(jp(inputs)),
 "build_unchanged":row(M/"build.zig",build),"catalog_unchanged":row(CAT,catalog),
 "compiler_executed":False,"native_executed":False,"formatter_executed":False,
 "metadata_auditor_executed":False,"project_generator_executed":False,"Main_written":False,
 "separate_lifecycle_question":"The beginAsyncClose completion-only observer is preserved exactly. Any correction requires a separate finite successor; this proposal makes no lifecycle acceptance claim."
}
proposal={
 "schema":"pi-zig-v35-fixture-shadowing-source-proposal-v1",
 "status":"UNEXECUTED SOURCE PROPOSAL; original V35 compile failure remains unqualified",
 "base_head":HEAD,"source_target":REL,"original":row(D/"original"/REL,original),
 "projected":row(D/"projected"/REL,candidate),"raw_git_original":row(D/"original/native_node_file_handle_owner_test_support.zig.raw",raw),
 "patch":row(D/"fixture-alpha-renames.patch",patch),
 "proof":row(D/"token-and-graph-proof.json",jp(proof)),
 "input_inventory":row(D/"input-inventory.json",jp(inputs)),
 "authority_excerpts":row(D/"zig-shadowing-authority.json",jp(excerpts)),
 "negative_compiler_record":row(D/"negative/compile.json",compile_bytes),
 "negative_compiler_stderr":row(D/"negative/compile.stderr.log",stderr),
 "original_negative_paths":[row(NEG/"compile.json",compile_bytes),row(NEG/"compile.stderr.log",stderr)],
 "preparation_source":row(Path(__file__)),
 "review_scope":"Eleven local bindings / 25 identifier tokens only; all ten reported errors and declaration notes retained. Full-file forward/inverse and four root import topologies checked. No live source write.",
 "control_counts":[{"root":g["source_root"],"declared":g["declared_controls"]} for g in graphs],
 "unchanged_constraints":["No production code change","No control, assertion, fixture operation, literal, import, or type change","No method or field name change","No Main, build, catalog, cache, lease or native execution","Original compile failure and SDK fixture remain unchanged","Separate phase observer issue is outside this packet"],
 "pending":["Independent source peer","Root review and failure closure","Any later Main intake and fresh exact-head catalog/grant","New compiler and runtime qualification"]
}
outputs={
 "original/"+REL:original,"projected/"+REL:candidate,
 "original/native_node_file_handle_owner_test_support.zig.raw":raw,
 "fixture-alpha-renames.patch":patch,"token-and-graph-proof.json":jp(proof),
 "input-inventory.json":jp(inputs),"zig-shadowing-authority.json":jp(excerpts),
 "negative/compile.json":compile_bytes,"negative/compile.stderr.log":stderr,
 "proposal.json":jp(proposal)
}
# FINAL OUTPUT PHASE: only create previously absent packet evidence.
for rel,b in outputs.items():
 p=D/rel;p.parent.mkdir(parents=True,exist_ok=True)
 with p.open("xb") as f:f.write(b)
print(json.dumps({"proposal":row(D/"proposal.json"),"projected":row(D/"projected"/REL),
 "proof":row(D/"token-and-graph-proof.json"),"bindings":11,"identifier_tokens":25,
 "diagnostics":len(diagnostics),"roots":len(graphs),"declared_controls":58,
 "current_inputs":len(inputs),"all_live_sources_preserved":True},indent=2))

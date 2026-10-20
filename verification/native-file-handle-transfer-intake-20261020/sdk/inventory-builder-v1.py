from pathlib import Path
import hashlib,json,re,posixpath,subprocess
w=Path("C:\\Users\\adyba\\pi-zig\\worktrees\\sdk-owners-resume-20261018");m=Path("C:\\Users\\adyba\\pi-zig\\main");p=Path("C:\\Users\\adyba\\pi-zig\\worktrees\\sdk-owners-resume-20261018\\verification\\native-file-handle-transfer-sourceonly-20261020")
def digest(b):return hashlib.sha256(b).hexdigest().upper()
def info(q):
 b=q.read_bytes();return {'path':str(q),'bytes':len(b),'sha256':digest(b)}
def emit(q,b):
 q.parent.mkdir(parents=True,exist_ok=True)
 with q.open('xb') as f:f.write(b)
 return info(q)
def dump(q,j):return emit(q,(json.dumps(j,indent=2)+'\n').encode())
head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=m,text=True).strip()
assert head=='c764130caf2f2c7c63728bec0f6d1e16ac5c59a4',head
base=(m/'build.zig').read_bytes()
block="        const node_file_handle_transfer = b.addTest(.{\n            .root_module = b.createModule(.{ .root_source_file = b.path(\"src/native_node_file_handle_transfer_test.zig\"), .target = target, .optimize = optimize }),\n            .filters = &.{\"native FileHandle transfer\"}, .use_llvm = use_llvm,\n        });\n        linkQuickJs(b, node_file_handle_transfer.root_module, quickjs, sqlite_lib_dir);\n        linkTypeScriptParser(b, node_file_handle_transfer.root_module, typescript_parser);\n        linkSqlite(node_file_handle_transfer.root_module, sqlite_lib_dir, sqlite_library);\n        node_file_handle_transfer.root_module.addImport(\"catalog_tool\", catalog_tool);\n        node_file_handle_transfer.root_module.addIncludePath(b.path(\"vendor/node-v24.13.0/uv/include\"));\n        node_file_handle_transfer.root_module.linkLibrary(network);\n        // One actual TLS diagnostic owner in this selected native artifact.\n        // This new owner is compiled directly; no production bootstrap is implied.\n        node_file_handle_transfer.root_module.addCSourceFile(.{\n            .file = b.path(\"src/extensions/native_node_diagnostic_context.c\"),\n            .flags = &.{\"-std=gnu11\"},\n        });\n        node_file_handle_transfer.root_module.addCSourceFile(.{\n            .file = b.path(\"src/extensions/native_node_file_handle_transfer.cpp\"),\n            .flags = &.{ \"-std=gnu++20\", \"-fno-exceptions\", \"-fno-rtti\", \"-fno-strict-aliasing\" },\n        });\n        if (target.result.os.tag == .windows) {\n            node_file_handle_transfer.root_module.linkSystemLibrary(\"advapi32\", .{});\n            node_file_handle_transfer.root_module.linkSystemLibrary(\"userenv\", .{});\n        }\n        b.step(\"build-native-node-file-handle-transfer\", \"Install thirteen actual FileHandle descriptor transfer controls without execution\").dependOn(&b.addInstallArtifact(node_file_handle_transfer, .{ .dest_sub_path = b.fmt(\"native-node-file-handle-transfer{s}\", .{if (target.result.os.tag == .windows) \".exe\" else \"\"}) }).step);\n".encode()
needle=b'        const native_node_fs_request_owner_tests = b.addTest(.{\n'
assert base.count(needle)==1
after=block+needle
projected=base.replace(needle,after)
assert projected.replace(after,needle)==base
build_original=emit(p/'build/original-build.zig',base)
build_selected=emit(p/'build/projected-build.zig',projected)
build_block=emit(p/'build/install-only-block.zig.txt',block)
build=dump(p/'build/proposal.json',{
 'schema':'pi-zig.file-handle-transfer-install-only-build.v1','source_only':True,
 'comparison_main_head':head,'original':build_original,'projected':build_selected,'block':build_block,
 'edits':[{'before':needle.decode(),'after':after.decode(),'occurrences_before':1,'occurrences_after':1}],
 'whole_forward_exact':True,'whole_inverse_exact':True,'install_only':True,'run_steps_added':0,
 'source_declared_controls':13,'new_roots':1,'artifact_basename':'native-node-file-handle-transfer',
 'required_dependency_packet':'A9D4A4D0BAC91764B52A9EE87BE7C555C2C8C61FCEB9FC87E7282A169700AD73',
 'native_sources_directly_compiled':['src/extensions/native_node_diagnostic_context.c','src/extensions/native_node_file_handle_transfer.cpp'],
 'common_native_dependencies':'Existing QuickJS -> one native network graph -> one native memory/TLS allocation domain; explicit diagnostic C source belongs only to this installed artifact.',
 'not_global_production_bootstrap':True,'compiler_executed':False,'native_executed':False})
old_inv=json.loads((w/'verification/native-file-handle-owner-controls-sourceonly-20261020/dependency-inventory.json').read_text())
selected={}
for x in old_inv['selected_production_and_control_files']:
 q=Path(x['selected']['path']);assert info(q)==x['selected']
 selected[x['relative_path']]=q
new_names=['src/extensions/native_node_file_handle_transfer.h','src/extensions/native_node_file_handle_transfer.cpp','src/extensions/native_node_file_handle_transfer.zig','src/native_node_file_handle_transfer_test.zig']
for n in new_names:
 q=p/('controls-selected' if n.endswith('_test.zig') else 'production')/n
 assert q.read_bytes()==(w/n).read_bytes()
 selected[n]=q
named=old_inv['named_import_owners']
def resolve(n):return selected.get(n,m/n)
seen={};embeds={};edges=[];includes=set();dynamic=[]
todo=['src/native_node_file_handle_transfer_test.zig']
imports=re.compile(r'@import\s*\(\s*"([^"]+)"\s*\)')
emb=re.compile(r'@embedFile\s*\(\s*"([^"]+)"\s*\)')
while todo:
 n=todo.pop()
 if n in seen:continue
 q=resolve(n);assert q.exists(),(n,q)
 b=q.read_bytes();t=b.decode()
 hits=[]
 for x in imports.findall(t):
  if x=='std' or x=='builtin':continue
  if x in named:r=named[x]
  elif x.endswith('.zig'):r=posixpath.normpath(posixpath.join(posixpath.dirname(n),x))
  else:raise AssertionError(('unmapped named import',n,x))
  hits.append(r);edges.append({'from':n,'to':r});todo.append(r)
 for x in emb.findall(t):
  r=posixpath.normpath(posixpath.join(posixpath.dirname(n),x))
  q2=resolve(r);assert q2.exists(),(n,r)
  embeds[r]={'relative_path':r,**info(q2)}
 includes.update(re.findall(r'@cInclude\s*\(\s*"([^"]+)"\s*\)',t))
 for match in re.finditer(r'@import\s*\(([^)]*)\)',t):
  if not re.match(r'\s*"[^"]+"\s*$',match.group(1)):dynamic.append({'file':n,'operand':match.group(1)})
 seen[n]={'relative_path':n,'owner':'selected overlay' if n in selected else 'Main','literal_imports':hits,**info(q)}
anonymous=[]
for n,x in seen.items():
 for i,line in enumerate(Path(x['path']).read_text().splitlines(),1):
  if re.match(r'\s*test\s*\{',line):anonymous.append({'relative_path':n,'line':i})
rootbytes=resolve('src/native_node_file_handle_transfer_test.zig').read_bytes()
names=[{'name':v.group(1).decode(),'line':rootbytes[:v.start()].count(b'\n')+1} for v in re.finditer(rb'^test "([^"]+)"',rootbytes,re.M)]
assert len(names)==13 and not dynamic
preserved=[]
for z in old_inv['preserved_prior_sources']:
 got=info(Path(z['path']));assert got['sha256']==z['sha256'] and got['bytes']==z['bytes']
 preserved.append(got)
for z in old_inv['selected_production_and_control_files']:
 got=info(Path(z['selected']['path']));assert got==z['selected']
for n in ['native_node_file_handle_owner_test_support.zig','native_node_file_handle_owner_test.zig','native_node_fs_before_hook_continuation_test.zig']:
 q=w/'src'/n
 expected=next(x['selected'] for x in old_inv['selected_production_and_control_files'] if x['relative_path']=='src/'+n)
 assert info(q)['sha256']==expected['sha256'];preserved.append(info(q))
cdep_names=['src/extensions/native_node_diagnostic_context.c','src/extensions/native_node_diagnostic_context.h','src/extensions/native_node_diagnostic_context.hpp','src/extensions/native_node_standard_allocator.hpp','src/extensions/native_simdjson_memory.hpp','src/extensions/native_simdjson_memory.cpp','src/extensions/native_node_check_failure.h','src/extensions/native_node_check_failure.c','src/extensions/engine_abi.c','src/extensions/engine_abi.h','tools/build_native_node_memory.zig','tools/build_native_node_network.zig','vendor/quickjs/quickjs.h','vendor/quickjs/quickjs.c','vendor/node-v24.13.0/uv/include/uv.h','vendor/node-v24.13.0/SOURCE-MANIFEST.json']
cdeps=[]
for n in cdep_names:
 q=m/n
 if not q.exists():raise AssertionError(('C dependency missing',n))
 cdeps.append({'relative_path':n,**info(q)})
result=dump(p/'dependency-inventory.json',{
 'schema':'pi-zig.file-handle-transfer-source-dependencies.v1','comparison_main_head':head,
 'method':'Conservative repository literal Zig import/embed closure over exact Main plus reviewed A9D4 source overlay plus four new files; named module owners explicit. This is not compiler reachability, C preprocessor closure or native metadata.',
 'required_owner_packet':info(w/'verification/native-file-handle-owner-controls-sourceonly-20261020/handoff.json'),
 'required_owner_inventory':info(w/'verification/native-file-handle-owner-controls-sourceonly-20261020/dependency-inventory.json'),
 'selected_source_overlay':[{'relative_path':n,'selected':info(q)} for n,q in sorted(selected.items())],
 'root':'src/native_node_file_handle_transfer_test.zig','filter':'native FileHandle transfer','install_step':'build-native-node-file-handle-transfer','artifact_basename':'native-node-file-handle-transfer',
 'source_declared_controls':13,'named_declarations':names,'module_count':len(seen),'modules':[seen[n] for n in sorted(seen)],
 'embed_count':len(embeds),'embeds':[embeds[n] for n in sorted(embeds)],'import_edges':edges,'named_import_owners':named,'c_include_names':sorted(includes),
 'literal_anonymous_source_blocks':sorted(anonymous,key=lambda x:x['relative_path']),'dynamic_import_operands':dynamic,
 'direct_native_c_dependency_pins':cdeps,'native_vendor_graph_is_existing_unchanged':True,
 'preserved_28_prior_plus_3_owner_controls':preserved,'all_31_preserved':True,'future_actual_metadata_count':None,
 'compiler_executed':False,'native_executed':False,'reference_executed':False})
print(json.dumps({'build':build,'inventory':result,'module_count':len(seen),'embed_count':len(embeds),'edge_count':len(edges),'anonymous_count':len(anonymous),'source_declared_controls':len(names)},indent=2))

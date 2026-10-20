"""Independent static audit; reads source/Git only and writes one result in this peer directory."""
from pathlib import Path, PurePosixPath
import hashlib, json, posixpath, re, subprocess
OWN = Path(r'C:\Users\adyba\pi-zig\worktrees\modules-io-resume-20261018')
SDK = Path(r'C:\Users\adyba\pi-zig\worktrees\sdk-owners-resume-20261018')
MAIN = Path(r'C:\Users\adyba\pi-zig\main')
OUT = Path(__file__).parent / 'source-audit.json'
P = SDK / 'verification/native-file-handle-owner-controls-sourceonly-20261020'
Q = SDK / 'verification/native-fsreqpromise-before-hook-followup-sourceonly-20261020'
R = SDK / 'verification/native-file-handle-owner-sourceonly-20261020'
S = SDK / 'verification/native-file-handle-close-settlement-followup-sourceonly-20261020'
BASE = 'f4c6abbc62ecd18b72ec50ab8fa206fe1664909f'
pins = {}
cache = {}
def sha(b): return hashlib.sha256(b).hexdigest().upper()
def raw(path):
    p = str(Path(path))
    if p not in cache:
        assert p.lower().startswith(r'c:\users\adyba\pi-zig'.lower() + '\\'), p
        cache[p] = Path(p).read_bytes()
    return cache[p]
def pin(path, expected=None, size=None):
    b = raw(path); h = sha(b)
    if expected is not None: assert h == expected.upper(), (str(path), h, expected)
    if size is not None: assert len(b) == size, (str(path), len(b), size)
    v = {'path': str(path), 'bytes': len(b), 'sha256': h}
    assert str(path) not in pins or pins[str(path)] == v
    pins[str(path)] = v
    return b
def doc(path, expected):
    return json.loads(pin(path, expected))
def walk_pins(value):
    if isinstance(value, dict):
        if isinstance(value.get('path'), str) and value.get('sha256') and Path(value['path']).is_absolute():
            pin(value['path'], value['sha256'], value.get('bytes'))
        for x in value.values(): walk_pins(x)
    elif isinstance(value, list):
        for x in value: walk_pins(x)
def git_bytes(head, rel):
    return subprocess.run(['git','show',head+':'+rel], cwd=MAIN, check=True, capture_output=True).stdout
def assert_git(head, rel, b):
    g = git_bytes(head, rel); assert g == b, (head, rel, sha(g), sha(b))
    return {'head': head, 'relative_path':rel, 'bytes':len(g), 'sha256':sha(g), 'raw_byte_equal':True}
def replay(f):
    original = pin(f['original']['path'], f['original']['sha256'], f['original']['bytes'])
    projected = pin(f['projected']['path'], f['projected']['sha256'], f['projected']['bytes'])
    current=original; offsets=[]
    for e in f['edits']:
        before=e['before'].encode();after=e['after'].encode()
        if 'input_sha256' in e: assert sha(current)==e['input_sha256']
        if 'offset_in_sequential_input' in e: offset=e['offset_in_sequential_input']
        else:
            assert current.count(before)==e.get('occurrences_before',1)
            offset=current.index(before)
        assert current[offset:offset+len(before)]==before
        current=current[:offset]+after+current[offset+len(before):]
        if 'output_sha256' in e: assert sha(current)==e['output_sha256']
        offsets.append(offset)
    assert current==projected
    for e,offset in reversed(list(zip(f['edits'],offsets))):
        before=e['before'].encode();after=e['after'].encode()
        assert current[offset:offset+len(after)]==after
        current=current[:offset]+before+current[offset+len(after):]
    assert current==original
    return {'relative_path':f.get('relative_path','build.zig'),'edit_count':len(f['edits']),
            'original_sha256':sha(original),'projected_sha256':sha(projected),
            'whole_forward_exact':True,'whole_inverse_exact':True,'sequential_offsets':offsets}
handoff=doc(P/'handoff.json','A9D4A4D0BAC91764B52A9EE87BE7C555C2C8C61FCEB9FC87E7282A169700AD73')
inventory=doc(P/'dependency-inventory.json','56BFF251AD680CE3B5B4E7D4D979CFDA2FA41345BC958432273007DAFD2330D1')
source_map=doc(P/'source-map.json','5E36100728A32C4ACC09F1D53BF11BC90102E506B581C8496DA9F1185749EBCA')
build=doc(P/'build/proposal.json','8DFCA25C7674D319464CE7E411BF6834E516F75418B2381AFF8026D4F13A16D3')
fs=doc(Q/'proposal.json','08F45EF3D26E4D2CBB8A5FA3A144E635AB6DA9B64B486871F7B1D102F6488B56')
close=doc(S/'proposal.json','BA6543E47B33A5D994AD097FBF0CBC58A6E35F262DF42FFE5909D9A736118319')
shared=doc(R/'shared/proposal.json','C195AE5D402ED457AF651D6BEB37B2BB8DBD3DF36CD74106EB172F00B64618FC')
owner=doc(R/'production-proposal.json','061258BF1085004B82EA8D1A9C237402F7D4075A4DE837F9C25B7D39D0D3A804')
provenance=doc(S/'support-main-provenance.json','EC644E04F8B897473874DF78B77F3F28D6AD882AA7ABF7A8C130C38448D1C455')
for d in [handoff,inventory,source_map,build,fs,close,shared,owner,provenance]: walk_pins(d)
for f in inventory['preserved_prior_sources']:
    if 'snapshot' in f: assert raw(f['snapshot']) == raw(f['path'])
assert len(inventory['preserved_prior_sources'])==28
for f in handoff['new_control_and_support_files']:
    assert raw(f['live']['path'])==raw(f['snapshot']['path'])
for f in owner['new_production_files']:
    assert raw(f['live']['path'])==raw(f['snapshot']['path'])
for a in fs['authority_files']:
    assert raw(a['path'])==pin(a['source_path'],a['sha256'],a['bytes'])
edits=[replay(f) for f in shared['files']+close['files']+fs['files']]
assert sum(x['edit_count'] for x in edits)==14
old_close=next(f for f in owner['new_production_files'] if f['relative_path']==close['files'][0]['relative_path'])
assert raw(old_close['snapshot']['path'])==raw(close['files'][0]['original']['path'])
git_bindings=[]
for f in shared['files']:
    git_bindings.append(assert_git(shared['main_predecessor_head'],f['relative_path'],raw(f['original']['path'])))
    git_bindings.append(assert_git(BASE,f['relative_path'],raw(f['original']['path'])))
git_bindings.append(assert_git(BASE,fs['files'][0]['relative_path'],raw(fs['files'][0]['original']['path'])))
git_bindings.append(assert_git(BASE,'build.zig',raw(build['original']['path'])))
build_replay=replay(dict(build,relative_path='build.zig'))
block=raw(build['block']['path'])
assert len(block)==2834
assert build['edits'][0]['after'].encode()==block+build['edits'][0]['before'].encode()
assert b'addRunArtifact' not in block and b'addSystemCommand' not in block
assert b'getInstallStep' not in block and b'default_step' not in block
assert block.count(b'b.addTest(')==2 and block.count(b'b.addInstallArtifact(')==2
assert block.count(b'.root_module.linkLibrary(network);')==2
selected={f['relative_path']:f for f in inventory['selected_production_and_control_files']}
assert len(selected)==12
for f in shared['files']+close['files']+fs['files']:
    assert selected[f['relative_path']]['selected']['sha256']==f['projected']['sha256']
for f in owner['new_production_files']:
    if 'close_request' not in f['relative_path']:
        assert selected[f['relative_path']]['selected']['sha256']==f['snapshot']['sha256']
new_paths={f['relative_path'] for f in owner['new_production_files']}|{f['relative_path'] for f in handoff['new_control_and_support_files']}
assert len(new_paths)==6
for rel in sorted(new_paths):
    x=subprocess.run(['git','cat-file','-e',BASE+':'+rel],cwd=MAIN,capture_output=True)
    assert x.returncode!=0, rel
mods={m['relative_path']:m for m in inventory['modules']}
assert len(mods)==inventory['module_count']==711
assert len(inventory['embeds'])==inventory['embed_count']==243
named=inventory['named_import_owners']
import_re=re.compile(r'@import\s*\(\s*"([^"]+)"\s*\)')
embed_re=re.compile(r'@embedFile\s*\(\s*"([^"]+)"\s*\)')
anon_re=re.compile(r'(?m)^[ \t]*test[ \t]*\{')
named_test_re=re.compile(r'(?m)^[ \t]*test[ \t]+"([^"]+)"[ \t]*\{')
derived_embeds=set(); anonymous=[]; all_edges=0
for rel,m in mods.items():
    source=raw(m['path']).decode('utf-8')
    imports=set()
    for op in import_re.findall(source):
        if op in ['std','builtin','root']: continue
        target=named.get(op)
        if target is None:
            assert op.endswith('.zig'), (rel,op)
            target=posixpath.normpath(posixpath.join(posixpath.dirname(rel),op))
        assert target in mods, (rel,target)
        imports.add(target)
    assert sorted(imports)==m['literal_imports'], (rel,'literal import mismatch')
    all_edges+=len(imports)
    for op in embed_re.findall(source):
        derived_embeds.add(posixpath.normpath(posixpath.join(posixpath.dirname(rel),op)))
    for match in anon_re.finditer(source):
        anonymous.append({'relative_path':rel,'line':source.count('\n',0,match.start())+1})
assert derived_embeds=={e['relative_path'] for e in inventory['embeds']}
key=lambda a:(a['relative_path'],a['line'])
assert sorted(anonymous,key=key)==sorted(inventory['literal_anonymous_source_blocks'],key=key)
assert len(anonymous)==8
root_results=[]
for root in inventory['roots']:
    rel=root['relative_path'];seen=set();todo=[rel]
    while todo:
        n=todo.pop()
        if n in seen: continue
        seen.add(n);todo.extend(mods[n]['literal_imports'])
    assert sorted(seen)==root['transitive_modules']
    assert len(seen)==root['transitive_module_count']==710
    source=raw(mods[rel]['path']).decode('utf-8')
    decl=[{'name':m.group(1),'line':source.count('\n',0,m.start())+1} for m in named_test_re.finditer(source)]
    assert decl==root['named_declarations']
    assert len(decl)==root['source_declared_controls']
    assert all(root['filter'] in x['name'] for x in decl)
    for text in [rel,root['filter'],root['install_step'],root['artifact_basename']+'{s}']:
        assert text.encode() in block, text
    assert sum(1 for a in anonymous if a['relative_path'] in seen)==8
    assert root['future_actual_metadata'] is None
    root_results.append({k:v for k,v in root.items() if k!='transitive_modules'})
assert sum(r['source_declared_controls'] for r in root_results)==21
assert handoff['source_declared_controls']==21
assert handoff['future_actual_metadata_count'] is None
assert {c['name'] for c in source_map['controls']}=={n['name'] for r in root_results for n in r['named_declarations']}
assert len(source_map['controls'])==21
existing=raw(fs['unchanged_existing_control_source']['path']).decode('utf-8')
existing_names=[m.group(1) for m in named_test_re.finditer(existing)]
assert existing_names==fs['existing_named_controls'] and len(existing_names)==25
assert raw(fs['unchanged_existing_control_source']['path'])==git_bytes(BASE,'src/native_node_fs_request_owner_test.zig')
peer_bindings=[
{'path':str(OWN/'verification/native-file-handle-sync-close-source-peer-20261020/peer.json'),'sha256':'090FA7C8485CA0DB4763BBFBA91BC2E2D481E76936BF26B9F9CBF2EE1237504C'},
{'path':r'C:\Users\adyba\pi-zig\evidence\independent-file-handle-owner-source-peer-20261020\peer.json','sha256':'27B01670A2F361328619A1F487093FEA183BFC12CA4A99471F9504CC7A2E6747'}]
walk_pins(peer_bindings)
result={
'schema':'pi-zig.independent-file-handle-owner-controls-source-audit.v1',
'reviewer':'/root/module_io_port','qualification':'Static source, raw-byte and read-only Git inspection only.',
'main_composition_basis':BASE,
'raw_git_basis_checks':git_bindings,
'selected_source_paths':sorted(selected),'new_paths':sorted(new_paths),
'exact_source_projections':edits,'exact_build_projection':build_replay,
'build_insert_bytes':len(block),'install_roots':root_results,
'conservative_graph':{'union_modules':len(mods),'per_root_modules':[710,710],'literal_import_edges':all_edges,'embedded_file_count':len(derived_embeds),'literal_anonymous_blocks':anonymous,'claim':'Lexical conservative closure only; neither compiler selection nor native/C preprocessor closure.'},
'preserved_sdk_source_paths':len(inventory['preserved_prior_sources']),
'unchanged_fs_owner_declarations':len(existing_names),
'prior_bounded_peers':peer_bindings,
'pinned_inputs':sorted(pins.values(),key=lambda x:x['path'].lower()),
'compiler_or_preprocessor_executed':False,'native_or_test_or_reference_executed':False,
'main_or_sdk_writes':False,'future_actual_metadata':None,'all_assertions_passed':True}
payload=(json.dumps(result,indent=2)+'\n').encode()
assert not OUT.exists()
OUT.write_bytes(payload)
print(json.dumps({'output':str(OUT),'bytes':len(payload),'sha256':sha(payload),'input_paths':len(pins),'modules':len(mods),'embeds':len(derived_embeds),'source_edits':sum(e['edit_count'] for e in edits),'build_edits':len(build['edits']),'controls':21,'passed':True}))

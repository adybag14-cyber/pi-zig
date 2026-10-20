"""Seal a finite source proposal and its evidence. No project or native execution."""
from pathlib import Path
import hashlib,json,subprocess
P=Path(__file__).parent
O=P.parents[1]
S=Path(r'C:\Users\adyba\pi-zig\worktrees\sdk-owners-resume-20261018')
REV='def0bdf8abee441cfcbf793a8dc24a6f3b899573'
def digest(b):return hashlib.sha256(b).hexdigest().upper()
def pin(path,expected=None):
 b=path.read_bytes();h=digest(b)
 if expected:assert h==expected,(str(path),h,expected)
 return {'path':str(path),'bytes':len(b),'sha256':h}
def write_new(name,value):
 path=P/name;assert not path.exists(),str(path)
 path.write_bytes((json.dumps(value,indent=2)+'\n').encode())
 return pin(path)
def read(name):return json.loads((P/name).read_text(encoding='utf-8'))
proof=read('source-body-proof.json')
assert proof['comparison_count']==5 and proof['all_equal']
for r in proof['inputs']:
 assert pin(Path(r['path']),r['sha256'])['bytes']==r['bytes']
external=[r for r in proof['inputs'] if not Path(r['path']).is_relative_to(P)]
reuse=read('contained-source-reuse.json')
bindings=[]
reuse_receipt=pin(P/'contained-source-reuse.json','8F2301C1F2929DED358EED4BA6EA108EEB3AF42AEF7E112DA94ECD68BDEED86B')
for i,r in enumerate(reuse['sources']):
 dst=pin(Path(r['path']),r['sha256']);src=pin(Path(r['source_path']),r['sha256'])
 assert dst['bytes']==src['bytes']==r['bytes']
 assert r['revision']==REV
 bindings.append({'authority':dst,'method':'byte-exact contained original reuse','upstream_path':r['upstream_path'],'revision':REV,
 'receipt':reuse_receipt,'receipt_selector':'sources['+str(i)+']','contained_original':src})
for receipt_name,native_name in [('traced-value-acquisition.json','traced-value-native-fetch.json'),('metadata-acquisition.json','metadata-native-fetch.json'),('process-object-acquisition.json','process-object-native-fetch.json')]:
 acquisition=read(receipt_name);records=acquisition.get('sources',[acquisition]);native=read(native_name)
 documents=native['structuredContent']['data']['documents']
 for i,r in enumerate(records):
  url=r.get('source_url',r.get('url'))
  assert '/'+REV+'/' in url
  matches=[(j,d) for j,d in enumerate(documents) if d.get('url')==url]
  assert len(matches)==1,(receipt_name,url)
  j,d=matches[0];assert d['status']=='ok' and d['http_status']==200
  assert d['body_sha256'].upper()==r['sha256']
  dst=pin(Path(r['path']),r['sha256']);assert dst['bytes']==r['bytes']
  bindings.append({'authority':dst,'method':'raw original with matching successful native fetch body','url':url,'revision':REV,
   'receipt':pin(P/receipt_name),'receipt_selector':('sources['+str(i)+']') if 'sources' in acquisition else '$',
   'native_receipt':pin(P/native_name),'native_selector':'structuredContent.data.documents['+str(j)+']',
   'native_http_status':200,'native_body_sha256':d['body_sha256'].upper()})
authorities=sorted(str(q) for q in (P/'authority').iterdir() if q.is_file())
assert len(bindings)==len(authorities)==19
assert sorted(r['authority']['path'] for r in bindings)==authorities
binding_pin=write_new('authority-bindings.json',{'schema':'pi-zig.tracing-event-authority-bindings.v1','revision':REV,
 'contained_reuse_count':14,'raw_fetch_count':5,'complete_authority_count':19,'bindings':bindings})
consumers=read('consumer-basis.json')
for r in consumers['records']:
 assert pin(Path(r['snapshot']),r['sha256'])['bytes']==r['bytes']
 assert pin(Path(r['source_path']),r['sha256'])['bytes']==r['bytes']
for path_key,hash_key in [('sdk_owner_projection_manifest','sdk_owner_projection_manifest_sha256'),('sdk_close_projection_manifest','sdk_close_projection_manifest_sha256')]:
 external.append(pin(Path(consumers[path_key]),consumers[hash_key]))
build=read('build-proposal.json')
a=Path(build['original']['path']).read_bytes();b=Path(build['projected']['path']).read_bytes();e=build['edits'][0]
assert len(build['edits'])==1 and a.count(e['before'].encode())==b.count(e['after'].encode())==1
assert a.replace(e['before'].encode(),e['after'].encode(),1)==b
assert b.replace(e['after'].encode(),e['before'].encode(),1)==a
for path in ['src/extensions/native_node_tracing_event_api.h','src/extensions/native_node_tracing_event_api.cpp']:
 assert not (O/path).exists(),'Proposed new file unexpectedly installed: '+path
preflight_path=O/'verification/native-node-tracing-platform-commit-closure-20261020/preflight.json'
external.append(pin(preflight_path,'71FAD3C1B2938F6BAB1E23DF0B287FAE7E40914E8226B29722C49F8D4643C687'))
preflight=json.loads(preflight_path.read_text(encoding='utf-8'))
preservation={}
for key in ['preserved_tracked_dirty','preserved_old_drafts','preserved_other_untracked']:
 for rel,expected in preflight[key].items():
  assert pin(O/rel,expected['sha256'])['bytes']==expected['bytes']
 preservation[key]={'entries':len(preflight[key]),'all_unchanged':True}
head=subprocess.check_output(['git','-C',str(O),'rev-parse','HEAD'],text=True).strip()
assert head=='5e4646ad8268fdfc8007691ccbda28b6d6985807'
assert subprocess.check_output(['git','-C',str(O),'diff','--cached','--name-only'],text=True)==''
dirty=subprocess.check_output(['git','-C',str(O),'diff','--name-only'],text=True).splitlines()
assert sorted(dirty)==sorted(preflight['preserved_tracked_dirty'])
external.append(pin(O/'verification/native-node-tracing-platform-sourceonly-20261020/manifest.json','AE6A1EA3302EB96D9BAF41B6E5390520546D47AE39D14A28998AACD051079518'))
inventory=[]
for path in sorted(P.rglob('*')):
 if path.is_file():
  r=pin(path);r['relative_path']=path.relative_to(P).as_posix();inventory.append(r)
assert len({r['relative_path'] for r in inventory})==len(inventory)
manifest={'schema':'pi-zig.tracing-event-bootstrap-source-proposal.v1',
 'qualification':'Source-only proposal and bounded source analysis. No compiler/preprocessor/native/reference/test/project-generator execution, no Main/SDK/live tracing source mutation, no installed bootstrap or linkage claim.',
 'worktree':str(O),'head':head,'branch':'work/modules-io-resume-20261018','upstream_revision':REV,
 'summary':'Five raw native trace event C ABI entries with exact original operation bodies; explicit native producer and process/Environment bootstrap mappings.',
 'candidate_sources':[pin(P/'proposal/src/extensions/native_node_tracing_event_api.h','454EE9ECD5E84795751A9D1826FCF18B52E3E43513CE70A200A5F41B01C7194F'),
 pin(P/'proposal/src/extensions/native_node_tracing_event_api.cpp','8CD4D1AF43AF6C0F80304020EB1027C82F72C9B3BFCA68D72FBF0AB1506837EB')],
 'build_proposal':pin(P/'build-proposal.json','3B7C750D5B671F63D141D3B337357EAB0A81FFE372C28F03C68EF12820067589'),
 'analysis':pin(P/'analysis.md'),'source_comparison_checker':pin(P/'source-body-audit.py','1CEBFA1EB0F4BCEBAB5F6C4B57B5D8E03E78BCC20AAA46233ACF3D622E4D6BAB'),
 'source_comparison_proof':pin(P/'source-body-proof.json','F85B637262B70874FA47AAD44D15A0EE0DA50B2316C51DBC32AAB4B2F0498EED'),
 'authority_bindings':binding_pin,'consumer_basis':pin(P/'consumer-basis.json','CDCE815B22D3413209370231020BA2BB90B15DB47991644BBFE7C65C7452FB45'),
 'five_declarations_and_definitions':proof['matching_C_declaration_definition_names'],'five_original_bodies_match':True,
 'two_scopes_first':True,'context_never_queued':True,'native_convertibles_adopted_before_nullable_global_lookup':True,
 'proposed_translation_units_added':1,'build_forward_and_whole_inverse_exact':True,
 'existing_committed_dependencies':[
  {'role':'clock/API','commit':'1700aeaa800003130cce60106c243f6f293e81a9','remote_branch':'work/pi-zig-tracing-clock-api-20261020'},
  {'role':'platform/Abseil/Recorder/contained SDK','commit':'5e4646ad8268fdfc8007691ccbda28b6d6985807','remote_branch':'work/modules-io-resume-20261018'},
  {'role':'genuine V8 fatal/clock diagnostic source owner','commit':'5059d6a04a29232fa3a39614d7e73e3690472c4f','remote_branch':'work/pi-zig-v8-fatal-owner-20261020'}],
 'remaining_owners':[
  'Genuine native TracedValue and typed EnvironmentArgs/AsyncWrapArgs/ProcessMeta factories with explicit I18N/header selection.',
  'Native immutable process metadata/version/release owner and original process-title retrieval.',
  'Exact native producer adapters and additive SDK State reset/destroy and Environment begin/end insertions.',
  'One-shot process trace observer and process-single Agent/client/native-producer bootstrap and teardown owner.',
  'Distinct Environment category observer with actual principal realm, owns_process_state, callback and verbose exception policy.',
  'Complete composite source/link admission, selected target owners and actual compiler/native/concurrency/OS qualification.',
  'Production fatal/stack bootstrap hook installation; no Node assert substitution.'],
 'release_macro_selection':'No DEBUG, NDEBUG or OFFICIAL_BUILD defined by the selected recipe; no Zig Debug parity claim.',
 'preservation':preservation,'seven_tracked_dirty_paths':dirty,'index_empty':True,
 'live_candidate_files_absent':True,'external_input_pins':external,
 'inventory_count_excluding_this_manifest':len(inventory),'inventory':inventory}
out=write_new('manifest.json',manifest)
print(json.dumps({'manifest':out,'analysis':manifest['analysis'],'authority_bindings':binding_pin,
 'inventory_files':len(inventory),'source_body_comparisons':5,'new_candidate_sources':2,'new_translation_units':1,
 'external_inputs':len(external),'preservation':preservation,'source_only':True},indent=2))

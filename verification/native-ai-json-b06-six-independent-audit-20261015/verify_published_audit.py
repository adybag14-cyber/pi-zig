import sys
import pathlib,json,hashlib,subprocess,zipfile,io,re,struct,base64
root=pathlib.Path(__file__).resolve().parent;repo=str(root.parents[1]);head=sys.argv[2] if len(sys.argv)>2 else '5d0ff0bd32a72d4392693552aad7f118a0e0b756';run_id=int(sys.argv[1]) if len(sys.argv)>1 else 38772663750
load=lambda p:json.loads(pathlib.Path(p).read_text(encoding='utf-8-sig'))
def rowsmap(rows):
 out={r['relative']:r['sha256'] for r in rows};assert len(out)==len(rows);return out
def check_inventory(before,after):
 assert after['before_count']==after['after_count']==len(before['rows']) and after['path_drift']==after['hash_drift']==[]
 assert rowsmap(before['rows'])==rowsmap(after['rows']);return len(before['rows'])
def owner_check(owner,timeout):
 assert owner['status']=='passed' and owner['exit_code']==0 and owner['retained_handle'] and owner['timeout_seconds']==timeout
 live=owner['live_identity'];assert live['pid']==owner['pid'] and live['created_utc']==owner['created_utc'] and live['executable'].lower()==owner['executable'].lower()
 assert live['command_line'] and live['command_line_method'] in ['Win32_Process.CommandLine','/proc cmdline exact bytes (base64)','ps command= exact output']
 if live['command_line_method'].startswith('/proc'):assert base64.b64decode(live['command_line'])==b'\0'.join(x.encode() for x in [owner['executable']]+owner['arguments'])+b'\0'
 return owner
run=load(root/(str(run_id)+'-run.json'));assert run['headSha']==head and run['status']=='completed' and run['conclusion']=='success'
assert len(run['jobs'])==7 and all(x['status']=='completed' and x['conclusion']=='success' for x in run['jobs'])
artifacts=load(root/(str(run_id)+'-artifacts.json'))['artifacts'];assert len(artifacts)==7
posix=load(root/(str(run_id)+'-independent-posix-audit.json'));assert posix['status']=='independent_linux_source39_audit_passed' and posix['head']==head
source_art,=[a for a in artifacts if 'posix-reference' in a['name']]
source_raw=(root/(str(source_art['id'])+'.zip')).read_bytes();assert 'sha256:'+hashlib.sha256(source_raw).hexdigest()==source_art['digest']
with zipfile.ZipFile(io.BytesIO(source_raw)) as z:source_payload={n:z.read(n) for n in z.namelist() if not n.endswith('/')}
source_doc=lambda name:json.loads(source_payload[name].decode('utf-8-sig'))
controls=source_doc('controls.json');candidate=rowsmap(controls['candidate']['rows']);assert len(candidate)==5437
# Recompute every candidate hash from the qualified ancestor's Git objects.
entries=[x.split(b'\t',1) for x in subprocess.check_output(['git','-C',repo,'ls-tree','-r','-z',head]).split(b'\0') if x]
p=subprocess.Popen(['git','-C',repo,'cat-file','--batch'],stdin=subprocess.PIPE,stdout=subprocess.PIPE);git_hashes={}
for meta,path in entries:
 oid=meta.split()[2];p.stdin.write(oid+b'\n');p.stdin.flush();header=p.stdout.readline().split();n=int(header[2]);data=p.stdout.read(n);assert p.stdout.read(1)==b'\n';git_hashes[path.decode()]=hashlib.sha256(data).hexdigest().upper()
p.stdin.close();assert p.wait(timeout=10)==0 and candidate==git_hashes
for before,post in [('candidate','controls-posthash.json'),('tracked_reference','source-posthash.json'),('reference','reference-tree-posthash.json'),('temporary_controls','temporary-controls-posthash.json')]:check_inventory(controls[before],source_doc(post))
check_inventory({'rows':source_doc('actual-node-tools.json')},source_doc('node-tools-posthash.json'))
check_inventory({'rows':source_doc('exact-runtime-dependency.json')},source_doc('dependency-posthash.json'))
historical=json.loads(subprocess.check_output(['git','-C',repo,'show',head+':verification/ai-json-final-b06-20261014/sdk-source-b06-full-manifest-20261014.json']));historical_map=rowsmap(historical)
tracked=rowsmap(controls['tracked_reference']['rows']);assert len(historical_map)==1965 and len(tracked)==1922 and all(historical_map[k]==v for k,v in tracked.items())
extras=set(historical_map)-set(tracked);assert len(extras)==43 and all(p.startswith('packages/ai/src/providers/data/') for p in extras)
source_result=source_doc('result.json');assert source_result['status']=='passed' and source_result['original_rows']==39 and source_result['fresh_reference_processes']==4
assert source_result['node_archive_sha256']=='41CD79BB7877C81605A9E68EC4C91547774F46A40C67A17E34D7179EF11729DF'
assert source_result['partial_json_version']=='0.1.7' and source_result['partial_json_integrity']=='sha512-Njv/59hHaokb/hRUjce3Hdv12wd60MtM9Z5Olmn+nehe0QDAsRtRbJPvJ0Z91TusF0SuZRIvnM+S4l6EIP8leA=='
assert 'sha512-'+base64.b64encode(hashlib.sha512((root/'partial-json-0.1.7.tgz').read_bytes()).digest()).decode()==source_result['partial_json_integrity']
identities=set()
for kind,count in [('parse',33),('delegate',6)]:
 golden=json.loads(subprocess.check_output(['git','-C',repo,'show',head+f':src/extensions/fixtures/ai-json-{kind}-b06.json']));raws=[]
 caller=subprocess.check_output(['git','-C',repo,'show',head+f':src/extensions/fixtures/ai-json-{kind}-b06.input.txt']);body=caller.split(b'\n',1)[1]
 for capture in [1,2]:
  stem=f'{kind}-original-{capture}.json';observed=source_doc(stem);owner=owner_check(source_doc(f'{kind}-owner-{capture}.json'),300);raw=source_payload[stem+'.rows.bin']
  assert observed['rows']==json.loads(raw)==golden['rows'] and len(golden['rows'])==count and observed['cases']==count
  assert hashlib.sha256(raw).hexdigest()==observed['rawRowsSha256'] and hashlib.sha256(caller).hexdigest()==observed['originalCallerSha256'] and hashlib.sha256(body).hexdigest()==observed['unchangedCallerBodySha256']
  assert observed['actualNode']['platform']=='linux' and observed['actualNode']['version']=='v24.14.0' and observed['actualNode']['pid']==owner['pid'] and observed['actualNode']['execPath']==owner['executable']
  identities.add((owner['pid'],owner['created_utc']));raws.append(raw)
 assert raws[0]==raws[1]
assert len(identities)==4

expected={}
for kind,stem in [('json','native_ai_json_parse_test'),('http','native_ai_http_test')]:
 source=subprocess.check_output(['git','-C',repo,'show',head+':src/'+stem+'.zig']).decode()
 expected[kind]=[stem+'.test.'+x for x in re.findall(r'^test "([^"]+)"',source,re.M)]+['extensions.native_durable_storage.test_0'];assert len(expected[kind])==6
 assert 'try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});' in source
profiles=[]
for art in artifacts:
 assert art['workflow_run']['head_sha']==head and not art['expired']
 if 'posix-reference' in art['name']:continue
 archive=(root/(str(art['id'])+'.zip')).read_bytes();digest='sha256:'+hashlib.sha256(archive).hexdigest();assert digest==art['digest']
 with zipfile.ZipFile(io.BytesIO(archive)) as z:payload={name:z.read(name) for name in z.namelist() if not name.endswith('/')}
 doc=lambda name:json.loads(payload[name].decode('utf-8-sig'))
 source,result=doc('source.json'),doc('result.json');assert source['head']==result['head']==head and source['product_base']==result['product_base']=='cc9053fbf63f057a63282359f8f49e30a83329e8'
 inputs,tools=doc('inputs.json'),doc('tools.json');assert rowsmap(inputs['rows'])==candidate
 assert check_inventory(inputs,doc('inputs-posthash.json'))==5437;tool_count=check_inventory(tools,doc('tools-posthash.json'))
 assert result['status']=='passed' and result['tests']==12 and result['json_selected']==result['http_selected']==6 and result['original_json_rows']==39 and result['raw_b45_wire_scenarios']==12
 for key in ['global_json_parse_replacement','public_activation','full_provider_qualified','latest_catalog_qualified']:assert result[key] is False
 for phase,timeout,targets in [('compile',1320,['build-native-ai-json-parse','build-native-ai-http']),('runtime',300,['test-native-ai-json-parse','test-native-ai-http'])]:
  owner=owner_check(doc(phase+'.json'),timeout);assert all(t in owner['arguments'] for t in targets)
  assert '-j1' in owner['arguments'] and '-Doptimize='+source['mode'] in owner['arguments'] and '--test-timeout' in owner['arguments'] and '120s' in owner['arguments']
  tool_hashes={x['path']:x['sha256'] for x in tools['rows']};assert tool_hashes[owner['executable']]==owner['executable_sha256']
  if 'Windows' in source['os']:assert owner['executable_sha256']=='086CE9D47BA42F33A514E1A6E04EB1D4A8FA1D75E0868E0213CAAD447C91E864'
 inventories=doc('selected-inventory.json');assert len(inventories)==2 and {x['kind'] for x in inventories}=={'json','http'}
 for index,inventory in enumerate(inventories):
  owner=owner_check(doc(f'inventory-{index}.json'),30);assert owner['arguments']==['--listen=-'] and owner['executable_sha256']==inventory['binary_sha256']
  assert inventory['version']=='0.16.0' and sorted(inventory['tests'])==sorted(expected[inventory['kind']])
  raw=payload[f'inventory-{index}.stdout.bin'];offset=0;tags=[];decoded=None;version=None
  while offset<len(raw):
   tag,size=struct.unpack_from('<II',raw,offset);offset+=8;body=raw[offset:offset+size];assert len(body)==size;offset+=size;tags.append(tag)
   if tag==0:version=body.decode()
   elif tag==3:
    n,count=struct.unpack_from('<II',body);assert count==6 and len(body)==8+8*count+n
    offsets=struct.unpack_from('<'+count*'I',body,8);panics=struct.unpack_from('<'+count*'I',body,8+4*count);assert all(x==0 for x in panics)
    strings=body[8+8*count:];decoded=[strings[o:strings.index(b'\0',o)].decode() for o in offsets]
   else:raise AssertionError('Metadata inventory emitted unit-execution protocol tag '+str(tag))
  assert tags==[0,3] and version=='0.16.0' and decoded==inventory['tests']
 log=payload['runtime.stderr.log'].decode('utf-8-sig').replace('\r\n','\n');assert re.search(r'^Build Summary:.*\b12/12 tests passed',log,re.M)
 for target in ['test-native-ai-json-parse','test-native-ai-http']:assert len(re.findall(r'^'+target+r' success\n[^\n]*run test 6 pass \(6 total\)',log,re.M))==1
 profiles.append(dict(artifact_id=art['id'],artifact=art['name'],zip_digest=digest,mode=source['mode'],os=source['os'],tests=12,json_tests=6,http_tests=6,original_json_rows=39,raw_source_wire_cases=12,candidate_exact_frozen_files=5437,compiler_frozen_files=tool_count,metadata_only_inventory_tags=[0,3],exact_selected_metadata_test_arrays=True,post_inventory_hash_drift=0,compile_and_runtime_exit_codes=[0,0],native_gpa_scope=result['host_gpa']))
assert len(profiles)==6 and len({(p['mode'],p['os']) for p in profiles})==6
assert {p['mode'] for p in profiles}=={'Debug','ReleaseSafe'}
report=dict(run_id=run_id,head=head,product_base='cc9053fbf63f057a63282359f8f49e30a83329e8',status='independent_ai_json39_raw_http_six_profile_audit_passed',genuine_linux_source39_qualified=True,linux_source39_audit=str(root/(str(run_id)+'-independent-posix-audit.json')),profiles=profiles,full_provider_qualified=False,latest_catalog_qualified=False,full_pi_qualified=False,public_activation=False)
recorded=load(root/(str(run_id)+'-independent-complete-audit.json'));assert all(report[k]==recorded[k] for k in report if k!='linux_source39_audit');print(json.dumps({'status':'offline_published_ai_audit_verified','run_id':run_id,'head':head,'genuine_linux_source39_qualified':True,'profiles':6,'tests_per_profile':12,'candidate_files_per_profile':5437,'compiler_files_per_profile':19546,'full_provider_qualified':False,'latest_catalog_qualified':False,'full_pi_qualified':False},indent=2))
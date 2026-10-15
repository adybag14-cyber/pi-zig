import sys
import pathlib,json,hashlib,subprocess,zipfile,io,re,struct,base64
root=pathlib.Path('C:/Users/adyba/pi-zig-update-evidence-20261003/ai-json-ci-qualification-20261015');repo='C:/Users/adyba/pi-zig-ai-json-ci-20261014';head=sys.argv[2] if len(sys.argv)>2 else '5ef07771487d052cfb3b752833e483d4aee83db8';run_id=int(sys.argv[1]) if len(sys.argv)>1 else 38770629459
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
candidate=rowsmap(load(root/(str(run_id)+'-posix-reference')/'controls.json')['candidate']['rows']);assert len(candidate)==5437
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
 directory=root/(str(run_id)+'-download')/art['name']
 with zipfile.ZipFile(io.BytesIO(archive)) as z:
  for name in z.namelist():
   if not name.endswith('/'):assert z.read(name)==(directory/name).read_bytes()
 doc=lambda name:load(directory/name)
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
  raw=(directory/f'inventory-{index}.stdout.bin').read_bytes();offset=0;tags=[];decoded=None;version=None
  while offset<len(raw):
   tag,size=struct.unpack_from('<II',raw,offset);offset+=8;body=raw[offset:offset+size];assert len(body)==size;offset+=size;tags.append(tag)
   if tag==0:version=body.decode()
   elif tag==3:
    n,count=struct.unpack_from('<II',body);assert count==6 and len(body)==8+8*count+n
    offsets=struct.unpack_from('<'+count*'I',body,8);panics=struct.unpack_from('<'+count*'I',body,8+4*count);assert all(x==0 for x in panics)
    strings=body[8+8*count:];decoded=[strings[o:strings.index(b'\0',o)].decode() for o in offsets]
   else:raise AssertionError('Metadata inventory emitted unit-execution protocol tag '+str(tag))
  assert tags==[0,3] and version=='0.16.0' and decoded==inventory['tests']
 log=(directory/'runtime.stderr.log').read_text();assert re.search(r'^Build Summary:.*\b12/12 tests passed',log,re.M)
 for target in ['test-native-ai-json-parse','test-native-ai-http']:assert len(re.findall(r'^'+target+r' success\n[^\n]*run test 6 pass \(6 total\)',log,re.M))==1
 profiles.append(dict(artifact_id=art['id'],artifact=art['name'],zip_digest=digest,mode=source['mode'],os=source['os'],tests=12,json_tests=6,http_tests=6,original_json_rows=39,raw_source_wire_cases=12,candidate_exact_frozen_files=5437,compiler_frozen_files=tool_count,metadata_only_inventory_tags=[0,3],exact_selected_metadata_test_arrays=True,post_inventory_hash_drift=0,compile_and_runtime_exit_codes=[0,0],native_gpa_scope=result['host_gpa']))
assert len(profiles)==6 and len({(p['mode'],p['os']) for p in profiles})==6
assert {p['mode'] for p in profiles}=={'Debug','ReleaseSafe'}
report=dict(run_id=run_id,head=head,product_base='cc9053fbf63f057a63282359f8f49e30a83329e8',status='independent_ai_json39_raw_http_six_profile_audit_passed',genuine_linux_source39_qualified=True,linux_source39_audit=str(root/(str(run_id)+'-independent-posix-audit.json')),profiles=profiles,full_provider_qualified=False,latest_catalog_qualified=False,full_pi_qualified=False,public_activation=False)
(root/(str(run_id)+'-independent-complete-audit.json')).write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
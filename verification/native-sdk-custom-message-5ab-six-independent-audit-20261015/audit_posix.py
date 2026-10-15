import pathlib,json,hashlib,subprocess,zipfile,io,base64,posixpath,tarfile,sys
root=pathlib.Path('C:/Users/adyba/pi-zig-update-evidence-20261003/custom-message-ci-qualification-20261015');repo='C:/Users/adyba/pi-zig-custom-message-ci-20261015';source_repo='C:/Users/adyba/pi-upstream-source-5ab7fe7-20261015'
run_id=int(sys.argv[1]) if len(sys.argv)>1 else 38780046188;head=sys.argv[2] if len(sys.argv)>2 else '0c5dad6539d42617afe0035348c8e3b852069387';source_head='5ab7fe74c400097b386662205cd93900695b8a71'
load=lambda p:json.loads(pathlib.Path(p).read_text(encoding='utf-8-sig'))
def git_file(repo,head,path):return subprocess.check_output(['git','-C',repo,'show',head+':'+path])
def authority(repo,head):
 entries=[x.split(b'\t',1) for x in subprocess.check_output(['git','-C',repo,'ls-tree','-r','-z',head]).split(b'\0') if x];p=subprocess.Popen(['git','-C',repo,'cat-file','--batch'],stdin=subprocess.PIPE,stdout=subprocess.PIPE);out={}
 for meta,path in entries:
  oid=meta.split()[2];p.stdin.write(oid+b'\n');p.stdin.flush();n=int(p.stdout.readline().split()[2]);data=p.stdout.read(n);assert p.stdout.read(1)==b'\n'
  if repo==source_repo and path.decode().endswith(('.bat','.cmd','.ps1')):data=data.replace(b'\r\n',b'\n').replace(b'\n',b'\r\n')
  out[path.decode()]=hashlib.sha256(data).hexdigest().upper()
 p.stdin.close();assert p.wait(timeout=10)==0;return out
def rowsmap(rows):
 out={r['relative']:r['sha256'] for r in rows};assert len(out)==len(rows);return out
def inventory(before,after):
 assert after['before_count']==after['after_count']==len(before['rows']) and after['path_drift']==after['hash_drift']==[] and rowsmap(before['rows'])==rowsmap(after['rows']);return len(before['rows'])
def owner_check(owner,timeout,intended_argv=True):
 assert owner['status']=='passed' and owner['exit_code']==0 and owner['retained_handle'] and owner['timeout_seconds']==timeout
 live=owner['live_identity'];assert live['pid']==owner['pid'] and live['created_utc']==owner['created_utc'] and live['executable']==owner['executable'] and live['command_line_method']=='/proc cmdline exact bytes (base64)'
 raw=base64.b64decode(live['command_line']);assert raw
 if intended_argv:assert raw==b'\0'.join(x.encode() for x in [owner['executable']]+owner['arguments'])+b'\0'
 else:assert raw.rstrip(b'\0')==b'npm ci' or raw==b'\0'.join(x.encode() for x in [owner['executable']]+owner['arguments'])+b'\0'
 return owner
artifacts=load(root/(str(run_id)+'-artifacts-initial.json'))['artifacts'];art,=[a for a in artifacts if a['name']=='native-sdk-custom-message-posix-'+head]
archive_path=root/(str(art['id'])+'.zip')
if not archive_path.exists():archive_path.write_bytes(subprocess.check_output(['gh','api',f"repos/adybag14-cyber/pi-zig/actions/artifacts/{art['id']}/zip"]))
archive=archive_path.read_bytes();assert 'sha256:'+hashlib.sha256(archive).hexdigest()==art['digest'] and art['workflow_run']['head_sha']==head
folder=root/(str(run_id)+'-posix-reference')
with zipfile.ZipFile(io.BytesIO(archive)) as z:
 for name in z.namelist():
  if not name.endswith('/'):assert z.read(name)==(folder/name).read_bytes()
doc=lambda name:load(folder/name)
inputs,result=doc('inputs.json'),doc('result.json');candidate=authority(repo,head);source=authority(source_repo,source_head)
assert len(candidate)==5611 and len(source)==1924 and rowsmap(inputs['candidate_controls']['rows'])==candidate
historical=json.loads(git_file(repo,head,'tools/ci/custom-message-reference/source5ab-full-manifest.json'));historical_map=rowsmap(historical);assert len(historical_map)==1967
assert all(historical_map[k]==v for k,v in source.items())
generated=set(historical_map)-set(source);assert len(generated)==43 and all(k.startswith('packages/ai/src/providers/data/') for k in generated)
provider_archive=git_file(repo,head,'tools/ci/custom-message-reference/frozen-provider-data.zip')
with zipfile.ZipFile(io.BytesIO(provider_archive)) as z:assert set(z.namelist())==generated and all(hashlib.sha256(z.read(k)).hexdigest().upper()==historical_map[k] for k in generated)
assert rowsmap(inputs['original_source_rows'])==historical_map
counts={}
for name,before,after in [('source_dependencies_links',inputs['full_source_dependencies_and_links'],'reference-posthash.json'),('candidate',inputs['candidate_controls'],'candidate-posthash.json'),('node_tools',inputs['official_node_tools'],'node-tools-posthash.json'),('temporary_controls',inputs['temporary_controls'],'temporary-controls-posthash.json')]:counts[name]=inventory(before,doc(after))
reference=inputs['full_source_dependencies_and_links'];source_root=reference['root'];files={r['path']:r['sha256'] for r in reference['rows'] if r['kind']=='file'};links=[r for r in reference['rows'] if r['kind']=='link']
assert len(reference['rows'])==len(files)+len(links) and all(r['resolved_target'].startswith(source_root+'/') for r in links)
for link in links:
 assert hashlib.sha256((link['link_target']+'\n'+link['resolved_target']).encode()).hexdigest().upper()==link['sha256']
 assert posixpath.normpath(posixpath.join(posixpath.dirname(link['path']),link['link_target']))==link['resolved_target']
for path,value in historical_map.items():assert files[source_root+'/'+path]==value
node_archive=pathlib.Path('C:/Users/adyba/pi-zig-update-evidence-20261003/ai-json-ci-qualification-20261015/node-v24.14.0-linux-x64.tar.xz').read_bytes()
assert hashlib.sha256(node_archive).hexdigest().upper()=='41CD79BB7877C81605A9E68EC4C91547774F46A40C67A17E34D7179EF11729DF'
with tarfile.open(fileobj=io.BytesIO(node_archive),mode='r:xz') as tar:node_files={m.name.removeprefix('node-v24.14.0-linux-x64/'):hashlib.sha256(tar.extractfile(m).read()).hexdigest().upper() for m in tar.getmembers() if m.isfile() or m.issym() or m.islnk()}
assert rowsmap(inputs['official_node_tools']['rows'])==node_files
install=owner_check(doc('install-exact-locked-dependencies.json'),300,False);assert all(a in install['arguments'] for a in ['ci','--ignore-scripts','--no-audit','--no-fund']) and install['executable_sha256']==node_files['bin/node']
contract=json.loads(git_file(repo,head,'tools/ci/custom-message-reference/official-workspace-contract.json'));assert contract['source_head']==source_head and len(contract['workspaces'])==16
assert contract['lock_sha256']==source['package-lock.json']
for workspace in contract['workspaces']:
 package=json.loads(git_file(source_repo,source_head,workspace['path']+'/package.json'));assert package['name']==workspace['packageName'] and package['version']==workspace['version'] and package.get('exports')==workspace['exports'] and package.get('main')==workspace['main']
golden=json.loads(git_file(repo,head,'src/extensions/fixtures/sdk-custom-message-5ab.json'));caller=git_file(repo,head,'src/extensions/fixtures/sdk-custom-message-5ab.input.txt')
assert len(golden['rows'])==40 and len(golden['descriptors'])==3 and hashlib.sha256(caller).hexdigest()==golden['inputSha256']
allowed=files|{r['path']:r['sha256'] for r in inputs['candidate_controls']['rows']};identities=set();captures=[];raws=[]
for number in (1,2):
 owner=owner_check(doc(f'owner-{number}.json'),300);observed=doc(f'original-{number}.json');closure=doc(f'closure-{number}.json');raw=(folder/f'original-{number}.json.rows.bin').read_bytes()
 assert observed['matchedOriginal'] is True and observed['sourceHead']==source_head and observed['cases']==40
 assert observed['rows']==golden['rows'] and observed['descriptors']==golden['descriptors'] and json.loads(raw)=={'descriptors':golden['descriptors'],'rows':golden['rows']}
 assert hashlib.sha256(raw).hexdigest()==observed['rawSha256'] and observed['inputSha256']==golden['inputSha256']
 actual=observed['actualNode'];assert actual['version']=='v24.14.0' and actual['platform']=='linux' and actual['arch']=='x64' and actual['pid']==owner['pid'] and actual['executable']==owner['executable'] and owner['executable_sha256']==node_files['bin/node']
 assert closure['source_head']==source_head and closure['exit_code']==0 and closure['unchanged_default_loader'] is True and closure['post_drift']==[] and closure['node']['pid']==owner['pid']
 loaded=[r for r in closure['records'] if r['kind']=='unchanged-default-module'];assert len({r['path'] for r in loaded})==len(loaded)
 assert all(allowed.get(r['path'])==r['file_sha256'] for r in loaded)
 assert len([r for r in loaded if r['path']==source_root+'/packages/coding-agent/src/core/agent-session.ts'])==1
 assert all(mapping['path'].startswith(source_root+'/packages/') and mapping['path'] in files for mapping in closure['workspace_mappings'])
 original,=[r for r in closure['records'] if r['kind']=='unchanged-original-caller'];assert original['sha256']==hashlib.sha256(caller).hexdigest().upper()
 assert closure['observer_sha256']==candidate['tools/ci/custom-message-reference/observe-latest-source.mjs']
 temporary=rowsmap(inputs['temporary_controls']['rows']);assert closure['manifest_sha256']==temporary['frozen-modules.json']
 identities.add((owner['pid'],owner['created_utc']));raws.append(raw);captures.append({'capture':number,'pid':owner['pid'],'created_utc':owner['created_utc'],'cases':40,'descriptors':3,'raw_sha256':observed['rawSha256'],'loaded_default_modules':len(loaded),'workspace_mappings':len(closure['workspace_mappings']),'matched_windows_original':True})
assert len(identities)==2 and raws[0]==raws[1]
assert result['status']=='passed' and result['source_head']==source_head and result['source_files']==1967 and result['tracked_source_files']==1924 and result['frozen_typed_catalog_files']==43 and result['fresh_reference_processes']==2 and result['source_cases']==40
for flag in ['full_factory_qualified','latest_catalog_qualified','full_pi_qualified','public_activation']:assert result[flag] is False
report={'status':'independent_genuine_linux_custom_message40_audit_passed','run_id':run_id,'head':head,'source_head':source_head,'artifact_id':art['id'],'zip_digest':art['digest'],'source_checkout_eol_authority':'Official .gitattributes CRLF only for Windows script files; remaining source blobs unchanged','source_files':1967,'tracked_source_files':1924,'frozen_typed_catalog_files':43,'latest_catalog_qualified':False,'inventories':counts,'reference_links':len(links),'official_node_version':'v24.14.0','all_node_files_match_official_archive':True,'exact_source_lock_npm_ci_passed':True,'npm_install_raw_process_title_preserved':base64.b64decode(install['live_identity']['command_line']).rstrip(b'\0').decode(errors='replace'),'captures':captures,'raw_double_capture_equal':True,'both_match_original_windows40_rows_and_descriptors':True,'all_post_inventory_hash_drift':0,'genuine_linux_source40_qualified':True,'full_factory_qualified':False,'full_pi_qualified':False,'public_activation':False}
(root/(str(run_id)+'-independent-posix-audit.json')).write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
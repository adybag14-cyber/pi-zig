import sys
import pathlib,json,hashlib,subprocess,base64,zipfile,io,urllib.parse,urllib.request,tarfile
root=pathlib.Path('C:/Users/adyba/pi-zig-update-evidence-20261003/ai-json-ci-qualification-20261015')
repo='C:/Users/adyba/pi-zig-ai-json-ci-20261014';source_repo='C:/Users/adyba/pi-upstream-source-b06c1f2-20261014'
head=sys.argv[2] if len(sys.argv)>2 else '5ef07771487d052cfb3b752833e483d4aee83db8';source_head='b06c1f2cf1dea6af8748ddeee18c23587d2cb7c6';run_id=int(sys.argv[1]) if len(sys.argv)>1 else 38770629459
def git_file(repo,head,path):return subprocess.check_output(['git','-C',repo,'show',head+':'+path])
def authority(repo,head):
 entries=[x.split(b'\t',1) for x in subprocess.check_output(['git','-C',repo,'ls-tree','-r','-z',head]).split(b'\0') if x]
 p=subprocess.Popen(['git','-C',repo,'cat-file','--batch'],stdin=subprocess.PIPE,stdout=subprocess.PIPE);out={}
 for meta,path in entries:
  mode,kind,oid=meta.split();assert kind==b'blob'
  p.stdin.write(oid+b'\n');p.stdin.flush();header=p.stdout.readline().split();n=int(header[2]);data=p.stdout.read(n);assert p.stdout.read(1)==b'\n'
  # Apply official b06 .gitattributes checkout EOL only to Windows script paths.
  if repo==source_repo and path.decode().endswith(('.bat','.cmd','.ps1')):data=data.replace(b'\r\n',b'\n').replace(b'\n',b'\r\n')
  out[path.decode()]=hashlib.sha256(data).hexdigest().upper()
 p.stdin.close();assert p.wait(timeout=10)==0
 return out
def rowsmap(rows):
 result={row['relative']:row['sha256'] for row in rows};assert len(result)==len(rows);return result
def inventory_pair(before,post):
 assert post['before_count']==post['after_count']==len(before['rows'])
 assert post['path_drift']==post['hash_drift']==[]
 assert rowsmap(before['rows'])==rowsmap(post['rows'])
 return len(before['rows'])
arts=json.loads((root/(str(run_id)+'-artifacts-initial.json')).read_text(encoding='utf-8-sig'))['artifacts']
art,= [x for x in arts if x['name']=='native-ai-json-b06-posix-reference-'+head]
assert art['workflow_run']['head_sha']==head
archive=subprocess.check_output(['gh','api',f"repos/adybag14-cyber/pi-zig/actions/artifacts/{art['id']}/zip"])
assert 'sha256:'+hashlib.sha256(archive).hexdigest()==art['digest'];(root/(str(art['id'])+'.zip')).write_bytes(archive)
directory=root/(str(run_id)+'-posix-reference')
with zipfile.ZipFile(io.BytesIO(archive)) as z:
 for name in z.namelist():
  if not name.endswith('/'):assert z.read(name)==(directory/name).read_bytes()
doc=lambda name:json.loads((directory/name).read_text(encoding='utf-8-sig'))
assert b'*.bat text eol=crlf' in git_file(source_repo,source_head,'.gitattributes') and b'*.ps1 text eol=crlf' in git_file(source_repo,source_head,'.gitattributes')
controls=doc('controls.json');candidate=authority(repo,head);source=authority(source_repo,source_head)
assert len(source)==1922 and rowsmap(controls['candidate']['rows'])==candidate
assert rowsmap(controls['tracked_reference']['rows'])==source
historical=json.loads(git_file(repo,head,'verification/ai-json-final-b06-20261014/sdk-source-b06-full-manifest-20261014.json'))
historical_map=rowsmap(historical);assert len(historical_map)==1965
assert all(historical_map[k]==v for k,v in source.items())
extras=set(historical_map)-set(source);assert len(extras)==43 and all(x.startswith('packages/ai/src/providers/data/') for x in extras)
counts={}
for kind,before,post in [('candidate',controls['candidate'],'controls-posthash.json'),('tracked_reference',controls['tracked_reference'],'source-posthash.json'),('reference_tree',controls['reference'],'reference-tree-posthash.json'),('temporary_controls',controls['temporary_controls'],'temporary-controls-posthash.json')]:counts[kind]=inventory_pair(before,doc(post))
node_rows=doc('actual-node-tools.json');package_rows=doc('exact-runtime-dependency.json')
counts['node_tools']=inventory_pair({'rows':node_rows},doc('node-tools-posthash.json'))
counts['dependency']=inventory_pair({'rows':package_rows},doc('dependency-posthash.json'))
assert counts['dependency']==9 and counts['reference_tree']==1922+9
reference_map=rowsmap(controls['reference']['rows'])
assert {k:v for k,v in reference_map.items() if not k.startswith('node_modules/')}==source
assert {k.removeprefix('node_modules/partial-json/'):v for k,v in reference_map.items() if k.startswith('node_modules/partial-json/')}==rowsmap(package_rows)
lock=json.loads(git_file(source_repo,source_head,'package-lock.json'));pin=lock['packages']['node_modules/partial-json']
assert pin['version']=='0.1.7' and pin['resolved']=='https://registry.npmjs.org/partial-json/-/partial-json-0.1.7.tgz'

package_archive_path=root/'partial-json-0.1.7.tgz'
if not package_archive_path.exists():package_archive_path.write_bytes(urllib.request.urlopen(pin['resolved'],timeout=120).read())
package_archive=package_archive_path.read_bytes()
assert 'sha512-'+base64.b64encode(hashlib.sha512(package_archive).digest()).decode()==pin['integrity']
temporary_map=rowsmap(controls['temporary_controls']['rows'])
assert hashlib.sha256(package_archive).hexdigest().upper()==temporary_map['partial-json.tgz']
with tarfile.open(fileobj=io.BytesIO(package_archive),mode='r:gz') as tar:
 actual_package={member.name.removeprefix('package/'):hashlib.sha256(tar.extractfile(member).read()).hexdigest().upper() for member in tar.getmembers() if member.isfile()}
assert actual_package==rowsmap(package_rows)

result=doc('result.json');assert result['status']=='passed' and result['source_head']==source_head and result['original_rows']==39 and result['fresh_reference_processes']==4
assert result['partial_json_integrity']==pin['integrity'] and result['partial_json_version']=='0.1.7'
assert result['node_archive_sha256']=='41CD79BB7877C81605A9E68EC4C91547774F46A40C67A17E34D7179EF11729DF'

node_archive_path=root/'node-v24.14.0-linux-x64.tar.xz'
if not node_archive_path.exists():node_archive_path.write_bytes(urllib.request.urlopen('https://nodejs.org/dist/v24.14.0/node-v24.14.0-linux-x64.tar.xz',timeout=120).read())
node_archive=node_archive_path.read_bytes()
assert hashlib.sha256(node_archive).hexdigest().upper()==result['node_archive_sha256']==temporary_map['node-v24.14.0-linux-x64.tar.xz']
with tarfile.open(fileobj=io.BytesIO(node_archive),mode='r:xz') as tar:
 actual_node={member.name.removeprefix('node-v24.14.0-linux-x64/'):hashlib.sha256(tar.extractfile(member).read()).hexdigest().upper() for member in tar.getmembers() if member.isfile() or member.issym() or member.islnk()}
assert actual_node==rowsmap(node_rows)
assert actual_node['bin/node']==result['node_executable_sha256']

assert result['node_version']=='v24.14.0' and result['node_tool_files']==counts['node_tools'] and result['tracked_source_files']==1922
assert result['historical_typed_catalog_files_used']==0 and result['latest_catalog_qualified'] is False and result['global_activation'] is False
captures=[];identities=set()
for kind,count in [('parse',33),('delegate',6)]:
 raw_captures=[];golden=json.loads(git_file(repo,head,f'src/extensions/fixtures/ai-json-{kind}-b06.json'))
 caller=git_file(repo,head,f'src/extensions/fixtures/ai-json-{kind}-b06.input.txt');body=caller.split(b'\n',1)[1]
 for capture in (1,2):
  stem=f'{kind}-original-{capture}.json';observed=doc(stem);owner=doc(f'{kind}-owner-{capture}.json');raw=(directory/(stem+'.rows.bin')).read_bytes()
  assert owner['status']=='passed' and owner['exit_code']==0 and owner['retained_handle'] and owner['timeout_seconds']==300
  live=owner['live_identity'];assert live['pid']==owner['pid'] and live['executable']==owner['executable'] and live['created_utc']==owner['created_utc']
  assert live['command_line_method']=='/proc cmdline exact bytes (base64)'
  assert base64.b64decode(live['command_line'])==b'\0'.join(s.encode() for s in [owner['executable']]+owner['arguments'])+b'\0'
  assert owner['executable_sha256']==result['node_executable_sha256']
  node=observed['actualNode'];assert node['version']=='v24.14.0' and node['platform']=='linux' and node['arch']=='x64' and node['pid']==owner['pid'] and node['execPath']==owner['executable']
  identities.add((owner['pid'],owner['created_utc']))
  assert observed['sourceHead']==source_head and observed['cases']==count and observed['matchedOriginal'] is True
  assert json.loads(raw)==observed['rows']==golden['rows'] and len(golden['rows'])==count
  assert hashlib.sha256(raw).hexdigest()==observed['rawRowsSha256']
  assert hashlib.sha256(caller).hexdigest()==observed['originalCallerSha256']==golden['callerSha256']
  assert hashlib.sha256(body).hexdigest()==observed['unchangedCallerBodySha256']
  source_root=owner['arguments'][4];target=source_root+'/packages/ai/src/utils/json-parse.ts';url='file://'+urllib.parse.quote(target,safe='/')
  adapted=('import * as api from '+json.dumps(url)+';\n').encode()+body
  assert hashlib.sha256(adapted).hexdigest()==observed['adaptedImportCallerSha256']
  loaded=[item['url'] for item in observed['loaded'] if 'url' in item]
  assert url in loaded and any(x.endswith('/node_modules/partial-json/dist/index.js') for x in loaded)
  assert all(x.startswith('file://'+source_root+'/') for x in loaded)
  raw_captures.append(raw);captures.append(dict(kind=kind,capture=capture,cases=count,pid=owner['pid'],created_utc=owner['created_utc'],raw_sha256=hashlib.sha256(raw).hexdigest(),windows_original_rows_equal=True,unchanged_caller_body_sha256=observed['unchangedCallerBodySha256'],source_and_dependency_resolution_contained=True,owner_exit_code=0))
 assert raw_captures[0]==raw_captures[1]
 comparison=doc(kind+'-double-capture.json');assert comparison['raw_equal'] is True and comparison['both_equal_original_windows_rows'] is True and comparison['cases']==count
assert len(identities)==4
report=dict(run_id=run_id,head=head,status='independent_linux_source39_audit_passed',artifact_id=art['id'],zip_digest=art['digest'],source_head=source_head,source_checkout_eol_authority='Official .gitattributes CRLF for Windows script paths; other source blobs unchanged',node_version='v24.14.0',node_arch='linux-x64',node_executable_sha256=result['node_executable_sha256'],official_node_archive_sha256=result['node_archive_sha256'],official_node_archive_independently_verified=True,all_node_files_match_official_archive=True,locked_partial_json_version='0.1.7',locked_partial_json_sha512=pin['integrity'],locked_partial_json_archive_sha512_independently_verified=True,all_dependency_files_match_locked_tarball=True,inventories=counts,historical_rows=1965,historical_generated_provider_data_extras=43,captures=captures,total_cases=39,raw_double_capture_equal=True,both_equal_windows_original39=True,all_post_inventory_hash_drift=0,genuine_linux_source39_qualified=True,full_provider_qualified=False,latest_catalog_qualified=False,full_pi_qualified=False,public_activation=False)
(root/(str(run_id)+'-independent-posix-audit.json')).write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
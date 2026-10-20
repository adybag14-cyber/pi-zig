from pathlib import Path
import hashlib,json,re,sys,urllib.request,concurrent.futures,datetime
own=Path(r'C:\Users\adyba\pi-zig/worktrees/modules-io-resume-20261018')
packet=own/'verification/native-node-tracing-platform-sourceonly-20261020'
old=own/'verification/native-node-tracing-sourceonly-20261020'
revision='def0bdf8abee441cfcbf793a8dc24a6f3b899573'
urlbase='https://raw.githubusercontent.com/nodejs/node/'+revision+'/'
abslprefix='deps/v8/third_party/abseil-cpp/'
vendor=own/'vendor/node-v24.13.0/abseil-cpp'
def sha(b):return hashlib.sha256(b).hexdigest().upper()
def save_new(p,b):
 p.parent.mkdir(parents=True,exist_ok=True)
 if p.exists():assert p.read_bytes()==b,('existing file differs',str(p))
 else:p.write_bytes(b)
def now():return datetime.datetime.now(datetime.timezone.utc).isoformat()
if sys.argv[1]=='prepare':
 g=old/'authority/abseil-initial/tools__v8_gypfiles__abseil.gyp';raw=g.read_bytes()
 assert sha(raw)=='827CCF3AC3DD6E5B5094B4D199EB332EC75ABE478E6B4C7EA150A23221AA3C40'
 rels=re.findall(r"'<\(ABSEIL_ROOT\)/(.*?)'",raw.decode())
 assert len(rels)==349 and len(set(rels))==349 and sum(x.endswith('.cc') for x in rels)==110
 known={}
 plan=json.loads((old/'abseil-initial-acquisition-plan.json').read_text())
 for x in plan['files']:
  if urlbase+abslprefix in x['url']:
   path=old/'authority/abseil-initial'/x['path'];b=path.read_bytes()
   assert sha(b)==x['sha256']
   known[x['url'].split(urlbase+abslprefix)[1]]={'original_source':str(path),'sha256':sha(b),'bytes':len(b)}
 plan=json.loads((old/'authority/abseil-thread-identity/acquisition.json').read_text())
 for x in plan['files']:
  path=Path(x['local_path']);b=path.read_bytes();assert sha(b)==x['sha256']
  known[x['url'].split(urlbase+abslprefix)[1]]={'original_source':str(path),'sha256':sha(b),'bytes':len(b)}
 rels.append('LICENSE')
 entries=[]
 for rel in rels:
  assert '..' not in Path(rel).parts and not Path(rel).is_absolute()
  entry={'relative_path':rel,'url':urlbase+abslprefix+rel}
  entry.update(known.get(rel,{}));entries.append(entry)
 save_new(packet/'authority/tools__v8_gypfiles__abseil.gyp',raw)
 d={'kind':'Exact Node Abseil source cohort transfer; no generated source','revision':revision,'source_only':True,'source_membership_authority':{'path':str(g),'sha256':sha(raw)},'gyp_members':349,'cpp_units':110,'license_files':1,'vendor_root':str(vendor),'max_file_bytes':1048576,'max_batch_files':24,'network_concurrency':8,'network_timeout_seconds':15,'files':entries,'reusable_originals':sum('original_source' in x for x in entries),'compiler':False,'native_execution':False}
 save_new(packet/'abseil-acquisition-plan.json',(json.dumps(d,indent=2)+'\n').encode())
 print(json.dumps({'files':len(entries),'cpp':110,'reused':d['reusable_originals'],'plan_sha256':sha((packet/'abseil-acquisition-plan.json').read_bytes())}))
elif sys.argv[1]=='fetch':
 kind=sys.argv[2];start=int(sys.argv[3]);count=int(sys.argv[4]);attempt=int(sys.argv[5]) if len(sys.argv)>5 else 1
 assert 1<=count<=24 and start>=0
 planfile=packet/('abseil-acquisition-plan.json' if kind=='abseil' else 'platform-authority-plan.json')
 plan=json.loads(planfile.read_text());selected=plan['files'][start:start+count]
 assert selected
 destroot=vendor if kind=='abseil' else packet/'authority'
 def take(x):
  item=dict(x);item['recorded_utc']=now()
  try:
   if 'original_source' in x:
    b=Path(x['original_source']).read_bytes();item['method']='reuse_pinned_original_bytes'
   else:
    assert x['url'].startswith(urlbase)
    req=urllib.request.Request(x['url'],headers={'User-Agent':'pi-zig-source-only-acquisition','Accept':'text/plain'})
    with urllib.request.urlopen(req,timeout=15) as response:
     assert response.status==200
     b=response.read(1048577);assert len(b)<=1048576
     item['final_url']=response.url;item['http_status']=response.status
    item['method']='bounded_https_original_source_bytes'
   actual=sha(b)
   if x.get('sha256'):assert actual==x['sha256'],(actual,x['sha256'])
   path=destroot/x['relative_path']
   save_new(path,b)
   item.update({'path':str(path),'bytes':len(b),'sha256':actual,'ok':True})
  except Exception as error:
   item.update({'ok':False,'error':str(error)})
  return item
 with concurrent.futures.ThreadPoolExecutor(max_workers=8) as executor:records=list(executor.map(take,selected))
 record={'kind':'Original source transfer only','cohort':kind,'revision':revision,'plan_sha256':sha(planfile.read_bytes()),'start':start,'count':len(selected),'attempt':attempt,'records':records,'compiler':False,'native_execution':False}
 dest=packet/'acquisition'/f'{kind}-{start:03d}-{start+len(selected)-1:03d}-attempt{attempt}.json'
 save_new(dest,(json.dumps(record,indent=2)+'\n').encode())
 failed=[x for x in records if not x['ok']]
 print(json.dumps({'cohort':kind,'start':start,'count':len(records),'success':len(records)-len(failed),'bytes':sum(x.get('bytes',0) for x in records if x['ok']),'receipt':str(dest),'receipt_sha256':sha(dest.read_bytes()),'failures':failed},indent=2))
 if failed:sys.exit(1)
else:raise RuntimeError('unknown acquisition action')

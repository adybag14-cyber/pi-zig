from pathlib import Path
import concurrent.futures,datetime,hashlib,json,urllib.request
own=Path(r'C:\Users\adyba\pi-zig\worktrees\modules-io-resume-20261018')
packet=own/'verification/native-node-tracing-platform-sourceonly-20261020'
planpath=packet/'build-authority-acquisition-plan.json'
plan=json.loads(planpath.read_text())
def sha(b):return hashlib.sha256(b).hexdigest().upper()
def save_new(p,b):
 p.parent.mkdir(parents=True,exist_ok=True)
 if p.exists():assert p.read_bytes()==b,('existing differs',str(p))
 else:p.write_bytes(b)
def take(x):
 item=dict(x)
 try:
  request=urllib.request.Request(x['url'],headers={'User-Agent':'pi-zig-source-only-acquisition','Accept':'text/plain'})
  with urllib.request.urlopen(request,timeout=15) as response:
   assert response.status==200
   b=response.read(1048577)
   assert len(b)<=1048576 and sha(b)==x['sha256'] and len(b)==x['bytes']
  dest=packet/x['relative_path'];save_new(dest,b)
  item.update({'path':str(dest),'ok':True})
 except Exception as error:item.update({'ok':False,'error':str(error)})
 return item
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as ex:records=list(ex.map(take,plan['files']))
d={'kind':'Original source acquisition only','recorded_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'plan_sha256':sha(planpath.read_bytes()),'records':records,'compiler':False,'native_execution':False,'source_generator':False}
dest=packet/'acquisition/build-authority-attempt1.json';save_new(dest,(json.dumps(d,indent=2)+'\n').encode())
print(json.dumps({'success':sum(x['ok'] for x in records),'files':len(records),'sha256':sha(dest.read_bytes()),'failures':[x for x in records if not x['ok']]},indent=2))
assert all(x['ok'] for x in records)

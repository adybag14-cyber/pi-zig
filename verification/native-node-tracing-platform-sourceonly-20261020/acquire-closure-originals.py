from pathlib import Path
import concurrent.futures,datetime,hashlib,json,urllib.request
own=Path(r'C:\Users\adyba\pi-zig\worktrees\modules-io-resume-20261018')
packet=own/'verification/native-node-tracing-platform-sourceonly-20261020'
planpath=packet/'closure-acquisition-plan.json'
plan=json.loads(planpath.read_text())
def sha(b):return hashlib.sha256(b).hexdigest().upper()
def save_new(p,b):
 p.parent.mkdir(parents=True,exist_ok=True)
 if p.exists():assert p.read_bytes()==b,('existing source differs',str(p))
 else:p.write_bytes(b)
def take(x):
 item=dict(x)
 try:
  request=urllib.request.Request(x['url'],headers={'User-Agent':'pi-zig-source-only-acquisition','Accept':'text/plain'})
  with urllib.request.urlopen(request,timeout=15) as response:
   assert response.status==200
   b=response.read(1048577)
   assert len(b)<=1048576 and sha(b)==x['sha256'] and len(b)==x['bytes']
   item.update({'http_status':response.status,'final_url':response.url})
  dest=own/x['relative_path'];save_new(dest,b)
  item.update({'path':str(dest),'ok':True,'recorded_utc':datetime.datetime.now(datetime.timezone.utc).isoformat()})
 except Exception as error:item.update({'ok':False,'error':str(error)})
 return item
with concurrent.futures.ThreadPoolExecutor(max_workers=5) as ex:records=list(ex.map(take,plan['files']))
receipt={'kind':'Raw original source byte acquisition only','plan_sha256':sha(planpath.read_bytes()),'records':records,'compiler':False,'native_execution':False,'source_generator':False}
dest=packet/'acquisition/closure-000-004-attempt1.json'
save_new(dest,(json.dumps(receipt,indent=2)+'\n').encode())
print(json.dumps({'success':sum(x['ok'] for x in records),'files':len(records),'receipt':str(dest),'sha256':sha(dest.read_bytes()),'failures':[x for x in records if not x['ok']]},indent=2))
assert all(x['ok'] for x in records)

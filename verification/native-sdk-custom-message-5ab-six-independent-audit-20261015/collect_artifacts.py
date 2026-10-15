import pathlib,json,hashlib,subprocess,zipfile,io,sys
root=pathlib.Path('C:/Users/adyba/pi-zig-update-evidence-20261003/custom-message-ci-qualification-20261015')
run_id=int(sys.argv[1]);head=sys.argv[2]
raw=subprocess.check_output(['gh','api',f'repos/adybag14-cyber/pi-zig/actions/runs/{run_id}/artifacts']);(root/(str(run_id)+'-artifacts.json')).write_bytes(raw);artifacts=json.loads(raw)['artifacts'];rows=[]
for artifact in artifacts:
 assert artifact['workflow_run']['head_sha']==head and artifact['name'].endswith('-'+head) and not artifact['expired']
 archive_path=root/(str(artifact['id'])+'.zip')
 if not archive_path.exists():archive_path.write_bytes(subprocess.check_output(['gh','api',f"repos/adybag14-cyber/pi-zig/actions/artifacts/{artifact['id']}/zip"]))
 rawzip=archive_path.read_bytes();digest='sha256:'+hashlib.sha256(rawzip).hexdigest();assert digest==artifact['digest']
 if '-posix-' not in artifact['name']:
  target=root/(str(run_id)+'-download')/artifact['name'];target.mkdir(parents=True,exist_ok=True)
  with zipfile.ZipFile(io.BytesIO(rawzip)) as z:
   names=[name for name in z.namelist() if not name.endswith('/')];assert len(names)==len(set(names)) and all('/' not in name and '\\' not in name and '..' not in name for name in names)
   for name in names:
    p=target/name;data=z.read(name)
    if p.exists():assert p.read_bytes()==data
    else:p.write_bytes(data)
 rows.append({'artifact_id':artifact['id'],'name':artifact['name'],'zip_sha256':digest,'zip_bytes':len(rawzip)})
(root/(str(run_id)+'-collected-artifacts.json')).write_text(json.dumps({'run_id':run_id,'head':head,'available_artifact_count':len(rows),'status':'available_raw_artifacts_collected_and_digest_verified','artifacts':rows},indent=2)+'\n');print(json.dumps({'run_id':run_id,'available_artifact_count':len(rows),'digests_verified':True}))
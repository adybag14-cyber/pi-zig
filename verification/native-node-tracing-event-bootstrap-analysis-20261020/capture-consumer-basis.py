"""Read-only source capture into this new evidence packet. No compiler or native program."""
from pathlib import Path
import hashlib,json,subprocess
P=Path(__file__).parent
M=Path(r'C:\Users\adyba\pi-zig\main')
S=Path(r'C:\Users\adyba\pi-zig\worktrees\sdk-owners-resume-20261018')
def h(b): return hashlib.sha256(b).hexdigest().upper()
def head(path):
 return subprocess.check_output(['git','-C',str(path),'rev-parse','HEAD'],text=True).strip()
basis=head(M)
selections=[
 ('main','src/extensions/native_node_async_wrap_make_callback.zig',M/'src/extensions/native_node_async_wrap_make_callback.zig','972B9D098E93A138A8F6333CDAD829CAFE4D6E6855B2E1811B4623F57E39FCA2'),
 ('main','src/extensions/native_node_async_wrap_state.zig',M/'src/extensions/native_node_async_wrap_state.zig',None),
 ('main','src/extensions/native_node_file_handle_read.zig',M/'src/extensions/native_node_file_handle_read.zig',None),
 ('main','src/extensions/native_process.zig',M/'src/extensions/native_process.zig',None),
 ('main','src/extensions/engine.zig',M/'src/extensions/engine.zig',None),
 ('sdk-owner-projected','src/extensions/native_node_async_wrap_state.zig',S/'verification/native-file-handle-owner-sourceonly-20261020/shared/projected/src/extensions/native_node_async_wrap_state.zig','48429726BE834396EFB669ABA15C90940CB024D3A2095DF27D1C4BA8CB297CE1'),
 ('sdk-owner-projected','src/extensions/native_node_callback_scope.zig',S/'verification/native-file-handle-owner-sourceonly-20261020/shared/projected/src/extensions/native_node_callback_scope.zig','E7F27B5E240664B1B24664B2B4AB406979D0467B27917EE9F50B3F675C711D6E'),
 ('sdk-close-projected','src/extensions/native_node_file_handle_close_request.zig',S/'verification/native-file-handle-close-settlement-followup-sourceonly-20261020/projected/src/extensions/native_node_file_handle_close_request.zig','C2016812A084329BCFC9DC113485F2732B2CC095C9ED6B8B21A18158205C443A'),
 ('sdk-owner-production','src/extensions/native_node_file_handle_gc_close.zig',S/'verification/native-file-handle-owner-sourceonly-20261020/production/src/extensions/native_node_file_handle_gc_close.zig','86E1100598B32022BB38D2DDAD2ABF904C061E915EC0E955C9CAE62B371B83F4')]
records=[]
loaded=[]
for group,rel,src,expected in selections:
 b=src.read_bytes()
 if expected: assert h(b)==expected,(str(src),h(b),expected)
 dst=P/'consumer-basis'/group/rel
 assert not dst.exists(),str(dst)
 loaded.append((src,dst,b))
 records.append({'kind':group,'source_path':str(src),'snapshot':str(dst),'bytes':len(b),'sha256':h(b)})
assert head(M)==basis
for src,dst,b in loaded:
 assert src.read_bytes()==b,str(src)
 dst.parent.mkdir(parents=True,exist_ok=True);dst.write_bytes(b)
document={'schema':'pi-zig.tracing-event-consumer-basis.v1','main_head_read_before_and_after':basis,
 'main_writes':False,'sdk_writes':False,'source_only':True,
 'snapshot_method':'Exact byte copies into this new analysis packet; every source reread unchanged before copy. No project code execution.',
 'records':records,
 'sdk_owner_projection_manifest':str(S/'verification/native-file-handle-owner-sourceonly-20261020/shared/proposal.json'),
 'sdk_owner_projection_manifest_sha256':'C195AE5D402ED457AF651D6BEB37B2BB8DBD3DF36CD74106EB172F00B64618FC',
 'sdk_close_projection_manifest':str(S/'verification/native-file-handle-close-settlement-followup-sourceonly-20261020/proposal.json'),
 'sdk_close_projection_manifest_sha256':'BA6543E47B33A5D994AD097FBF0CBC58A6E35F262DF42FFE5909D9A736118319'}
out=P/'consumer-basis.json';assert not out.exists()
b=(json.dumps(document,indent=2)+'\n').encode();out.write_bytes(b)
print(json.dumps({'path':str(out),'bytes':len(b),'sha256':h(b),'main_basis':basis,'records':records},indent=2))

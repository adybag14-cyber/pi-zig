#!/usr/bin/env python3
"""Real PTY browser/device authentication dialog validation for checkpoint 179."""
from __future__ import annotations
import argparse, contextlib, http.client, http.server, json, os, pty, select, subprocess, tempfile, threading, time, urllib.parse
from pathlib import Path
from typing import Any

def req(ok: bool, msg: str) -> None:
    if not ok: raise AssertionError(msg)

class Server(http.server.ThreadingHTTPServer):
    daemon_threads=True; allow_reuse_address=True
    def __init__(self):
        self.requests=[]; self.lock=threading.Lock(); super().__init__(("127.0.0.1",0), Handler)
class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version="HTTP/1.1"
    def log_message(self,*_:object)->None: pass
    def reply(self,status:int,obj:Any)->None:
        body=json.dumps(obj,separators=(",",":")).encode(); self.send_response(status); self.send_header("content-type","application/json"); self.send_header("content-length",str(len(body))); self.end_headers(); self.wfile.write(body); self.wfile.flush()
    def do_GET(self)->None:
        s:Server=self.server  # type: ignore
        with s.lock: s.requests.append(("GET",self.path,b""))
        if self.path=="/v1/oauth": return self.reply(200,{"authorizationEndpoint":f"http://127.0.0.1:{s.server_port}/authorize"})
        if self.path=="/v1/config": return self.reply(200,{"baseUrl":f"http://127.0.0.1:{s.server_port}/v1","models":[{"id":"fast","name":"Fast 179","reasoning":False,"input":["text"],"cost":{},"contextWindow":4096,"maxTokens":512}]})
        if self.path.startswith("/authorize"): return self.reply(200,{"ok":True})
        return self.reply(404,{"error":"not_found"})
    def do_POST(self)->None:
        s:Server=self.server  # type: ignore
        n=int(self.headers.get("content-length","0")); body=self.rfile.read(n)
        with s.lock: s.requests.append(("POST",self.path,body))
        if self.path=="/v1/oauth/device": return self.reply(200,{"device_code":"device-179","user_code":"CODE-179","verification_uri":f"http://127.0.0.1:{s.server_port}/device","expires_in":600,"interval":1})
        if self.path=="/v1/oauth/token":
            text=body.decode(errors="replace")
            if "device_code" in text: return self.reply(400,{"error":"authorization_pending"})
            return self.reply(200,{"access_token":"access-179","refresh_token":"refresh-179","expires_in":3600,"scope":"gateway offline_access"})
        return self.reply(404,{"error":"not_found"})

def wait_for(master:int,out:bytearray,p:subprocess.Popen[bytes],marker:bytes,start:int=0,timeout:float=45)->int:
    end=time.monotonic()+timeout
    while time.monotonic()<end:
        i=out.find(marker,start)
        if i>=0:return i+len(marker)
        if p.poll() is not None:break
        r,_,_=select.select([master],[],[],.1)
        if r:
            with contextlib.suppress(OSError): out.extend(os.read(master,65536))
    raise AssertionError(f"missing {marker!r}; tail={out[-10000:].decode(errors='replace')}")

def drain(master:int,out:bytearray,p:subprocess.Popen[bytes],timeout:float=20)->None:
    end=time.monotonic()+timeout
    while p.poll() is None and time.monotonic()<end:
        r,_,_=select.select([master],[],[],.1)
        if r:
            with contextlib.suppress(OSError): out.extend(os.read(master,65536))
    req(p.poll() is not None,"process did not exit")

def run(binary:Path, report:Path|None)->dict[str,Any]:
    server=Server(); thread=threading.Thread(target=server.serve_forever,daemon=True); thread.start()
    try:
      with tempfile.TemporaryDirectory(prefix="pi-auth-dialog-179-") as raw:
        root=Path(raw); agent=root/"agent"; sessions=root/"sessions"; work=root/"work"; home=root/"home"; bindir=root/"bin"
        for d in (agent,sessions,work,home,bindir):d.mkdir()
        opened=root/"opened-url.txt"
        xdg=bindir/"xdg-open"; xdg.write_text(f'#!/bin/sh\nprintf "%s" "$1" > "{opened}"\n',encoding='utf-8'); xdg.chmod(0o755)
        (agent/"models.json").write_text(json.dumps({"providers":{"corp179":{"name":"Corp 179","baseUrl":f"http://127.0.0.1:{server.server_port}/v1","api":"pi-messages","oauth":"radius","models":[{"id":"fast","name":"Fast 179","contextWindow":4096,"maxTokens":512}]}}}),encoding='utf-8')
        (agent/"settings.json").write_text(json.dumps({"quietStartup":True,"enableInstallTelemetry":False,"collapseChangelog":True}),encoding='utf-8')
        mock=root/"mock.json"; mock.write_text(json.dumps([{"content":"unused-179"}]),encoding='utf-8')
        env=os.environ.copy(); env.update({"PI_AGENT_DIR":str(agent),"HOME":str(home),"TERM":"xterm-256color","COLUMNS":"120","LINES":"38","NO_COLOR":"1","PI_SKIP_VERSION_CHECK":"1","PI_TELEMETRY":"0","PATH":str(bindir)+os.pathsep+env.get("PATH","")})
        cmd=[str(binary),"--mock-script",str(mock),"--session-dir",str(sessions),"--no-context-files","--no-skills","--no-prompt-templates","--no-themes","--no-extensions","--approve"]
        master,slave=pty.openpty(); p=subprocess.Popen(cmd,cwd=work,env=env,stdin=slave,stdout=slave,stderr=subprocess.PIPE,close_fds=True); os.close(slave); os.set_blocking(master,False); out=bytearray()
        try:
            pos=wait_for(master,out,p,b"> ")
            os.write(master,b"/login corp179 browser\r")
            dialog_start=len(out); pos=wait_for(master,out,p,b"Open this link to continue:",dialog_start)
            end=time.monotonic()+10
            while not opened.exists() and time.monotonic()<end: time.sleep(.05)
            req(opened.exists(),"browser opener did not receive URL")
            url=opened.read_text(); q=urllib.parse.parse_qs(urllib.parse.urlparse(url).query); state=q.get("state",[""])[0]; req(bool(state),f"missing state in {url}")
            req(b"\x1b]8;;http://127.0.0.1:" in out[dialog_start:],"OSC8 auth hyperlink missing")
            conn=http.client.HTTPConnection("127.0.0.1",1456,timeout=10); conn.request("GET",f"/oauth/callback?code=browser-code-179&state={urllib.parse.quote(state)}"); resp=conn.getresponse(); resp.read(); conn.close(); req(resp.status==200,f"callback status {resp.status}")
            pos=wait_for(master,out,p,b"Radius OAuth credential stored",pos,timeout=60); pos=wait_for(master,out,p,b"> ",pos)
            stored=json.loads((agent/"auth.json").read_text()); req(stored["corp179"]["access"]=="access-179","browser token not persisted")
            os.write(master,b"/login corp179 device-code\r")
            device_start=len(out); pos=wait_for(master,out,p,b"CODE-179",device_start,timeout=30)
            req(b"Authorize this device:" in out[device_start:],"device dialog missing")
            os.write(master,b"\x1b")
            pos=wait_for(master,out,p,b"Login cancelled.",pos,timeout=30); pos=wait_for(master,out,p,b"> ",pos)
            os.write(master,b"/quit\r"); drain(master,out,p)
            assert p.stderr is not None; stderr=p.stderr.read().decode(errors='replace'); req(p.returncode==0,f"exit={p.returncode}: {stderr}"); req(stderr=="",f"stderr={stderr}")
            result={"browserDialog":True,"osc8Hyperlink":True,"callbackCompletion":True,"credentialPersisted":True,"deviceCodeDialog":True,"cooperativeCancellation":True,"terminalRestored":True,"exit":0,"stderrBytes":0}
            if report: report.write_text(json.dumps(result,indent=2,sort_keys=True)+"\n")
            return result
        finally:
            with contextlib.suppress(OSError):os.close(master)
            if p.poll() is None:p.kill(); p.wait(timeout=3)
    finally:
      server.shutdown(); server.server_close(); thread.join(timeout=3)

def main()->int:
    ap=argparse.ArgumentParser(); ap.add_argument('--binary',type=Path,required=True); ap.add_argument('--report',type=Path); a=ap.parse_args(); r=run(a.binary.resolve(),a.report.resolve() if a.report else None); print('AUTH_DIALOG_E2E_179=PASS'); [print(f'{k}={v}') for k,v in r.items()]; return 0
if __name__=='__main__': raise SystemExit(main())

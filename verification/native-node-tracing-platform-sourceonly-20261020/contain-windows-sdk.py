from pathlib import Path
import hashlib,json,datetime
own=Path(r'C:\Users\adyba\pi-zig\worktrees\modules-io-resume-20261018')
p=own/'verification/native-node-tracing-platform-sourceonly-20261020'
source=Path(r'C:\Program Files (x86)\Windows Kits\10\Include\10.0.22621.0\shared\TraceLoggingProvider.h')
dest=p/'authority/windows-sdk/10.0.22621.0/shared/TraceLoggingProvider.h'
b=source.read_bytes()
expected='C060AF7E8703386736C651A62686908D509B8B9CB627D898D72A4CA6506901A4'
assert len(b)==294943 and hashlib.sha256(b).hexdigest().upper()==expected
assert not dest.exists()
dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(b)
receipt={'schema':1,'kind':'Exact contained installed Windows SDK original','created_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'version':'10.0.22621.0','installed_original_path':str(source),'contained_path':str(dest),'bytes':len(b),'sha256':expected,'byte_exact':True,'copyright_notice_preserved':True,'acquisition':'Read-only local installed SDK original; exact byte copy into owned authority packet.','direct_actual_include':'evntprov.h','dependency_selection':'Pinned Zig 0.16.0 MinGW evntprov.h and its Windows declaration family. No SDK include directory or second SDK header is introduced. Full selected compiler compatibility remains unverified.','compiler_execution':False,'native_execution':False}
r=p/'acquisition/windows-sdk-10.0.22621.0-contained.json';assert not r.exists();r.write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf-8',newline='\n')
recipe=own/'tools/build_native_node_tracing.zig'
old=recipe.read_bytes()
previous=p/'original/build_native_node_tracing-before-contained-sdk.zig';assert not previous.exists();previous.write_bytes(old)
text=old.decode()
old_options='''pub const Options = struct {
    // Genuine installed Windows SDK header. Only this file is copied to the
    // build include directory, so SDK shared headers do not shadow MinGW's
    // complete Windows header set. Its exact bytes are an integration input.
    windows_tracelogging_header: ?std.Build.LazyPath = null,
};'''
new_options='''// Contained exact Windows SDK original. This directory holds only this
// header, so evntprov.h and the Windows declaration family still resolve to
// the pinned Zig 0.16.0 MinGW toolchain. The installed location is provenance,
// not a build input; the authority receipt pins all 294943 original bytes.
pub const windows_sdk = struct {
    pub const version = "10.0.22621.0";
    pub const include_path = "verification/native-node-tracing-platform-sourceonly-20261020/authority/windows-sdk/10.0.22621.0/shared";
    pub const header_path = include_path ++ "/TraceLoggingProvider.h";
    pub const sha256 = "C060AF7E8703386736C651A62686908D509B8B9CB627D898D72A4CA6506901A4";
};'''
assert text.count(old_options)==1;text=text.replace(old_options,new_options)
text=text.replace('owners: Owners, options: Options','owners: Owners')
old_copy='''            const sdk_header = options.windows_tracelogging_header orelse
                std.debug.panic("The original Windows Recorder requires an explicit genuine Windows SDK TraceLoggingProvider.h", .{});
            const sdk_copy = b.addWriteFiles();
            _ = sdk_copy.addCopyFile(sdk_header, "TraceLoggingProvider.h");
            module.addIncludePath(sdk_copy.getDirectory());'''
new_copy='''            module.addIncludePath(b.path(windows_sdk.include_path));'''
assert text.count(old_copy)==1;text=text.replace(old_copy,new_copy)
recipe.write_text(text,encoding='utf-8',newline='\n')
seal=p/'seal-source-cohort.py';s=seal.read_text()
s=s.replace("6AA6586C71DAE6E72F1A59860E54F550E076AC9BEFF5FA67264C59FD6A3CFFEA3","6AA6586C71DAE6E72F1A59860E54F550E076AC9BEFFFA67264C59FD6A3CFFEA3")
s=s.replace("# The API header pin is read from its already committed immutable unit record.\nfrozen[-1]=(frozen[-1][0],'6AA6586C71DAE6E72F1A59860E54F550E076AC9BEFFFA67264C59FD6A3CFFEA3')\n","")
s=s.replace("'source_body_proof':body_pin,'body_comparisons':41,","'source_body_proof':body_pin,'body_comparisons':41,\n 'contained_windows_sdk_header':pin(packet/'authority/windows-sdk/10.0.22621.0/shared/TraceLoggingProvider.h'),\n 'windows_sdk_acquisition':pin(packet/'acquisition/windows-sdk-10.0.22621.0-contained.json'),")
seal.write_text(s,encoding='utf-8',newline='\n')
for x in [dest,r,recipe,seal]:
 bb=x.read_bytes();print(json.dumps({'path':str(x),'bytes':len(bb),'sha256':hashlib.sha256(bb).hexdigest().upper()}))

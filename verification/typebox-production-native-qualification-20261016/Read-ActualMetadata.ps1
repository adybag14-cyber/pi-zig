function Read-ActualTypeBoxMetadata {
 param([string]$Binary,[string]$Root,[string]$Receipt)
 $owned=Invoke-CiOwnedProcess $Binary @('--listen=-') $Root $Receipt 30 ([byte[]](4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
 $bytes=[IO.File]::ReadAllBytes("$Receipt.stdout.bin");$offset=0;$version=$null;$names=$null
 while($offset-lt$bytes.Length){
  if($offset+8-gt$bytes.Length){throw 'Truncated actual metadata header'}
  $tag=[BitConverter]::ToUInt32($bytes,$offset);$size=[BitConverter]::ToUInt32($bytes,$offset+4);$offset+=8
  if($size-gt1MB-or$offset+$size-gt$bytes.Length){throw 'Actual metadata length mismatch'}
  if($tag-eq0){$version=[Text.Encoding]::UTF8.GetString($bytes,$offset,$size)}elseif($tag-eq3){
   if($null-ne$names-or$size-lt8){throw 'Duplicate or truncated metadata array'}
   $strings=[BitConverter]::ToUInt32($bytes,$offset);$count=[BitConverter]::ToUInt32($bytes,$offset+4)
   if($count-lt3-or$count-gt1000-or$size-ne8+8*$count+$strings){throw 'Actual metadata count/layout mismatch'}
   $start=$offset+8+8*$count;$names=@()
   for($i=0;$i-lt$count;$i++){$nameOffset=[BitConverter]::ToUInt32($bytes,$offset+8+4*$i);$panic=[BitConverter]::ToUInt32($bytes,$offset+8+4*$count+4*$i);if($panic-ne0-or$nameOffset-ge$strings){throw 'Actual metadata panic/offset mismatch'};$end=$nameOffset;while($end-lt$strings-and$bytes[$start+$end]-ne0){$end++};if($end-eq$strings){throw 'Unterminated actual metadata name'};$names+=[Text.Encoding]::UTF8.GetString($bytes,$start+$nameOffset,$end-$nameOffset)}
  }else{throw "Unexpected metadata-only protocol tag $tag"}
  $offset+=$size
 }
 if($version-cne'0.16.0'-or$names.Count-lt3){throw 'Actual Zig metadata/version missing'}
 return @{binary=$Binary;binary_sha256=$owned.executable_sha256;version=$version;tests=$names;method='Actual Zig0.16 metadata query and clean exit; no unit run request';owner=$owned}
}

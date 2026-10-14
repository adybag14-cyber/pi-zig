param([string]$SourceDir,[string]$Receipt='verification/native-ai-json-b06-posix-reference')
. "$PSScriptRoot/native_ai_ci.ps1"
if(!$IsLinux){throw 'This reference owner is scoped to Linux POSIX'}
$taskRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$taskSource=[IO.Path]::GetFullPath($SourceDir)
$taskReceipt=Join-Path $taskRoot $Receipt
New-Item -ItemType Directory -Path $taskReceipt -Force > $null
$taskHead='b06c1f2cf1dea6af8748ddeee18c23587d2cb7c6'
if((git -C $taskSource rev-parse HEAD).Trim() -cne $taskHead){throw 'Official Source head mismatch'}
$taskTracked=@(git -C $taskSource ls-files|Sort-Object)
if($taskTracked.Count -ne 1922){throw 'Official tracked Source inventory changed'}
$taskSourceRows=Get-AiRows $taskSource $taskTracked
$taskHistorical=Get-Content -LiteralPath (Join-Path $taskRoot 'verification/ai-json-final-b06-20261014/sdk-source-b06-full-manifest-20261014.json') -Raw|ConvertFrom-Json
$taskOriginal=@{}
foreach($taskRow in $taskHistorical){$taskRelative=$taskRow.path.Replace('\','/').Replace('C:/Users/adyba/pi-upstream-source-b06c1f2-20261014/','');$taskOriginal[$taskRelative]=$taskRow.sha256}
foreach($taskRow in $taskSourceRows){if(!$taskOriginal.ContainsKey($taskRow.relative) -or $taskOriginal[$taskRow.relative] -cne $taskRow.sha256){throw "Official tracked Source content differs: $($taskRow.relative)"}}
$taskTemp=Join-Path $env:RUNNER_TEMP ('ai-json-reference-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $taskTemp > $null
$taskVersion='v24.14.0';$taskArch=$env:RUNNER_ARCH.ToLowerInvariant()
if($taskArch -notin @('x64','arm64')){throw 'Unsupported reference architecture'}
# Official release SHASUMS: https://nodejs.org/en/blog/release/v24.14.0
$taskPinnedArchive=@{x64='41CD79BB7877C81605A9E68EC4C91547774F46A40C67A17E34D7179EF11729DF';arm64='E7ADFCA03D9173276114A6F2219DF1A7D25E1BFD6BBD771D3F839118A2053094'}[$taskArch]
$taskArchiveName="node-$taskVersion-linux-$taskArch.tar.xz"
$taskSums=Join-Path $taskTemp 'node-SHASUMS256.txt';$taskArchive=Join-Path $taskTemp $taskArchiveName
Invoke-WebRequest "https://nodejs.org/dist/$taskVersion/SHASUMS256.txt" -OutFile $taskSums -TimeoutSec 120
$taskExpected=@(Get-Content -LiteralPath $taskSums|Where-Object {$_ -match ('^[0-9a-f]{64}\s+'+[regex]::Escape($taskArchiveName)+'$')})
if($taskExpected.Count -ne 1){throw 'Official Node archive checksum missing'}
if($taskExpected[0].Substring(0,64).ToUpperInvariant() -cne $taskPinnedArchive){throw 'Published Node archive checksum changed'}
Invoke-WebRequest "https://nodejs.org/dist/$taskVersion/$taskArchiveName" -OutFile $taskArchive -TimeoutSec 120
if((Get-FileHash -LiteralPath $taskArchive).Hash -cne $taskPinnedArchive){throw 'Official Node archive digest mismatch'}
$taskNodePrefix="node-$taskVersion-linux-$taskArch/"
$taskNodeEntries=@(& tar -tJf $taskArchive)
if($LASTEXITCODE -ne 0 -or @($taskNodeEntries|Where-Object {!$_.StartsWith($taskNodePrefix,[StringComparison]::Ordinal) -or $_.Split('/') -contains '..'}).Count){throw 'Node archive containment mismatch'}
& tar -xJf $taskArchive -C $taskTemp
if($LASTEXITCODE -ne 0){throw 'Node extraction failed'}
$taskNodeRoot=Join-Path $taskTemp $taskNodePrefix.TrimEnd('/')
$taskNode=Join-Path $taskNodeRoot 'bin/node'
$taskLock=Get-Content -LiteralPath (Join-Path $taskSource 'package-lock.json') -Raw|ConvertFrom-Json
$taskPin=$taskLock.packages.PSObject.Properties['node_modules/partial-json'].Value
if($taskPin.version -cne '0.1.7' -or $taskPin.resolved -cne 'https://registry.npmjs.org/partial-json/-/partial-json-0.1.7.tgz'){throw 'Pinned partial-json contract changed'}
$taskPackageArchive=Join-Path $taskTemp 'partial-json.tgz'
Invoke-WebRequest $taskPin.resolved -OutFile $taskPackageArchive -TimeoutSec 120
$taskIntegrity='sha512-'+[Convert]::ToBase64String([Security.Cryptography.SHA512]::HashData([IO.File]::ReadAllBytes($taskPackageArchive)))
if($taskIntegrity -cne $taskPin.integrity){throw 'Locked partial-json archive integrity mismatch'}
$taskEntries=@(& tar -tzf $taskPackageArchive)
if($LASTEXITCODE -ne 0 -or @($taskEntries|Where-Object {!$_.StartsWith('package/',[StringComparison]::Ordinal) -or $_.Split('/') -contains '..'}).Count){throw 'Package archive containment mismatch'}
$taskPackageRoot=Join-Path $taskSource 'node_modules/partial-json'
if(Test-Path -LiteralPath $taskPackageRoot){throw 'Reference package unexpectedly preinstalled'}
New-Item -ItemType Directory -Path $taskPackageRoot -Force > $null
& tar -xzf $taskPackageArchive --strip-components=1 -C $taskPackageRoot
if($LASTEXITCODE -ne 0){throw 'Reference package extraction failed'}
$taskPackage=Get-Content -LiteralPath (Join-Path $taskPackageRoot 'package.json') -Raw|ConvertFrom-Json
if($taskPackage.name -cne 'partial-json' -or $taskPackage.version -cne '0.1.7' -or $taskPackage.dependencies){throw 'Reference runtime dependency contract mismatch'}
$taskPackageRows=Get-AiRows $taskPackageRoot @(Get-ChildItem -LiteralPath $taskPackageRoot -File -Recurse|Sort-Object FullName|ForEach-Object {[IO.Path]::GetRelativePath($taskPackageRoot,$_.FullName)})
$taskNodeRows=Get-AiRows $taskNodeRoot @(Get-ChildItem -LiteralPath $taskNodeRoot -File -Recurse|Sort-Object FullName|ForEach-Object {[IO.Path]::GetRelativePath($taskNodeRoot,$_.FullName)})
$taskDriver=Join-Path $taskTemp 'observe-original.mjs'
$taskDriverText=@'
import {readFileSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {pathToFileURL,fileURLToPath} from 'node:url';
import {resolve,sep} from 'node:path';
import {registerHooks,isBuiltin} from 'node:module';
const [sourceRoot,packageRoot,callerPath,goldenPath,outputPath,countText]=process.argv.slice(2);
const actualNode={execPath:process.execPath,version:process.version,v8:process.versions.v8,platform:process.platform,arch:process.arch,pid:process.pid};
if(actualNode.version!=='v24.14.0'||actualNode.platform!=='linux')throw Error('Actual reference Node identity mismatch');
const hash=x=>createHash('sha256').update(x).digest('hex');
const original=readFileSync(callerPath),text=original.toString('utf8'),line=text.indexOf('\n');
const expected="import * as api from 'file:///C:/Users/adyba/pi-upstream-source-b06c1f2-20261014/packages/ai/src/utils/json-parse.ts';";
if(line<0||text.slice(0,line)!==expected)throw Error('Original caller import boundary changed');
const body=text.slice(line+1),adapted='import * as api from '+JSON.stringify(pathToFileURL(resolve(sourceRoot,'packages/ai/src/utils/json-parse.ts')).href)+';\n'+body;
const callerURL='data:text/javascript;base64,'+Buffer.from(adapted).toString('base64');
const roots=[resolve(sourceRoot)+sep,resolve(packageRoot)+sep],loaded=[];
registerHooks({resolve(specifier,context,next){const result=next(specifier,context);if(isBuiltin(result.url))return result;if(result.url===callerURL){loaded.push({kind:'original-caller',sha256:hash(adapted)});return result;}if(!result.url.startsWith('file:'))throw Error('Reference resolution escape '+result.url);const path=resolve(fileURLToPath(result.url));if(!roots.some(root=>path.startsWith(root)))throw Error('Reference Source/dependency escape '+path);loaded.push({url:result.url});return result;}});
const parse=JSON.parse,stringify=JSON.stringify,golden=parse(readFileSync(goldenPath,'utf8'));
const rows=(await import(callerURL)).default;
if(rows.length!==Number(countText)||stringify(rows)!==stringify(golden.rows))throw Error('Genuine POSIX original observations differ from immutable golden');
writeFileSync(outputPath,stringify({sourceHead:'b06c1f2cf1dea6af8748ddeee18c23587d2cb7c6',actualNode,cases:rows.length,matchedOriginal:true,originalCallerSha256:hash(original),adaptedImportCallerSha256:hash(adapted),unchangedCallerBodySha256:hash(body),loaded,scope:'Actual unchanged official b06 utility and exact locked partial-json, fresh Node24.14 Linux process; caller import URL alone adapted, no Source replacement or exception normalization',rows},null,2));
'@
[IO.File]::WriteAllText($taskDriver,$taskDriverText,[Text.UTF8Encoding]::new($false))
$taskSourceRows|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskReceipt 'official-tracked-source.json') -Encoding utf8NoBOM
$taskPackageRows|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskReceipt 'exact-runtime-dependency.json') -Encoding utf8NoBOM
$taskNodeRows|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskReceipt 'actual-node-tools.json') -Encoding utf8NoBOM
$taskControls=Get-AiRows $taskRoot @('tools/ci/native_ai_ci.ps1','tools/ci/observe_ai_json_posix.ps1','src/extensions/fixtures/ai-json-parse-b06.input.txt','src/extensions/fixtures/ai-json-parse-b06.json','src/extensions/fixtures/ai-json-delegate-b06.input.txt','src/extensions/fixtures/ai-json-delegate-b06.json')
$taskControls+=Get-AiRows $taskTemp @('observe-original.mjs',$taskArchiveName,'node-SHASUMS256.txt','partial-json.tgz')
$taskControls|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskReceipt 'controls.json') -Encoding utf8NoBOM
try {
 foreach($taskSpec in @(@('parse',33),@('delegate',6))){
  $taskStem="ai-json-$($taskSpec[0])-b06"
  $taskCaller=Join-Path $taskRoot "src/extensions/fixtures/$taskStem.input.txt"
  $taskGolden=Join-Path $taskRoot "src/extensions/fixtures/$taskStem.json"
  $taskOutput=Join-Path $taskReceipt "$($taskSpec[0])-original.json"
  $taskOwner=Invoke-AiOwnedProcess $taskNode @('--max-old-space-size=256','--conditions=source','--experimental-transform-types',$taskDriver,$taskSource,$taskPackageRoot,$taskCaller,$taskGolden,$taskOutput,[string]$taskSpec[1]) $taskSource (Join-Path $taskReceipt "$($taskSpec[0])-owner") 300
  $taskObserved=Get-Content -LiteralPath $taskOutput -Raw|ConvertFrom-Json
  if(!$taskObserved.matchedOriginal -or $taskObserved.cases -ne $taskSpec[1] -or $taskObserved.actualNode.pid -ne $taskOwner.pid -or $taskObserved.actualNode.execPath -cne $taskNode){throw 'Genuine reference identity/cases mismatch'}
 }
 @{status='passed';source_head=$taskHead;node_version='v24.14.0';node_executable_sha256=(Get-FileHash -LiteralPath $taskNode).Hash;node_archive_sha256=(Get-FileHash -LiteralPath $taskArchive).Hash;partial_json_version=$taskPin.version;partial_json_integrity=$taskIntegrity;original_rows=39;tracked_source_files=$taskSourceRows.Count;runtime_dependency_files=$taskPackageRows.Count;node_tool_files=$taskNodeRows.Count;historical_typed_catalog_files_used=0;latest_catalog_qualified=$false;global_activation=$false;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskReceipt 'result.json') -Encoding utf8NoBOM
}finally{
 Assert-AiRows $taskSourceRows (Join-Path $taskReceipt 'source-posthash.json')
 Assert-AiRows $taskPackageRows (Join-Path $taskReceipt 'dependency-posthash.json')
 Assert-AiRows $taskNodeRows (Join-Path $taskReceipt 'node-tools-posthash.json')
 Assert-AiRows $taskControls (Join-Path $taskReceipt 'controls-posthash.json')
}

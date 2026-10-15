param([ValidateSet('first','second')][string]$Attempt='first')
$ErrorActionPreference='Stop'
$ev=$PSScriptRoot
$root='C:/Users/adyba/pi-zig-native-oauth-callback-20261015'
$expectedHead='d43f3cf8b8e375f8545813d88f0ef48343c5f286'
$name="oauth-callback-native-d43f3cf8-$Attempt-debug-20261015"
$zig='C:/Users/adyba/pi-zig-toolchain-20261003/zig-x86_64-windows-0.16.0/zig.exe'
$owner=Join-Path $ev 'Invoke-Env15-OwnedJob-20261015.ps1'
$source='C:/Users/adyba/pi-upstream-source-ae7b16d-20261015'
$runtime='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012'
$compilerManifest=Join-Path $ev 'durable-latest89-full-inspect-53ae-tool-prehash-20261011.json'
function Rows($paths){@($paths|Sort-Object -Unique|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})}
function Drift($rows){$changed=[Collections.Generic.List[string]]::new();foreach($row in $rows){if(!(Test-Path -LiteralPath $row.path -PathType Leaf)){$changed.Add($row.path);continue};$stream=[IO.File]::OpenRead($row.path);try{$hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream))}finally{$stream.Dispose()};if($hash -cne $row.sha256.ToUpperInvariant()){$changed.Add($row.path)}};@($changed)}
function CandidatePaths{@(git -C $root ls-files --cached --others --exclude-standard|Where-Object{Test-Path -LiteralPath (Join-Path $root $_) -PathType Leaf}|ForEach-Object{Join-Path $root $_})}
function VendorPaths{@(Get-ChildItem -LiteralPath (Join-Path $root 'vendor') -File -Recurse -Force|ForEach-Object{if($_.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Vendor reparse input refused'};$_.FullName})}
function SourcePaths{@(@(git -C $source ls-files --cached --others --exclude-standard|Where-Object{Test-Path -LiteralPath (Join-Path $source $_) -PathType Leaf}|ForEach-Object{Join-Path $source $_})+@(Get-ChildItem -LiteralPath (Join-Path $source 'packages/ai/src/providers/data') -File -Force|ForEach-Object FullName)|Sort-Object -Unique)}
function Admit($phase){$free=[long](Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory*1024;$roots=@(Get-CimInstance Win32_Process -Filter "Name='zig.exe'"|Where-Object{$_.CommandLine -match '\sbuild\s'});$row=[ordered]@{root_slot=3;phase=$phase;free_bytes=$free;required_bytes=16GB;other_native_build_roots=$roots.Count;max_roots=4;jobs=1;compile_seconds=1320;runtime_seconds=300;test_seconds=120;await_ms=10000;settle_seconds=10;candidate=$expectedHead;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')};$row|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $ev "$name-$phase-admission.json") -Encoding utf8NoBOM;if($free -lt 16GB -or $roots.Count -ge 4){throw 'Normal16GiB/max4 admission denied'};return $row}
if((git -C $root rev-parse HEAD) -cne $expectedHead -or @(git -C $root status --porcelain).Count){throw 'Exact clean callback candidate required'}
if((git -C $source rev-parse HEAD) -cne 'ae7b16d43b7c78c5b6fa3213fdd1215bb339729d'){throw 'Original Source HEAD changed'}
if((Get-FileHash -LiteralPath $zig).Hash -cne '086CE9D47BA42F33A514E1A6E04EB1D4A8FA1D75E0868E0213CAAD447C91E864'){throw 'Pinned Zig changed'}
$source16=Get-Content -LiteralPath (Join-Path $ev 'oauth-callback-ae7-source16-first-20261015-posthash.json') -Raw|ConvertFrom-Json
$source16Owner=Get-Content -LiteralPath (Join-Path $ev 'oauth-callback-ae7-source16-first-20261015.json') -Raw|ConvertFrom-Json
if($source16Owner.status -cne 'passed' -or @($source16.manifests|Where-Object drift -ne 0).Count -or $source16.extra_control_drift.Count -or $source16.absent_dependency_drift.Count -or $source16.control_manifest_drift){throw 'Source16 terminal fullpost0 prerequisite missing'}
if((Get-FileHash -LiteralPath (Join-Path $root 'src/extensions/fixtures/ai-oauth-callback-ae7.json')).Hash -cne '5BC8BC4451AA115F8C18BFC5D638F65CD1DFDDD978DFB653BA3C1BEC8D469612'){throw 'Genuine expected Source16 fixture changed'}
$specs=@(@{name='source';file='sourceae7-full-manifest-20261015.json';count=1968},@{name='dependencies';file='sourceae7-runtime-manifest-20261015.json';count=31064},@{name='node';file='sourceae7-node-tools-before-20261015.json';count=1774})
$frozen=@()
foreach($spec in $specs){$r=@(Get-Content -LiteralPath (Join-Path $ev $spec.file) -Raw|ConvertFrom-Json);if($r.Count -ne $spec.count){throw 'Reference inventory count changed'};if(@(Drift $r).Count){throw 'Reference prehash drift'};$frozen+=@{name=$spec.name;rows=$r}}
$compiler=@((Get-Content -LiteralPath $compilerManifest -Raw|ConvertFrom-Json).inputs);if($compiler.Count -ne 19546 -or @(Drift $compiler).Count){throw 'Full compiler19546 prehash drift'}
$contract=Get-Content -LiteralPath (Join-Path $ev 'sourceae7-dependency-contract-audit-20261015.json') -Raw|ConvertFrom-Json
$absent=@($contract.pins|Where-Object status -eq 'platform_optional_absent'|ForEach-Object{Join-Path $runtime $_.path})+@($contract.mismatches|ForEach-Object{Join-Path $runtime $_.path})
if($absent.Count -ne 84 -or @($absent|Where-Object{Test-Path -LiteralPath $_}).Count){throw '84 historical absences changed'}
$before=Rows (CandidatePaths);$vendor=Rows (VendorPaths)
if(Compare-Object @($frozen[0].rows.path|ForEach-Object{[IO.Path]::GetFullPath($_)}) @(SourcePaths|ForEach-Object{[IO.Path]::GetFullPath($_)})){throw 'Full Original Source inventory changed'}
$controlPaths=@($PSCommandPath,$owner,$compilerManifest,(Join-Path $ev 'sourceae7-preparation-controls-20261015.json'),(Join-Path $ev 'sourceae7-preparation-readiness-20261015.json'),(Join-Path $ev 'sourceae7-dependency-contract-audit-20261015.json'),(Join-Path $ev 'sourceae7-observe-20261015.mjs'),(Join-Path $ev 'ai-oauth-callback-source-20261015.mjs'),(Join-Path $ev 'Run-OAuthCallbackAe7Source16-20261015.ps1'))+@($specs|ForEach-Object{Join-Path $ev $_.file})+@(Get-ChildItem -LiteralPath $ev -Filter 'oauth-callback-ae7-source16-first-20261015*' -File|ForEach-Object FullName)
$controls=Rows $controlPaths
$before|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $ev "$name-native-before.json") -Encoding utf8NoBOM
$vendor|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $ev "$name-vendor-before.json") -Encoding utf8NoBOM
$controls|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $ev "$name-controls-before.json") -Encoding utf8NoBOM
$compile=$null;$run=$null
function Post($phase){$reference=@();foreach($item in $frozen){$reference+=@{name=$item.name;count=$item.rows.Count;drift=@(Drift $item.rows).Count}};$result=[ordered]@{phase=$phase;candidate=$expectedHead;candidate_after=(git -C $root rev-parse HEAD);native=$before.Count;native_drift=@(Drift $before).Count;native_inventory_drift=@(Compare-Object @($before.path) @(CandidatePaths|Sort-Object -Unique)).Count;vendor=$vendor.Count;vendor_drift=@(Drift $vendor).Count;vendor_inventory_drift=@(Compare-Object @($vendor.path) @(VendorPaths|Sort-Object -Unique)).Count;compiler=$compiler.Count;compiler_drift=@(Drift $compiler).Count;controls=$controls.Count;control_drift=@(Drift $controls).Count;references=$reference;absences=$absent.Count;absence_drift=@($absent|Where-Object{Test-Path -LiteralPath $_}).Count;source_inventory_drift=@(Compare-Object @($frozen[0].rows.path|ForEach-Object{[IO.Path]::GetFullPath($_)}|Sort-Object) @(SourcePaths|ForEach-Object{[IO.Path]::GetFullPath($_)}|Sort-Object)).Count;compile=if($compile){$compile.status}else{'not_run'};runtime=if($run){$run.status}else{'not_run'};full_pi_qualified=$false;public_activation=$false;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')};$result|ConvertTo-Json -Depth 7|Set-Content -LiteralPath (Join-Path $ev "$name-$phase-posthash.json") -Encoding utf8NoBOM;if($result.candidate_after -cne $expectedHead -or $result.native_drift -or $result.native_inventory_drift -or $result.vendor_drift -or $result.vendor_inventory_drift -or $result.compiler_drift -or $result.control_drift -or $result.absence_drift -or $result.source_inventory_drift -or @($reference|Where-Object drift -ne 0).Count){throw 'Full native freeze posthash drift'};return $result}
try{
 $null=Admit 'compile'
 @{native=$before.Count;vendor=$vendor.Count;compiler=$compiler.Count;controls=$controls.Count;source1968=$frozen[0].rows.Count;dependencies31064=$frozen[1].rows.Count;node1774=$frozen[2].rows.Count;absences84=$absent.Count;head=$expectedHead;runner_sha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash;owner_sha256=(Get-FileHash -LiteralPath $owner).Hash}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $ev "$name-launch-identity.json") -Encoding utf8NoBOM
 try{& $owner -Executable $zig -WorkingDirectory $root -Arguments @('build','build-native-ai-oauth-callback','-Doptimize=Debug','-Duse-llvm=true','-j1','--test-timeout','120s','--summary','all') -ReceiptBase (Join-Path $ev "$name-compile") -TimeoutSeconds 1320}finally{$compile=Get-Content -LiteralPath (Join-Path $ev "$name-compile.process.json") -Raw|ConvertFrom-Json;$null=Post 'compile'}
 if($compile.status -cne 'passed'){throw 'Compile prerequisite failed; runtime refused'}
 $null=Admit 'runtime'
 & $owner -Executable $zig -WorkingDirectory $root -Arguments @('build','test-native-ai-oauth-callback','-Doptimize=Debug','-Duse-llvm=true','-j1','--test-timeout','120s','--summary','all') -ReceiptBase (Join-Path $ev "$name-runtime") -TimeoutSeconds 300
 $run=Get-Content -LiteralPath (Join-Path $ev "$name-runtime.process.json") -Raw|ConvertFrom-Json
}finally{if(Test-Path -LiteralPath (Join-Path $ev "$name-runtime.process.json")){$run=Get-Content -LiteralPath (Join-Path $ev "$name-runtime.process.json") -Raw|ConvertFrom-Json};$post=Post 'terminal';$post|ConvertTo-Json -Depth 7}
if(!$compile -or $compile.status -cne 'passed' -or !$run -or $run.status -cne 'passed'){throw 'Native callback pair failed'}

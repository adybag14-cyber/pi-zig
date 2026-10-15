param([Parameter(Mandatory)][ValidateRange(1,4)][int]$RootSlot,[string]$Attempt='first')
$ErrorActionPreference='Stop'
$evidence=$PSScriptRoot
$root='C:\Users\adyba\pi-zig-session-exports-20261015'
$original='C:\Users\adyba\pi-upstream-source-5ab7fe7-20261015'
$node='C:\Program Files\nodejs\node.exe'
$name="ordinary-session-exports5ab-more-source-$Attempt-20261015"
$owner=Join-Path $evidence 'Invoke-OwnedEeSourceJob-20261012.ps1'
$observer=Join-Path $evidence 'source5ab-observe-20261015.mjs'
$driver=Join-Path $evidence 'ordinary-session-exports5ab-more-source-capture-20261015.mjs'
if(Test-Path -LiteralPath (Join-Path $evidence "$name.json")){throw 'Refuse immutable receipt replay'}
function Drift($rows){$changed=[Collections.Generic.List[string]]::new();foreach($row in $rows){if(!(Test-Path -LiteralPath $row.path -PathType Leaf)){$changed.Add($row.path);continue};$stream=[IO.File]::OpenRead($row.path);try{$sha=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream))}finally{$stream.Dispose()};if($sha -cne $row.sha256.ToUpperInvariant()){$changed.Add($row.path)}};@($changed)}
function Native-Rows{@(git -C $root ls-files --cached --others --exclude-standard|Sort-Object -Unique|Where-Object{Test-Path -LiteralPath (Join-Path $root $_) -PathType Leaf}|ForEach-Object{[ordered]@{relative=$_;path=(Join-Path $root $_);sha256=(Get-FileHash -LiteralPath (Join-Path $root $_)).Hash}})}
function Admit{$free=[long](Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory*1024;$builds=@(Get-CimInstance Win32_Process -Filter "Name='zig.exe'"|Where-Object{$_.CommandLine -match '\sbuild\s'});if($free -lt 2GB -or $builds.Count -ge 4){throw 'Source2GiB/max4 admission denied'};[ordered]@{root_slot=$RootSlot;required_bytes=2GB;free_bytes=$free;other_native_build_roots=$builds.Count;max_coordinated_jobs=4;heap_mb=256;operation_seconds=300;host_await_ms=10000;observed_utc=[datetime]::UtcNow.ToString('o')}}
$admission=Admit
if((git -C $original rev-parse HEAD).Trim() -cne '5ab7fe74c400097b386662205cd93900695b8a71'){throw 'Latest Original head changed'}
$originalManifest=Join-Path $evidence 'source5ab-full-manifest-20261015.json'
$dependencyManifest=Join-Path $evidence 'durable-19cb534-reference-20261012-all-built-runtime.json'
$toolManifest=Join-Path $evidence 'root-current8a-npm-tools-before.json'
$source=@(Get-Content -LiteralPath $originalManifest -Raw|ConvertFrom-Json);$dependencies=@(Get-Content -LiteralPath $dependencyManifest -Raw|ConvertFrom-Json);$tools=@(Get-Content -LiteralPath $toolManifest -Raw|ConvertFrom-Json)
if($source.Count -ne 1967 -or $dependencies.Count -ne 31064 -or $tools.Count -ne 1774){throw 'Full frozen inventory count changed'}
if(@(Drift $source).Count -or @(Drift $dependencies).Count -or @(Drift $tools).Count){throw 'Original/dependency/Node prehash changed'}
$shellDirectories=@('C:\Program Files\Git\bin','C:\Program Files\Git\usr\bin')
foreach($directory in $shellDirectories){$item=Get-Item -LiteralPath $directory;if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Shell runtime root is reparse'}}
function Shell-Rows{@($shellDirectories|ForEach-Object{Get-ChildItem -LiteralPath $_ -File}|ForEach-Object{if($_.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Shell runtime file is reparse'};[ordered]@{path=$_.FullName;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}})}
$shellTools=Shell-Rows
$shellManifest=Join-Path $evidence "$name-shell-tools-before.json"
$shellTools|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $shellManifest -Encoding utf8NoBOM
$before=Native-Rows
$before|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $evidence "$name-native-before.json") -Encoding utf8NoBOM
$controls=@(@($PSCommandPath,$owner,$observer,$driver,$shellManifest,$originalManifest,$dependencyManifest,$toolManifest,(Join-Path $evidence 'source5ab-dependency-contract-audit-20261015.json'))|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})
$controlManifest=Join-Path $evidence "$name-controls-before.json"
$controls|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $controlManifest -Encoding utf8NoBOM
$controlDirectory=Join-Path $evidence "$name-frozen-controls"
New-Item -ItemType Directory -Path $controlDirectory|Out-Null
foreach($row in $controls){Copy-Item -LiteralPath $row.path -Destination (Join-Path $controlDirectory ([IO.Path]::GetFileName($row.path)))}
$admission=Admit;$admission|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $evidence "$name-admission.json") -Encoding utf8NoBOM
try{& $owner -Name $name -Executable $node -WorkingDirectory $original -Arguments @('--max-old-space-size=256','--import',([Uri]$observer).AbsoluteUri,$driver) -TimeoutSeconds 300 -EnvironmentOverrides @{NODE_PATH='';NODE_OPTIONS='';PI_OFFLINE='1';PI_SOURCE_ORACLE_CONTROL_MANIFEST=$controlManifest}}finally{
 $nativeDrift=@(Drift $before);$sourceDrift=@(Drift $source);$dependencyDrift=@(Drift $dependencies);$toolDrift=@(Drift $tools);$controlDrift=@(Drift $controls);$shellDrift=@(Drift $shellTools);$shellAfter=@($shellDirectories|ForEach-Object{Get-ChildItem -LiteralPath $_ -File}|ForEach-Object{$_.FullName});$shellInventoryDrift=@(Compare-Object @($shellTools.path) $shellAfter)
 $after=Native-Rows;$pathDrift=@(Compare-Object @($before.relative) @($after.relative))
 $record=if(Test-Path -LiteralPath (Join-Path $evidence "$name.json")){Get-Content -LiteralPath (Join-Path $evidence "$name.json") -Raw|ConvertFrom-Json}else{$null}
 [ordered]@{status=if($record){$record.status}else{'not_launched'};exit_code=if($record){$record.exit_code}else{$null};root_slot=$RootSlot;native_source=$before.Count;native_drift=$nativeDrift.Count;native_inventory_drift=$pathDrift.Count;original=$source.Count;original_drift=$sourceDrift.Count;dependencies=$dependencies.Count;dependency_drift=$dependencyDrift.Count;node_tools=$tools.Count;node_tool_drift=$toolDrift.Count;controls=$controls.Count;control_drift=$controlDrift.Count;shell_tools=$shellTools.Count;shell_tool_drift=$shellDrift.Count;shell_inventory_drift=$shellInventoryDrift.Count;public_activation=$false;full_constructor_qualified=$false;completed_utc=[datetime]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $evidence "$name-posthash.json") -Encoding utf8NoBOM
 if($nativeDrift.Count -or $sourceDrift.Count -or $dependencyDrift.Count -or $toolDrift.Count -or $controlDrift.Count -or $pathDrift.Count -or $shellDrift.Count -or $shellInventoryDrift.Count){throw 'Full freeze changed during genuine Source capture'}
}
$post=Get-Content -LiteralPath (Join-Path $evidence "$name-posthash.json") -Raw|ConvertFrom-Json
$post|ConvertTo-Json -Depth 5
if($post.status -cne 'passed'){throw 'Owned Source terminal failure'}
$capture=Get-Content -LiteralPath (Join-Path $evidence "$name.stdout.log") -Raw|ConvertFrom-Json
$artifacts=@(Get-ChildItem -LiteralPath $capture.root -File -Recurse|ForEach-Object{[ordered]@{path=$_.FullName;relative=[IO.Path]::GetRelativePath($capture.root,$_.FullName);sha256=(Get-FileHash -LiteralPath $_.FullName).Hash;bytes=$_.Length}})
$artifacts|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $evidence "$name-artifacts.json") -Encoding utf8NoBOM

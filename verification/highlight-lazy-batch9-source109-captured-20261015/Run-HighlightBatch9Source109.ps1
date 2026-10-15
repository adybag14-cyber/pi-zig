$ErrorActionPreference='Stop'
$taskEvidence=$PSScriptRoot
$taskRootEvidence='C:/Users/adyba/pi-zig-update-evidence-20261003'
$taskPrivate='C:/Users/adyba/pi-zig-highlight-lazy-batch9-20261015'
$taskHead='27f78f4d34c42e7572b224d1d405c3606995c7ce'
$taskName='highlight-lazy-batch9-source109-second-20261015'
$taskNode='C:/Program Files/nodejs/node.exe'
$taskSource='C:/Users/adyba/pi-upstream-source-5ab7fe7-20261015'
$taskRuntime='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012'
$taskHl='C:/Users/adyba/pi-upstream-source-b45e0eb-20261014/node_modules/highlight.js'
$taskInput=Join-Path $taskPrivate 'src/extensions/fixtures/sdk-highlight-lazy-batch9-10_7_3.input.txt'
$taskExpected=Join-Path $taskPrivate 'src/extensions/fixtures/sdk-highlight-lazy-batch9-10_7_3.json'
$taskDriver=Join-Path $taskPrivate 'verification/highlight-lazy-batch9-prepared-20261015/capture-highlight-lazy-batch9-20261015.mjs'
$taskOwner=Join-Path $taskEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1'
$taskObserver=Join-Path $taskRootEvidence 'source5ab-observe-20261015.mjs'
$taskAudit=Join-Path $taskRootEvidence 'source5ab-dependency-contract-audit-20261015.json'
$taskOutput=Join-Path $taskEvidence "$taskName-output.json"
$taskState=Join-Path $taskEvidence 'caller-state.json'
function State([string]$status){@{status=$status;utc=[DateTimeOffset]::UtcNow.ToString('o');candidate_head=$taskHead;expected_present=(Test-Path -LiteralPath $taskExpected)}|ConvertTo-Json|Set-Content -LiteralPath $taskState -Encoding utf8NoBOM}
function TaskGit([string[]]$argv){& git.exe -c gc.auto=0 -c maintenance.auto=false -c pack.threads=2 -c pack.windowMemory=64m -C $taskPrivate @argv}
function Check-Rows($rows){$changed=[Collections.Generic.List[string]]::new();foreach($row in $rows){if(!(Test-Path -LiteralPath $row.path -PathType Leaf) -or (Get-FileHash -LiteralPath $row.path).Hash -ine $row.sha256){$changed.Add($row.path)}};return @($changed)}
function Freeze-Paths($paths,[string]$manifest){$rows=@($paths|ForEach-Object{@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}});$rows|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $manifest -Encoding utf8NoBOM;return ,$rows}
try {
 State 'preparing'
 if((TaskGit @('rev-parse','HEAD')) -cne $taskHead -or @(TaskGit @('status','--porcelain')).Count){throw 'Exact published clean batch9 candidate required'}
 if(Test-Path -LiteralPath $taskExpected){throw 'Expected Source109 fixture must remain absent'}
 if(Test-Path -LiteralPath $taskOutput){throw 'Fresh actual Source109 output required'}
 if((Get-FileHash -LiteralPath $taskNode).Hash -cne '63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088'){throw 'Node24.14.0 pin changed'}
 $releaseOwner=Get-Content -Raw (Join-Path $taskRootEvidence 'oauth-anthropic-router-ae7-source24-first-20261015.json')|ConvertFrom-Json
 $releasePost=Get-Content -Raw (Join-Path $taskRootEvidence 'oauth-anthropic-router-ae7-source24-first-20261015-posthash.json')|ConvertFrom-Json
 if($releaseOwner.status -cne 'passed' -or @($releasePost.manifests|Where-Object drift -ne 0).Count -or $releasePost.control_manifest_drift -or @($releasePost.extra_control_drift).Count -or @($releasePost.absent_dependency_drift).Count){throw 'Preceding AnthropicRouter Source24 fullpost0 release absent'}
 $specs=@(@{name='source';file='source5ab-full-manifest-20261015.json';count=1967},@{name='dependencies';file='durable-19cb534-reference-20261012-all-built-runtime.json';count=31064},@{name='node_tools';file='root-current8a-npm-tools-before.json';count=1774})
 $frozen=@()
 State 'full-prehash'
 foreach($spec in $specs){$rows=@(Get-Content -Raw (Join-Path $taskRootEvidence $spec.file)|ConvertFrom-Json);if($rows.Count -ne $spec.count -or @(Check-Rows $rows).Count){throw "Original full $($spec.name) prehash mismatch"};$frozen+=@{name=$spec.name;rows=$rows}}
 if((& git.exe -c gc.auto=0 -c maintenance.auto=false -c pack.threads=2 -c pack.windowMemory=64m -C $taskSource rev-parse HEAD) -cne '5ab7fe74c400097b386662205cd93900695b8a71'){throw 'Historical5ab source head changed'}
 $contract=Get-Content -Raw $taskAudit|ConvertFrom-Json
 if($contract.latestHead -cne '5ab7fe74c400097b386662205cd93900695b8a71'){throw 'Historical dependency contract head changed'}
 $absent=@($contract.pins|Where-Object status -eq 'platform_optional_absent'|ForEach-Object{Join-Path $taskRuntime $_.path})+@($contract.mismatches|ForEach-Object{Join-Path $taskRuntime $_.path})
 if($absent.Count -ne 84 -or @($absent|Where-Object{Test-Path -LiteralPath $_}).Count){throw 'Historical84 absent dependency records changed'}
 $hlPackage=Get-Content -Raw (Join-Path $taskHl 'package.json')|ConvertFrom-Json
 $indexText=Get-Content -Raw (Join-Path $taskHl 'lib/index.js')
 $canonical=@([regex]::Matches($indexText,"require\('./languages/([^']+)'\)")|ForEach-Object{$_.Groups[1].Value})
 if($hlPackage.version -cne '10.7.3' -or $canonical.Count -ne 191 -or @($canonical|Sort-Object -Unique).Count -ne 191){throw 'Canonical191 highlight.js10.7.3 inventory changed'}
 $hlPaths=@((Join-Path $taskHl 'package.json'))+@(Get-ChildItem -LiteralPath (Join-Path $taskHl 'lib') -File|ForEach-Object{$_.FullName})+@($canonical|ForEach-Object{Join-Path $taskHl "lib/languages/$_.js"})
 $hlManifest=Join-Path $taskEvidence 'canonical-highlight191-before.json'
 $hlRows=Freeze-Paths $hlPaths $hlManifest
 $frozen+=@{name='canonical_highlight_package';rows=$hlRows}
 $candidatePaths=@(TaskGit @('ls-files')|ForEach-Object{Join-Path $taskPrivate $_})
 $candidateManifest=Join-Path $taskEvidence 'whole-candidate-before.json'
 $candidateRows=Freeze-Paths $candidatePaths $candidateManifest
 $frozen+=@{name='whole_candidate';rows=$candidateRows}
 $controlPaths=@($PSCommandPath,$taskOwner,$taskDriver,$taskInput,$taskObserver,$taskAudit,$hlManifest,$candidateManifest,(Join-Path $taskPrivate 'verification/highlight-lazy-batch9-prepared-20261015/original-native-factory-inputs.json'))+@($specs|ForEach-Object{Join-Path $taskRootEvidence $_.file})
 $controlManifest=Join-Path $taskEvidence 'controls-before.json'
 $controls=Freeze-Paths $controlPaths $controlManifest
 # Make every canonical external original visible to the immutable-source observer.
 $observedManifest=Join-Path $taskEvidence 'observer-controls-before.json'
 @($controls)+@($hlRows)|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $observedManifest -Encoding utf8NoBOM
 $observedManifestHash=(Get-FileHash -LiteralPath $observedManifest).Hash
 $sourcePathsBefore=@(Get-ChildItem -LiteralPath $taskSource -File -Force -Recurse|ForEach-Object{[IO.Path]::GetRelativePath($taskSource,$_.FullName)}|Sort-Object)
 $candidateNamesBefore=@(TaskGit @('ls-files'))
 $free=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
 if($free -lt 2MB){throw 'Root LIGHT5 Source2GiB admission denied'}
 @{status='admitted';candidate_head=$taskHead;candidate_files=$candidateRows.Count;canonical_languages=191;canonical_package_files=$hlRows.Count;free_kib=$free;required_kib=2MB;heap_mb=256;timeout_seconds=300;cases=109;expected_absent=$true;owner_sha256=(Get-FileHash -LiteralPath $taskOwner).Hash;caller_sha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash;input_sha256=(Get-FileHash -LiteralPath $taskInput).Hash;driver_sha256=(Get-FileHash -LiteralPath $taskDriver).Hash;node_sha256=(Get-FileHash -LiteralPath $taskNode).Hash;utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskEvidence 'admission.json') -Encoding utf8NoBOM
 State 'source-running'
 try {
  & $taskOwner -Name $taskName -Executable $taskNode -WorkingDirectory $taskSource -Arguments @('--max-old-space-size=256','--conditions=source','--import',([Uri]$taskObserver).AbsoluteUri,$taskDriver,$taskOutput,$taskInput) -TimeoutSeconds 300 -EnvironmentOverrides @{NODE_OPTIONS='';NODE_PATH='';PI_SOURCE_ORACLE_CONTROL_MANIFEST=$observedManifest}
 } finally {
  State 'full-posthash'
  $post=@();foreach($item in $frozen){$changed=@(Check-Rows $item.rows);$post+=@{name=$item.name;files=$item.rows.Count;drift=$changed.Count;changed=$changed}}
  $controlDrift=@(Check-Rows $controls)
  $absentDrift=@($absent|Where-Object{Test-Path -LiteralPath $_})
  $observerManifestDrift=(Get-FileHash -LiteralPath $observedManifest).Hash -cne $observedManifestHash
  $sourcePathsAfter=@(Get-ChildItem -LiteralPath $taskSource -File -Force -Recurse|ForEach-Object{[IO.Path]::GetRelativePath($taskSource,$_.FullName)}|Sort-Object)
  $pathDrift=@(Compare-Object $sourcePathsBefore $sourcePathsAfter)
  $candidateNameDrift=@(Compare-Object $candidateNamesBefore @(TaskGit @('ls-files')))
  $candidateHeadDrift=(TaskGit @('rev-parse','HEAD')) -cne $taskHead
  $candidateDirty=@(TaskGit @('status','--porcelain'))
  @{manifests=$post;control_drift=$controlDrift;observer_manifest_drift=$observerManifestDrift;absent_dependency_drift=$absentDrift;absence_records=$absent.Count;source_path_drift=$pathDrift;candidate_name_drift=$candidateNameDrift;candidate_head_drift=$candidateHeadDrift;candidate_dirty=$candidateDirty;expected_present=(Test-Path -LiteralPath $taskExpected);completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 7|Set-Content -LiteralPath (Join-Path $taskEvidence 'full-posthash.json') -Encoding utf8NoBOM
  if(@($post|Where-Object drift -ne 0).Count -or $controlDrift.Count -or $absentDrift.Count -or $observerManifestDrift -or $pathDrift.Count -or $candidateNameDrift.Count -or $candidateHeadDrift -or $candidateDirty.Count -or (Test-Path -LiteralPath $taskExpected)){throw 'Source109 immutable full-posthash controls drifted'}
 }
 $terminal=Get-Content -Raw (Join-Path $taskEvidence "$taskName.json")|ConvertFrom-Json
 if($terminal.status -cne 'passed' -or $terminal.exit_code -ne 0){throw 'Genuine Source109 process terminal failure'}
 $result=Get-Content -Raw $taskOutput|ConvertFrom-Json -Depth 1024
 if($result.cases -ne 109 -or @($result.rows).Count -ne 109 -or $result.source -cne 'highlight.js@10.7.3 actual installed modules'){throw 'Genuine Source109 output invalid'}
 Copy-Item -LiteralPath $taskOutput -Destination $taskExpected
 @{cases=109;expected_sha256=(Get-FileHash -LiteralPath $taskExpected).Hash;published_after_terminal_and_fullpost0=$true;native_compile_run=$false;native_runtime_run=$false;candidate_head=$taskHead}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence 'validation.json') -Encoding utf8NoBOM
 State 'passed-source109-fullpost0'
 Write-Output 'GENUINE_SOURCE109_TERMINAL_AND_FULLPOST0_EXPECTED_ACCEPTED'
} catch {
 State 'failed'
 @{message=$_.Exception.Message;stack=$_.ScriptStackTrace;utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskEvidence 'caller-error.json') -Encoding utf8NoBOM
 throw
}

$ErrorActionPreference='Stop'
$taskNativeSlot=1
if($taskNativeSlot -lt 1 -or $taskNativeSlot -gt 4){throw 'Prepared owner only: Root native slot grant is required before any prehash or launch'}
$taskEvidence='C:/Users/adyba/pi-zig-update-evidence-20261003'
$taskPrivate='C:/Users/adyba/pi-zig-ai-bedrock-lifecycle-files-source-20261015'
$taskExpectedHead='89710fd46e402cb392183e1c97ba4b807de41ce2'
$taskName='native-ai-bedrock-c18-lifecycle-89710fd4-debug-native1-20261015'
$taskZig='C:/Users/adyba/pi-zig-toolchain-20261003/zig-x86_64-windows-0.16.0/zig.exe'
$taskOwner=Join-Path $taskEvidence 'Invoke-OwnedEeSourceJob-20261012.ps1'
$taskToolReference=Join-Path $taskEvidence 'durable-latest89-full-inspect-53ae-tool-prehash-20261011.json'
function Source-Rows {
 @(git -C $taskPrivate ls-files --cached --others --exclude-standard|Sort-Object -Unique|Where-Object{Test-Path -LiteralPath (Join-Path $taskPrivate $_) -PathType Leaf}|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath (Join-Path $taskPrivate $_)).Hash}})
}
function Tool-Drift($rows){
 $mismatches=[Collections.Generic.List[string]]::new()
 foreach($row in $rows){
  if(!(Test-Path -LiteralPath $row.path -PathType Leaf)){$mismatches.Add($row.path);continue}
  $stream=[IO.File]::OpenRead($row.path)
  try{$actual=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream))}finally{$stream.Dispose()}
  if($actual -cne $row.sha256){$mismatches.Add($row.path)}
 }
 return @($mismatches)
}
if((git -C $taskPrivate rev-parse HEAD) -cne $taskExpectedHead -or (git -C $taskPrivate status --porcelain)){throw 'Exact clean candidate required'}
$taskBefore=Source-Rows
$taskVendorBefore=@($taskBefore|Where-Object path -Like 'vendor/*')
$taskTools=(Get-Content -LiteralPath $taskToolReference -Raw|ConvertFrom-Json).inputs
if($taskTools.Count -ne 19546){throw 'Full compiler manifest required'}
$taskReferenceSpecs=@(
 @{name='source';file='source5ab-full-manifest-20261015.json';count=1967},
 @{name='dependencies';file='durable-19cb534-reference-20261012-all-built-runtime.json';count=31064},
 @{name='node_tools';file='root-current8a-npm-tools-before.json';count=1774}
)
$taskReferences=@()
foreach($taskSpec in $taskReferenceSpecs){
 $taskRows=@(Get-Content -LiteralPath (Join-Path $taskEvidence $taskSpec.file) -Raw|ConvertFrom-Json)
 if($taskRows.Count -ne $taskSpec.count){throw "Full reference count mismatch $($taskSpec.name)"}
 $taskReferences+=@{name=$taskSpec.name;rows=$taskRows}
}
$taskAudit=Join-Path $taskEvidence 'source5ab-dependency-contract-audit-20261015.json'
$taskContract=Get-Content -LiteralPath $taskAudit -Raw|ConvertFrom-Json
if($taskContract.latestHead -cne '5ab7fe74c400097b386662205cd93900695b8a71' -or $taskContract.installed_metadata_verified -ne 281 -or $taskContract.platform_optional_absent_records -ne 80 -or $taskContract.historical_missing_records_retained -ne 4){throw 'Reference dependency contract mismatch'}
$taskReferenceRuntime='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012'
$taskAbsent=@($taskContract.pins|Where-Object status -eq 'platform_optional_absent'|ForEach-Object {Join-Path $taskReferenceRuntime $_.path})+@($taskContract.mismatches|ForEach-Object {Join-Path $taskReferenceRuntime $_.path})
function Check-References {
 $taskChecks=@()
 foreach($taskReference in $taskReferences){$taskMismatch=@(Tool-Drift $taskReference.rows);$taskChecks+=@{name=$taskReference.name;files=$taskReference.rows.Count;drift=$taskMismatch.Count;changed=$taskMismatch}}
 $taskAbsentPresent=@($taskAbsent|Where-Object {Test-Path -LiteralPath $_})
 $taskChecks+=@{name='absences';files=$taskAbsent.Count;drift=$taskAbsentPresent.Count;changed=$taskAbsentPresent}
 return $taskChecks
}
if($taskAbsent.Count -ne 84){throw 'Full84 historical absences required'}
$taskReferencePre=Check-References
if(@($taskReferencePre|Where-Object drift -ne 0).Count){throw 'Reference prehash drift'}
$taskReferencePre|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-reference-prehash.json") -Encoding utf8NoBOM
$taskControls=@($PSCommandPath,$taskOwner,$taskToolReference,'C:/Users/adyba/pi-zig-update-evidence-20261003/bedrock-empty-aws-20261015/config','C:/Users/adyba/pi-zig-update-evidence-20261003/bedrock-empty-aws-20261015/credentials',$taskAudit)+@($taskReferenceSpecs|ForEach-Object{Join-Path $taskEvidence $_.file})|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}}
if((Get-FileHash -LiteralPath $taskZig).Hash -cne '086CE9D47BA42F33A514E1A6E04EB1D4A8FA1D75E0868E0213CAAD447C91E864'){throw 'Pinned Zig SHA256 changed'}
$taskBefore|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-source-before.json") -Encoding utf8NoBOM
$taskControls|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-controls-before.json") -Encoding utf8NoBOM
if(@(Tool-Drift $taskTools).Count){throw 'Compiler prehash drift'}
if(@(Tool-Drift $taskControls).Count){throw 'Control prehash drift'}
[GC]::Collect();[GC]::WaitForPendingFinalizers();[GC]::Collect()
$taskFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
$taskOtherNative=@(Get-CimInstance Win32_Process -Filter "Name = 'zig.exe'"|Select-Object ProcessId,ParentProcessId,ExecutablePath,CommandLine,@{n='created_utc';e={([DateTimeOffset]$_.CreationDate).UtcDateTime.ToString('o')}})
$taskBuildRoots=@($taskOtherNative|Where-Object{$_.CommandLine -match '\sbuild\s'})
$taskAdmission=[ordered]@{status=if($taskFree -lt 16MB -or $taskBuildRoots.Count -ge 4){'admission_failed'}else{'admitted'};candidate=$taskExpectedHead;slot=$taskNativeSlot;free_kib=$taskFree;threshold_kib=16MB;max_native_roots=4;other_native=$taskOtherNative;source=$taskBefore.Count;vendor=$taskVendorBefore.Count;tools=$taskTools.Count;controls=$taskControls.Count;authority='Root native slot grant required before launch; maximum4 coordinated roots';jobs=1;llvm=$true;compile_timeout_seconds=1320;runtime_outer_timeout_seconds=300;test_timeout_seconds=120;host_await_timeout_seconds=10;native_launched=$false;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}
$taskAdmission|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-admission.json") -Encoding utf8NoBOM
if($taskAdmission.status -cne 'admitted'){$taskAdmission|ConvertTo-Json -Depth 6;exit 2}
& $taskOwner -Name "$taskName-compile" -Executable $taskZig -WorkingDirectory $taskPrivate -Arguments @('build','build-native-ai-bedrock18','build-native-ai-bedrock-credentials','-Doptimize=Debug','-Duse-llvm=true','-j1','--test-timeout','120s','--summary','all') -TimeoutSeconds 1320 -EnvironmentOverrides @{AWS_PROFILE='';AWS_DEFAULT_PROFILE='';AWS_ACCESS_KEY_ID='';AWS_SECRET_ACCESS_KEY='';AWS_SESSION_TOKEN='';AWS_BEARER_TOKEN_BEDROCK='';AWS_CONFIG_FILE='C:/Users/adyba/pi-zig-update-evidence-20261003/bedrock-empty-aws-20261015/config';AWS_SHARED_CREDENTIALS_FILE='C:/Users/adyba/pi-zig-update-evidence-20261003/bedrock-empty-aws-20261015/credentials';AWS_ROLE_ARN='';AWS_WEB_IDENTITY_TOKEN_FILE='';AWS_ROLE_SESSION_NAME='';AWS_ENDPOINT_URL_STS='';AWS_ENDPOINT_URL_SSO='';AWS_ENDPOINT_URL_SSO_OIDC='';AWS_ENDPOINT_URL_SIGNIN='';AWS_LOGIN_CACHE_DIRECTORY='';AWS_CONTAINER_CREDENTIALS_RELATIVE_URI='';AWS_CONTAINER_CREDENTIALS_FULL_URI='';AWS_CONTAINER_AUTHORIZATION_TOKEN='';AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE='';AWS_EC2_METADATA_DISABLED='true';AWS_EC2_METADATA_SERVICE_ENDPOINT='';AWS_EC2_METADATA_SERVICE_ENDPOINT_MODE='';AWS_EC2_METADATA_V1_DISABLED='';AWS_AUTH_SCHEME_PREFERENCE='';HTTP_PROXY='';HTTPS_PROXY='';ALL_PROXY='';NO_PROXY='127.0.0.1,localhost'}
$taskCompile=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName-compile.json") -Raw|ConvertFrom-Json
$taskRuntime=$null
if($taskCompile.status -ceq 'passed'){
 $taskBetween=Source-Rows
 if(@(Compare-Object ($taskBefore|ForEach-Object{"$($_.path):$($_.sha256)"}) ($taskBetween|ForEach-Object{"$($_.path):$($_.sha256)"})).Count -or @(Tool-Drift $taskTools).Count -or @(Tool-Drift $taskControls).Count){throw 'Frozen pair drift before runtime'}
 if(@(Check-References|Where-Object drift -ne 0).Count){throw 'Reference drift between compile and runtime'}
 $taskRuntimeFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
 if($taskRuntimeFree -lt 16MB){throw 'Fresh runtime admission below normal16GiB'}
 & $taskOwner -Name "$taskName-runtime" -Executable $taskZig -WorkingDirectory $taskPrivate -Arguments @('build','test-native-ai-bedrock18','test-native-ai-bedrock-credentials','-Doptimize=Debug','-Duse-llvm=true','-j1','--test-timeout','120s','--summary','all') -TimeoutSeconds 300 -EnvironmentOverrides @{AWS_PROFILE='';AWS_DEFAULT_PROFILE='';AWS_ACCESS_KEY_ID='';AWS_SECRET_ACCESS_KEY='';AWS_SESSION_TOKEN='';AWS_BEARER_TOKEN_BEDROCK='';AWS_CONFIG_FILE='C:/Users/adyba/pi-zig-update-evidence-20261003/bedrock-empty-aws-20261015/config';AWS_SHARED_CREDENTIALS_FILE='C:/Users/adyba/pi-zig-update-evidence-20261003/bedrock-empty-aws-20261015/credentials';AWS_ROLE_ARN='';AWS_WEB_IDENTITY_TOKEN_FILE='';AWS_ROLE_SESSION_NAME='';AWS_ENDPOINT_URL_STS='';AWS_ENDPOINT_URL_SSO='';AWS_ENDPOINT_URL_SSO_OIDC='';AWS_ENDPOINT_URL_SIGNIN='';AWS_LOGIN_CACHE_DIRECTORY='';AWS_CONTAINER_CREDENTIALS_RELATIVE_URI='';AWS_CONTAINER_CREDENTIALS_FULL_URI='';AWS_CONTAINER_AUTHORIZATION_TOKEN='';AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE='';AWS_EC2_METADATA_DISABLED='true';AWS_EC2_METADATA_SERVICE_ENDPOINT='';AWS_EC2_METADATA_SERVICE_ENDPOINT_MODE='';AWS_EC2_METADATA_V1_DISABLED='';AWS_AUTH_SCHEME_PREFERENCE='';HTTP_PROXY='';HTTPS_PROXY='';ALL_PROXY='';NO_PROXY='127.0.0.1,localhost'}
 $taskRuntime=Get-Content -LiteralPath (Join-Path $taskEvidence "$taskName-runtime.json") -Raw|ConvertFrom-Json
}
$taskAfter=Source-Rows
$taskVendorAfter=@($taskAfter|Where-Object path -Like 'vendor/*')
$taskVendorDrift=@(Compare-Object ($taskVendorBefore|ForEach-Object{"$($_.path):$($_.sha256)"}) ($taskVendorAfter|ForEach-Object{"$($_.path):$($_.sha256)"}))
$taskSourceDrift=@(Compare-Object ($taskBefore|ForEach-Object{"$($_.path):$($_.sha256)"}) ($taskAfter|ForEach-Object{"$($_.path):$($_.sha256)"}))
$taskToolDrift=@(Tool-Drift $taskTools)
$taskControlDrift=@(Tool-Drift $taskControls)
[ordered]@{candidate=$taskExpectedHead;source=$taskBefore.Count;source_after=$taskAfter.Count;source_drift=$taskSourceDrift.Count;vendor=$taskVendorBefore.Count;vendor_after=$taskVendorAfter.Count;vendor_drift=$taskVendorDrift.Count;tools=$taskTools.Count;tool_drift=$taskToolDrift.Count;controls=$taskControls.Count;control_drift=$taskControlDrift.Count;compile=$taskCompile.status;runtime=if($taskRuntime){$taskRuntime.status}else{'not_run'};completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Tee-Object -FilePath (Join-Path $taskEvidence "$taskName-posthash.json")
if($taskSourceDrift.Count -or $taskVendorDrift.Count -or $taskToolDrift.Count -or $taskControlDrift.Count){throw 'Frozen pair terminal posthash mismatch'}
$taskReferencePost=Check-References
$taskReferencePost|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $taskEvidence "$taskName-reference-posthash.json") -Encoding utf8NoBOM
if(@($taskReferencePost|Where-Object drift -ne 0).Count){throw 'Full reference terminal posthash mismatch'}
if($taskCompile.status -cne 'passed' -or !$taskRuntime -or $taskRuntime.status -cne 'passed'){exit 1}








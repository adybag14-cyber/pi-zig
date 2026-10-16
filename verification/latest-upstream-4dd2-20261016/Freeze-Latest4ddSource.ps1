param(
    [Parameter(Mandatory)][string]$CandidateHead,
    [Parameter(Mandatory)][string]$OutputManifest,
    [Parameter(Mandatory)][string]$Receipt,
    [ValidateSet('before','post')][string]$Phase='before',
    [string]$AdditionalControls
)
$ErrorActionPreference='Stop'
$taskCandidate=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$taskEvidence='C:\Users\adyba\pi-zig-update-evidence-20261003'
$taskSource='C:\Users\adyba\pi-upstream-source-4dd2b149-20261016'
$taskGit='C:\Program Files\Git\cmd\git.exe'
$taskDependencyLink=Join-Path $taskSource 'node_modules'
$taskDependencyTarget='C:\Users\adyba\pi-upstream-runtime-19cb534-20261012\node_modules'
function Check-DependencyLink {
    $taskItem=Get-Item -LiteralPath $taskDependencyLink -Force
    if($taskItem.LinkType -cne 'Junction' -or @($taskItem.Target).Count -ne 1){throw 'Expected owned Source dependency junction'}
    $taskTarget=[IO.Path]::GetFullPath([string]$taskItem.Target)
    if($taskTarget -ine $taskDependencyTarget){throw 'Source dependency junction target changed'}
    return @{path=$taskDependencyLink;target=$taskTarget;link_type=$taskItem.LinkType}
}
function Read-Rows([string]$Path){
    $taskDocument=Get-Content -LiteralPath $Path -Raw|ConvertFrom-Json
    if($taskDocument -is [System.Array]){return @($taskDocument)}
    if($taskDocument.inputs){return @($taskDocument.inputs)}
    return @($taskDocument)
}
function Check-Rows($Rows){
    $taskChanged=[Collections.Generic.List[string]]::new()
    foreach($taskRow in $Rows){
        try{if(!(Test-Path -LiteralPath $taskRow.path -PathType Leaf) -or
           (Get-FileHash -LiteralPath $taskRow.path).Hash -cne ([string]$taskRow.sha256).ToUpperInvariant()){$taskChanged.Add($taskRow.path)}}catch{$taskChanged.Add($taskRow.path)}
    }
    return @($taskChanged)
}
$taskMetadataErrors=[Collections.Generic.List[string]]::new()
try{
    $taskActualHead=(& $taskGit -C $taskCandidate rev-parse HEAD).Trim()
    if($LASTEXITCODE -ne 0 -or $taskActualHead -cne $CandidateHead){$taskMetadataErrors.Add('Exact candidate HEAD mismatch')}
    if((& $taskGit -C $taskCandidate status --porcelain).Count){$taskMetadataErrors.Add('Candidate dirty')}
    if((& $taskGit -C $taskSource rev-parse HEAD).Trim() -cne '4dd2b149d155d7369de16ea4dc77c84e9f5ffb24'){$taskMetadataErrors.Add('Official latest source HEAD mismatch')}
}catch{$taskMetadataErrors.Add('Git identity check failed')}
$taskActualLink=$null
try{$taskActualLink=Check-DependencyLink}catch{$taskMetadataErrors.Add('Source dependency junction mismatch')}
if($Phase -eq 'before'){
    if(Test-Path -LiteralPath $OutputManifest){throw 'Refuse to overwrite an existing before freeze'}
    $taskSpecs=@(
        @{name='source';path=(Join-Path $PSScriptRoot 'source4dd-full-manifest-before.json');count=1970},
        @{name='runtime';path=(Join-Path $taskCandidate 'verification/ai-model-operations-4954-20261015/reference-controls/source4954-runtime-manifest-20261015.json');count=31064},
        @{name='node';path=(Join-Path $taskCandidate 'verification/web-headers-node24-20261015/receipts/root-current8a-npm-tools-before.json');count=1774},
        @{name='compiler';path=(Join-Path $taskCandidate 'verification/ai-one-shot-native-20261015/pinned-compiler19546-reference.json');count=19546}
    )
    $taskGroups=@(foreach($taskSpec in $taskSpecs){
        $taskRows=@(Read-Rows $taskSpec.path)
        if($taskRows.Count -ne $taskSpec.count){$taskMetadataErrors.Add("Full $($taskSpec.name) inventory mismatch")}
        @{name=$taskSpec.name;rows=$taskRows;manifest_path=$taskSpec.path;manifest_sha256=(Get-FileHash -LiteralPath $taskSpec.path).Hash}
    })
    $taskCandidateRows=@(& $taskGit -C $taskCandidate ls-files|ForEach-Object {
        $taskPath=Join-Path $taskCandidate $_
        @{path=$taskPath;sha256=(Get-FileHash -LiteralPath $taskPath).Hash}
    })
    $taskGroups+=@{name='candidate';rows=$taskCandidateRows}
    $taskControls=@(
        'src/extensions/fixtures/sdk-summary-latest4dd.input.txt',
        'src/extensions/fixtures/sdk-summary-generation-b45.input.txt',
        'src/extensions/fixtures/ai-openai-tool-output4dd-native.input.txt',
        'src/extensions/fixtures/ai-google-tool-output4dd-native.input.txt',
        'verification/latest-upstream-4dd2-20261016/summary-source-capture.mjs',
        'verification/latest-upstream-4dd2-20261016/summary-original45-source-capture.mjs',
        'verification/latest-upstream-4dd2-20261016/source-observe.mjs',
        'verification/latest-upstream-4dd2-20261016/Freeze-Latest4ddSource.ps1',
        'verification/openai-tool-output4dd-prepared-20261016/capture-primary-tool-output.mjs',
        'verification/openai-tool-output4dd-prepared-20261016/primary-tool-callers.mjs',
        'verification/google-tool-output4dd-prepared-20261016/capture-primary-tool-output.mjs',
        'verification/google-tool-output4dd-prepared-20261016/primary-tool-callers.mjs',
        'verification/latest-upstream-4dd2-20261016/CAPTURE-PLAN.md',
        'verification/latest-upstream-4dd2-20261016/Run-Latest4ddSerialCapture.ps1',
        'verification/latest-upstream-4dd2-20261016/Invoke-Latest4ddPhase.ps1',
        'verification/latest-upstream-4dd2-20261016/source-network-guard.mjs',
        'verification/latest-upstream-4dd2-20261016/ordered-case-ids.json',
        'verification/latest-upstream-4dd2-20261016/Confirm-Latest4ddOuterAbsent.ps1',
        'verification/latest-upstream-4dd2-20261016/EXECUTABLE-LAUNCHER.md'
    )
    $taskGroups+=@{name='controls';rows=@($taskControls|ForEach-Object{$taskPath=Join-Path $taskCandidate $_;@{path=$taskPath;sha256=(Get-FileHash -LiteralPath $taskPath).Hash}})}
    if($AdditionalControls){$taskGroups+=@{name='run_controls';rows=@(Read-Rows $AdditionalControls)+@(@{path=$AdditionalControls;sha256=(Get-FileHash -LiteralPath $AdditionalControls).Hash})}}
    $taskOwner=Join-Path $taskEvidence 'Invoke-OwnedModelsClassSource-20261016.ps1'
    $taskOwnerHash=(Get-FileHash -LiteralPath $taskOwner).Hash
    if($taskOwnerHash -cne '96BEA0CF8E17535C322EE4F36C0115387386F16988BC2B98465BD070A504F5E5'){throw 'Retained exact Source owner changed'}
    $taskGroups+=@{name='owner';rows=@(@{path=$taskOwner;sha256=$taskOwnerHash})}
    $taskAbsences=@(Get-Content -LiteralPath (Join-Path $taskEvidence 'env-readable-pipe-source4954-absence84-resume-20261016.json') -Raw|ConvertFrom-Json|ForEach-Object {
        @{relative=$_.relative;runtime=$_.runtime;source=([string]$_.source).Replace('pi-upstream-source-4954d76-20261015','pi-upstream-source-4dd2b149-20261016')}
    })
    if($taskAbsences.Count -ne 84){throw 'Exact inherited absence84 inventory mismatch'}
    $taskFrozen=@{candidate_head=$CandidateHead;source_head='4dd2b149d155d7369de16ea4dc77c84e9f5ffb24';groups=$taskGroups;absences=$taskAbsences;dependency_link=$taskActualLink}
    $taskFrozen|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $OutputManifest -Encoding utf8NoBOM
    @($taskFrozen.groups|Where-Object {$_.name -in @('controls','run_controls')}|ForEach-Object{$_.rows})|ConvertTo-Json -Depth 5|Set-Content -LiteralPath ($OutputManifest+'.controls.json') -Encoding utf8NoBOM
}else{
    $taskFrozen=Get-Content -LiteralPath $OutputManifest -Raw|ConvertFrom-Json
    if($taskFrozen.candidate_head -cne $CandidateHead){$taskMetadataErrors.Add('Frozen candidate identity mismatch')}
    if($taskFrozen.dependency_link.path -cne $taskActualLink.path -or $taskFrozen.dependency_link.target -ine $taskActualLink.target -or $taskFrozen.dependency_link.link_type -cne $taskActualLink.link_type){$taskMetadataErrors.Add('Frozen dependency path/target mismatch')}
}
$taskFailures=$taskMetadataErrors.Count
$taskResults=@(foreach($taskGroup in $taskFrozen.groups){
    $taskChanged=@(Check-Rows @($taskGroup.rows))
    $taskFailures+=$taskChanged.Count
    @{name=$taskGroup.name;files=@($taskGroup.rows).Count;drift=$taskChanged.Count;changed=$taskChanged}
})
$taskPresent=@(foreach($taskAbsent in $taskFrozen.absences){foreach($taskPath in @($taskAbsent.runtime,$taskAbsent.source)){if(Test-Path -LiteralPath $taskPath){$taskPath}}})
$taskFailures+=$taskPresent.Count
@{phase=$Phase;candidate_head=$CandidateHead;dependency_link=$taskActualLink;metadata_errors=@($taskMetadataErrors);groups=$taskResults;absence_inventory=@($taskFrozen.absences).Count;unexpected_present=$taskPresent;failures=$taskFailures;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $Receipt -Encoding utf8NoBOM
if($taskFailures){throw "Full $Phase freeze failed: $taskFailures"}
Write-Output "LATEST4DD_FULL_$($Phase.ToUpperInvariant())_DRIFT=0"

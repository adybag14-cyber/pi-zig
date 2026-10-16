param(
    [Parameter(Mandatory)][string]$CandidateHead,
    [Parameter(Mandatory)][string]$OutputManifest,
    [Parameter(Mandatory)][string]$Receipt,
    [ValidateSet('before','post')][string]$Phase='before'
)
$ErrorActionPreference='Stop'
$taskCandidate=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$taskEvidence='C:\Users\adyba\pi-zig-update-evidence-20261003'
$taskSource='C:\Users\adyba\pi-upstream-source-4dd2b149-20261016'
function Read-Rows([string]$Path){
    $taskDocument=Get-Content -LiteralPath $Path -Raw|ConvertFrom-Json
    if($taskDocument.inputs){return @($taskDocument.inputs)}
    return @($taskDocument)
}
function Check-Rows($Rows){
    $taskChanged=[Collections.Generic.List[string]]::new()
    foreach($taskRow in $Rows){
        if(!(Test-Path -LiteralPath $taskRow.path -PathType Leaf) -or
           (Get-FileHash -LiteralPath $taskRow.path).Hash -cne ([string]$taskRow.sha256).ToUpperInvariant()){$taskChanged.Add($taskRow.path)}
    }
    return @($taskChanged)
}
$taskActualHead=(& git -C $taskCandidate rev-parse HEAD).Trim()
if($LASTEXITCODE -ne 0 -or $taskActualHead -cne $CandidateHead){throw 'Exact candidate HEAD mismatch'}
if((& git -C $taskCandidate status --porcelain).Count){throw 'Candidate must be clean before full freeze'}
if((& git -C $taskSource rev-parse HEAD).Trim() -cne '4dd2b149d155d7369de16ea4dc77c84e9f5ffb24'){throw 'Official latest source HEAD mismatch'}
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
        if($taskRows.Count -ne $taskSpec.count){throw "Full $($taskSpec.name) inventory mismatch"}
        @{name=$taskSpec.name;rows=$taskRows;manifest_path=$taskSpec.path;manifest_sha256=(Get-FileHash -LiteralPath $taskSpec.path).Hash}
    })
    $taskCandidateRows=@(& git -C $taskCandidate ls-files|ForEach-Object {
        $taskPath=Join-Path $taskCandidate $_
        @{path=$taskPath;sha256=(Get-FileHash -LiteralPath $taskPath).Hash}
    })
    $taskGroups+=@{name='candidate';rows=$taskCandidateRows}
    $taskControls=@(
        'src/extensions/fixtures/sdk-summary-latest4dd.input.txt',
        'src/extensions/fixtures/ai-openai-tool-output4dd-native.input.txt',
        'verification/latest-upstream-4dd2-20261016/summary-source-capture.mjs',
        'verification/latest-upstream-4dd2-20261016/source-observe.mjs',
        'verification/latest-upstream-4dd2-20261016/Freeze-Latest4ddSource.ps1',
        'verification/openai-tool-output4dd-prepared-20261016/capture-primary-tool-output.mjs',
        'verification/openai-tool-output4dd-prepared-20261016/primary-tool-callers.mjs'
    )
    $taskGroups+=@{name='controls';rows=@($taskControls|ForEach-Object{$taskPath=Join-Path $taskCandidate $_;@{path=$taskPath;sha256=(Get-FileHash -LiteralPath $taskPath).Hash}})}
    $taskAbsences=@(Get-Content -LiteralPath (Join-Path $taskEvidence 'env-readable-pipe-source4954-absence84-resume-20261016.json') -Raw|ConvertFrom-Json|ForEach-Object {
        @{relative=$_.relative;runtime=$_.runtime;source=([string]$_.source).Replace('pi-upstream-source-4954d76-20261015','pi-upstream-source-4dd2b149-20261016')}
    })
    if($taskAbsences.Count -ne 84){throw 'Exact inherited absence84 inventory mismatch'}
    $taskFrozen=@{candidate_head=$CandidateHead;source_head='4dd2b149d155d7369de16ea4dc77c84e9f5ffb24';groups=$taskGroups;absences=$taskAbsences}
}else{
    $taskFrozen=Get-Content -LiteralPath $OutputManifest -Raw|ConvertFrom-Json
    if($taskFrozen.candidate_head -cne $CandidateHead){throw 'Frozen candidate identity mismatch'}
}
$taskFailures=0
$taskResults=@(foreach($taskGroup in $taskFrozen.groups){
    $taskChanged=@(Check-Rows @($taskGroup.rows))
    $taskFailures+=$taskChanged.Count
    @{name=$taskGroup.name;files=@($taskGroup.rows).Count;drift=$taskChanged.Count;changed=$taskChanged}
})
$taskPresent=@(foreach($taskAbsent in $taskFrozen.absences){foreach($taskPath in @($taskAbsent.runtime,$taskAbsent.source)){if(Test-Path -LiteralPath $taskPath){$taskPath}}})
$taskFailures+=$taskPresent.Count
@{phase=$Phase;candidate_head=$CandidateHead;groups=$taskResults;absence_inventory=@($taskFrozen.absences).Count;unexpected_present=$taskPresent;failures=$taskFailures;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $Receipt -Encoding utf8NoBOM
if($taskFailures){throw "Full $Phase freeze failed: $taskFailures"}
if($Phase -eq 'before'){
    $taskFrozen|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $OutputManifest -Encoding utf8NoBOM
    @($taskFrozen.groups|Where-Object name -eq 'controls'|ForEach-Object{$_.rows})|ConvertTo-Json -Depth 5|Set-Content -LiteralPath ($OutputManifest+'.controls.json') -Encoding utf8NoBOM
}
Write-Output "LATEST4DD_FULL_$($Phase.ToUpperInvariant())_DRIFT=0"

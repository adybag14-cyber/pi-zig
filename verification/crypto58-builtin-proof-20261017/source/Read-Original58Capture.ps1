# Strict single-JSON framing/structure validator; no authored observation values.
function Assert-CryptoJsonUniqueProperties([System.Text.Json.JsonElement]$Element){
    if($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Object){
        $taskNames=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach($taskProperty in $Element.EnumerateObject()){
            if(!$taskNames.Add($taskProperty.Name)){throw 'Duplicate JSON property'}
            Assert-CryptoJsonUniqueProperties $taskProperty.Value
        }
    }elseif($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Array){foreach($taskItem in $Element.EnumerateArray()){Assert-CryptoJsonUniqueProperties $taskItem}}
}
function Read-CryptoSingleJson([byte[]]$Bytes){
    if($Bytes.Length -eq 0 -or $Bytes.Length -gt 2MB){throw 'Bounded capture JSON byte length required'}
    $taskText=[Text.UTF8Encoding]::new($false,$true).GetString($Bytes)
    if(!$taskText.StartsWith('{',[StringComparison]::Ordinal) -or !$taskText.EndsWith("}`n",[StringComparison]::Ordinal) -or $taskText.Contains("`r")){throw 'Exact single JSON object plus LF framing required'}
    $taskDocument=[System.Text.Json.JsonDocument]::Parse($taskText)
    try{Assert-CryptoJsonUniqueProperties $taskDocument.RootElement}finally{$taskDocument.Dispose()}
    return ConvertFrom-Json -InputObject $taskText -AsHashtable
}
function Read-CryptoOriginal58([byte[]]$Bytes,$Owner,[string[]]$CaseIds,[string]$InputSha256){
    $taskValue=Read-CryptoSingleJson $Bytes
    if((($taskValue.Keys|Sort-Object) -join ',') -cne 'capture,count,inputSha256,rows,runtime,subject'){throw 'Exact capture top-level fields required'}
    if(($taskValue.count -isnot [int] -and $taskValue.count -isnot [long]) -or $taskValue.rows -isnot [System.Array] -or ($taskValue.runtime.pid -isnot [int] -and $taskValue.runtime.pid -isnot [long])){throw 'Integer counts/PID and array rows required'}
    if($taskValue.subject -cne 'actual node:crypto SHA256 PackageManager dependency' -or $taskValue.count -ne 58 -or @($taskValue.rows).Count -ne 58 -or $CaseIds.Count -ne 58 -or $taskValue.inputSha256 -cne $InputSha256.ToLowerInvariant()){throw 'Original58 subject/input/census differs'}
    if((($taskValue.runtime.Keys|Sort-Object) -join ',') -cne 'execPath,executableSha256,pid,version'){throw 'Exact actual Node identity fields required'}
    if($taskValue.runtime.version -cne 'v24.14.0' -or $taskValue.runtime.pid -ne $Owner.pid -or $taskValue.runtime.execPath -ine $Owner.executable -or $taskValue.runtime.executableSha256 -cne '63c259c81e5d472b5f11c8d506070130cb04a1ecf84b80377a34ed6ec9048088'){throw 'Actual original Node identity differs'}
    for($taskIndex=0;$taskIndex -lt 58;$taskIndex++){
        $taskRow=$taskValue.rows[$taskIndex]
        if($taskRow -isnot [Collections.IDictionary] -or $taskRow.name -cne $CaseIds[$taskIndex]){throw 'Ordered original58 case ID differs'}
        $taskKeys=($taskRow.Keys|Sort-Object) -join ','
        if($taskKeys -cnotin @('name,value','error,name')){throw 'Original observation must contain exactly value or error'}
        if($taskKeys -ceq 'error,name'){
            if($taskRow.error -isnot [Collections.IDictionary] -or @($taskRow.error.Keys|Where-Object {$_ -cnotin @('name','message','code','raw')}).Count -or $taskRow.error.raw -isnot [bool]){throw 'Exact observation error structure required'}
            foreach($taskName in @('name','message','code')){if($taskRow.error.Contains($taskName) -and $taskRow.error[$taskName] -isnot [string]){throw 'Original error text fields must be strings'}}
        }
    }
    $taskCapture=$taskValue.capture
    if((($taskCapture.Keys|Sort-Object) -join ',') -cne 'addonAllowed,builtinOnly,childAllowed,deletedRuntimeUsed,environmentNames,filesystemWritesAllowed,moduleAttempts,networkAttempts,stdinFence,workerAllowed'){throw 'Exact builtin capture policy fields required'}
    foreach($taskName in @('stdinFence','builtinOnly')){if($taskCapture[$taskName] -isnot [bool] -or !$taskCapture[$taskName]){throw 'Builtin capture policy proof missing'}}
    foreach($taskName in @('deletedRuntimeUsed','childAllowed','workerAllowed','addonAllowed','filesystemWritesAllowed')){if($taskCapture[$taskName] -isnot [bool] -or $taskCapture[$taskName]){throw 'Standalone capture scope differs'}}
    if(@($taskCapture.networkAttempts).Count -or @($taskCapture.moduleAttempts).Count){throw 'Unexpected network or module resolution recorded'}
    return $taskValue
}

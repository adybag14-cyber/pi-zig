function Get-ModelsNativeCandidates {
 param([Parameter(Mandatory)][object[]]$Rows,[Parameter(Mandatory)][string]$Container)
 $taskContainerPrefix=[IO.Path]::GetFullPath($Container).TrimEnd('\')+'\'
 $taskContainedPattern=[regex]::Escape($taskContainerPrefix)+'(?:.*\\)?(?:\.zig-cache|zig-out)\\.*\.exe(?:["\s]|$)'
 foreach($taskRow in $Rows){
  $taskName=([string]$taskRow.Name).Trim()
  $taskExe=([string]$taskRow.ExecutablePath).Replace('/','\')
  $taskCommand=([string]$taskRow.CommandLine).Replace('/','\')
  $taskReasons=[Collections.Generic.List[string]]::new()
  if($taskName -iin @('zig.exe','build.exe','test.exe')){$taskReasons.Add('known_native_name')}
  if($taskExe.EndsWith('\zig.exe',[StringComparison]::OrdinalIgnoreCase)){$taskReasons.Add('zig_executable')}
  if($taskExe.StartsWith($taskContainerPrefix,[StringComparison]::OrdinalIgnoreCase)-and$taskExe -imatch '\\(?:\.zig-cache|zig-out)\\.*\.exe$'){$taskReasons.Add('contained_native_executable')}
  if($taskCommand -imatch $taskContainedPattern){$taskReasons.Add('contained_native_command_line')}
  # A wholly unidentified row cannot establish that no native candidate exists.
  if(!$taskName-and!$taskExe-and!$taskCommand){$taskReasons.Add('unclassified_missing_identity')}
  if(!$taskReasons.Count){continue}
  $taskCreated=$null
  if($null -ne $taskRow.CreationDate){try{$taskCreated=([DateTimeOffset]$taskRow.CreationDate).UtcDateTime.ToString('o')}catch{}}
  [pscustomobject][ordered]@{
   ProcessId=$taskRow.ProcessId;ParentProcessId=$taskRow.ParentProcessId;Name=$taskName
   ExecutablePath=$taskRow.ExecutablePath;CommandLine=$taskRow.CommandLine;created_utc=$taskCreated
   incomplete_identity=(!$taskExe-or!$taskCommand-or!$taskCreated-or!$taskRow.ProcessId)
   admission_reasons=@($taskReasons)
  }
 }
}

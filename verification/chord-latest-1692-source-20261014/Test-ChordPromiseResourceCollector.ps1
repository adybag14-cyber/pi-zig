$ErrorActionPreference='Stop'
$collector=Join-Path $PSScriptRoot 'Invoke-ChordPromiseResourceCandidate.ps1'
$tokens=$null;$errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile($collector,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Focused collector syntax failed'}
$function=$ast.Find({param($node)$node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Assert-Focused'},$true)
if(!$function){throw 'Actual focused collector function missing'}
. ([scriptblock]::Create($function.Extent.Text))
$ExpectedHead='9efabf6816231246be2153c89af0571144fbc8c1';$Mode='Debug';$Platform='windows-latest'
$proof=Join-Path $PSScriptRoot 'module-resource-9efabf68-debug'
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('chord-promise-collector-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot|Out-Null
try{
 [ordered]@{head=$ExpectedHead;source='1692bba6347a287ab0f3cb554a4430fafffc474b';zig_version='0.16.0';mode=$Mode;platform=$Platform;total_source_cases=54;public_activation=$false;full_pi_qualified=$false}|ConvertTo-Json|Set-Content "$testRoot/source.json"
 [ordered]@{head=$ExpectedHead;mode=$Mode;platform=$Platform;native_targets=2;compiled_tests=12;source_cases=4;guarded_source_cases=4;public_activation=$false;full_pi_qualified=$false}|ConvertTo-Json|Set-Content "$testRoot/focused-source.json"
 $prefix='chord-module-promise-debug-runtime-import-fifth-20261014'
 foreach($name in @('module','resource')){
  $result=Get-Content (Join-Path $proof "$prefix-$name-result.json") -Raw|ConvertFrom-Json
  # Adapt retained real owner/result fields to the hosted receipt schema, preserving every measured guard.
  [ordered]@{head=$result.head;status=$result.owner.status;exit_code=$result.owner.exit_code;root_pid_absent=$result.root_pid_absent;deadline_seconds=$result.outer_seconds;test_timeout_seconds=$result.test_seconds;host_await_seconds=$result.host_seconds;jobs=1}|ConvertTo-Json|Set-Content "$testRoot/runtime-$name-owner.json"
  foreach($side in @('stdout','stderr')){Copy-Item -LiteralPath (Join-Path $proof "$prefix-$name.$side.log") -Destination "$testRoot/runtime-$name.$side.log"}
 }
 $compile=Get-Content (Join-Path $proof 'chord-module-promise-debug-compile-import-fifth-20261014.json') -Raw|ConvertFrom-Json -AsHashtable
 $compilePost=Get-Content (Join-Path $proof 'chord-module-promise-debug-compile-import-fifth-20261014-posthash.json') -Raw|ConvertFrom-Json
 $compile.root_pid_absent=$compilePost.root_pid_absent
 $compile|ConvertTo-Json -Depth 8|Set-Content "$testRoot/compile-owner.json"
 $positive=Assert-Focused $testRoot
 if($positive.status -cne 'passed' -or $positive.components.Count -ne 2 -or $positive.components[0].targeted_vm_budget_coverage.completed -ne 514){throw 'Real retained focused positive failed'}
 $negativeCount=0
 $mutations=@(
  @{file='runtime-module.stderr.log';before='"completed":514';after='"completed":513'},
  @{file='runtime-module.stderr.log';before='"owner_leaks":0';after='"owner_leaks":1'},
  @{file='runtime-module.stderr.log';before='"successes_by_program":[229,102]';after='"successes_by_program":[228,103]'},
  @{file='runtime-module.stderr.log';before='CHORD_MODULE_VM_HEAP_LIMIT_COVERAGE=';after='REMOVED_VM_COVERAGE='},
  @{file='runtime-module.stderr.log';before='run test 7 pass (7 total)';after='run test 6 pass (7 total)'},
  @{file='runtime-resource.stderr.log';before='CHORD_RESOURCE_ORIGINAL_CALLER_FAILURE_INDEX=856 baseline=858';after='CHORD_RESOURCE_ORIGINAL_CALLER_FAILURE_INDEX=855 baseline=858'},
  @{file='runtime-resource.stderr.log';before='CHORD_RESOURCE_AWAIT_GPA_BASELINE_ALLOCATIONS=858';after='CHORD_RESOURCE_AWAIT_GPA_BASELINE_ALLOCATIONS=0'},
  @{file='runtime-resource-owner.json';before='"deadline_seconds": 300';after='"deadline_seconds": 301'},
  @{file='runtime-module-owner.json';before='"root_pid_absent": true';after='"root_pid_absent": false'},
  @{file='compile-owner.json';before='"status": "passed"';after='"status": "failed"'},
  @{file='focused-source.json';before='"public_activation": false';after='"public_activation": true'}
 )
 foreach($mutation in $mutations){
  $path=Join-Path $testRoot $mutation.file;$original=[IO.File]::ReadAllText($path)
  if(!$original.Contains($mutation.before,[StringComparison]::Ordinal)){throw "Negative test mutation did not match $($mutation.file)"}
  [IO.File]::WriteAllText($path,$original.Replace($mutation.before,$mutation.after))
  $rejected=$false
  try{Assert-Focused $testRoot|Out-Null}catch{$rejected=$true}
  finally{[IO.File]::WriteAllText($path,$original)}
  if(!$rejected){throw "Focused collector accepted negative $($mutation.before)"}
  $negativeCount++
 }
 [ordered]@{actual_collector=$collector;retained_positive=1;negative_rejections=$negativeCount;native_jobs=0;source_body_replaced=$false}|ConvertTo-Json
}finally{
 $resolved=[IO.Path]::GetFullPath($testRoot)
 $tempPrefix=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
 if(!$resolved.StartsWith($tempPrefix,[StringComparison]::OrdinalIgnoreCase) -or (Get-Item -LiteralPath $resolved).Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)){throw 'Collector temporary cleanup containment failed'}
 Remove-Item -LiteralPath $resolved -Recurse -Force
 if(Test-Path -LiteralPath $resolved){throw 'Collector owned temporary directory remains'}
}

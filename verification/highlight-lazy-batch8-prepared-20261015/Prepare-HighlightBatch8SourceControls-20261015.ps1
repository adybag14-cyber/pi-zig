$ErrorActionPreference='Stop'
$taskEvidence=$PSScriptRoot
$taskPrivate='C:/Users/adyba/pi-zig-highlight-lazy-batch8-20261015'
$taskNames="['coq','mipsasm','n1ql','purebasic','llvm','applescript','arcade','armasm','ruleslanguage','aspectj','sas','lasso','cos','clojure','elixir','excel','routeros','scheme','puppet','qml']"
$taskInput=Get-Content -LiteralPath (Join-Path $taskPrivate 'src/extensions/fixtures/sdk-highlight-lazy-batch3-10_7_3.input.txt') -Raw
$taskInput=$taskInput.Replace('batch3','batch8').Replace('Batch3','Batch8').Replace('102','106')
$taskInput=[regex]::Replace($taskInput,'(?m)^const names=.*?;$',('const names='+$taskNames+';'))
$taskSamples=@'
const samples={
 coq:['Theorem identity : forall P : Prop, P -> P.\nProof. intros P H. exact H. Qed.\n','(* TODO: proof *)\nInductive item : Type := Empty | Value : nat -> item.\n'],
 mipsasm:['.text\nmain:\n addiu $sp, $sp, -16\n li $v0, 1\n syscall\n','# TODO: MIPS\n.data\nvalue: .word 42\n lw $t0, value\n'],
 n1ql:["SELECT name, COUNT(*) FROM bucket WHERE active = true GROUP BY name;\n",'CREATE INDEX idx ON bucket(name); /* TODO */\nSELECT ARRAY_LENGTH(values) FROM bucket;\n'],
 purebasic:['Procedure.i Square(value.i)\n ProcedureReturn value * value\nEndProcedure\n','; TODO: PB\n#NAME = "hello"\nDebug #NAME\n'],
 llvm:['define i32 @square(i32 %x) {\nentry:\n %result = mul i32 %x, %x\n ret i32 %result\n}\n','; TODO: IR\n@message = private constant [6 x i8] c"hello\\00"\n'],
 applescript:['tell application "Finder"\n activate\nend tell\n','-- TODO: script\non greet(name)\n display dialog "Hello " & name\nend greet\n'],
 arcade:['var value = Abs(-42);\nreturn Text(value);\n','// TODO: GIS\nvar item = Feature($feature);\nreturn AreaGeodetic(item, "square-meters");\n'],
 armasm:['.text\nmain:\n mov r0, #42\n bx lr\n','; TODO: ARM\n.align 4\nloop:\n add r1, r1, #1\n bne loop\n'],
 ruleslanguage:['IF HASVALUE(NUMBER) THEN\n SET TOTAL = ROUND(NUMBER);\nEND\n','// TODO: rules\nFOR EACH ACCOUNT IN LIST\n CALL INTDLOAD;\nNEXT\n'],
 aspectj:['public aspect Logging { before(): execution(* demo.*(..)) { System.out.println("hello"); } }\n','/** @author demo */\npointcut calls(): call(* *(..));\n// TODO: AspectJ\n'],
 sas:['data demo;\n input name $ value;\n datalines;\nhello 42\n;\nrun;\n','%let value = 42;\nproc print data=demo;\nrun; /* TODO */\n'],
 lasso:['<?lasso local(name = "hello"); #name ?>\n','[noprocess]<p>text</p>[/noprocess]\n[define greet(name) => { return #name }]\n'],
 cos:['Class Demo.Item Extends %RegisteredObject\n{\n ClassMethod Run() { write "hello" quit }\n}\n','; TODO: COS\nset value = 42\nwrite $ztime(60), ^globalName\n'],
 clojure:['(ns demo.core)\n(defn square [x] (* x x))\n','; TODO: Clojure\n(let [value {:name "hello" :ready true}] (println value))\n'],
 elixir:['defmodule Demo do\n def square(x), do: x * x\nend\n','name = "world"\nIO.puts("hello #{name}")\nvalue = ~r/demo/i # TODO\n'],
 excel:['=SUM(A1:B10) + ROUND(AVERAGE(C1:C4), 2)\n','=IF(A1>0, "yes", "no") + N("TODO: formula")\n'],
 routeros:[':local name "demo"\n:put $name\n/ip address print\n','# TODO: RouterOS\n:foreach item in=[/interface find] do={ :put $item }\n'],
 scheme:['(define (square x) (* x x))\n(display (square 42))\n',"; TODO: Scheme\n(let ([value '(one two #t)]) (write value))\n"],
 puppet:['class demo { file { "/tmp/demo": ensure => present, content => "hello", } }\n','# TODO: config\n$owner = "demo"\npackage { "git": ensure => installed, }\n'],
 qml:['import QtQuick 2.0\nRectangle { id: root; width: 100; property string title: "Hello" }\n','Item { signal ready(int value); function square(x) { return x*x; } } // TODO\n']
};
'@
$taskInput=[regex]::Replace($taskInput,'(?s)const samples=\{.*?\n\};',[Text.RegularExpressions.MatchEvaluator]{param($m) $taskSamples})
$taskAlias=@'
record('actual batch8 canonical registration and aliases',()=>({registry:highlightCoreAPI.listLanguages(),aliases:[['mips','mipsasm'],['pb','purebasic'],['pbi','purebasic'],['osascript','applescript'],['arm','armasm'],['ls','lasso'],['lassoscript','lasso'],['cls','cos'],['clj','clojure'],['xlsx','excel'],['xls','excel'],['mikrotik','routeros'],['pp','puppet'],['qt','qml']].map(([alias,name])=>({alias,name,same:highlightCoreAPI.getLanguage(alias)===highlightCoreAPI.getLanguage(name)}))}));
record('AppleScript actual spread operations use live array iterator',()=>{const trace=[],original=Array.prototype[Symbol.iterator];Array.prototype[Symbol.iterator]=function(){trace.push(this.length);return Reflect.apply(original,this,[])};let grammar;try{grammar=highlightLazyFactories.applescript(highlightCoreAPI)}finally{Array.prototype[Symbol.iterator]=original}return{trace,graph:graph(grammar)}});
record('RouterOS actual dynamic keyword split and join calls',()=>{const trace=[],split=String.prototype.split,join=Array.prototype.join;String.prototype.split=function(...args){trace.push(['split',String(this),args]);return Reflect.apply(split,this,args)};Array.prototype.join=function(...args){trace.push(['join',this.length,args]);return Reflect.apply(join,this,args)};let grammar;try{grammar=highlightLazyFactories.routeros(highlightCoreAPI)}finally{String.prototype.split=split;Array.prototype.join=join}return{trace,graph:graph(grammar)}});
record('Elixir actual substitution shares complete language modes',()=>{const g=highlightLazyFactories.elixir(highlightCoreAPI);return{shared:g.contains[0].contains[1].contains===g.contains,rawOverrides:g.contains[0].variants.slice(2,6).map(mode=>mode.contains.length),lowerShared:g.contains[2].contains[0].contains[0].contains[1]===g.contains[0].contains[1]}});
record('Arcade actual template substitution shares parameter mode elements',()=>{const g=highlightLazyFactories.arcade(highlightCoreAPI),subst=g.contains[2].contains[1],params=g.contains[9].contains[1].contains;return{templateCycle:subst.contains[2]===g.contains[2],parameterNumber:params[3]===g.contains[6],sharedComment:params[5]===g.contains[4],graph:graph(subst)}});
'@
$taskInput=[regex]::Replace($taskInput,'(?m)^record\(''actual batch8 canonical registration and aliases''.*$', [Text.RegularExpressions.MatchEvaluator]{param($m) $taskAlias})
$taskTarget=Join-Path $taskPrivate 'src/extensions/fixtures/sdk-highlight-lazy-batch8-10_7_3.input.txt'
if(Test-Path -LiteralPath $taskTarget){throw 'Fresh batch8 fixture required'}
[IO.File]::WriteAllText($taskTarget,$taskInput,[Text.UTF8Encoding]::new($false))
$taskDriver=Get-Content -LiteralPath (Join-Path $taskEvidence 'capture-highlight-lazy-batch7-20261015.mjs') -Raw
$taskPrevious=[regex]::Match($taskDriver,'(?m)^const names=(.*?);$').Groups[1].Value
$taskBaseline=[regex]::Match($taskDriver,'(?m)^const baseline=(.*?);$').Groups[1].Value
$taskDriver=$taskDriver.Replace('batch7','batch8').Replace('Batch7','Batch8')
$taskDriver=[regex]::Replace($taskDriver,'(?m)^const baseline=.*?;$',('const baseline='+$taskBaseline.TrimEnd(']')+','+$taskPrevious.TrimStart('[')+';'))
$taskDriver=[regex]::Replace($taskDriver,'(?m)^const names=.*?;$',('const names='+$taskNames+';'))
[IO.File]::WriteAllText((Join-Path $taskEvidence 'capture-highlight-lazy-batch8-20261015.mjs'),$taskDriver,[Text.UTF8Encoding]::new($false))
$taskOwner=(Get-Content -LiteralPath (Join-Path $taskEvidence 'Run-HighlightLazyBatch7Source-20261015.ps1') -Raw).Replace('batch7','batch8').Replace('Batch7','Batch8')
[IO.File]::WriteAllText((Join-Path $taskEvidence 'Run-HighlightLazyBatch8Source-20261015.ps1'),$taskOwner,[Text.UTF8Encoding]::new($false))
Write-Output 'PREPARED_GENUINE_BATCH8_SOURCE106_CONTROLS_ONLY'

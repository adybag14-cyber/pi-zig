$ErrorActionPreference='Stop'
$taskEvidence=$PSScriptRoot
$taskPrivate='C:/Users/adyba/pi-zig-highlight-lazy-batch6-20261015'
$taskNames="['dust','autohotkey','sml','smali','apache','basic','lisp','elm','ocaml','tp','crmsh','xl','haml','actionscript','django','vhdl','nginx','axapta','avrasm','tcl']"
$taskInput=Get-Content -LiteralPath (Join-Path $taskPrivate 'src/extensions/fixtures/sdk-highlight-lazy-batch3-10_7_3.input.txt') -Raw
$taskInput=$taskInput.Replace('batch3','batch6').Replace('Batch3','Batch6')
$taskInput=[regex]::Replace($taskInput,'(?m)^const names=.*?;$',('const names='+$taskNames+';'))
$taskSamples=@'
const samples={
 dust:['<h1>{title}</h1>{#items}<p>{name}</p>{/items}\n','{! TODO: template !}{?ready}{>partial/}{:else}no{/ready}\n'],
 autohotkey:['#NoEnv\nMsgBox, Hello\nreturn\n','^j::\nRun, notepad.exe\nSleep, 1000\nreturn ; TODO\n'],
 sml:['fun square x = x * x;\nval answer = square 42;\n','(* TODO (* nested *) *)\ndatatype item = Empty | Value of int\n'],
 smali:['.class public Ldemo/Main;\n.super Ljava/lang/Object;\n.method public run()V\n const/4 v0, 0x1\n return-void\n.end method\n','# TODO: bytecode\n.field private name:Ljava/lang/String;\n invoke-virtual {v0}, Ldemo/Main;->run()V\n'],
 apache:['<VirtualHost *:80>\nServerName example.test\nDocumentRoot /var/www\n</VirtualHost>\n','# TODO: config\nRewriteEngine On\nRewriteRule ^/demo$ /index.php [L]\n'],
 basic:['10 PRINT "hello"\n20 GOTO 10\n','REM TODO: basic\nFOR I = 1 TO 42\n NEXT I\n'],
 lisp:['(defun square (x) (* x x))\n(print (square 42))\n','; TODO: lisp\n\'(one :two #\\Space)\n#| nested #| comment |# |#\n'],
 elm:['module Main exposing (main)\nmain = text "Hello"\n','{- TODO {- nested -} -}\ntype Item = Empty | Value Int\nvalue = if True then 42 else 0\n'],
 ocaml:['let square x = x * x\nlet value = square 42\n','(* TODO (* nested *) *)\ntype item = Empty | Value of int\n'],
 tp:['/PROG DEMO\n/MN\n1: CALL WORK ;\n2: R[1:count]=42 ;\n/END\n','! TODO: robot ;\nWAIT DI[1]=ON ;\nJ P[1] 100% CNT100 ;\n'],
 crmsh:['primitive web ocf:heartbeat:apache params configfile="demo"\n','node 1: alpha\nlocation prefer web 100: alpha\n# TODO: cluster\n'],
 xl:['import "demo"\nvalue x -> x + 42\n','// TODO: XL\nif true then text <<hello>>\n'],
 haml:['!!! 5\n%div.container\n  %h1= title\n','-# TODO: template\n%a{ :href => "/demo", :title => "hello" } Link\n'],
 actionscript:['package demo { public class Item extends Object { } }\n','function greet(name:String, ...args):void { trace("hello"); }\n// TODO\n'],
 django:['<h1>{{ title|upper }}</h1>\n','{% for item in items %}{{ item.name|default:"none" }}{% empty %}none{% endfor %}{# TODO #}\n'],
 vhdl:['entity demo is port(clk : in std_logic); end demo;\n','-- TODO: HDL\nsignal value : integer := 16#ff#;\nvalue <= 42 when ready = \'1\' else 0;\n'],
 nginx:['server { listen 80; server_name example.test; location / { proxy_pass http://backend; } }\n','# TODO: nginx\nset $value "hello ${name}";\nlocation ~* \\.php$ { fastcgi_pass 127.0.0.1:9000; }\n'],
 axapta:['public class Item extends Object { int value; }\n','ttsbegin;\nselect firstonly item where item.Value == 42;\nttscommit; // TODO\n'],
 avrasm:['.include "m128def.inc"\nldi r16, 0xff\nout DDRB, r16\n','; TODO: AVR\nloop:\n inc r16\n brne loop\n'],
 tcl:['proc square {x} { expr {$x * $x} }\nputs [square 42]\n','# TODO: Tcl\nset name "hello $::demo::name"\nputs ${value}\n']
};
'@
$taskInput=[regex]::Replace($taskInput,'(?s)const samples=\{.*?\n\};',[Text.RegularExpressions.MatchEvaluator]{param($m) $taskSamples})
$taskAlias=@'
record('actual batch6 canonical registration and aliases',()=>({registry:highlightCoreAPI.listLanguages(),aliases:[['ahk','autohotkey'],['crm','crmsh'],['pcmk','crmsh'],['tao','xl'],['as','actionscript'],['jinja','django'],['nginxconf','nginx'],['x++','axapta'],['tk','tcl']].map(([alias,name])=>({alias,name,same:highlightCoreAPI.getLanguage(alias)===highlightCoreAPI.getLanguage(name)})),ml:highlightCoreAPI.getLanguage('ml')===highlightCoreAPI.getLanguage('ocaml')}));
'@
$taskInput=[regex]::Replace($taskInput,'(?m)^record\(''actual batch6 canonical registration and aliases''.*$', [Text.RegularExpressions.MatchEvaluator]{param($m) $taskAlias})
$taskTarget=Join-Path $taskPrivate 'src/extensions/fixtures/sdk-highlight-lazy-batch6-10_7_3.input.txt'
if(Test-Path -LiteralPath $taskTarget){throw 'Fresh batch6 fixture required'}
[IO.File]::WriteAllText($taskTarget,$taskInput,[Text.UTF8Encoding]::new($false))
$taskDriver=Get-Content -LiteralPath (Join-Path $taskEvidence 'capture-highlight-lazy-batch5-20261015.mjs') -Raw
$taskPrevious=[regex]::Match($taskDriver,'(?m)^const names=(.*?);$').Groups[1].Value
$taskBaseline=[regex]::Match($taskDriver,'(?m)^const baseline=(.*?);$').Groups[1].Value
$taskDriver=$taskDriver.Replace('batch5','batch6').Replace('Batch5','Batch6').Replace('112','102')
$taskDriver=[regex]::Replace($taskDriver,'(?m)^const baseline=.*?;$',('const baseline='+$taskBaseline.TrimEnd(']')+','+$taskPrevious.TrimStart('[')+';'))
$taskDriver=[regex]::Replace($taskDriver,'(?m)^const names=.*?;$',('const names='+$taskNames+';'))
[IO.File]::WriteAllText((Join-Path $taskEvidence 'capture-highlight-lazy-batch6-20261015.mjs'),$taskDriver,[Text.UTF8Encoding]::new($false))
$taskOwner=(Get-Content -LiteralPath (Join-Path $taskEvidence 'Run-HighlightLazyBatch5Source-20261015.ps1') -Raw).Replace('batch5','batch6').Replace('Batch5','Batch6').Replace('112','102')
[IO.File]::WriteAllText((Join-Path $taskEvidence 'Run-HighlightLazyBatch6Source-20261015.ps1'),$taskOwner,[Text.UTF8Encoding]::new($false))
Write-Output 'PREPARED_GENUINE_BATCH6_SOURCE102_CONTROLS_ONLY'

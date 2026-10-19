# Actual synchronous native parameter ownership

This additive unit follows the existing linked QuickJS implementation's actual
argument-slot choice. Its source parent is commit
93c82663d21a9bcb38a5fe03f3e2757e5314d67c. The prior bytecode, async, template and
borrowed-operation algorithms are unchanged.

## VM ownership

JS_PiCallSyncArguments receives the original JSClassCall flags and argument
buffer. It uses the same JS_CallBytecode condition: COPY_ARGV or fewer actual
arguments than declared formals copies the declared slots and initializes the
missing slots to undefined; otherwise the caller's actual slots are shared.
Zero declared formals create no copied argument array. Observable Function.length
is a separate factory argument: Module(id = '', parent), for example, has length
zero and two declared parameter slots.

The native callback reads mutable parameters through JS_PiSyncArgumentGet and
consumes assignments through JS_PiSyncArgumentSet. The unchanged set_value
primitive stores the replacement before retiring the previous value. A native
callback must not continue reading a saved old argv slice after assignment.
Rest/default/arguments-object prologues remain each actual Source owner's work.

Captured parameters use actual JSVarRef objects and the existing close_var_ref,
free_var_ref and GC representation. The live stack table is borrowed. Dropping an
unescaped closure removes its entry without adding a hidden parameter copy.
Escaped closures detach to the current assigned value and continue to share that
same reference after the call.

Terminal order is: close parameter references; detach local capture cells;
retire copied formals; retire original local slots; release local state; release
the effective call receiver. Aliased arguments remain owned by the real caller.
Each cleanup reduces actual pending failures without inferring cause from
diagnostic DATA or a callback-wide allocation generation.

## Native opt-in

native_sync_arguments.Definition holds formal_count, callback, strictness and
optional detach/retire hooks. native_node_function adds createWithArguments,
createArrowWithArguments and createMethodWithArguments. Existing callbacks and
generated continuation plans retain their original route.

An opted-in callback uses Arguments.get/take/copy, and capture plus sync.read/
assign for escaping parameter references. For native lexical locals it calls
Arguments.createFrame(scope, FrameType) once and supplies
sync.frameHooks(FrameType). It must leave those locals installed until the C
terminal hooks run. The additive Frame.createSync lookup is borrowed;
detachCaptures closes local cells without prematurely retiring original locals.

The constructor adapter resolves the actual Object prototype through the
existing borrowed constructor bridge, allocates the actual receiver, then passes
that receiver and original flags to the argument owner. The raw JSClassCall
newTarget is never substituted for Source this. Arrows keep their actual
call-site receiver rooted while the callback ignores it.

These APIs are trusted native-owner interfaces. A stack frame pointer never
escapes; only the counted private reference owner can be retained by a closure.
The argument frame's bounded stack allocation is checked by the existing VM
stack guard. This unit does not claim equal bytecode recursion-budget accounting
for arbitrary native algorithms.

## Authored controls and validation boundary

src/native_vm_sync_arguments_test.zig contains 22 named controls under the
"VM sync arguments" filter. The install-only target is
build-native-vm-sync-arguments. The controls run literal Source functions and
actual native opt-ins in separate fresh engines over actual finalizable C
holders. They cover direct alias versus COPY_ARGV, missing/default formal count,
zero and extra arguments, call/apply/bound/spread routes, live reassignment,
escaped and dropped captures, store-before-free reentry, copied-argument versus
local retirement, closed-reference GC cycles, ordinary/method/arrow and real
cross-realm constructor behavior, private DATA, actual fatal precedence and
pending-entry ownership.

Source reviews are finite; installed artifact names, imported metadata, compiler
success and execution results still require Root's separately authorized build,
independent metadata audit and runtime phases. No native execution was performed
while authoring this unit.

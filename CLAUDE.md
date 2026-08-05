# hashlink-debugger

Debugger for the [HashLink](https://hashlink.haxe.org) VM.

## Code style

**Never let a tool change a file's line endings.** Files here are a mix of CRLF and LF, per file, in
this repo and in the HashLink and Haxe sources. `sed -i` under MSYS rewrites a CRLF file as LF, so a
one-line substitution turns into a whole-file diff that buries the real change — and it does it to
every file the glob matched, including the ones the substitution did not touch. Use the editing tools,
which preserve the convention; if a batch edit is genuinely needed, do it in a way that writes bytes
back unchanged, and check `git diff --stat` afterwards: a file whose insertions plus deletions equal
its length was rewritten, whatever the visible diff says.

**Do not add comments**, unless one is genuinely necessary. This holds for every file you touch —
this repo, the tests, and the HashLink and Haxe sources. Put whatever a change needs explained in
this file instead.

Existing comments are **not** off limits: edit, adapt or delete them as the code around them changes.
A comment left describing behaviour that no longer exists is worse than no comment, so a change that
invalidates one must update it rather than work around it.

## Architecture

- The debugger gets its data from the HashLink VM by **connecting to a socket**; the other end of
  that socket lives in the HashLink sources.
- Debug info (line numbers, variable names, register mapping) is embedded in the `.hl` file
  **by the Haxe compiler**.

VM and compiler internals are deliberately **not** documented here: they move independently of this
repo, and a stale description is worse than none. Where the debugger depends on something the VM
produces, this file names the debugger-side code that decodes it — read the current layout there, and
check the VM sources when that is not enough.

### Walking the stack

`Debugger.makeStack` does not unwind, it **scans**: every stack word that looks like a saved ebp
followed by a word that resolves into JIT code is taken for a frame. Three things keep that from
inventing frames, and all three are needed.

- The VM **erases the return address** of every HL call once the call returns, so the debris of calls
  that already completed cannot match. Without it the scan reports frames from a chain that is long
  gone. Erasing is on only under `--debug` without `--debug-opt`; V1 has always done this, V2 lost it
  and had it restored.
- `Debugger.isCallerOf` accepts a candidate only if it is **suspended on a call to the frame already
  found below it**, which anchors the whole chain on the innermost frame — that one is exact, it comes
  from the instruction pointer. The target is compared where the bytecode names it; for a closure,
  method or `this` call it cannot, and any callee is then accepted.
- A candidate's ebp must be **strictly above** the ebp of the frame already found below it. The stack
  grows down, so a caller always sits at a higher address, and a candidate that does not is debris —
  it is rejected rather than pushed, and the scan keeps looking. This is the only guard that survives
  a candidate `isCallerOf` cannot judge: it costs nothing, because the scan already walks in
  increasing address order.

The erase decides where a caller frame *resolves*, not only whether it is found: a return address
lands on the op **after** the call whenever the call is its op's last instruction, and the erase
instruction is what keeps it inside the call op. So without it every caller frame in `bt` reports the
following line — `tests/unit/TestCallerLine` pins that. `isCallerOf` tolerates both, since a native
call is never erased.

The erase also only covers a call that **returned**: an exception unwinds past its frames instead, so
everything the throw skipped keeps a real saved-ebp/return-address pair. A function entered after the
catch stands on that debris, and a frame with enough locals holds several of those pairs — each one a
candidate the ebp order rejects and nothing else would. Where the debris was left by a closure, method
or `this` call, `isCallerOf` waves it through, and the resulting frame reads as a wrong object of a
wrong type or throws a memory read failure that ends the session.

`tests/unit/TestStaleFrames` pins it. It reproduces on V2 and not on V1, whose frame layout puts no
usable pair inside the stopped function — so it guards V2 and merely runs on V1, which is still reason
to keep it in `tests/unit/`: it needs nothing from v6.

The ebp order is not checked for the synthetic frame the scan pushes at the bottom slot of the
scanned range while the innermost function is still in its prolog: that frame's ebp is `esp`, not a
scanned value, and the caller's saved ebp is not on the stack yet.

The scanned range does not always start at `esp`. A JIT frame of tens of kilobytes is subtracted from
`esp` in one go, and a function that never touches its lowest slots leaves those pages **uncommitted**
— one `api.read` over `esp → stackTop` then fails on the whole live stack, at the first stop, before a
single command. So `makeStack` falls back to `findReadableBase`, which binary searches the lowest
address the rest of the range reads from. That is sound because committed stack pages are contiguous
from the low-water mark up to the top, so readability is monotonic in the offset — and it loses
nothing, since the innermost frame comes from the registers and every frame the scan looks for sits
above the untouched region. A range that is unreadable *everywhere* still throws.

### Crossing a C frame

A C frame between the break and a JIT frame defeats the scan on its own: the debugger has no unwind
information for it, so it knows neither where the caller's frame is nor what the C code did with the
persist registers. Both are recovered, by two different mechanisms — which one applies depends on
whether the **VM was running** when the debugger stopped.

- **The break was raised from C** — a throw, `hl.Api.breakpoint`, an assert. The VM is executing, so
  it unwinds its own C frames first and leaves the innermost HL frame's `rip`, `rsp`, `rbp` and every
  register in the thread info, next to `exc_stack_trace`. `Debugger.readBreakContext` decodes it;
  `makeStack` takes its `rip`/`rsp`/`rbp` for the innermost frame, which also puts the whole C region
  outside the scanned range, and `Eval.readNatReg` reads registers from it instead of from the live
  CPU. This needs a platform unwinder and only Win64 has one in the VM, so elsewhere no context is
  captured — `Eval.nativeBreak` then makes register reads report `<overwritten>` rather than whatever
  the C code left behind, and `tests/v2/TestThrowRegs` is gated to Windows for that reason. Lifting it
  means unwinding with DWARF CFI: `_Unwind_Backtrace` plus `_Unwind_GetGR` reports the callee-saved
  registers per frame, and SysV has no callee-saved FPU register to recover.
- **A plain breakpoint under a native callback.** No VM code runs at an `INT3`, so nothing can be
  captured after the fact. Instead a native that can re-enter HL is **tagged**, and calls to it go
  through a trampoline that leaves a frame holding the caller's persist registers, its `ebp` and the
  call site. `makeStack` recognises such a frame by the address the trampoline returns to — the only
  part the VM sends — and hops over the C region in one step.

The trampoline frame is a **frame like any other**, reported as `<native>` and standing for the whole
C region below it, however many C functions that is. It carries `Eval.TRAMPOLINE_FIDX` as its `fidx`,
which is what every consumer tests to know a frame has no HL code behind it — no variables, no
stepping, no context. For registers it needs no special case at all: `Eval.getSavedRegs` answers for
it the way it answers for a JIT prologue, out of the vars blob. It saves *all* the persist registers,
so the walk never has to look past one — a register missing from it is one the call destroyed, not
one to keep searching for.

Its layout is **not** in the protocol: `JitInfo.makeTrampoline` derives it from the ABI, the way
`Eval.evalCall` already picks argument registers per calling convention. Read it there, and keep it in
step with the VM's own notion of persistent registers.

Tagging a native is `HL_CALLB` after the return type of its `DEFINE_PRIM`, which puts a flag at the end
of the signature the VM already checks when it resolves the native — so a third-party lib can tag its
own. Because the trampoline keeps a frame between caller and callee, arguments the caller passed on
the stack are no longer where the callee expects them: it forwards a fixed 32-byte window, which
covers four of them, and the JIT skips the trampoline entirely past that. So an over-eager tag loses
the frame rather than corrupting the call.

All of this is only emitted under `--debug` without `--debug-opt`. With `--debug-opt` a callback still
hides the frames below it, as before. `tests/v2/TestThrowRegs`, `tests/v2/TestNativeCallbackFrames` and
`tests/v2/TestCallbackNative` cover the three shapes.

#### A C region with no trampoline

A native the VM did **not** tag leaves no trampoline frame, and the scan still finds the HL frames
above it: a caller reached through a closure or method call is accepted by `isCallerOf` whatever the
callee turns out to be. So `bt` reports that caller directly above a frame that is *not* its callee,
with nothing in between — and the two frames are then **not adjacent**. A callee's saved-register area
holds the persist registers of the C code that called it, not the caller's, so reading a parent frame's
register variable out of it returns a wrong object, or an address that ends the session on a memory
read failure.

`Eval.isDirectCallee` is what keeps the walk out of that: a frame only answers for its caller's
registers if the **saved ebp at its frame base is that caller's ebp**, which is exactly the relation a
JIT prologue establishes and exactly what a hidden region breaks. The walk stops at the first frame
that fails the test and reports `<overwritten>` — the same outcome as a register the callee destroyed,
and the only honest one, since nothing on the stack says where the C code put the value. A trampoline
frame is compared at the caller ebp it carries itself (`rbpOffset`), so it passes by construction.

The check costs one pointer read per step and it also covers the flavours that involve no C code at
all: a frame the scan could not report — rejected by `isCallerOf`, or by the ebp ordering — leaves the
same gap, and a frame whose ebp was guessed rather than scanned fails it too.

`tests/v2/TestNativeGapRegs` pins it with `hl.Api.makeVarArgs`: calling the varargs closure it returns
crosses an untagged C wrapper, so the caller's `bt` entry sits right above a frame that is not its
callee. It has to be a V2 test — V1 keeps every variable in an EBP slot, so the gap costs it nothing.
What `bt` prints is still misleading there, the C region being invisible; only the register reads are
answered honestly.

### Stepping

`Debugger.step` places its breakpoints by walking the current function's CFG from the stop, and the
walk **must stay iterative** — it visits one position per bytecode op, so a recursion overflows the
*debugger's own* stack in a large function. `finish` is the one that reaches every op: it has no line
change to stop at, only a `CRet`, so it explores the whole function whatever its size.

There is deliberately no test for it: the overflow is a function of the *host* stack, so a function
big enough to trip it on Windows (1 MB) does nothing on Linux (8 MB), and one big enough for Linux
costs more time than the suite's per-test budget allows.

A `c <timeout>` sets `Debugger.customTimeout`, and while it is set `wait` hands `Timeout` and
`Handled` back to its caller instead of looping on them. That is only meaningful for the command
that asked for a timeout, so `Main` clears it when that command ends — otherwise the next
`next`/`step`/`finish`, or a call evaluated inside `p`, silently inherits it and aborts on the first
unrelated thread event.

### The exception value

What the VM hands over on a break is rarely what the user threw, so `Debugger.getException` is the
**one** place that normalises it — a `haxe.ValueException` is unwrapped to the value inside, a
`SysError` to its message, and a VM-raised error, which is a bare bytes dynamic rather than a
`String`, is decoded as UCS-2. Both frontends and `makeStack`'s own `Can't cast ` test read the
result, so anything doing this per-caller instead goes stale the moment one of the shapes changes —
that is how a bytes error message ended up reported as a hex preview.
`tests/unit/TestExceptionValue` pins the two ends of it.

## HL V1 / V2 compatibility

Both VM versions must keep working — `jit.hlVersion` tells them apart (`>= 2` is V2).

- **V1 has no native CPU registers**: every variable lives in a stack slot at a fixed EBP offset, so
  `readRegAddress` returns an `AAddr` directly and none of the native-register logic applies.
- **V2** places variables in CPU registers over code ranges, described by a per-function `vars` blob
  the VM sends (`jit.getFunctionVars`, `null` on V1 — always guard for it). Everything that reads
  that blob (overwrite detection, saved registers, parent-frame resolution) must stay inside the
  `hlVersion >= 2` branch or degrade to a no-op when `vars` is `null`.

The blob is a VM-side binary format. `Eval.getVarRecords` is the **only** place that decodes it, into
`Eval.VarRecord`; read the layout there rather than assuming one, and keep every other caller working
off `VarRecord` so a format change stays a one-line fix. `CodeGraph.LocalAccess.vid` gives the id to
look up for a variable at a code position, already encoded, so resolving is a plain
`rec.id == loc.vid`.

An id does **not** map to a single record, and records do **not** partition the code range. Each
assign of a variable is its own id, and all of them stay valid until the end of the variable's
scope, so records for branches that never ran still cover the current position. Where branches
merge, the VM emits one more record for the merged value and names it after the **first** assign it
can come from — both sides must agree on that, so `lookupLocal` keeps the lowest `vid` when
predecessors disagree, and the VM does the same when a phi inherits an id.

Consequently `readRegAddress` must pick, among the records matching `loc.vid` and covering the
position, the one that **starts last** — that is the merged value rather than a stale branch. Taking
any other match reads a register holding an unrelated value, which surfaces as a variable showing a
wrong object, `null`, or a memory read failure in the VSCode adapter.
`tests/v2/TestBranchAssignMerge` covers it.

That rule only works if the merged record starts **exactly** where the branches join, because a
breakpoint on the line that follows the assignment stops on the first op of that merge point. A
merged record starting even a few bytes later leaves only the branch records covering the
breakpoint, so the debugger reads the slot of the branch that may not have run — the variable then
shows a stale value that "fixes itself" after one step, once the position reaches the merged record.
`tests/v2/TestBranchMergeStart` covers it; the fix for such an off-by-one belongs in the VM, the
debugger cannot tell a late start from a genuinely later one.

A merged record's **end** must cover the op of its last read, since a breakpoint on the consuming
line stops *on* that op — an end computed from the reading op's own start leaves the record covering
everything but the one position that needs it. `tests/v2/TestMergedScopeEnd` covers it.

Past that last read the value is still in scope, so the VM widens a merged record's end to the
**scope end** rather than stopping at the last read. That alone is wrong, and the reason "starts last" is not the whole rule: a record
is a flat address range, while a merged value is only valid on the paths that reach its join. Between
an inner and an outer join sits the **other** predecessor's code, at a higher address, so a widened
inner record would win there and name a register that path never wrote.

So a record is only a candidate if the block its start falls in **dominates** the current position —
`CodeGraph.dominates`, answered on the debugger's own bytecode CFG by asking whether the entry block
still reaches the current block once the record's block is removed. `Eval.getRecordBlock` maps a
record's native start back to that block by comparing it against each block's first op address
(`jit.getCodePos`), biased by one byte because the VM starts a merged record one byte early.
`tests/v2/TestBranchAssignMerge` is the guard: its inner join does not dominate the `else if` that
follows, so the widened inner record must be rejected there. It has to stay under `tests/v2/` even
though it passes on older bytecode too — no v6 means no widening, so nothing is ever rejected and the
test passes just as well with the dominance check deleted.

Both halves are load-bearing and neither works alone. Widening without the dominance test reads the
wrong branch's register; the dominance test without widening leaves nothing covering the position,
and the read falls back to the assign from before the branch — a stale value, not an error.

The merged record therefore has to exist for **every** variable in scope at a join, including one
nothing reads afterwards. A merged value used to be emitted only where the program itself needed one,
so a variable assigned on both sides of a branch and then never read again kept each branch's own
storage — two records, two different registers, both widened to the scope end and neither valid past
the join. The dominance test then rejects the one the debugger resolved to, correctly, and the
variable reads `undef` even though it is plainly live. That is a **VM** defect and was fixed there,
not worked around here: nothing in the record set says which branch ran, so there is no debugger-side
answer. `tests/v2/TestDeadBranchMerge` pins it, and reads `undef` on a VM without the fix.

The shape is easy to miss because it needs the variable to be *dead* after the join, which is rare in
a test written on purpose and common in real code — an unused optional argument's default-value
prologue is exactly it, and so is a flag computed then handed straight to a call.

A name is only in scope where **every** path to the position writes it, so `CodeGraph.lookupLocal`
rejects one that a predecessor does not report — and one reported in a different register, which is an
inner scope shadowing it. Both rejections share an escape: a definition whose block **dominates** the
position is executed whatever the branches did, so it survives, the latest such one winning.

Neither half works alone, and they fail in opposite directions. Without the rejection a variable stays
listed past the end of its scope and reads `undef` — there was no merge there, so the VM emits no
merged record and the dominance test above rejects the branch record, correctly. Without the escape a
name shadowed in an inner scope is lost wherever a `break` and its loop exit meet, those two paths
reporting different registers, and it is lost for reading too, not only for listing. This surfaces as
a *parent frame* defect because a parent frame is stopped at a call, so nearly always past a join and
near the end of its function, where the most scopes have closed. `tests/unit/TestOutOfScope` pins both
halves.

Arguments — including `this` — are identified by **index**, never by an assign entry, because the
compiler emits no assign for `this`. `tests/unit/TestArgFirstLocal` covers the case that breaks when
that is confused: a local assigned at op 0 being consumed as an argument and becoming unresolvable.

An assign entry is only usable if the op it names **writes a register**: that write is what gives the
variable its storage, on both sides — the VM records nothing for an op that stores nothing, and
`CodeGraph.lookupLocal` reads the register out of the op itself with `opFx`. An assign naming an op
that only *reads* — a structure literal's `OSetField`, from `hlopt`'s assign remap before it was
fixed — is therefore resolvable nowhere, and `lookupLocal` hands back `rid = -1` with a null type.
That descriptor is not null, so `getLocalsRaw` lists the variable while every resolver fails on it,
and `info variables` ends the session on `Unknown identifier`.

This is **deliberately not guarded** here. The crash is the signal that the debug info is wrong, and
the fix belongs in the compiler, where the variable is genuinely readable afterwards rather than
merely hidden — skipping the assign silently drops the variable, or worse falls back to an earlier
one and reads a value that has since been overwritten. Read `rid = -1`, or a `Null access` out of
`Eval.typeStr` on `info dbg_regs`, as *this* diagnosis.

### Variable scopes and overwritten registers (bytecode v6)

Without help, the JIT frees a variable's register at its **last read**, so a variable that is still
in scope but no longer used reads as `<overwritten>` — or worse, as whatever value took the register
over. Bytecode **version 6** fixes this: the compiler records a *scope end* per assign, and the VM
keeps the register reserved for as long as the variable is in scope.

What that means for this repo:

- v6 is only emitted when compiling with `-D hl-ver=2.0.0` or higher, so tests that rely on it belong
  under [tests/v2/](tests/v2/), not [tests/unit/](tests/unit/). A test lands there **by accident** far
  more easily than it should: any breakpoint placed past a value's last read reads `<overwritten>`
  without v6, so a test about something else entirely — a name, a type, a display — ends up needing
  v6. Keep every value the test prints live past the stop (read it again on a later line) and the test
  belongs in `tests/unit/`, where it runs against both VM versions instead of one.
- Scope extension only applies under `--debug <port>` **without** `--debug-opt`. `--debug-opt` gives
  back full JIT speed while debugging, at the cost of `<overwritten>` variables — so a test asserting
  a variable stays readable past its last read must not run with it.
- Older bytecode carries no scope info and degrades to the previous behaviour, which is why
  `<overwritten>` must stay a supported outcome rather than an error.
- `-D hl-ver=2.0.0` only *asks* for v6; the compiler still has to emit it. An older `haxe.exe` accepts
  the flag and silently writes v4, so the whole of `tests/v2/` runs on v4 and passes for the wrong
  reason — every v6-only behaviour untested, and a VM change that breaks the v6 path green. **Check
  the byte, don't trust the flag**: `xxd -l 8 test.hl` prints `HLB` followed by the version, which must
  be `06`. Worth doing whenever a v2 test starts passing or failing for no visible reason.
- Reading v6 also needs the **`format` haxelib to know about it**. The stock one throws
  `HL Version 6 is not supported` and reads two fields per assign instead of three; the third is the
  scope end (`-1` below v6). `format/hl/Reader.hx` and `format/hl/Data.hx` carry a local patch for
  that. It fails loudly rather than silently, but only once a compiler that emits v6 is on PATH.

Known gap: the VM reports a **single** location per value, so a variable that moved between a
register and a stack slot during its lifetime is reported at its final location over its whole range,
and reads wrong before the move.

### Local VM builds

Testing both VM versions needs a separate HashLink checkout per version — one on the V2 branch, one
on a 1.16 tag. Rebuild each from its own checkout root with

```sh
MSBuild hl.vcxproj    /p:Configuration=Release /p:Platform=x64
MSBuild libhl.vcxproj /p:Configuration=Release /p:Platform=x64
```

Both matter, and for different reasons — **`hl.exe` holds the JIT** (register allocation, and the
`vars` blob), while **`libhl.dll` holds the debug API** the debugger calls to read the debuggee's
memory and CPU registers. The optional lib projects in `hl.sln` fail on a missing v142 toolset; that
is unrelated, build the two projects above on their own.

Building `libhl.vcxproj` drops `libhl.dll` into `x64\Release` next to `hl.exe`, where it wins the DLL
search. Skip it and `hl.exe` silently picks up whatever `libhl.dll` sits on `PATH` — often an
unrelated runtime copy that no VM build refreshes. A mismatched one breaks V2 variable reads
wholesale, in a way that looks like a debugger bug: register reads come back 0, so variables in a
native register read as `0` or garbage while stack-slot variables still read fine. **Suspect this
first when most V2 tests fail at once with zeroed values** — check it by comparing the two files'
build times before debugging anything in this repo.

Running the suite against V1 needs `-D hl-ver=1.16.0` on **both** the debugger and the test programs
— the Haxe 5 std lib otherwise calls natives that VM does not have and thread init crashes at
startup. `RunCi` takes care of that, see [Building / running](#building--running).

When changing anything around variable resolution, run the unit tests against **both** a V1 and a V2
`hl` build.

### Local Haxe compiler build

Fixing a "bad debug info" bug sometimes means rebuilding the compiler from a Haxe checkout. Two
traps, on Windows:

- The OCaml toolchain only resolves from the **cygwin shell embedded in the checkout**
  (`opam/repo/.cygwin/root/bin/bash.exe`), with the opam env sourced for that switch. Running `dune`
  from Git Bash instead fails in `flexlink` with `cygpath: error converting "/usr/lib/gcc/..."`.
- The dev profile turns warnings into errors, so build with `dune build --profile release
  src/haxe.exe`, then copy `_build/default/src/haxe.exe` over the `haxe.exe` on `PATH`.

## Building / running

- Command-line version: build in the [debugger/](debugger/) directory
  (`haxe debugger.hxml` → `debug.hl`, run with `hl debug.hl`).
- Unit tests: in the [tests/](tests/) directory (`haxe RunCi.hxml`). Each test is a folder under
  [tests/unit/](tests/unit/) containing `Test.hx`, optional `compile.txt` (extra haxe flags),
  `input.txt` (debugger commands) and `output.txt` (expected output). `haxe RunCi.hxml` uses the
  `hl` on PATH and the prebuilt `debugger/debug.hl`.
- Tests under [tests/v2/](tests/v2/) have the same layout but need a HL 2 VM: they are compiled with
  `-D hl-ver=2.0.0` (so, v6 bytecode) and the whole directory is skipped when targeting an older VM.
- A test whose subject only works on some systems carries a `platform.txt` listing the
  `Sys.systemName()` values it runs on, one per line, and is skipped elsewhere. Use it only where the
  *behaviour* is platform-specific, never to paper over a platform-specific bug.
- `--hl` sets the VM for **both** roles, and both matter. It runs the debugger, and `RunCi` forwards it
  to the debugger's `--cmd` so it runs the debuggee too. Without that forwarding the debuggee launches
  under the `hl` on PATH: the JIT under test is then never exercised, only its debug API, and the whole
  suite passes against a VM whose code generation was never run.
- Unit tests against another VM: `hl RunCi.hl --hl-ver <version> --hl <path to that hl>`
  (`haxe RunCi.hxml` first, to rebuild `RunCi.hl`). `--hl-ver` adds `-D hl-ver=` to every test
  compile and rebuilds the debugger as `debugger/debug-<version>.hl` from `debugger.hxml`, so the
  V2 `debug.hl` is left alone. Against a V1 build:

  ```sh
  hl RunCi.hl --hl-ver 1.16.0 --hl <v1-checkout>/x64/Release/hl.exe
  ```

### Installing the debugger after a change

Once a debugger change is done and tested, build it and **overwrite the installed extension** so the
machine actually runs it (`make build` needs `-lib vscode -lib vshaxe -lib vscode-debugadapter`):

```sh
haxe -cp src -lib vscode -lib vshaxe -lib vscode-debugadapter -D js-es=6 -js extension.js Extension
haxe build.hxml            # -> adapter.js
haxe debugger.hxml         # -> debugger/debug.hl, from the debugger/ directory
cp adapter.js extension.js bindings.js package.json \
   "<vscode-extensions-dir>/haxefoundation.haxe-hl-<version>/"
```

Copy `package.json` too whenever launch options or settings changed, otherwise VSCode will not offer
them. Reload the VSCode window to pick the new files up.

## Debugging a "variable displays wrong" report

A report gives: project name (e.g. `test`), the `.hx` file, the line number, and the variable that
displays incorrectly.

Workflow:

1. Locate the project's `.hl` file so you know **which file to run from which cwd**.
2. Get a native dump: run `hl --dump <project.hl>` with a **debug** build of `hl`. This prints a full
   bytecode + native code dump to stdout.
3. Add a reproducing unit test under [tests/unit/](tests/unit/) and run it.
4. Once the issue is reproducible, fix it in the debugger, the HashLink VM, or the Haxe compiler —
   depending on which layer is wrong.

**A test must always be standalone.** Never breakpoint into a Haxe std file (`Reflect.hx`,
`Array.hx`, …): its line numbers move with every compiler version, so the test would break for
reasons unrelated to the debugger. When a report points at a std function, reproduce the *shape* of
that function — its arity, argument types, and what the first statements do — in the test's own
`Test.hx`, and breakpoint there. Prefer argument and variable types whose expected output is
unambiguous, so `output.txt` states plainly what a correct read must return.

### Locating the faulty layer

Three `info` commands split the responsibility:

| Command              | Checks                                                              | Fix location    |
| -------------------- | ------------------------------------------------------------------- | --------------- |
| `info dbg_natregs`   | The VM giving bad **native** register information                    | HashLink VM     |
| `info dbg_regs`      | The debugger resolving the variable to the wrong **virtual** register | this repo       |
| `info dbg_hlregs`    | The Haxe compiler giving bad info for a variable                     | Haxe compiler   |

Two of them also work away from the current frame, which is what makes a report on a **big program
you cannot easily drive to the faulty line** tractable — launch it under the command-line debugger
and answer both questions while it is still paused at startup, without ever running it:

- `info dbg_natregs <fidx>` lists the records of any function, not just the one being executed.
- `info dbg_oppos <fidx> <from> <to>` prints where each bytecode op of a function starts in native
  code, with its source line.

Together they say whether the record that should be live at a given line actually covers the address
the breakpoint on that line lands at. Get `<fidx>` by loading the `.hl` with `hld.Module` and looking
up `getBreaks(file, line)`.

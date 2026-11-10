# hashlink-debugger

Debugger for the [HashLink](https://hashlink.haxe.org) VM.

## What goes in this file

Rules and traps that hold across the repo. A rule a later edit could break unnoticed (see Code style)
is one bullet in this shape; procedures and traps may be plain bullets or paragraphs, under the same
cap:

```
- **<The rule, imperative.>** Code: `<where it holds>`. Why: <what breaks without it>. Test: `<what pins it>`.
```

- **Keep each entry under 60 words**, bullet or paragraph, counted in words, not lines. Go past it
  only for a very strong reason: an entry that does not fit is usually two rules, or carries history.
  `Why` is one sentence, omitted when the rule is obvious.
- **Amend an existing entry before adding one**, and delete it when its code goes.
- **Not here**: how a bug was found, what used to be broken, measurements, why a test sits in a given
  directory, VM or compiler internals beyond what a rule needs. They go stale, and they cost every
  session.

## Code style

**Never let a tool change a file's line endings.** Files mix CRLF and LF, per file, here and in the
HashLink and Haxe sources, and `sed -i` under MSYS rewrites CRLF as LF. Use the editing tools; after
a batch edit, a file whose `git diff --stat` insertions plus deletions equal its length was rewritten.

**Do not add comments**, unless one is genuinely necessary — then one line. This holds for every file
you touch — this repo, the tests, and the HashLink and Haxe sources. A change gets an entry here only
if a later edit could break it without failing a test on every run; most changes need none.

Existing comments are **not** off limits: edit, adapt or delete them as the code around them changes.
A comment left describing behaviour that no longer exists is worse than no comment, so a change that
invalidates one must update it rather than work around it.

**Mention only public projects and public setup** — this repo, Haxe, HashLink, and the public libs
and tools they build with — in this file, the code, the tests, commit and PR messages. Anything else,
including the program a report came from, is described by its shape, the way a test reproduces it.

## Architecture

- The debugger gets its data from the VM over a **socket**; the other end lives in the HashLink
  sources.
- Debug info (lines, variable names, register mapping) is written into the `.hl` by the **Haxe
  compiler**.

Where the debugger depends on something the VM produces, read the layout in the debugger-side code
that decodes it, then in the VM sources.

### Stack walking

- **Scan, don't unwind: a candidate frame must pass `isCallerOf` and have an ebp strictly above the
  frame below it, except the synthetic prolog frame.** Code: `Debugger.makeStack`. Why: `isCallerOf`
  cannot judge closure, method or `this` calls, so debris left by an exception passes as a caller.
  Test: `TestStaleFrames`.
- **Rely on the VM erasing the return address of every returned HL call, under `--debug` without
  `--debug-opt`.** Code: `Debugger.makeStack`. Why: otherwise finished calls show up as frames, and
  callers resolve to the next line. Test: `TestCallerLine`.
- **Start the scan at the lowest readable address, not at `esp`.** Code: `Debugger.findReadableBase`.
  Why: a large JIT frame leaves uncommitted pages under `esp`, and one read of the whole range fails.
- **A break raised from C takes the innermost frame and its registers from the break context.** Code:
  `Debugger.readBreakContext`, `Eval.readNatReg`. Why: only Win64 captures one; elsewhere
  `Eval.nativeBreak` must report `<overwritten>`, not what C left. Test: `TestThrowRegs` (Windows).
- **Treat a trampoline frame (native tagged `HL_CALLB`) as a normal frame with
  `Eval.TRAMPOLINE_FIDX`, its layout matching the VM's persist registers.** Code:
  `JitInfo.makeTrampoline`. Test: `v2/TestNativeCallback`.
- **Never look for a saved register past a trampoline frame.** Code: `Eval.getSavedRegs`. Why: it
  saves every persist register, so one missing there was destroyed by the call, and searching further
  reads a C frame's value as the caller's.
- **A frame answers for its caller's registers only if its saved ebp is the caller's ebp.** Code:
  `Eval.isDirectCallee`. Why: across an untagged C region the saved registers are the C code's. Test:
  `v2/TestNativeGapRegs`.

### Connecting

- **`HLAdapter.CONNECTION_TIMEOUT` (`hldebug.connectionTimeout`) is the only deadline on waiting for
  the VM to start; never add another, even for launch — stopping early on `procExited` is fine.**
  Code: `Debugger.connectTries`. Why: a second deadline makes raising the setting useless.

### Stepping

- **Keep the CFG walk iterative.** Code: `Debugger.step`. Why: recursion overflows the debugger's own
  stack on large functions. Test: none, the limit depends on the host stack.
- **Restore an INT3 hit while single-stepping past a `CRet`/`CCall`; never take it for the
  single-step trap.** Code: `Debugger.wait`. Why: resuming mid-instruction corrupts `rsp`. Tests:
  `TestReturnBreakpoint`, `TestStepMultiReturn` (guards only a VM without the `--debug` epilogue
  `NOP`), both needing three values live across a call to get a shared epilogue.
- **Clear `Debugger.customTimeout` when the command that set it ends.** Code: `Main` (`c <timeout>`),
  `HLAdapter`. Why: otherwise the next step, or a call inside `p`, aborts on an unrelated thread event.

### Exception value

- **Normalise the thrown value only in `Debugger.getException`.** Why: decoding it per caller goes
  stale when one of its shapes changes. Test: `TestExceptionValue`.

## HL V1 / V2 compatibility

Both VM versions must keep working; `jit.hlVersion >= 2` is V2. V1 keeps every variable in an EBP
slot; V2 describes register placement in a per-function `vars` blob. When changing variable
resolution, run all three configurations.

- **Guard every use of the `vars` blob.** Code: `jit.getFunctionVars`. Why: it is `null` on V1, where
  `Eval.readRegAddress` returns an `AAddr` directly.
- **Decode the blob only in `Eval.getVarRecords`; elsewhere work off `Eval.VarRecord` and resolve by
  `rec.id == loc.vid`.** Why: a format change then stays a one-line fix.
- **Among the records covering the position, keep those whose start block dominates it, and take the
  one starting last.** Code: `Eval.readRegAddress`, `CodeGraph.dominates`, `Eval.getRecordBlock`. Why:
  records of branches that never ran, and merged records widened to the scope end, name registers
  this path never wrote. Tests: `TestBranchAssignMerge` (v6 run only), `TestMergedScopeEnd`.
- **When predecessors disagree, keep the lowest `vid`.** Code: `CodeGraph.lookupLocal`. Why: the VM
  names a merged value after its first assign.
- **Fix a variable reading `undef` after a join, or a stale value that fixes itself after one step,
  in the VM's merged record.** Why: nothing in the records says which branch ran, so the debugger
  cannot. Test: `v2/TestDeadBranchMerge`.
- **Drop a name that a predecessor does not report, or reports in another register, unless its
  definition dominates.** Code: `CodeGraph.lookupLocal`. Why: without the drop a variable outlives its
  scope; without the escape a shadowed name is lost where a `break` meets the loop exit. Test:
  `TestOutOfScope`.
- **On v6, an assign is a candidate only while `pos < scopeEnd`.** Code: `CodeGraph.lookupLocal`.
  Why: a dominating definition otherwise stays listed after its inner scope, on a reused register.
  Test: `v2/TestLoopVarScope`.
- **Resolve arguments, `this` included, by index.** Why: the compiler emits no assign for `this`.
  Test: `TestArgFirstLocal`.
- **Do not guard `rid = -1`, or a `Null access` in `Eval.typeStr` on `info dbg_regs`: fix the
  compiler's debug info.** Why: a guard hides the variable or reads an overwritten one.

Known gap: the VM reports one location per value, so a variable moved between register and stack
slot reads wrong before the move.

### Bytecode v6

v6 records a scope end per assign, and the VM keeps the register reserved until then.

- Only emitted with `-D hl-ver=2.0.0` or higher, and only applied under `--debug` **without**
  `--debug-opt`. `<overwritten>` stays a supported outcome, not an error.
- The flag only asks: an older `haxe.exe` silently writes v4. **Check the byte**: `xxd -l 8 test.hl`
  must print `HLB` then `06`.
- The `format` haxelib carries a local patch (`format/hl/Reader.hx`, `Data.hx`) to read v6.

## Building / running

- Command-line debugger: `haxe debugger.hxml` in [debugger/](debugger/) → `debug.hl`, run with
  `hl debug.hl`.
- Tests: `haxe RunCi.hxml` in [tests/](tests/), with the `hl` on PATH and the **prebuilt**
  `debugger/debug.hl` — rebuild it after a debugger change, or the suite tests the old one.
- **Never delete or loosen an existing test to make a change pass; change its expected output only
  when the old one was wrong.** Why: tests are what lets a fix go without an entry here, so a failing
  one is a regression until shown otherwise.
- A test is a folder with `Test.hx`, optional `compile.txt` (extra haxe flags, appended after the
  directory's, so it wins), `input.txt` and `output.txt`.
- [tests/v2/](tests/v2/) has the same layout, is always compiled with `-D hl-ver=2.0.0`, and is
  skipped on an older VM.
- `platform.txt` lists the `Sys.systemName()` values a test runs on — only when the *behaviour* is
  platform-specific, never to hide a bug. `output-<Sys.systemName()>.txt` replaces `output.txt` where
  the correct output differs (usually the ABI); `output.txt` is SysV, and `Mac` falls back to it.
- `--hl` sets the VM for **both** the debugger and the debuggee. `--hl-ver` adds `-D hl-ver=` to
  `tests/unit/` and rebuilds the debugger as `debugger/debug-<version>.hl`. Rebuild `RunCi.hl` with
  `haxe RunCi.hxml` first.

### The three configurations

A change is tested only once all three are green:

| command | VM | `tests/unit/` | `tests/v2/` |
| --- | --- | --- | --- |
| `hl RunCi.hl --hl-ver 1.16.0 --hl <v1>/x64/Release/hl.exe` | V1 | **v4** | skipped |
| `haxe RunCi.hxml` | V2 on PATH | **v4** | **v6** |
| `hl RunCi.hl --hl-ver 2.0.0` | V2 on PATH | **v6** | **v6** |

The middle row compiles `tests/unit/` at v4 even on a V2 VM; only the third runs it at v6.

> **A test that passes in all three goes in `tests/unit/`, never in `tests/v2/`** — even when its
> subject is v6. `tests/v2/` is only for a test that needs a V2 VM or whose output differs between v4
> and v6.

To keep a test in `tests/unit/`, read every value it prints again on a later line: past its last
read a value is `<overwritten>` without v6.

### Local VM builds

One HashLink checkout per version (V2 branch, 1.16 tag). From each root:

```sh
MSBuild hl.vcxproj    /p:Configuration=Release /p:Platform=x64
MSBuild libhl.vcxproj /p:Configuration=Release /p:Platform=x64
```

`hl.exe` holds the JIT, `libhl.dll` the debug API. Skip the second and `hl.exe` loads whatever
`libhl.dll` is on `PATH`: register reads come back 0. **Suspect this first when most V2 tests fail
with zeroed values**, and compare the two files' build times. Other projects in `hl.sln` fail on a
missing v142 toolset; ignore them.

### Local Haxe compiler build

- Run from the cygwin shell of the opam install the checkout uses, with the opam env sourced; Git Bash
  fails in `flexlink`.
- `dune build --profile release src/haxe.exe`, then copy `_build/default/src/haxe.exe` over the one
  on `PATH`.

### Installing the debugger after a change

```sh
haxe -cp src -lib vscode -lib vshaxe -lib vscode-debugadapter -D js-es=6 -js extension.js Extension
haxe build.hxml            # -> adapter.js
haxe debugger.hxml         # -> debugger/debug.hl, from the debugger/ directory
cp adapter.js extension.js bindings.js package.json \
   "<vscode-extensions-dir>/haxefoundation.haxe-hl-<version>/"
```

Then reload the VSCode window.

## Debugging a "variable displays wrong" report

A report gives the project, the `.hx` file, the line and the variable.

1. Find the project's `.hl` and the cwd it runs from.
2. `hl --dump <project.hl>` with a **debug** `hl` for a bytecode + native dump.
3. Add a reproducing test under [tests/unit/](tests/unit/).
4. Fix it in the layer that is wrong.

**Tests are standalone**: never breakpoint into a Haxe std file, its lines move with each compiler.
Reproduce the std function's shape in `Test.hx`, with types whose correct output is unambiguous.

| Command            | Checks                                                  | Fix in        |
| ------------------ | ------------------------------------------------------- | ------------- |
| `info dbg_natregs` | the VM's **native** register info                       | HashLink VM   |
| `info dbg_regs`    | the debugger's mapping to a **virtual** register        | this repo     |
| `info dbg_hlregs`  | the compiler's debug info for the variable              | Haxe compiler |

For a program you cannot drive to the line, stay paused at startup: `info dbg_natregs <fidx>` lists
any function's records, `info dbg_oppos <fidx> <from> <to>` where each op starts in native code. Get
`<fidx>` from `hld.Module`'s `getBreaks(file, line)`.

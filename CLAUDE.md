# hashlink-debugger

Debugger for the [HashLink](https://hashlink.haxe.org) VM.

## Code style

**Never add comments.** This holds for every file you touch — this repo, the tests, and the HashLink
and Haxe sources. Leave the existing ones alone, and put whatever a change needs explained in this
file instead.

## Architecture

- The debugger gets its data from the HashLink VM by **connecting to a socket**; the other end of
  that socket lives in the HashLink sources.
- Debug info (line numbers, variable names, register mapping) is embedded in the `.hl` file
  **by the Haxe compiler**.

VM and compiler internals are deliberately **not** documented here: they move independently of this
repo, and a stale description is worse than none. Where the debugger depends on something the VM
produces, this file names the debugger-side code that decodes it — read the current layout there, and
check the VM sources when that is not enough.

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

Arguments — including `this` — are identified by **index**, never by an assign entry, because the
compiler emits no assign for `this`. `tests/unit/TestArgFirstLocal` covers the case that breaks when
that is confused: a local assigned at op 0 being consumed as an argument and becoming unresolvable.

### Variable scopes and overwritten registers (bytecode v6)

Without help, the JIT frees a variable's register at its **last read**, so a variable that is still
in scope but no longer used reads as `<overwritten>` — or worse, as whatever value took the register
over. Bytecode **version 6** fixes this: the compiler records a *scope end* per assign, and the VM
keeps the register reserved for as long as the variable is in scope.

What that means for this repo:

- v6 is only emitted when compiling with `-D hl-ver=2.0.0` or higher, so tests that rely on it belong
  under [tests/v2/](tests/v2/), not [tests/unit/](tests/unit/).
- Scope extension only applies under `--debug <port>` **without** `--debug-opt`. `--debug-opt` gives
  back full JIT speed while debugging, at the cost of `<overwritten>` variables — so a test asserting
  a variable stays readable past its last read must not run with it.
- Older bytecode carries no scope info and degrades to the previous behaviour, which is why
  `<overwritten>` must stay a supported outcome rather than an error.

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

# hashlink-debugger

Debugger for the [HashLink](https://hashlink.haxe.org) VM.

## Architecture

- The debugger gets its data from the HashLink VM by **connecting to a socket**. The VM side lives in the
  HashLink sources, in `debugger.c`.
- Debug info (line numbers, variable names, register mapping) is embedded in the `.hl` file
  **by the Haxe compiler**.

## HL V1 / V2 compatibility

Both VM versions must keep working — `jit.hlVersion` tells them apart (`>= 2` is V2).

- **V1 has no native CPU registers**: every variable lives in a stack slot at a fixed EBP offset, so
  `readRegAddress` returns an `AAddr` directly and none of the native-register logic applies.
- **V2** places variables in CPU registers over code ranges, described by the per-function `vars`
  blob sent by the VM (`jit.getFunctionVars`, `null` on V1 — always guard for it). Everything that
  reads that blob (overwrite detection, saved registers, parent-frame resolution) must stay inside
  the `hlVersion >= 2` branch or degrade to a no-op when `vars` is `null`.

The `vars` blob is a flat array of 16-byte records `(id, start, end, reg)`, emitted by
`hl_regs_flush` in HashLink's `jit_regs.c`:

- `0 <= id < nargs` — the **argument** `id` lives in native location `reg` over the code range
  `[start, end)`. Every argument is tracked, including `this`, for which the Haxe compiler emits no
  assign entry — so an argument cannot be identified by an assign, only by its index.
- `id >= nargs` — same, for the value of a *variable* (not of a virtual register), produced by the
  assign at **op position `id - nargs`**. Op positions are shifted above the arguments because the
  two namespaces would otherwise overlap.
- `id < 0` — a persistent register the prolog pushes: `reg` is saved at `start` (an offset relative
  to that function's EBP). Used to read a parent frame's registers off its callees' stacks. Those
  records come first in the blob.

`Eval.getVarRecords` parses the blob into that form; `CodeGraph.LocalAccess.vid` gives the id to look
up for a variable at a code position, already encoded, so resolving is a plain `rec.id == loc.vid`.

The JIT tags argument values in `hl_emit_function`'s prolog, where `ctx->in_args` tells
`emit_store_reg` not to match them against an assign — a local assigned at op 0 would otherwise be
consumed by the `this` store and become unresolvable (`tests/unit/TestArgFirstLocal` covers it).

### Local VM builds

| Version | Sources                  | `hl.exe`                                   |
| ------- | ------------------------ | ------------------------------------------ |
| V2      | `D:\Projects\hashlink`    | `D:\Projects\hashlink\x64\Release\hl.exe` (the one on PATH) |
| V1 1.16 | `D:\Projects\hashlink_v1` | `D:\Projects\hashlink_v1\x64\Release\hl.exe` |

Rebuild the VM with
`MSBuild hl.vcxproj /p:Configuration=Release /p:Platform=x64` — the JIT (`jit_emit.c`, `jit_regs.c`)
lives in `hl.exe`, not in `libhl.dll`. The optional lib projects in `hl.sln` fail on a missing v142
toolset; that is unrelated, build `hl.vcxproj` alone.

Running the suite against V1 needs `-D hl-ver=1.16.0` on **both** the debugger and the test programs
— the Haxe 5 std lib otherwise calls natives that VM does not have and thread init crashes at
startup. `RunCi` takes care of that, see [Building / running](#building--running).

When changing anything around variable resolution, run the unit tests against **both** a V1 and a V2
`hl` build.

## Building / running

- Command-line version: build in the [debugger/](debugger/) directory
  (`haxe debugger.hxml` → `debug.hl`, run with `hl debug.hl`).
- Unit tests: in the [tests/](tests/) directory (`haxe RunCi.hxml`). Each test is a folder under
  [tests/unit/](tests/unit/) containing `Test.hx`, optional `compile.txt` (extra haxe flags),
  `input.txt` (debugger commands) and `output.txt` (expected output). `haxe RunCi.hxml` uses the
  `hl` on PATH and the prebuilt `debugger/debug.hl`.
- Unit tests against another VM: `hl RunCi.hl --hl-ver <version> --hl <path to that hl>`
  (`haxe RunCi.hxml` first, to rebuild `RunCi.hl`). `--hl-ver` adds `-D hl-ver=` to every test
  compile and rebuilds the debugger as `debugger/debug-<version>.hl` from `debugger.hxml`, so the
  V2 `debug.hl` is left alone. For the V1 build listed above:

  ```sh
  hl RunCi.hl --hl-ver 1.16.0 --hl D:/Projects/hashlink_v1/x64/Release/hl.exe
  ```

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

### Locating the faulty layer

Three `info` commands split the responsibility:

| Command              | Checks                                                              | Fix location    |
| -------------------- | ------------------------------------------------------------------- | --------------- |
| `info dbg_natregs`   | The VM giving bad **native** register information                    | HashLink VM     |
| `info dbg_regs`      | The debugger resolving the variable to the wrong **virtual** register | this repo       |
| `info dbg_hlregs`    | The Haxe compiler giving bad info for a variable                     | Haxe compiler   |

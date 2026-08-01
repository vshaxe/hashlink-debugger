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

- `id >= 0` — variable `id` lives in native location `reg` over the code range `[start, end)`.
- `id < 0` — a persistent register the prolog pushes: `reg` is saved at `start` (an offset relative
  to that function's EBP). Used to read a parent frame's registers off its callees' stacks.

When changing anything around variable resolution, run the unit tests against **both** a V1 and a V2
`hl` build.

## Building / running

- Command-line version: build in the [debugger/](debugger/) directory
  (`haxe debugger.hxml` → `debug.hl`, run with `hl debug.hl`).
- Unit tests: in the [tests/](tests/) directory (`haxe RunCi.hxml`). Each test is a folder under
  [tests/unit/](tests/unit/) containing `Test.hx`, optional `compile.txt` (extra haxe flags),
  `input.txt` (debugger commands) and `output.txt` (expected output).

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

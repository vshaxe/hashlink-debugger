## 1.4.29 (April 17, 2025)

* improved display on ValueException, now show inner error
* fixed return I64 display
* fixed missing static var inside @:struct
* allow eval hl.NativeArray similar to an Array
* allow inspect inside hl.CArray with hint

## 1.4.28 (March 7, 2025)

* improved support for multi-line string
* added Add To Watch support for Enum, Map (by index)

## 1.4.27 (February 4, 2025)

* fixed vscode not focusing on exception when the stack is empty
* added hl.GUID support for hl & haxe nightly

## 1.4.26 (January 23, 2025)

* fixed error on mac when hl is only available after preLaunchTask (#135)

## 1.4.25 (January 16, 2025)

* fixed expression 1e2, 1e-5 showing as infinity (lib hscript)
* added an early error when trying to debug hl/c
* fixed step next break on inner recursive call
* fixed copy value returning wrong result

## 1.4.24 (November 26, 2024)

* fixed launch error displayed twice
* added error message when bytecode has no debug info
* fixed eval error when variable reuse argument registers
* added comparison string/null
* fixed can't get fields for this warning when break in std
* added pointer hint display for funRepr, HAbstract
* added command @d @f for advanced debugging based on pointer
* fixed evalCall corrupting jit registers R10, R11
* fixed conditional breakpoint in small loop blocking the debugger

## 1.4.23 (October 14, 2024)

* fixed reg corruption when eval call fail early (e.g. unsupported arg)
* added variables section Add To Watch support

## 1.4.22 (August 9, 2024)

* added connection timeout in settings
* improved bin/hex hint display, now as 2's complement and full length
* added ArrayBytes I64 support for haxe nightly build

## 1.4.21 (July 23, 2024)

* fixed stack when Null access .xxx and Can't cast xxx to String
* fixed f32 array display
* added array access for bytes
* added eval hint UI8(i), UI16(i), I32(i), I64(i), F32(i), F64(i) for bytes

## 1.4.20 (July 15, 2024)

* fixed Sys.command detected as access violation on Linux

## 1.4.19 (July 11, 2024)

* fixed restart stopped thread still show as stopped

## 1.4.18 (July 5, 2024)

* fixed multi captured variable
* fixed map value fetch when the size is around 128
* fixed inlined variable display when captured as args
* improved step on throw with try-catch handler

## 1.4.17 (July 1, 2024)

* added break only active process for multi-target debugging
* added eval hint p for other values with pointer representation

## 1.4.16 (June 24, 2024)

* added previous exception stack in variables section when hl.Api.rethrow
* added eval hint p for pointer

## 1.4.15 (June 20, 2024)

* fixed eval call: stack/reg/breakpoint corruption, function resolution
* fixed single captured variable
* fixed macOS code signature verification when hl path has spaces (#132)

## 1.4.14 (June 5, 2024)

* fixed eval this

## 1.4.13 (June 3, 2024)

* improved eval access to class with file/package prefix
* added eval support for null-safe field access operator (?.)
* added comparison for enum value

## 1.4.12 (May 30, 2024)

* fixed comparison pointer/null
* fixed compound launch

## 1.4.11 (May 28, 2024)

* added a pop-up when hl exit code 4 (debug port occupied)
* added comparison for pointer, int64, bool
* fixed step when leaving function on Linux

## 1.4.10 (May 2, 2024)

* fixed thread exception before first breakpoint
* fixed pause before first breakpoint on Linux

## 1.4.9 (April 22, 2024)

* fixed timeout/breakpoint/stop on Linux

## 1.4.8 (April 17, 2024)

* fixed exception window not shown

## 1.4.7 (April 16, 2024)

* added configuration snippets
* added extension settings
* added comparison for string, fixed not equal (!=) not working
* fixed continue not working on Linux

## 1.4.6 (April 5, 2024)

* added eval hint support

## 1.4.5 (March 26, 2024)

* added inlined constructor variable support for haxe nightly build
* improved source line resolution when break by value watch
* improved eval when hovering haxe keywords
* fixed error message when failed to evaluate variable path
* improved eval access to abstract type
* added support for conditional breakpoint
* added debug context menu option show as hex/bin

## 1.4.4 (October 13, 2023)

* fixed dynobj support with hl 1.15

## 1.4.3 (September 16, 2023)

* disable eval of getters by default
* remove deasync requirement (fix vscode 1.82)
* added OPrefetch support
* additional fixes

## 1.4.2 (June 23, 2023)

* fixed some eval calls causing crashes on node

## 1.4.0 (January 28, 2023)

* added support of hl 1.13 maps and @:packed
* added named threads support
* added evaluation of method calls
* object getter resolution

## 1.3.4 (July 27, 2022)

* improved multithread support
* added int64 support
* added @:packed and improved @:struct support
* (again) fixed timeout issue when connecting on debug port

## 1.3.2 (April 14, 2022)

* fixed timeout issue when connecting on debug port

## 1.3.1 (March 23, 2022)

* changed to native API (no longer FFI, super fast)
* fixed timing issue at startup with latest node

## 1.2.2 (Jan 29, 2022)

* added support for return value display
* added support for data breakpoints
* fixed display of empty array/map and closure
* improved set variable
* allow numeric operations in expression eval
* bug fixes

## 1.1.2 (May 6, 2021)

* fixed support for VSCode 1.56 (Electron 12.0)

## 1.1.1 (September 26, 2020)

* fixed pause was broken again
* improved multithread support
* fixed some vars displayed as <...> after some time
* fixed bug when stepping out of some functions

## 1.1.0 (June 13, 2020)

* removed the need to specify `hxml` in `launch.json` (#4)
* added OSX support (contributed by @rcstuber, thanks!)
* added closures context display
* added closures stack (requires HL 1.12+)
* bug fixes

## 1.0.0 (February 2, 2020)

* reimplemented the step system using predictive temporary breakpoints
* improved display of types and values

## 0.9.1 (November 30, 2019)

* fixes for exception stack management in win64
* fixes for stepping in/out in x64
* fixed partial fetching for array/map/bytes

## 0.9.0 (November 22, 2019)

* improved exception stack detection
* added profileSamples configuration on launch (hl 1.11 profiler)

## 0.8.2 (November 11, 2019)

* compatible with VSCode 1.40 (Electron 6.2)
* added hotReload experimental configuration on launch

## 0.8.0 (October 10, 2019)

* added x64 function arguments support
* do not display variables once they are out of scope

## 0.7.1 (July 6, 2019)

* compatible with VSCode 1.36 (Electron 4.2.5)

## 0.7.0 (June 11, 2019)

* added an error message for trying to debug on macOS (#28)
* added optional `hl` and `env` fields to launch configs (#55)
* fixed pause button
* fixed some startup errors on Windows/Linux

## 0.6.0 (March 4, 2019)

* added optional `program` support (#3)
* fixed a crash with compile time cwd != runtime cwd
* fixed "Start Debugging" not doing anything without a `launch.json`
* updated `${workspaceRoot}` to `${workspaceFolder}`
* improved enum display in tree view
* added explicit error on ENOENT
* fixed static variables lookup
* fixed current package type lookup
* make sure to have correct port on launch (#37)
* prevent overflow error when doing pointer difference (#46)

## 0.5.2 (February 7, 2019)

* VSCode 1.31 compatibility (electron 3.1.2)

## 0.5.1 (December 3, 2018)

* More HashLink 1.9 (bytecode 5) support

## 0.5.0 (November 18, 2018)

* VSCode 1.29 compatibility (electron 2.0.12)
* HashLink bytecode 5 support
* stack overflow correctly reported on windows

## 0.4.4 (September 17, 2018)

* VSCode 1.27 compatibility (bugfix stepping)

## 0.4.3 (August 26, 2018)

* VSCode 1.26 compatibility (electron 2.0.5)
* added "break on all exceptions" support
* started set variable implementation (very little support for now)
* fixed HL 1.6- support

## 0.4.2 (July 11, 2018)

* added haxe.io.Bytes custom display
* fixed statics in classes within a package
* fixed error message when var unknown
* fixed with single captured var ptr

## 0.4.1 (July 11, 2018)

* fixed regression regarding locals resolution

## 0.4.0 (July 9, 2018)

* added attach/detach support
* fixed pause
* add member and static vars preview
* fixed static var eval()
* move breakpoint to next valid line when no opcode at this pos
* don't step in hl/haxe standard library anymore
* hl 1.7 support
* many other fixes

## 0.3.0 (June 12, 2018)

* added Linux support
* fixed initialize errors
* fixed newlines mix in debugger trace output
* don't escape strings in exception reports
* improved file resolution for breakpoints

## 0.2.0 (April 16, 2018)

* added HL 1.6 bytecode support
* started threads support

## 0.1.0 (April 9, 2018)

* added class/method in stack trace
* added hover eval (support member and static vars)
* allow access to member vars without this. prefix
* added native Map support
* fixed CALL skip bug when stepping
* group object fields by class scope with inheritance
* bugfix with field hashing in JS
* initial HL debugging

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
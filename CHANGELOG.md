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
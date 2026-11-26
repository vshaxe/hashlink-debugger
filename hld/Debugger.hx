package hld;

enum StepMode {
	Out;
	Next;
	Into;
}

enum DebugRegsKind {
	HLRegs;
	Regs;
	NatRegs;
}

@:publicFields @:structInit
class Address {
	var ptr : Pointer;
	var t : format.hl.Data.HLType;
}

@:publicFields @:structInit
class WatchPoint {
	var addr : Address;
	var regs : Array<{ offset : Int, bits : Int, r : Api.Register }>;
	var forReadWrite : Bool;
}

@:publicFields @:structInit
class StackRawInfo {
	var fidx : Int;
	var fpos : Int;
	var codePos : Pointer;
	var ebp : Null<hld.Pointer>;
}

@:publicFields @:structInit
class BreakContext {
	var rip : Pointer;
	var regs : Array<Pointer>;
}

@:publicFields @:structInit
class StackInfo {
	var file : String;
	var line : Int;
	var ebp : Pointer;
	var context : Null<{ obj : format.hl.Data.ObjPrototype, field : String }>;
	var localName : Null<String> = null;
}

class Debugger {

	public static inline var NATIVE_FRAME = "<native>";
	static inline var INT3 = 0xCC;
	static inline var PATCH_SIZE = 12;
	static inline var CMD_RUN = 1;
	static inline var CMD_MODULE_DEBUG = 3;
	static inline var CMD_MODULE_BYTES = 4;
	static inline var MSG_MODULE_ADDED = 0x100;
	static var HW_REGS : Array<Api.Register> = [Dr0, Dr1, Dr2, Dr3];
	public static var DEBUG = false;
	public static var IGNORED_ROOTS = [
		"hl",
		"sys",
		"haxe",
		"Date",
		"EReg",
		"Math",
		"Reflect",
		"Std",
		"String",
		"StringBuf",
		"Sys",
		"Type",
		"Xml",
		"IntIterator",
		"ArrayObj" // special
	];

	var sock : #if hxnodejs js.node.net.Socket #else sys.net.Socket #end;

	var api : Api;
	var module : Module;
	var modulesCache : Map<String, Module> = new Map();
	var watchedFile : { path : String, time : Float, size : Int, lastCheck : Float };
	var userBreaks : Array<{ file : String, line : Int, condition : String }> = [];
	var requests : Array<Null<haxe.io.Bytes> -> Void> = [];
	var prefetched : Map<Int, { debug : haxe.io.Bytes, module : Module }> = new Map();
	var sockData : haxe.io.Bytes;
	var runSent = false;
	var jit : JitInfo;
	var processExit : Bool;
	var ignoredRoots : Map<String,Bool>;

	var breakPoints : Array<{ fid : Int, pos : Int, codePos : Pointer, oldByte : Int, condition : String }>;
	var nextStep(default,set): Pointer = Pointer.make(0,0);
	var currentStack : Array<StackRawInfo>;
	var watches : Array<WatchPoint>;
	var threads : Map<Int,{ id : Int, stackTop : Pointer, exception : Pointer, ?exceptionStack: Array<StackRawInfo>, ?exceptionTrap: Pointer, ?breakContext: BreakContext, name : String }>;
	var afterStep = false;

	public var is64(get, never) : Bool;

	public var eval : Eval;
	public var currentStackFrame : Int;
	public var breakOnThrow(default, set) : Bool;
	public var stackFrameCount(get, never) : Int;
	public var mainThread(default, null) : Int = 0;
	public var stoppedThread(default,set) : Null<Int>;
	public var currentThread(default,set) : Null<Int>;

	public var customTimeout : Null<Float>;
	public var printHotReload = false;

	public var watchBreak : Address; // set if breakpoint occur on watch expression

	public function new() {
		breakPoints = [];
		watches = [];
	}

	function set_nextStep(v:Pointer) {
		if( DEBUG ) trace("NEXT STEP "+jit.codePtrToString(v));
		return nextStep = v;
	}

	function set_currentThread(v) {
		currentThread = v;
		eval.currentThread = v;
		return v;
	}

	function set_stoppedThread(v) {
		return stoppedThread = currentThread = v;
	}

	function get_is64() {
		return jit.is64;
	}

	public function loadModule( content : haxe.io.Bytes ) {
		module = decodeModule(content);
	}

	function decodeModule( content : haxe.io.Bytes ) {
		var m = new Module();
		m.load(content);
		var id = buildIdKey(m.code.buildId);
		if( id != null )
			modulesCache.set(id, m);
		return m;
	}

	static function buildIdKey( id : haxe.io.Bytes ) {
		if( id == null )
			return null;
		var key = id.toHex();
		return ~/^0+$/.match(key) ? null : key;
	}

	public function watchFile( path : String ) {
		watchedFile = { path : path, time : 0., size : 0, lastCheck : 0. };
		try {
			var st = sys.FileSystem.stat(path);
			watchedFile.time = st.mtime.getTime();
			watchedFile.size = st.size;
		} catch( e : Dynamic ) {
		}
	}

	function checkWatchedFile() {
		var w = watchedFile;
		if( w == null || Sys.time() - w.lastCheck < 0.5 )
			return;
		w.lastCheck = Sys.time();
		var st = try sys.FileSystem.stat(w.path) catch( e : Dynamic ) null;
		if( st == null || (st.mtime.getTime() == w.time && st.size == w.size) )
			return;
		try {
			var content = sys.io.File.getBytes(w.path);
			if( content.length >= 8 && content.get(3) >= 7 && content.getInt32(4) != content.length )
				return;
			decodeModule(content);
			w.time = st.mtime.getTime();
			w.size = st.size;
		} catch( e : Dynamic ) {
		}
	}

	function findModule( buildId : haxe.io.Bytes ) {
		var key = buildIdKey(buildId);
		if( key == null )
			return null;
		var m = modulesCache.get(key);
		if( m == null ) {
			checkWatchedFile();
			m = modulesCache.get(key);
		}
		return m;
	}

	inline function mod( fidx : Int ) {
		return jit.getModule(fidx);
	}

	public function connectTries( host : String, port : Int, timeout : Float, onResult : Bool -> Void, ?retry : Void -> Bool ) {
		if( timeout <= 0 ) {
			onResult(false);
			return;
		}
		var ts = Sys.time();
		connect(host,port,function(b) {
			if( b ) {
				onResult(true);
				return;
			}
			if( retry != null && !retry() ) {
				onResult(false);
				return;
			}
			haxe.Timer.delay(function() {
				connectTries(host, port, timeout - (Sys.time()-ts), onResult, retry);
			},20);
		});
	}

	public function connect( host : String, port : Int, onResult : Bool -> Void ) {
		function done(mods) {
			if( mods == null ) {
				close();
				onResult(false);
				return;
			}
			bindModules(mods, function(b) {
				if( !b ) close();
				onResult(b);
			});
		}

		#if hxnodejs
		var inputData = haxe.io.Bytes.alloc(0);
		var dumpRead = false;
		var pending : js.node.Timers.Immediate = null;
		var s = sock = new js.node.net.Socket();
		function tryRead() {
			pending = null;
			if( sock != s )
				return;
			var input = new haxe.io.BytesInput(inputData);
			var mods = try {
				jit = new JitInfo();
				jit.read(input);
			} catch( e : haxe.io.Eof ) {
				return;
			}
			dumpRead = true;
			if( input.position < inputData.length )
				onSocketData(inputData.sub(input.position, inputData.length - input.position));
			inputData = null;
			done(mods);
		}
		sock.on("data", function(buf:js.node.Buffer) {
			if( dumpRead ) {
				onSocketData(buf.hxToBytes());
				return;
			}
			var data = buf.hxToBytes();
			var all = haxe.io.Bytes.alloc(inputData.length + data.length);
			all.blit(0, inputData, 0, inputData.length);
			all.blit(inputData.length, data, 0, data.length);
			inputData = all;
			if( pending == null )
				pending = js.Node.setImmediate(tryRead);
		});
		js.node.Dns.lookup(host, {family: 4}, function(err, address:String, family) {
			if( err != null ) {
				onResult(false);
				return;
			}
			sock.on("error", function(err) {
				if( onResult != null ) {
					close();
					onResult(false);
					return;
				}
			});
			sock.connect(port, address, function() {
				// wait data
			});
		});
		#else
		sock = new sys.net.Socket();
		try {
			sock.connect(new sys.net.Host(host), port);
		} catch( e : Dynamic ) {
			sock.close();
			Sys.sleep(0.1);
			onResult(false);
			return;
		}
		jit = new JitInfo();
		done(try jit.read(sock.input) catch( e : Dynamic ) null);
		#end
	}

	function bindModules( mods : Array<JitInfo.JitModule>, onResult : Bool -> Void ) {
		if( mods.length == 0 ) {
			onResult(true);
			return;
		}
		var m = mods.shift();
		function bind( md : Module ) {
			if( md == null || !jit.addModule(m, md) ) {
				onResult(false);
				return;
			}
			md.init(jit.align);
			bindModules(mods, onResult);
		}
		var md = findModule(m.buildId);
		if( md == null && m.index == 0 && (m.rawSize == 0 || buildIdKey(m.buildId) == null) )
			md = module;
		if( md != null || m.rawSize == 0 ) {
			bind(md);
			return;
		}
		sendCommand(CMD_MODULE_BYTES, m.index, function(bytes) bind(bytes == null ? null : decodeModule(bytes)));
	}

	function sendCommand( cmd : Int, ?arg : Int, ?onAnswer : Null<haxe.io.Bytes> -> Void ) {
		if( sock == null ) {
			if( onAnswer != null ) onAnswer(null);
			return;
		}
		var out = new haxe.io.BytesOutput();
		out.writeByte(cmd);
		if( arg != null ) out.writeInt32(arg);
		if( onAnswer != null ) requests.push(onAnswer);
		#if hxnodejs
		sock.write(js.node.Buffer.hxFromBytes(out.getBytes()));
		#else
		sock.output.write(out.getBytes());
		while( requests.length > 0 ) {
			var code = sock.input.readInt32();
			var size = sock.input.readInt32();
			onMessage(code, sock.input.read(size));
		}
		#end
	}

	function onSocketData( data : haxe.io.Bytes ) {
		if( sockData != null && sockData.length > 0 ) {
			var all = haxe.io.Bytes.alloc(sockData.length + data.length);
			all.blit(0, sockData, 0, sockData.length);
			all.blit(sockData.length, data, 0, data.length);
			data = all;
		}
		var pos = 0;
		while( data.length - pos >= 8 ) {
			var size = data.getInt32(pos + 4);
			if( data.length - pos - 8 < size ) break;
			var code = data.getInt32(pos);
			var payload = data.sub(pos + 8, size);
			pos += 8 + size;
			onMessage(code, payload);
		}
		sockData = data.sub(pos, data.length - pos);
	}

	function onMessage( code : Int, data : haxe.io.Bytes ) {
		if( code == MSG_MODULE_ADDED ) {
			var index = data.getInt32(0);
			var p = { debug : null, module : findModule(data.sub(4, 16)) };
			prefetched.set(index, p);
			#if hxnodejs
			sendCommand(CMD_MODULE_DEBUG, index, function(b) p.debug = b);
			if( p.module == null )
				sendCommand(CMD_MODULE_BYTES, index, function(b) if( b != null ) p.module = decodeModule(b));
			#end
			return;
		}
		var cb = requests.shift();
		if( cb != null ) cb(code < 0 ? null : data);
	}

	function isModuleBreak( codePos : Pointer ) {
		return jit.registry != null && !jit.isCodePtr(codePos) && eval.readI32(jit.registry.offset(4)) == 1;
	}

	function syncModules() {
		if( jit.registry == null )
			return;
		var count = eval.readI32(jit.registry);
		if( count <= jit.modules.length )
			return;
		var ptr = jit.align.ptr;
		var entries = eval.readPointer(jit.registry.offset(8));
		var entrySize = ptr * 2 + 8 + 16;
		var added = false;
		for( i in jit.modules.length...count ) {
			var e = entries.offset(i * entrySize);
			var p = prefetched.get(i);
			var data = p != null && p.debug != null ? p.debug : readBytes(eval.readPointer(e), eval.readI32(e.offset(ptr * 2)));
			var m = jit.readModuleData(data, i);
			var md = p != null && p.module != null ? p.module : findModule(m.buildId);
			if( md == null ) {
				var raw = eval.readPointer(e.offset(ptr));
				if( raw.isNull() ) {
					if( DEBUG || printHotReload )
						trace("Hot reload: module " + i + " not loaded: bytecode not found");
					break;
				}
				md = decodeModule(readBytes(raw, eval.readI32(e.offset(ptr * 2 + 4))));
			}
			if( !jit.addModule(m, md) ) {
				if( DEBUG || printHotReload )
					trace("Hot reload: module " + i + " not loaded: bytecode does not match");
				break;
			}
			md.init(jit.align);
			if( DEBUG || printHotReload )
				trace("Hot reload: module " + i + " loaded");
			prefetched.remove(i);
			added = true;
		}
		if( !added )
			return;
		for( b in breakPoints.copy() )
			if( b.fid >= 0 && isPatched(b.fid) )
				removeBP(b);
		for( b in userBreaks )
			setBreakpoint(b.file, b.line, b.condition);
	}

	function readBytes( ptr : Pointer, size : Int ) {
		return readMem(ptr, size).toBytes(size);
	}

	public function init( api : Api ) {
		this.api = api;
		eval = new Eval(api, jit);
		eval.resumeDebug = evalResumeDebug;
		eval.setSingleStep = singleStep;
		if( !api.start() )
			return false;
		wait(); // wait first break
		return true;
	}

	function evalResumeDebug() {
		resume();
		wait(false, true);
	}

	function close() {
		requests = [];
		if( sock != null ) {
			#if hxnodejs sock.destroy() #else sock.close() #end;
			sock = null;
		}
	}

	public function run() {
		afterStep = false;
		// closing the socket or sending RUN will unlock waiting thread
		if( jit.hasModulesInfos() ) {
			if( !runSent ) {
				runSent = true;
				sendCommand(CMD_RUN);
			}
		} else
			close();
		if( stoppedThread != null )
			resume();
		return wait();
	}

	public function getThreads() {
		var tl = [for( t in threads ) t.id];
		tl.sort(Reflect.compare);
		return tl;
	}

	public function setCurrentThread(tid) {
		currentThread = tid;
		prepareStack();
	}

	public function pause() {
		if( !api.breakpoint() )
			throw "Failed to break process";
		var r = wait(false, false, true);
		// if we have stopped on a not HL thread, let's switch on main thread
		var found = false;
		for( t in threads )
			if( t.id == stoppedThread ) {
				found = true;
				break;
			}
		if( !found ) {
			currentThread = mainThread;
			prepareStack();
		}
		return r;
	}

	function singleStep(tid,set=true) {
		var r = getReg(tid, EFlags).toInt();
		if( set ) r |= 256 else r &= ~256;
		if( DEBUG ) trace("SINGLESTEP "+set);
		setReg(tid, EFlags, hld.Pointer.make(r,0));
	}

	public function getException() : Null<Value> {
		var t = threads.get(currentThread);
		if( t == null )
			return null;
		var exc = t.exception;
		if( exc.isNull() )
			return null;
		var v = eval.readVal(exc, HDyn);
		switch( v.t ) {
		case HObj({ name : "haxe.ValueException" }):
			try v = eval.readField(v, "value") catch( e : Dynamic ) {}
		case HObj({ name : "SysError" }):
			try {
				switch( eval.readField(v, "msg").v ) {
				case VString(msg, p):
					v = { v : VString("SysError: " + msg, p), t : v.t };
				default:
				}
			} catch( e : Dynamic ) {}
		default:
		}
		return v;
	}

	public function getVMExceptionStack() {
		var t = threads.get(currentThread);
		if( t == null )
			return null;
		var stack = t.exceptionStack;
		if( stack == null )
			return null;
		return stack.map(e -> stackInfo(e));
	}

	public function hasStack() {
		return currentStack.length > 0;
	}

	public function getCurrentVars( args : Bool ) {
		var s = currentStack[currentStackFrame];
		if( s == null || s.fidx == Eval.TRAMPOLINE_FIDX ) return [];
		var g = mod(s.fidx).getGraph(s.fidx);
		if( args )
			return g.getArgs();
		var locals = g.getLocals(s.fpos);
		if( afterStep && currentStackFrame == 0 && g.getReturnReg(s.fpos) != null )
			locals.push("$ret");
		return locals;
	}

	public function getDebugContext() : String {
		if( !setContext(false) )
			return null;
		return eval.getContextStr();
	}

	public function getDebugRegs( kind : DebugRegsKind, ?fidx : Int ) : Array<String> {
		if( kind == NatRegs && fidx != null )
			return eval.getNatRegs(fidx);
		if( !setContext(false) )
			return [];
		return switch( kind ) {
		case HLRegs: eval.getHLRegs();
		case Regs: eval.getDebugRegs();
		case NatRegs: eval.getNatRegs(fidx);
		}
	}

	public function getOpPositions( fidx : Int, from : Int, to : Int ) : Array<String> {
		var out = [];
		var start = jit.getFunctionPos(fidx);
		var f = mod(fidx).getFunction(fidx);
		if( to > f.ops.length ) to = f.ops.length;
		for( i in from...to ) {
			var s = mod(fidx).resolveSymbol(fidx, i);
			out.push('@$i [${s.line}] +0x${StringTools.hex(jit.getCodePos(fidx,i).sub(start))} ${f.ops[i]}');
		}
		return out;
	}

	public function getCurrentClass() {
		var s = currentStack[currentStackFrame];
		if( s.fidx == Eval.TRAMPOLINE_FIDX )
			return null;
		var ctx = mod(s.fidx).getMethodContext(s.fidx);
		if( ctx == null )
			return null;
		var name = ctx.obj.name;
		return name.split("$").join("");
	}

	public function getClassStatics( cl : String ) {
		var v = getValue(cl, true);
		if( v == null )
			throw "No such class "+cl;
		var fields = eval.getFields(v);
		fields.remove("__name__");
		fields.remove("__type__");
		fields.remove("__meta__");
		fields.remove("__implementedBy__");
		fields.remove("__constructor__");
		return fields;
	}

	function wait( onSingleStep = false, onEvalCall = false, onPause = false ) : Api.WaitResult {
		var cmd = null;
		var condition : String = null;
		watchBreak = null;
		while( true ) {
			cmd = api.wait(customTimeout == null ? 1000 : Math.ceil(customTimeout * 1000));

			if( cmd.r == Breakpoint && !onEvalCall && (jit.isCodePtr(nextStep) || onSingleStep) ) {
				if( onSingleStep ) {
					var codePos = getCodePos(cmd.tid).offset(-1);
					for( b in breakPoints )
						if( b.codePos == codePos && b.oldByte >= 0 && getAsm(codePos) == INT3 ) {
							setAsm(codePos, b.oldByte);
							setReg(cmd.tid, Eip, codePos);
							nextStep = codePos;
							stoppedThread = cmd.tid;
							return SingleStep;
						}
				}
				// On Linux, singlestep is not reset
				cmd.r = SingleStep;
				singleStep(cmd.tid,false);
			}

			if( DEBUG ) switch(cmd.r) {
				case Error:
					trace("**** ERROR ****");
				case Breakpoint:
					trace("BREAK");
				case SingleStep:
					trace("STEP");
				case Exit:
					trace("EXIT");
				case Handled, Timeout:
				default:
					trace(cmd.r);
				}

			var tid = cmd.tid;
			switch( cmd.r ) {
			case Timeout, Handled:
				checkWatchedFile();

				if( customTimeout != null )
					return cmd.r;

			case Breakpoint:
				var codePos = getCodePos(tid).offset(-1);
				if( isModuleBreak(codePos) ) {
					stoppedThread = tid;
					syncModules();
					resume();
					if( customTimeout != null )
						return Handled;
					continue;
				}
				for( b in breakPoints ) {
					if( b.codePos == codePos ) {
						condition = b.condition;
						// restore code
						setAsm(codePos, b.oldByte);
						// move backward
						setReg(tid, Eip, getReg(tid, Eip).offset(-1));
						singleStep(tid);
						nextStep = codePos;
						break;
					}
				}
				break;
			case SingleStep:
				// restore our breakpoint
				if( jit.isCodePtr(nextStep) ) {
					setAsm(nextStep, INT3);
					nextStep = Pointer.make(0, 0);
				} else if( watches.length > 0 ) {

					// check if we have a break on a watchpoint
					var dr6 = api.readRegister(tid, Dr6);
					var watchBits = dr6.toInt() & 15;
					if( watchBits != 0 ) {
						for( w in watches )
							for( r in w.regs )
								if( watchBits & (1 << HW_REGS.indexOf(r.r)) != 0 ) {
									watchBreak = w.addr;
									break;
								}
						api.writeRegister(tid, Dr6, Pointer.make(0, 0));
						if( watchBreak != null ) {
							cmd.r = Watchbreak;
							break;
						}
					}

				}
				stoppedThread = tid;
				if( onSingleStep )
					return SingleStep;
				resume();
			case Exit:
				processExit = true;
				stoppedThread = tid;
				return Exit;
			case Error, Watchbreak, StackOverflow:
				break;
			}
		}
		stoppedThread = cmd.tid;
		syncModules();

		// Do not overwrite stack on evalCall
		if( onEvalCall )
			return cmd.r;

		// in thread-disabled we don't know the main thread id in HL:
		// first stop is on a special thread in windows
		// wait for second stop with is user-specific
		if( jit.oldThreadInfos != null )
			mainThread = jit.oldThreadInfos.id;
		else if( mainThread == 0 )
			mainThread = -1;
		else if( mainThread == -1 )
			mainThread = stoppedThread;

		readThreads();
		prepareStack(cmd.r == Watchbreak);
		eval.onBeforeBreak();

		// if breakpoint has a condition, try to evaluate and do not actually break on false
		if( !onSingleStep && !onEvalCall && !onPause && condition != null ) {
			try {
				var value = getValue(condition);
				if( value != null ) {
					switch( value.v ) {
					case VBool( b ) if( !b ): return Handled;
					default:
					}
				}
			} catch( e : Dynamic ) {
				trace("Can't evaluate condition (" + condition + ") for breakpoint: " + e);
			}
		}
		return cmd.r;
	}

	public function getThreadName( id : Int, ?opt ) {
		var t = threads.get(id);
		return t == null || t.name == null ? (opt == null ? "Thread "+id : opt) : t.name+":"+id;
	}

	function readThreads() {
		var old = jit.oldThreadInfos;
		threads = new Map();
		if( old != null ) {
			threads.set(old.id, { id : old.id, stackTop : old.stackTop, exception : eval.readPointer(old.debugExc), name : "Main" });
			return;
		}
		var count = eval.readI32(jit.threads);
		var tinfos = eval.readPointer(jit.threads.offset(8));
		var flagsPos = jit.align.ptr * 6 + 8;
		var excPos = jit.align.ptr * 5 + 8;
		var excTrapPos = jit.align.ptr * 2 + 8;
		var excStackCountPos = flagsPos + 4;
		var excStackPos = flagsPos + 8 + 256 + (jit.hlVersion >= 1.13 ? 128 : 0);
		var namePos = jit.hlVersion >= 1.13 ? flagsPos + 8 : -1;
		var breakPos = excStackPos + 256 * jit.align.ptr;
		for( i in 0...count ) {
			var tinf = eval.readPointer(tinfos.offset(jit.align.ptr * i));
			var tid = eval.readI32(tinf);
			var flags = eval.readI32(tinf.offset(flagsPos));
			if( flags & 16 != 0 ) continue; // invisible
			if( tid == 0 )
				tid = mainThread;
			else if( mainThread <= 0 )
				mainThread = tid;
			var name = null;
			if( namePos >= 0 ) {
				var tname = @:privateAccess eval.readMem(tinf.offset(namePos), 128).readStringUTF8();
				if( tname != "" )
					name = tname;
			}
			var trapCtx = eval.readPointer(tinf.offset(excTrapPos));
			var t = {
				id : tid,
				stackTop : eval.readPointer(tinf.offset(8)),
				exception : flags & 4 == 0 ? null : tinf.offset(excPos),
				exceptionStack : flags & 1 == 0 ? null : readVMExceptionStack(tinf.offset(excStackPos), eval.readI32(tinf.offset(excStackCountPos))),
				exceptionTrap : trapCtx.isNull() ? null : new Pointer(eval.readPointer(trapCtx.offset(10 * 8))),
				breakContext : readBreakContext(tinf.offset(breakPos)),
				name : name,
			};
			threads.set(tid, t);
		}
		if( !threads.exists(currentThread) )
			threads.set(currentThread,{ id : currentThread, stackTop: null, exception: null, name : null });
	}

	function readBreakContext( base : Pointer ) : Null<BreakContext> {
		if( jit.hlVersion < 2 )
			return null;
		var rip = eval.readPointer(base);
		if( rip.isNull() || !jit.isCodePtr(rip) )
			return null;
		return {
			rip : rip,
			regs : [for( i in 0...32 ) eval.readPointer(base.offset((i + 1) * jit.align.ptr))],
		};
	}

	function readVMExceptionStack(base : Pointer, count : Int) : Array<StackRawInfo> {
		var stack = [];
		if( count <= 0 || count >= 256 || base.isNull() )
			return stack;
		for( i in 0...count ) {
			var codePtr = eval.readPointer(base.offset(i * jit.align.ptr));
			var e = jit.resolveAsmPos(codePtr);
			if( e != null )
				stack.push(e);
		}
		return [for( s in stack ) if( mod(s.fidx).isValid(s.fidx, s.fpos) ) s];
	}

	function prepareStack( isWatchbreak=false ) {
		currentStackFrame = 0;
		currentStack = makeStack(currentThread, isWatchbreak);
		var t = threads.get(currentThread);
		var brk = t == null ? null : t.breakContext;
		eval.breakRegs = brk == null ? null : brk.regs;
		eval.nativeBreak = brk == null && stoppedThread != null && jit.resolveAsmPos(getCodePos(currentThread)) == null;
	}

	function skipFunction( fidx : Int ) {
		var ctx = mod(fidx).getMethodContext(fidx);
		var name = ctx == null ? new haxe.io.Path(mod(fidx).resolveSymbol(fidx, 0).file).file : ctx.obj.name.split(".")[0];
		if( name.charCodeAt(0) == "$".code ) name = name.substr(1);
		if( ignoredRoots == null ) {
			ignoredRoots = new Map();
			for( r in IGNORED_ROOTS )
				ignoredRoots.set(r,true);
		}
		return ignoredRoots.exists(name);
	}

	public function step( mode : StepMode ) : Api.WaitResult {
		var tid = currentThread;
		var s = currentStack[0];
		var depth = currentStack.length;
		var onException = getException() != null;

		function runToStop() {
			var r;
			do r = run() while( r == Handled );
			return r;
		}

		if( s == null || s.fidx == Eval.TRAMPOLINE_FIDX || onException ) {
			if( DEBUG ) trace("Step not supported, continue.");
			return runToStop();
		}

		var orig = mod(s.fidx).resolveSymbol(s.fidx, s.fpos);
		var graph = mod(s.fidx).getGraph(s.fidx);
		var marked = new Map();
		var currentCodePos = getCodePos(tid);
		var onBreakPoint = false;
		var immediateProcess = false;
		var userBreaks = new Map();

		for( b in breakPoints )
			if( b.fid == s.fidx ) {
				if( b.pos == s.fpos ) {
					onBreakPoint = true;
				} else
					userBreaks.set(b.pos, true);
			}

		// Add trap breakpoint if current trap is not in current function
		var trap = threads.get(tid).exceptionTrap;
		if( trap != null ) {
			var e = jit.resolveAsmPos(trap);
			if( e != null && e.fidx != s.fidx ) {
				var old = getAsm(trap);
				var bp = { fid : -4, pos : e.fpos, codePos : trap, oldByte : old, condition : null };
				breakPoints.push(bp);
				marked.set(-1, bp);
				setAsm(trap, INT3);
			}
		}

		var todo = [s.fpos];
		while( todo.length > 0 ) {
			var pos = todo.pop();
			if( marked.exists(pos) )
				continue;
			var l = mod(s.fidx).resolveSymbol(s.fidx, pos);
			var c = graph.control(pos);
			var lineChange = mode != Out && (l.file != orig.file || l.line != orig.line) && !c.match(CCatch | CJAlways(_));
			switch( c ) {
			case CCall(f) if( f >= 0 && mode == Into ):
				// skip calls to std library
				var fid = mod(s.fidx).getFunctionIndex(f);
				if( fid == null || skipFunction(fid) )
					c = CNo;
			default:
			}
			if( lineChange || c == CRet || (mode == Into && c.match(CCall(_))) ) {
				var codePos = jit.getCodePos(s.fidx, pos);
				var old = getAsm(codePos);
				var bp = { fid : lineChange ? -1 : (c == CRet ? -2 : -3), pos : pos, codePos : codePos, oldByte : old, condition : null };
				breakPoints.push(bp);
				marked.set(pos, bp);
				if( codePos == currentCodePos && onBreakPoint ) {
					immediateProcess = true;
					bp.oldByte = -1;
				} else if( userBreaks.exists(pos) ) {
					bp.oldByte = -1;
				} else
					setAsm(codePos, INT3);
				// if we are on same op but after the call (after returning from a finish)
				if( c.match(CCall(_)) && codePos < currentCodePos )
					todo.push(pos+1);
				continue;
			}
			if( !c.match(CNo | CCall(_)) )
				marked.set(pos, null);
			for( p in graph.getNextPos(pos) )
				todo.push(p);
		}
		function cleanup() {
			for( bp in marked )
				if( bp != null ) {
					if( bp.oldByte == -1 )
						breakPoints.remove(bp);
					else
						removeBP(bp);
				}
		}
		var userHit = false;
		if( !immediateProcess ) {
			while( true ) {
				resume();
				var r = wait();
				if( r != Exit && currentStack.length == 0 )
					r = wait();
				var onUser = false, onStep = false;
				for( b in breakPoints )
					if( b.codePos == nextStep ) {
						if( b.fid >= 0 )
							onUser = true;
						else
							onStep = true;
					}
				userHit = r == Breakpoint && onUser;
				if( r == Handled ) {
					if( currentThread != tid || !onStep )
						continue;
					r = Breakpoint;
				}
				if( (r != Breakpoint && r != SingleStep) || currentThread != tid || currentStack.length == 0 || currentStack[0].fidx != s.fidx ) {
					cleanup();
					return r;
				}
				// fix recursive methods that are breaking on the inner function
				if( (mode == Out || mode == Next) && currentStack.length > depth && !userHit ) {
					var isRecursive = false;
					for( b in breakPoints )
						if( (b.fid == -2 || b.fid == -1) && nextStep == b.codePos ) {
							isRecursive = true;
							break;
						}
					if( isRecursive ) {
						if( DEBUG ) trace("RECURSIVE");
						continue;
					}
				}
				break;
			}
		}
		// execute until the end of Call/Ret if we stopped on it !
		for( b in breakPoints ) {
			if( userHit || nextStep != b.codePos || b.fid >= -1 ) continue;
			var isRet = b.fid == -2;
			while( true ) {
				var eip = getReg(tid, Eip);
				var op = api.readByte(eip, 0);
				if( op == 0x48 )
					op = api.readByte(eip, 1);
				singleStep(tid);
				resume();
				var r = wait(true);
				if( r != SingleStep || currentThread != tid )
					break;
				var st = makeStack(tid,false,1)[0];
				if( isRet ) {
					if( op == 0xC3 ) {
						if( st == null ) {
							// ret on final main() ? - run till exit
							prepareStack();
							if( currentStack.length == 0 ) {
								return runToStop();
							}
						}
						break;
					}
				} else {
					// call : wait we changed line !
					if( st != null && (st.fidx != s.fidx || st.fpos != b.pos) ) break;
				}
			}
			// in case we singleStepped !
			prepareStack();
			break;
		}
		cleanup();
		afterStep = true;
		return Breakpoint;
	}

	function isCallerOf( caller : StackRawInfo, callee : StackRawInfo ) {
		if( callee == null )
			return true;
		var f = mod(caller.fidx).getFunction(caller.fidx);
		if( f == null )
			return true;
		for( pos in [caller.fpos, caller.fpos - 1] ) {
			if( pos < 0 || pos >= f.ops.length )
				continue;
			switch( CodeGraph.opControl(f.ops[pos]) ) {
			case CCall(-1):
				return true;
			case CCall(findex):
				if( callee.fidx == Eval.TRAMPOLINE_FIDX || jit.getModule(callee.fidx) != mod(caller.fidx) )
					return true;
				if( mod(caller.fidx).getFunctionIndex(findex) == callee.fidx )
					return true;
			default:
			}
		}
		return false;
	}

	function makeStack( tid, isWatchbreak : Bool, max = 0 ) {
		var stack = [];
		var tinf = threads.get(tid);
		if( tinf == null || tinf.stackTop == null )
			return stack;
		var brk = tinf.breakContext;
		var esp = brk == null ? getReg(tid, Esp) : brk.regs[(Eval.NativeReg.Esp : Eval.NativeReg).toInt()];
		var ebp = brk == null ? getReg(tid, Ebp) : brk.regs[(Eval.NativeReg.Ebp : Eval.NativeReg).toInt()];
		var size = tinf.stackTop.sub(esp) + jit.align.ptr;
		if( size < 0 ) size = 0;
		var memBase = esp.offset(-jit.align.ptr);
		var mem = tryReadMem(memBase, size);
		if( mem == null ) {
			var skip = findReadableBase(memBase, size);
			if( skip >= size )
				throw "Failed to read stack @" + memBase.toString() + "[" + size + "]";
			memBase = memBase.offset(skip);
			size -= skip;
			mem = readMem(memBase, size);
		}
		var prologPos = esp.sub(memBase) - jit.align.ptr;

		var eip = brk == null ? getReg(tid, Eip) : brk.rip;
		var asmPos = eip;
		if( isWatchbreak || brk != null )
			asmPos = asmPos.offset(-1);
		var e = jit.resolveAsmPos(asmPos);
		var inProlog = false;
		var exc = getException();
		var isExcCantCast = false;
		if( exc != null ) {
			switch( exc.v ){
			case VString(v,_):
				if( StringTools.startsWith(v, "Can't cast ") )
					isExcCantCast = true;
			default:
			}
		}

		//trace(eip,"0x"+api.readByte(eip, 0), e);

		if( e != null && !mod(e.fidx).isValid(e.fidx,e.fpos) )
			e = null;

		// if we are on ret, our EBP is wrong, so let's ignore this stack part
		if( e != null && brk == null ) {
			var op = api.readByte(eip, 0);
			if( op == 0x48 && jit.is64 )
				op = api.readByte(eip, 1);
			if( op == 0xC3 ) // RET
				e = null;
		}

		if( e != null ) {
			if( e.fpos < 0 && jit.is64) {
				// we can't consider being in a function while we are in the prolog
				// because our regs args have not yet been stored on stack
				e = null;
			} else if( e.fpos < 0 ) {
				// we are in function prolog
				var delta = jit.getFunctionPos(e.fidx).sub(asmPos);
				e.fpos = 0;
				if( delta == 0 )
					e.ebp = esp.offset(-jit.align.ptr); // not yet pushed ebp
				else
					e.ebp = esp;
				inProlog = true;
			} else
				e.ebp = ebp;
			if( e != null )
				stack.push(e);
		}

		// when requiring only top level stack, do not look further if we are in a C function
		// because we need to step so we don't want false positive
		if( max == 1 ) return stack;

		inline function readStack( p : Pointer ) : Null<Pointer> {
			var offset = p.sub(memBase);
			return offset < 0 || offset + jit.align.ptr > size ? null : mem.getPointer(offset, jit.align);
		}

		function fromNative( f : StackRawInfo ) {
			if( f.ebp == null )
				return true;
			var ret = readStack(f.ebp.offset(jit.align.ptr));
			if( ret == null )
				return true;
			var e = jit.resolveAsmPos(ret);
			return e == null || !mod(e.fidx).isValid(e.fidx, e.fpos);
		}

		// similar to module/module_capture_stack
		if( is64 ) {
			// on windows x64, we can't guarantee a stack pointer for our native funs...
			var skipFirstCheck = (e == null && jit.isWinCall);
			var trampoline = jit.trampoline;
			var atGap = e == null || fromNative(e);
			for( i in 0...(size >> 3)-1 ) {
				var val = mem.getPointer(i << 3, jit.align);
				if( atGap && trampoline != null && val == trampoline.marker ) {
					var slot = memBase.offset(i << 3);
					var frameEbp = readStack(slot.offset(trampoline.rbpOffset));
					var callSite = readStack(slot.offset(trampoline.callOffset));
					if( frameEbp != null && callSite != null && frameEbp > esp && frameEbp < tinf.stackTop ) {
						var e = jit.resolveAsmPos(callSite.offset(-1));
						if( e != null && e.fpos >= 0 && mod(e.fidx).isValid(e.fidx, e.fpos) ) {
							e.ebp = frameEbp;
							stack.push({ fidx : Eval.TRAMPOLINE_FIDX, fpos : 0, codePos : val, ebp : slot });
							stack.push(e);
							atGap = fromNative(e);
							skipFirstCheck = false;
							if( max > 0 && stack.length >= max ) return stack;
							continue;
						}
					}
				}
				if( (val > esp && val < tinf.stackTop) || (inProlog && (i << 3) == prologPos) || skipFirstCheck ) {
					var codePtr = skipFirstCheck ? val : mem.getPointer((i + 1) << 3, jit.align);
					var e = jit.resolveAsmPos(codePtr);
					if( e != null && e.fpos >= 0 && isCallerOf(e, stack[stack.length - 1]) ) {
						if( skipFirstCheck ) {
							e.ebp = ebp;
							// this ebp might not be good, so let's look for
							// the first potential ebp backup starting after our esi
							var validEsp = esp.offset(i << 3);
							if( e.ebp < validEsp || e.ebp > tinf.stackTop ) {
								var k = i - 1;
								if( isExcCantCast && is64 && jit.isWinCall ) {
									// Only do this for can't cast, as Null access .xxx has RSP+10h valid but is wrong
									// look first at saved RBP at prev RSP+10h
									var val2 = mem.getPointer((i + 2) << 3, jit.align); // Can't cast xxx to i32
									var val4 = mem.getPointer((i + 4) << 3, jit.align); // Can't cast xxx to obj (e.g String)
									var val = null;
									if( val2 > validEsp && val2 < tinf.stackTop ) val = val2;
									if( val4 > validEsp && val4 < tinf.stackTop ) val = val4;
									if( val != null ) {
										e.ebp = val;
										k = -1;
									}
								}
								var first = true;
								while( k > 0 ) {
									var val = mem.getPointer((k--) << 3, jit.align);
									if( val > validEsp && val < tinf.stackTop ) {
										var code = readMem(val.offset(jit.align.ptr),jit.align.ptr).getPointer(0, jit.align);
										if( !jit.isCodePtr(code) ) continue;
										if( first || val < e.ebp ) {
											e.ebp = val;
											first = false;
										}
									}
								}
							}
							skipFirstCheck = false;
						} else
							e.ebp = val;
						var prev = stack[stack.length - 1];
						var ordered = prev == null || prev.ebp == null || e.ebp > prev.ebp;
						if( !ordered && !(inProlog && (i << 3) == prologPos) ) continue;
						stack.push(e);
						atGap = fromNative(e);
						if( max > 0 && stack.length >= max ) return stack;
					}
				}
			}
		} else {
			var stackBottom = esp.toInt();
			var stackTop = tinf.stackTop.toInt();
			for( i in 0...size >> 2 ) {
				var val = mem.getI32(i << 2);
				if( val > stackBottom && val < stackTop || (inProlog && (i << 2) == prologPos) ) {
					var codePtr = mem.getPointer((i + 1) << 2, jit.align);
					var e = jit.resolveAsmPos(codePtr);
					if( e != null && e.fpos >= 0 ) {
						e.ebp = Pointer.make(val,0);
						stack.push(e);
						if( max > 0 && stack.length >= max ) return stack;
					}
				}
			}
		}

		return [for( s in stack ) if( s.fidx == Eval.TRAMPOLINE_FIDX || mod(s.fidx).isValid(s.fidx,s.fpos) ) s];
	}

	inline function get_stackFrameCount() return currentStack.length;

	public function getBackTrace() : Array<StackInfo> {
		return [for( e in currentStack ) stackInfo(e)];
	}

	public function getStackFrame( ?frame ) : StackInfo {
		if( frame == null ) frame = currentStackFrame;
		var f = currentStack[frame];
		if( f == null )
			return { file : "???", line : 0, ebp : Pointer.make(0, 0), context : null };
		return stackInfo(f);
	}

	public function getClosureStack( value ) : Array<StackInfo> {
		var stack = @:privateAccess eval.getClosureStack(value);
		var out = [];
		for( ptr in stack ) {
			var e = jit.resolveAsmPos(ptr);
			if( e == null || !mod(e.fidx).isValid(e.fidx,e.fpos) || e.fpos < 0 ) continue;
			out.push(stackInfo({ fidx : e.fidx, fpos : e.fpos, ebp: null }));
		}
		return out;
	}

	function stackInfo( f ) : StackInfo {
		if( f.fidx == Eval.TRAMPOLINE_FIDX )
			return { file : "<native>", line : 0, ebp : f.ebp, context : null };
		var s = mod(f.fidx).resolveSymbol(f.fidx, f.fpos);
		return { file : s.file, line : s.line, ebp : f.ebp, context : mod(f.fidx).getMethodContext(f.fidx), localName : mod(f.fidx).getFunction(f.fidx).localName };
	}

	function setContext(global:Bool) {
		var cur = currentStack[currentStackFrame];
		if( cur == null || cur.fidx == Eval.TRAMPOLINE_FIDX ) return false;
		eval.globalContext = global;
		var children = [for( i in 0...currentStackFrame ) currentStack[currentStackFrame - 1 - i]];
		eval.setContext(cur.fidx, cur.fpos, jit.getNativeCodePos(cur.codePos), cur.ebp, children);
		return true;
	}

	public function getValue( expr : String, global = false ) : Value {
		if( !setContext(global) )
			return null;
		var v = eval.eval(expr);
		eval.globalContext = false;
		return v;
	}

	public function setValue( expr : String, value : String, global = false ) : Value {
		if( !setContext(global) )
			return null;
		return eval.setValue(expr, value);
	}

	public function getRef( expr : String, global = false ) : Address {
		if( !setContext(global) )
			return null;
		var v = eval.ref(expr);
		eval.globalContext = global;
		return v;
	}

	public function getWatches() {
		return [for( w in watches ) w.addr];
	}

	public function watch( a : Address, forReadWrite = false ) {
		var size = jit.align.typeSize(a.t);
		var availableRegs = HW_REGS.copy();
		for( w in watches )
			for( r in w.regs )
				availableRegs.remove(r.r);
		var w : WatchPoint = {
			addr : a,
			regs : [],
			forReadWrite : forReadWrite,
		};
		var offset = 0;
		var bitSize = [1, 2, 8, 4];
		while( size > 0 ) {
			var r = availableRegs.shift();
			if( r == null )
				throw "Not enough hardware register to watch: remove previous watches";
			var v = if( size >= 8 ) 2 else if( size >= 4 ) 3 else if( size >= 2 ) 1 else 0;
			w.regs.push({ r : r, offset : offset, bits : v });
			var delta = bitSize[v];
			size -= delta;
			offset += delta;
		}
		watches.push(w);
		syncDebugRegs();
		return w;
	}

	public function unwatch( a : Address ) {
		for( w in watches )
			if( w.addr == a ) {
				watches.remove(w);
				syncDebugRegs();
				return true;
			}
		return false;
	}


	function syncDebugRegs() {
		var wasPaused = false;
		if( currentThread == null ) {
			pause();
			wasPaused = true;
		}
		var dr7 = 0x100;
		for( w in watches ) {
			for( r in w.regs ) {
				var rid = HW_REGS.indexOf(r.r);
				dr7 |= 1 << (rid * 2);
				dr7 |= ((w.forReadWrite ? 3 : 1) | (r.bits << 2)) << (16 + rid * 4);
			}
		}
		api.writeRegister(currentThread, Dr7, Pointer.make(dr7, 0));
		for( w in watches )
			for( r in w.regs )
				api.writeRegister(currentThread, r.r, w.addr.ptr.offset(r.offset));
		if( wasPaused )
			resume();
	}

	function getCodePos(tid) {
		var eip = getReg(tid, Eip);
		return eip;
	}

	public function resume() {
		if( stoppedThread == null )
			throw "No thread stopped";
		if( DEBUG ) trace("RUN " + jit.codePtrToString(getCodePos(currentThread)));
		if( !api.resume(stoppedThread) && !processExit )
			throw "Could not resume "+stoppedThread;
		stoppedThread = null;
		watchBreak = null;
	}

	public function end() {
		close();
		if( stoppedThread != null ) resume();
		if( api != null ) {
			api.stop();
			api = null;
		}
	}

	function tryReadMem( addr : Pointer, size : Int ) : Null<Buffer> {
		var mem = new Buffer(size);
		return api.read(addr, mem, size) ? mem : null;
	}

	function readMem( addr : Pointer, size : Int ) {
		var mem = tryReadMem(addr, size);
		if( mem == null )
			throw "Failed to read memory @" + addr.toString() + "[" + size+"]";
		return mem;
	}

	function findReadableBase( addr : Pointer, size : Int ) {
		var ptr = jit.align.ptr;
		var min = 0, max = Std.int(size / ptr);
		while( min < max ) {
			var mid = (min + max) >> 1;
			if( tryReadMem(addr.offset(mid * ptr), size - mid * ptr) != null ) max = mid else min = mid + 1;
		}
		return min * ptr;
	}

	function getAsm( ptr : Pointer ) {
		if( !jit.isCodePtr(ptr) )
			throw "Assert invalid ptr " + ptr;
		return api.readByte(ptr, 0);
	}

	function setAsm( ptr : Pointer, byte : Int ) {
		if( !jit.isCodePtr(ptr) )
			throw "Assert invalid ptr " + ptr;
		if( DEBUG ) trace('Set ${jit.codePtrToString(ptr)}=$byte');
		api.writeByte(ptr, 0, byte);
		api.flush(ptr, 1);
	}

	function getReg(tid, reg) {
		return Pointer.ofPtr(api.readRegister(tid, reg));
	}

	function setReg(tid, reg, value) {
		if( !api.writeRegister(tid, reg, value) )
			throw "Failed to set register " + reg;
	}

	function getBreaks( file : String, line : Int ) {
		var all = null;
		for( m in jit.modules ) {
			var b = m.module.getBreaks(file, line);
			if( b == null ) continue;
			var list = [for( x in b.breaks ) if( jit.hasCode(x.ifun) && !isPatched(x.ifun) ) x];
			if( all == null )
				all = { breaks : list, line : b.line };
			else {
				for( x in list ) all.breaks.push(x);
				if( list.length > 0 ) all.line = b.line;
			}
		}
		return all;
	}

	function isPatched( fidx : Int ) {
		if( jit.modules.length < 2 )
			return false;
		var mem = tryReadMem(jit.getFunctionPos(fidx), PATCH_SIZE);
		return mem != null && mem.getUI8(0) == 0x48 && mem.getUI8(1) == 0xB8 && mem.getUI8(10) == 0xFF && mem.getUI8(11) == 0x20;
	}

	function isPatchedAt( codePos : Pointer ) {
		if( jit.modules.length < 2 )
			return false;
		var e = jit.resolveAsmPos(codePos);
		return e != null && codePos.sub(jit.getFunctionPos(e.fidx)) < PATCH_SIZE && isPatched(e.fidx);
	}

	public function checkBreakpointLine(file : String, line : Int) {
		var breaks = getBreaks(file, line);
		return breaks == null ? -1 : breaks.line;
	}

	public function addBreakpoint( file : String, line : Int, condition : Null<String> ) {
		var found = false;
		for( b in userBreaks )
			if( b.file == file && b.line == line ) {
				b.condition = condition;
				found = true;
			}
		if( !found )
			userBreaks.push({ file : file, line : line, condition : condition });
		return setBreakpoint(file, line, condition);
	}

	function setBreakpoint( file : String, line : Int, condition : Null<String> ) {
		var breaks = getBreaks(file, line);
		if( breaks == null )
			return -1;
		// check already defined
		var set = false;
		for( b in breaks.breaks ) {
			var found = false;
			for( a in breakPoints ) {
				if( a.fid == b.ifun && a.pos == b.pos ) {
					found = true;
					break;
				}
			}
			if( found ) continue;

			var codePos = jit.getCodePos(b.ifun, b.pos);
			var old = getAsm(codePos);
			setAsm(codePos, INT3);
			breakPoints.push({ fid : b.ifun, pos : b.pos, oldByte : old, codePos : codePos, condition : condition });
			set = true;
		}
		return breaks.line;
	}

	public function clearBreakpoints( file : String ) {
		for( b in userBreaks.copy() )
			if( b.file == file )
				userBreaks.remove(b);
		for( m in jit.modules ) {
			var ffuns = m.module.getFileFunctions(file);
			if( ffuns == null )
				continue;
			for( b in breakPoints.copy() )
				for( f in ffuns.functions )
					if( b.fid == f.ifun ) {
						removeBP(b);
						break;
					}
		}
	}

	function removeBP( bp ) {
		breakPoints.remove(bp);
		if( !isPatchedAt(bp.codePos) )
			setAsm(bp.codePos, bp.oldByte);
		if( nextStep == bp.codePos ) {
			singleStep(currentThread, false);
			nextStep = Pointer.make(0, 0);
		}
	}

	public function removeBreakpoint( file : String, line : Int ) {
		for( b in userBreaks.copy() )
			if( b.file == file && b.line == line )
				userBreaks.remove(b);
		var breaks = getBreaks(file, line);
		if( breaks == null )
			return false;
		var rem = false;
		for( b in breaks.breaks )
			for( a in breakPoints )
				if( a.fid == b.ifun && a.pos == b.pos ) {
					rem = true;
					removeBP(a);
					break;
				}
		return rem;
	}

	function set_breakOnThrow(b) {
		var count = eval.readI32(jit.threads);
		var tinfos = eval.readPointer(jit.threads.offset(8));
		var flagsPos = jit.align.ptr * 6 + 8;
		for( i in 0...count ) {
			var tinf = eval.readPointer(tinfos.offset(jit.align.ptr * i));
			var flags = eval.readI32(tinf.offset(flagsPos));
			if( b ) flags |= 2 else flags &= ~2;
			eval.writeI32(tinf.offset(flagsPos), flags);
		}
		return breakOnThrow = b;
	}

}

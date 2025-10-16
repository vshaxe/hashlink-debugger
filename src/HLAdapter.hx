import Utils;

import vscode.debugProtocol.DebugProtocol;
import vscode.debugAdapter.DebugSession;
import js.node.ChildProcess;
import js.node.Buffer;
import js.node.child_process.ChildProcess as ChildProcessObject;

enum VarValue {
	VScope( k : Int );
	VValue( v : hld.Value, evalName : String );
	VUnkownFile( file : String );
	VObjFields( v : hld.Value, o : format.hl.Data.ObjPrototype, evalName : String );
	VStatics( cl : String );
	VStack( stack : Array<hld.Debugger.StackInfo> );
}

class HLAdapter extends DebugSession {

	static var UID = 0;
	public static var inst : HLAdapter;
	public static var DEBUG = false;
	public static var DEFAULT_PORT : Int = 6112;
	public static var CONNECTION_TIMEOUT : Float = 2;

	var isSessionActive(default, set) : Bool;
	var breakOnlyActive(default, set) : Bool;

	var proc : ChildProcessObject;
	var workspaceDirectory : String;
	var classPath : Array<String>;

	var debugPort : Int;
	var doDebug : Bool;
	var dbg : hld.Debugger;
	var startTime : Float;
	var timer : haxe.Timer;
	var shouldRun : Bool;

	var varsValues : Map<Int,VarValue>;
	var ptrValues : Array<hld.Debugger.Address>;
	var breakPos : Map<String, Array<{ line : Int, condition : String }>>;
	var watchedPtrs : Array<hld.Debugger.WatchPoint>;
	var isPause : Bool;
	var threads : Map<Int,Bool>;
	var allowEvalGetters : Bool;

	static var isWindows = Sys.systemName() == "Windows";
	static var isMac = Sys.systemName() == "Mac";

	public function new() {
		super();
		allowEvalGetters = false;
		isSessionActive = false;
		breakOnlyActive = false;
		debugPort = DEFAULT_PORT;
		doDebug = true;
		threads = new Map();
		startTime = haxe.Timer.stamp();
		ptrValues = [];
		breakPos = [];
		watchedPtrs = [];
		inst = this;
		shouldRun = false;
	}

	function set_isSessionActive( b : Bool ) {
		if( b != isSessionActive ) {
			if( breakOnlyActive )
				setBreakPos(b);
		}
		return isSessionActive = b;
	}

	function set_breakOnlyActive( b : Bool ) {
		if( b != breakOnlyActive ) {
			if( !isSessionActive )
				setBreakPos(!b);
		}
		return breakOnlyActive = b;
	}

	override function initializeRequest(response:InitializeResponse, args:InitializeRequestArguments) {

		haxe.Log.trace = function(v:Dynamic, ?p:haxe.PosInfos) {
			var str = haxe.Log.formatOutput(v, p);
			sendEvent(new OutputEvent(Std.int((haxe.Timer.stamp() - startTime)*10) / 10 + "> " + str+"\n"));
		};

		debug("Initialize");

		response.body.supportsConfigurationDoneRequest = true;
		response.body.supportsFunctionBreakpoints = false;
		response.body.supportsConditionalBreakpoints = true;
		response.body.supportsEvaluateForHovers = true;
		response.body.supportsStepBack = false;
		response.body.supportsSetVariable = true;
		response.body.supportsDataBreakpoints = true;

		response.body.exceptionBreakpointFilters = [
			{ filter : "all", label : "Stop on all exceptions" },
			{ filter : "activeOnly", label : "Break only active process" }
		];

		sendResponse( response );
	}

	function debug(v:Dynamic, ?pos:haxe.PosInfos) {
		if( DEBUG ) haxe.Log.trace(v, pos);
	}

	override function launchRequest(response:LaunchResponse, args:LaunchRequestArguments) {

		debug("Launch");

		if( args.noDebug )
			doDebug = false;

		var args:Arguments = cast args;

		setClassPath(args.classPaths);
		workspaceDirectory = formatDirPath(if( args.cwd == null ) haxe.io.Path.directory(args.program) else args.cwd);
		Sys.setCwd(workspaceDirectory);
		var port = args.port;
		if( port == null ) port = debugPort;
		if( args.allowEval != null ) allowEvalGetters = args.allowEval;

		function onError(e : String) {
			errorMessageAndResponse(cast response, e + "\n" + haxe.CallStack.toString(haxe.CallStack.exceptionStack()));
			sendEvent(new TerminatedEvent());
		}

		try {
			launch(args, response);
			if( doDebug ) {
				startDebug(args.program, port, function(msg) {
					if( msg != null ) {
						proc.kill();
						dbg = null;
						onError(msg);
						return;
					}
					sendEvent(new InitializedEvent());
					sendResponse(response);
				});
			}
		} catch( e : Dynamic ) {
			onError(e);
		}
	}

	override function setExceptionBreakPointsRequest(response:SetExceptionBreakpointsResponse, args:SetExceptionBreakpointsArguments) {
		if( Sys.systemName() != "Mac" ) { // TODO: Fix issue with corrupted memory on Mac
			dbg.breakOnThrow = args.filters.indexOf("all") >= 0;
		}
		breakOnlyActive = args.filters.indexOf("activeOnly") >= 0;
		sendResponse(response);
	}

	function formatDirPath(path:String) {
		path = haxe.io.Path.addTrailingSlash(haxe.io.Path.normalize(path));
		// capitalize the drive letter on Windows
		if (isWindows && haxe.io.Path.isAbsolute(path)) {
			path = path.charAt(0).toUpperCase() + path.substr(1);
		}
		return path;
	}

	function setClassPath(classPath:Array<String>) {
		if (classPath == null) {
			throw "Missing classPath";
		}
		// make sure the paths have the format we expect
		this.classPath = classPath.map((path) -> formatDirPath(path));
		var stdPath = this.classPath[this.classPath.length-1];
		if( stdPath != null ) {
			this.classPath.insert(-1, stdPath+"/hl/_std/");
		}
		this.classPath.push(""); // for absolute paths
	}

	override function attachRequest(response:AttachResponse, args:AttachRequestArguments) {
		debug("Attach");

		var args:Arguments = cast args;
		setClassPath(args.classPaths);
		workspaceDirectory = formatDirPath(args.cwd);
		Sys.setCwd(workspaceDirectory);
		startDebug(args.program,args.port, function(msg) {
			if( msg != null ) {
				errorMessageAndResponse(cast response, msg);
				sendEvent(new TerminatedEvent());
				return;
			}
			sendEvent(new InitializedEvent());
			sendResponse(response);
		});
	}

	function errorMessageAndResponse<T>(response:Response<T>, message:Dynamic) {
		errorMessage("ERROR : " + message);
		sendErrorResponse(cast response, 3000, "" + message);
	}

	/**
		Translate a classpath-relative file into a workspace-relative (or absolute) path.
		Returns null if not found
	**/
	function getFilePath( file : String ) {
		if( sys.FileSystem.exists(workspaceDirectory + file) )
			return workspaceDirectory + file;
		for( c in classPath )
			if( sys.FileSystem.exists(c + file) )
				return c + file;
		return null;
	}

	static final r_trace = ~/^([A-Za-z0-9_.\/]+):([0-9]+): /;
	static final r_call = ~/^Called from [^(]+\(([A-Za-z0-9_.\/\\:]+) line ([0-9]+)\)/;

	function processLine( str : String, ?out : OutputEventCategory ) {
		var e = new OutputEvent(str+"\n", out);
		var reg = null;
		if( r_trace.match(str) ) reg = r_trace else if( r_call.match(str) ) reg = r_call;
		if( reg != null ) {
			var file = reg.matched(1);
			var path = getFilePath(file);
			if( path != null ) {
				e.body.source = {
					name : file,
					path : path,
				}
				e.body.line = Std.parseInt(reg.matched(2));
				e.body.column = 0;
			}
		}
		sendEvent(e);
	}

	function launch( args : Arguments, response : LaunchResponse ) {

		var port = args.port == null ? debugPort : args.port;
		var hlArgs = ["--debug", "" + port, args.program];

		if( doDebug )
			hlArgs.unshift("--debug-wait");

		if( args.hotReload )
			hlArgs.unshift("--hot-reload");

		if( args.profileSamples != null ) {
			hlArgs.unshift(""+args.profileSamples);
			hlArgs.unshift("--profile");
		}

		if( args.args != null ) hlArgs = hlArgs.concat(args.args);
		if( args.argsFile != null ) {
			var words = sys.io.File.getContent(args.argsFile).split(" ");
			// parse double quote from source file
			while( words.length > 0 ) {
				var w = words.shift();
				if( w == "" ) continue;
				if( StringTools.startsWith(w,'"') ) {
					var buf = [w.substr(1)];
					while( true ) {
						var w = words.shift();
						if( w == null ) break;
						if( StringTools.endsWith(w,'"') ) {
							w = w.substr(0,-1);
							buf.push(w);
							break;
						}
						buf.push(w);
					}
					w = buf.join(" ");
				}
				hlArgs.push(w);
			}
		}
		// ALLUSERSPROFILE required to spawn correctly on Windows, see vshaxe/hashlink-debugger#51.
		var hlPath = (args.hl != null) ? args.hl : 'hl';
		if(args.hl != null && js.Node.process.env.get('LIBHL_PATH') == null) {
			js.Node.process.env.set('LIBHL_PATH', js.node.Path.dirname(args.hl));
		}

		proc = ChildProcess.spawn(hlPath, hlArgs, {cwd: args.cwd, env:args.env});
		debug("Start process " + hlPath + " " + hlArgs + " pid=" + proc.pid);
		proc.stdout.setEncoding('utf8');
		var prev = "";
		proc.stdout.on('data', function(buf) {
			prev += (buf:Buffer).toString().split("\r\n").join("\n");
			// buffer might be sent incrementaly, only process until newline is sent
			while( true ) {
				var index = prev.indexOf("\n");
				if( index < 0 ) break;
				var str = prev.substr(0, index);
				prev = prev.substr(index + 1);
				processLine(str, Stdout);
			}
			// remaining data ?, wait a little before sending -- if it's really a progressive trace
			if( prev != "" ) {
				var cur = prev;
				var t = new haxe.Timer(200);
				t.run = function() {
					if( prev == cur ) {
						sendEvent(new OutputEvent(prev, Stdout));
						prev = "";
					}
				};
			}
		} );
		proc.stderr.setEncoding('utf8');
		proc.stderr.on('data', function(buf){
			sendEvent(new OutputEvent(buf.toString(), OutputEventCategory.Stderr));
		} );
		proc.on('close', function(code) {
			var exitedEvent:ExitedEvent = {type:MessageType.Event, event:"exited", seq:0, body : { exitCode:code}};
			debug("Exit code " + code);
			sendEvent(exitedEvent);
			sendEvent(new TerminatedEvent());
			stopDebug();
			if( code == 4 ) {
				var msg = "hl exit code 4. Please check if the debug port " + port + " is already occupied, or specifiy a different port in launch configuration.";
				errorMessage(msg);
				#if vscode
				Vscode.window.showErrorMessage(msg, {modal: true});
				#end
			}
		});
		proc.on('error', function(err) {
			if( err.message == "spawn hl ENOENT" )
				errorMessageAndResponse(cast response, "Could not start 'hl' process, executable was not found in PATH.\nRestart VSCode or computer.");
			else
				errorMessageAndResponse(cast response, 'Failed to start hl process (${err.message})');
		});
	}


	function startDebug( program : String, port : Int, onError : String -> Void ) {
		dbg = new hld.Debugger();

		Sys.sleep(0.01); // make sure the process is started

		// TODO : load & validate after run() -- save some precious time
		debug("Load module " + program);
		dbg.loadModule(sys.io.File.getBytes(program));

		debug("Connecting to 127.0.0.1:" + port);
		dbg.connectTries("127.0.0.1", port, CONNECTION_TIMEOUT, function(b) {
			if( !b ) {
				// wait a bit (keep eventual HL error message)
				haxe.Timer.delay(function() {
					onError("Failed to connect on debug port");
				},2000);
				return;
			}

			var pid = @:privateAccess dbg.jit.pid;
			if( pid == 0 ) {
				if( proc == null ) {
					onError("Process attach requires HL 1.7+");
					return;
				}
				pid = proc.pid;
			}
			var api = new hld.NodeDebugApiNative(pid, dbg.is64);
			if( !dbg.init(api) ) {
				var msg = "Failed to initialize debugger";
				if( Sys.systemName() == "Linux" )
					msg += ". On Linux, please try set /proc/sys/kernel/yama/ptrace_scope to 0.";
				onError(msg);
				return;
			}
			dbg.eval.allowEvalGetters = allowEvalGetters;
			dbg.eval.printEvalCall = DEBUG;
			syncThreads();
			debug("Connected");
			onError(null);
		});
	}

	override function configurationDoneRequest(response:ConfigurationDoneResponse, args:ConfigurationDoneArguments) {
		debug("Init done");
		shouldRun = true;
		timer = new haxe.Timer(16);
		timer.run = function() {
			if( dbg == null )
				return;
			if( shouldRun || dbg.stoppedThread == null ) {
				shouldRun = false;
				run();
			}
		};
	}

	function stopDebug() {
		if( dbg == null ) return;
		dbg.end();
		dbg = null;
		if( timer != null ) {
			timer.stop();
			timer = null;
		}
	}

	function frameStr( f : hld.Debugger.StackInfo, ?debug ) {
		return f.file+":" + f.line + (debug ? " @"+f.ebp.toString():"");
	}

	function stackStr( f : hld.Debugger.StackInfo ) {
		if( f.context != null ) {
			var clName = f.context.obj.name.split(".");
			var field = f.context.field;
			for( i in 0...clName.length )
				if( clName[i].charCodeAt(0) == "$".code )
					clName[i] = clName[i].substr(1);
			if( field == "__constructor__" )
				field = "new";
			return clName.join(".") + "." + field;
		}
		return "<local function>";
	}

	function run() {
		if( dbg == null )
			return true;
		dbg.customTimeout = 0;
		var ret = false;
		var count = 0;
		while( true ) {
			var msg = dbg.run();
			handleWait(msg);
			switch( msg ) {
			case Timeout:
				break;
			case Error, Breakpoint, Exit, Watchbreak, StackOverflow:
				ret = true;
				break;
			case Handled, SingleStep:
				// wait a bit (prevent locking the process until next tick when many events are pending)
				dbg.customTimeout = 0.1;
				// prevent small loop with conditional breakpoint locking the adapter process
				count++;
				if( count > 100 ) {
					shouldRun = true;
					break;
				}
			}
		}
		if( dbg != null )
			dbg.customTimeout = null;
		return ret;
	}

	function syncThreads() {
		var prev = threads.copy();
		threads = new Map();
		for( t in dbg.getThreads() ) {
			// skipped stopped thread with no stack (thread allocated for breaking on windows)
			if( t == dbg.currentThread && t != dbg.mainThread && !dbg.hasStack() ) {
				debug("Skip thread "+t);
				continue;
			}
			if( !prev.remove(t) ) {
				debug("Started thread "+t);
				sendEvent(new ThreadEvent("started",t));
			}
			threads.set(t, true);
		}
		for( t in prev.keys() ) {
			debug("Exited thread "+t);
			sendEvent(new ThreadEvent("exited",t));
		}
	}

	function handleWait( msg : hld.Api.WaitResult ) {
		switch( msg ) {
		case Breakpoint, Watchbreak:
			//debug("Thread " + dbg.currentThread + " paused " + frameStr(dbg.getStackFrame()));
			var exc = dbg.getException();
			var str = null;
			if( exc != null ) {
				switch( exc.t ) {
				case HObj({ name:"haxe.ValueException" }):
					try {
						exc = dbg.eval.readField(exc, "value");
					} catch(e) {
						debug("Error extracting ValueException value: " + e.message);
					}
				default:
				}
				switch( exc.t ) {
				case HObj({ name:"SysError" }):
					try {
						switch( dbg.eval.readField(exc, "msg").v ) {
						case VString(str, _):
							exc = { v: VString("SysError: " + str, hld.Pointer.make(0,0)), t: HVoid };
						default:
						};
					} catch(e) {
						debug("Error extracting SysError value: " + e.message);
					}
				default:
				}
				str = switch( exc.v ) {
				case VString(str, _): str;
				default: dbg.eval.valueStr(exc);
				};
				debug("Exception: " + str);
			}

			var reason = if( msg == Watchbreak )
				"data breakpoint"
			else if( exc != null )
				"exception"
			else if( isPause )
				"paused"
			else
				"breakpoint";
			var tid = dbg.currentThread;
			syncThreads();
			beforeStop();
			debug("Stopped (" + reason+ ") on " + tid);
			if( tid != dbg.mainThread && !dbg.hasStack() ) {
				tid = dbg.mainThread;
				dbg.setCurrentThread(tid);
				debug("Switch thread "+tid);
			}
			var ev = new StoppedEvent(reason, tid, str);
			ev.allThreadsStopped = true;
			sendEvent(ev);
		case Error, StackOverflow:
			var error = msg == Error ? "Access Violation" : "Stack Overflow";
			debug("*** "+error+" ***");
			syncThreads();
			beforeStop();
			var bt = dbg.getBackTrace();
			debug("Callstack(tid:" + dbg.currentThread + "): " + bt.slice(0,5).map(f -> f.file + ":" + f.line));
			var ev = new StoppedEvent(
				"exception",
				dbg.stoppedThread,
				error
			);
			ev.allThreadsStopped = true;
			sendEvent(ev);
		case Exit:
			debug("Exit event");
			dbg.resume();
			stopDebug();
			sendEvent(new TerminatedEvent());
		case Handled, Timeout:
			// nothing
		default:
			errorMessage("??? "+msg);
		}
		isPause = false;
	}

	function beforeStop() {
		varsValues = new Map();
	}

	function getLocalFiles( file : String ) {
		file = file.split("\\").join("/");
		var filePath = file.toLowerCase();
		var matches = [];
		if( StringTools.startsWith(filePath, workspaceDirectory.toLowerCase()) )
			matches.push(file.substr(workspaceDirectory.length));
		for( c in classPath )
			if( StringTools.startsWith(filePath, c.toLowerCase()) )
				matches.push(file.substr(c.length));
		return matches;
	}

	override function setBreakPointsRequest(response:SetBreakpointsResponse, args:SetBreakpointsArguments):Void {
		//debug("Setbreakpoints request");
		var files = getLocalFiles(args.source.path);
		if( files.length == 0 ) {
			response.body = { breakpoints : [for( a in args.breakpoints ) { line : a.line, verified : false, message : "Could not resolve file " + args.source.path }] };
			sendResponse(response);
			return;
		}
		for( f in files ) {
			breakPos.set(f, []);
		}
		var bps = [];
		response.body = { breakpoints : bps };
		for( bp in args.breakpoints ) {
			var line = -1;
			for( f in files ) {
				line = dbg.checkBreakpointLine(f, bp.line);
				if( line >= 0 ) {
					breakPos.get(f).push({line : line, condition : bp.condition});
					bps.push({ line : line, verified : true, message : null });
					break;
				}
			}
			if( line < 0 )
				bps.push({ line : bp.line, verified : false, message : "No code found here" });
		}
		if( !breakOnlyActive || isSessionActive )
			setBreakPos(true);
		sendResponse(response);
	}

	function setBreakPos(active : Bool) {
		if( dbg == null )
			return;
		var forcePaused = false;
		if( dbg.stoppedThread == null ) {
			// On Linux, ptrace needs to be in ptrace-stop state in order to read/write
			forcePaused = true;
			safe(() -> dbg.pause());
		}
		for( f in breakPos.keys() )
			dbg.clearBreakpoints(f);
		if( active ) {
			for( f => bps in breakPos ) {
				for( bp in bps )
					var line = dbg.addBreakpoint(f, bp.line, bp.condition);
			}
		}
		if( forcePaused )
			shouldRun = true;
	}

	override function threadsRequest(response:ThreadsResponse) {
		//debug("Threads request");
		var threads = [];
		if( dbg != null ) {
			for( t in dbg.getThreads() ) {
				if( !this.threads.exists(t) ) continue;
				threads.push({
					name : t == dbg.mainThread ? "Main thread" : dbg.getThreadName(t),
					id : t,
				});
			}
		}
		response.body = {
			threads : threads,
		};
		sendResponse(response);
	}

	function setThread( tid : Int ) {
		if( tid != dbg.currentThread ) dbg.setCurrentThread(tid);
	}

	override function stackTraceRequest(response:StackTraceResponse, args:StackTraceArguments) {
		//debug("Stacktrace request");
		setThread(args.threadId);
		var bt = dbg.getBackTrace();
		var start = args.startFrame;
		var count = args.levels == null || args.levels + start > bt.length ? bt.length - start : args.levels;
		response.body = {
			stackFrames : [for( i in 0...count ) {
				var f = bt[start + i];
				var file = getFilePath(f.file);
				{
					id : start + i,
					name : stackStr(f),
					source : {
						name : f.file.split("/").pop(),
						path : file == null ? js.Lib.undefined : (isWindows ? file.split("/").join("\\") : file),
						sourceReference : file == null ? allocValue(VUnkownFile(f.file)) : 0,
					},
					line : f.line,
					column : 1
				};
			}],
			totalFrames : bt.length,
		};
		if( response.body.stackFrames.length == 0 ) {
			response.body.stackFrames.push({
				id : start + 0,
				name : "Empty Stack",
				line : 0,
				column : 0,
			});
		}
		sendResponse(response);
	}

	function allocValue( v ) {
		var id = ++UID;
		varsValues.set(id, v);
		return id;
	}

	function allocPtr( a : hld.Debugger.Address ) {
		for( i => p in ptrValues )
			if( p != null && p.ptr.i64 == a.ptr.i64 )
				return i + 1;
		ptrValues.push(a);
		return ptrValues.length;
	}

	override function scopesRequest(response:ScopesResponse, args:ScopesArguments) {
		//debug("Scopes Request " + args);
		dbg.currentStackFrame = args.frameId;
		var args = dbg.getCurrentVars(true);
		var locals = dbg.getCurrentVars(false);
		var hasThis = args.indexOf("this") >= 0 || locals.indexOf("this") >= 0;
		response.body = {
			scopes : [{
				name : "Locals",
				variablesReference : allocValue(VScope(dbg.currentStackFrame)),
				expensive : false,
				namedVariables : args.length + locals.length,
			}],
		};
		if( hasThis ) {
			try {
				var vthis = dbg.getValue("this");
				var fields = dbg.eval.getFields(vthis);
				if( fields == null )
					debug("Can't get fields for this: " + vthis.v.getName() + " of " + dbg.eval.typeStr(vthis.t));
				else
					response.body.scopes.push({
						name : "Members",
						variablesReference : allocValue(VValue(vthis, "this")),
						expensive : false,
						namedVariables : fields.length,
					});
			} catch( e : Dynamic ) {
				errorMessage(e);
			}
		}
		var cl = dbg.getCurrentClass();
		if( cl != null ) {
			try {
				var fields = dbg.getClassStatics(cl);
				for( f in fields.copy() ) {
					var v = try dbg.getValue(cl+"."+f, true) catch( e : Dynamic ) { errorMessage(e+" ("+cl+"."+f+")"); continue; };
					if( v == null || v.t.match(HFun(_)) )
						fields.remove(f);
				}
				if( fields.length > 0 )
					response.body.scopes.push({
						name : "Statics",
						variablesReference : allocValue(VStatics(cl)),
						expensive : false,
						namedVariables : fields.length,
					});
			} catch( e : Dynamic ) {
				errorMessage(e);
			}
		}
		var exception = dbg.getVMExceptionStack();
		if( exception != null )
			response.body.scopes.push({
				name : "Exception Stack",
				variablesReference : allocValue(VStack(exception)),
				expensive : false,
			});
		sendResponse(response);
	}

	function makeVar( name : String, value : hld.Value, ?evalName : String ) : vscode.debugProtocol.DebugProtocol.Variable {
		if( value == null )
			return { name : name, value : "Unknown variable", variablesReference : 0 };
		var tstr = dbg.eval.typeStr(value.t);
		var pstr = switch( value.hint ) {
			case HPointer:
				var p = @:privateAccess dbg.eval.getPtr(value);
				p == null ? "" : " " + p.toString();
			default: "";
		}
		switch( value.v ) {
		case VPointer(_):
			var fields = dbg.eval.getFields(value);
			if( fields != null && fields.length > 0 )
				return { name : name, type : tstr, value : tstr + pstr, evaluateName : evalName ?? "#" + tstr, variablesReference : allocValue(VValue(value, evalName)), namedVariables : fields.length };
		case VEnum(c,values,_) if( values.length > 0 ):
			var str = c + "(" + [for( v in values ) switch( v.v ) {
				case VEnum(c,values,_) if( values.length == 0 ): c;
				case VPointer(_), VEnum(_), VArray(_), VMap(_), VBytes(_): "...";
				default: dbg.eval.valueStr(v);
			}].join(", ")+")";
			return { name : name, type : tstr, value : str + pstr, evaluateName : evalName ?? "#" + str, variablesReference : allocValue(VValue(value, evalName)), namedVariables : values.length };
		case VArray(_, len, _, _), VMap(_, len, _, _):
			var str = dbg.eval.valueStr(value);
			return { name : name, type : tstr, value : str + pstr, evaluateName : evalName ?? "#" + str, variablesReference : len == 0 ? 0 : allocValue(VValue(value, evalName)), indexedVariables : len };
		case VBytes(len, _):
			switch( value.hint ) {
			case HReadBytes(t, _):
				var str = dbg.eval.valueStr(value);
				return { name : name, type : dbg.eval.typeStr(t), value : str, evaluateName : evalName ?? "#" + str, variablesReference : 0 };
			default:
			}
			var str = tstr+":"+len;
			return { name : name, type : tstr, value : str + pstr, evaluateName : evalName ?? "#" + str, variablesReference : allocValue(VValue(value, evalName)), indexedVariables : (len+15)>>4 };
		case VClosure(f,context,_):
			var str = dbg.eval.funStr(f, value.hint == HPointer);
			return { name : name, type : tstr, value : str + pstr, evaluateName : evalName ?? "#" + str, variablesReference : allocValue(VValue(value, evalName)), indexedVariables : 2 };
		case VInlined(fields):
			var str = dbg.eval.valueStr(value);
			return { name : name, type : tstr, value : str, evaluateName : evalName ?? "#" + str, variablesReference : fields.length == 0 ? 0 : allocValue(VValue(value, evalName)), namedVariables : fields.length };
		case VMapPair(_, _):
			var str = dbg.eval.valueStr(value);
			return { name : name, type : tstr, value : str + pstr, evaluateName : evalName ?? "#" + str, variablesReference : allocValue(VValue(value, evalName)), namedVariables : 2 };
		case VString(_, _):
			if( value.hint == HNone )
				value.hint = HNoEscape;
		default:
		}
		var str = dbg.eval.valueStr(value);
		return { name : name, type : tstr, value : str + pstr, evaluateName : evalName ?? "#" + str, variablesReference : 0 };
	}

	override function variablesRequest(response:VariablesResponse, args:VariablesArguments) {
		//debug("Variables request " + args);
		var vref = varsValues.get(args.variablesReference);
		var vars = [];
		response.body = { variables : vars };
		switch( vref ) {
		case VScope(k):
			dbg.currentStackFrame = k;
			var vnames = dbg.getCurrentVars(true).concat(dbg.getCurrentVars(false));
			for( v in vnames ) {
				try {
					var value = dbg.getValue(v);
					if( v == "$ret" ) v = "(return)";
					vars.push(makeVar(v, value, v));
				} catch( e : Dynamic ) {
					vars.push({
						name : v,
						value : Std.string(e),
						variablesReference : 0,
					});
				}
			}
		case VValue(v, evalName), VObjFields(v, _, evalName):
			switch( v.v ) {
			case VPointer(_):

				var fields;
				switch( [vref, v.t] ) {
				case [VObjFields(_, p, _), _]:
					fields = [for( f in p.fields ) if( f.name != "" ) f.name];
				case [_,HObj(o)]:
					var p = o.tsuper;
					while( p != null )
						switch( p ) {
						case HObj(o):
							if( o.fields.length > 0 )
								vars.unshift({ name : o.name, type : "", value : "", variablesReference : allocValue(VObjFields(v, o, evalName)) });
							p = o.tsuper;
						default:
						}
					fields = [for( f in o.fields ) if( f.name != "" ) f.name];
				default:
					fields = dbg.eval.getFields(v);
				}

				for( f in fields ) {
					try {
						var value = dbg.eval.readField(v, f);
						vars.push(makeVar(f, value, evalName == null ? null : evalName+"."+f));
					} catch( e : Dynamic ) {
						vars.push({
							name : f,
							value : Std.string(e),
							variablesReference : 0,
						});
					}
				}
			case VArray(_, len, get, _):
				var start = args.start == null ? 0 : args.start;
				var count = args.count == null ? len - start : args.count;
				for( i in start...start+count ) {
					try {
						var value = get(i);
						vars.push(makeVar("" + i, value, evalName == null ? null : evalName+"["+i+"]"));
					} catch( e : Dynamic ) {
						vars.push({
							name : "" + i,
							value : Std.string(e),
							variablesReference : 0,
						});
					}
				}
			case VBytes(len, read, _):
				var max = (len + 15) >> 4;
				var start = args.start == null ? 0 : args.start;
				var count = args.count == null ? max - start : args.count;

				for( i in start...start+count ) {
					var p = i * 16;
					var size = p + 16 > len ? len - p : 16;
					var b = haxe.io.Bytes.alloc(size);
					for( k in 0...size )
						b.set(k,read(p+k));
					vars.push({ name : ""+p, value : "0x"+b.toHex().toUpperCase(), variablesReference : 0 });
				}
			case VEnum(_,values, _):
				for( i in 0...values.length )
					try {
						var value = values[i];
						vars.push(makeVar("" + i, value, evalName == null ? null : evalName+".$"+i));
					} catch( e : Dynamic ) {
						vars.push({
							name : "" + i,
							value : Std.string(e),
							variablesReference : 0,
						});
					}
			case VMap(tkey, len, getKey, getValue, _):
				var start = args.start == null ? 0 : args.start;
				var count = args.count == null ? len - start : args.count;
				if( len > 0 ) getKey(len - 1); // fetch all
				for( i in start...start+count ) {
					try {
						var key = getKey(i);
						var value = getValue(i);
						if( tkey == HDyn ) {
							vars.push(makeVar("" + i, { v: VMapPair(key,value), t : tkey }, evalName == null ? null : evalName+".$"+i));
						} else
							vars.push(makeVar(dbg.eval.valueStr(key), value, evalName == null ? null : evalName+".$"+i+".$value"));
					} catch( e : Dynamic ) {
						vars.push({
							name : "" + i,
							value : Std.string(e),
							variablesReference : 0,
						});
					}
				}
			case VMapPair(key, value):
				vars.push(makeVar("key", key, evalName == null ? null : evalName+".$key"));
				vars.push(makeVar("value", value, evalName == null ? null : evalName+".$value"));
			case VClosure(_, context, _):
				if( context != null )
					switch( context.t ) {
					case HEnum(e) if( e.name.charCodeAt(0) == "$".code ):
						vars.push({
							name : "Context",
							value : "",
							variablesReference : allocValue(VValue(context, ""))
						});
					default:
						vars.push(makeVar("Context", context));
					}
				var stack = dbg.getClosureStack(v.v);
				if( stack.length > 0 )
					vars.push({
						name : "Stack",
						value : "",
						variablesReference : allocValue(VStack(stack)),
					});
			case VInlined(fields):
				for( f in fields )
					try {
						var value = dbg.eval.readField(v, f.name);
						vars.push(makeVar(f.name, value, evalName == null ? null : evalName+"."+f.name));
					} catch( e : Dynamic ) {
						vars.push({
							name : f.name,
							value : Std.string(e),
							variablesReference : 0,
						});
					}
			default:
				vars.push({
					name : "TODO",
					value : dbg.eval.typeStr(v.t),
					variablesReference : 0,
				});
			}
		case VStatics(cl):
			for( f in dbg.getClassStatics(cl) ) {
				var v = dbg.getValue(cl+"."+f, true);
				if( v.t.match(HFun(_)) ) continue;
				vars.push(makeVar(f, v, cl+"."+f));
			}
		case VStack(stack):
			for( i in 0...stack.length ) {
				var st = stack[i];
				vars.push({
					name : ""+i,
					value : stackStr(st) + " (" + getFilePath(st.file) + ":" + st.line + ")",
					variablesReference: 0,
				});
			}
		case VUnkownFile(_):
			throw "assert";
		}
		sendResponse(response);
	}

	override function pauseRequest(response:PauseResponse, args:PauseArguments):Void {
		debug("Pause request");
		if( dbg.stoppedThread != null ) {
			// already paused, stop all threads
			sendResponse(response);
			for( tid in threads.keys() ) {
				if( tid != dbg.currentThread ) {
					var ev = new StoppedEvent("paused", tid);
					sendEvent(ev);
				}
			}
			return;
		}
		isPause = true;
		sendResponse(response);
		safe(() -> handleWait(dbg.pause()));
	}

	override function disconnectRequest(response:DisconnectResponse, args:DisconnectArguments) {
		debug("Disconnect request");
		if( proc != null ) proc.kill();
		sendResponse(response);
		if( dbg.stoppedThread != null ) {
			var ev = new ContinuedEvent(dbg.stoppedThread, true);
			sendEvent(ev);
		}
		stopDebug();
	}

	function safe(f:Void->Void) {
		try {
			f();
		} catch( e : Dynamic ) {
			errorMessage("***** ERRROR ***** "+e+haxe.CallStack.toString(haxe.CallStack.exceptionStack()));
		}
	}

	override function nextRequest(response:NextResponse, args:NextArguments) {
		debug("Next");
		sendResponse(response);
		setThread(args.threadId);
		safe(() -> handleWait(dbg.step(Next)));
	}

	override function stepInRequest(response:StepInResponse, args:StepInArguments) {
		debug("StepIn");
		sendResponse(response);
		setThread(args.threadId);
		safe(() -> handleWait(dbg.step(Into)));
	}

	override function stepOutRequest(response:StepOutResponse, args:StepOutArguments) {
		debug("StepOut");
		sendResponse(response);
		setThread(args.threadId);
		safe(() -> handleWait(dbg.step(Out)));
	}

	override function continueRequest(response:ContinueResponse, args:ContinueArguments) {
		debug("Continue");
		sendResponse(response);
		// On Linux, api.resume() and api.wait() need to be called at the same location
		shouldRun = true;
	}

	override function sourceRequest(response:SourceResponse, args:SourceArguments) {
		switch( varsValues.get(args.sourceReference) ) {
		case VUnkownFile(file):
			response.body = { content : "Unknown file " + file };
			sendResponse(response);
		default:
			throw "assert";
		}
	}

	static var KEYWORDS = [for( k in [
			// ref: haxe/src/core/ast.ml/s_keyword, without null/true/false/this
			"function","class","static","var","if","else","while","do","for","break","return","continue","extends","implements","import","switch","case","default",
			"private","public","try","catch","new","throw","extern","enum","in","interface","untyped","cast","override","typedef","dynamic","package","inline",
			"using","abstract","macro","final","operator","overload",
		] ) k => true];

	override function evaluateRequest(response:EvaluateResponse, args:EvaluateArguments) {
		//debug("Eval " + args);
		dbg.currentStackFrame = args.frameId;
		try {
			// ?ident => hover on optional param (most likely)
			if( ~/^\?[A-Za-z0-9_]+$/.match(args.expression) )
				args.expression = args.expression.substr(1);
			if( KEYWORDS.exists(args.expression) ) {
				// Do nothing
			} else if( args.expression.charCodeAt(0) == '@'.code ) {
				// Advanced commands based on address
				switch( args.expression.charCodeAt(1) ) {
				case ':'.code:
					// skip metadata hover, such as @:privateAccess
				case 'd'.code:
					// @d + ptr: try to evaluate pointer as Dynamic value
					var p = new hld.Pointer(hld.Value.parseInt64(args.expression.substr(2)));
					var value = @:privateAccess dbg.eval.convertVal(p, HDyn);
					value.hint = HPointer;
					var v = makeVar("", value);
					response.body = {
						result : v.value,
						type : v.type,
						variablesReference : v.variablesReference,
						namedVariables : v.namedVariables,
						indexedVariables : v.indexedVariables,
					};
				case 'f'.code:
					// @f + ptr: try to evaluate pointer as FunRepr
					var p = new hld.Pointer(hld.Value.parseInt64(args.expression.substr(2)));
					@:privateAccess var index = dbg.jit.functionFromAddr(p);
					response.body = {
						result : dbg.eval.funStr(index == null ? FUnknown(p) : FIndex(index, p), true),
						variablesReference : 0,
					};
				default:
					debug("Unsupported command " + args.expression);
				}
			} else if( args.expression.charCodeAt(0) == '#'.code ) {
				// Fake evalName for Copy value request
				response.body = {
					result : args.expression.substr(1),
					variablesReference : 0,
				};
			} else {
				var value = dbg.getValue(args.expression);
				var ext = hld.Value.extractHint(args.expression);
				var v = makeVar(ext.expr, value, ext.expr);
				response.body = {
					result : v.value,
					type : v.type,
					variablesReference : v.variablesReference,
					namedVariables : v.namedVariables,
					indexedVariables : v.indexedVariables,
				};
			}
		} catch( e : Dynamic ) {
			response.body = {
				result : Std.string(e),
				variablesReference : 0,
			};
		}
		sendResponse(response);
	}

	override function setVariableRequest(response:SetVariableResponse, args:SetVariableArguments) {
		try {
			var ptr = getVarAddress(args.variablesReference, args.name);
			if( ptr == null ) throw "Can't get address for "+args.name;
			var value = dbg.eval.eval(args.value);
			if( value != null ) {
				dbg.eval.setPtr(ptr, value);
				response.body = makeVar(args.name, value);
			}
		} catch( e : Dynamic ) {
			errorMessage(""+e);
		}
		sendResponse(response);
	}

	override function setFunctionBreakPointsRequest(response:SetFunctionBreakpointsResponse, args:SetFunctionBreakpointsArguments) {
		debug("Unhandled request");
		sendResponse(response);
	}

	override function setDataBreakpointsRequest(response:SetDataBreakpointsResponse, args:SetDataBreakpointsArguments) {
		//debug("SetDataBreakpoints request");
		var current = watchedPtrs.copy();
		for( a in args.breakpoints ) {
			if( a.dataId == null ) continue;
			var ptr = ptrValues[(cast a.dataId:Int) - 1];
			for( w in current ) {
				if( w.addr.ptr.i64 == ptr.ptr.i64 ) {
					current.remove(w);
					ptr = null;
					break;
				}
			}
			if( ptr == null ) continue;
			try {
				var w = dbg.watch(ptr);
				debug("WATCHING "+ptr.ptr.toString()+":"+dbg.eval.typeStr(ptr.t));
				watchedPtrs.push(w);
			} catch( e : Dynamic ) {
				errorMessage(""+e);
			}
		}
		for( w in current ) {
			debug("UNWATCH "+w.addr.ptr.toString());
			watchedPtrs.remove(w);
			dbg.unwatch(w.addr);
		}
		sendResponse(response);
	}

	function getVarAddress( varRef : Int, name : String ) {
		var ref = varsValues.get(varRef);
		if( ref == null )
			return null;
		var addr = switch( ref ) {
		case VScope(k):
			dbg.currentStackFrame = k;
			return dbg.getRef(name);
		case VValue(v, _) | VObjFields(v, _, _):
			if( v.v.match(VArray(_)) )
				dbg.eval.readArrayAddress(v, Std.parseInt(name));
			else
				dbg.eval.readFieldAddress(v, name);
		case VStatics(cl):
			var value = dbg.getValue(cl, true);
			dbg.eval.readFieldAddress(value, name);
		default:
			return null;
		}
		return switch( addr ) { case AAddr(ptr,t): { ptr : ptr, t : t }; default: null; };
	}

	override function dataBreakpointInfoRequest(response:DataBreakpointInfoResponse, args:DataBreakpointInfoArguments) {
		try {
			var ptr = getVarAddress(args.variablesReference, args.name);
			if( ptr != null ) {
				var desc = switch( varsValues.get(args.variablesReference) ) {
				case VScope(_): "local "+args.name;
				case VValue({v : VArray(_)}, _): "["+args.name+"]";
				default: "field "+args.name;
				}
				response.body = {
					dataId : cast allocPtr(ptr),
					description : "Write "+desc+":"+ptr.ptr.toString(),
					accessTypes : [Write],
				};
			}
		} catch( e : Dynamic ) {
			response.body = {
				dataId : null,
				description : ""+e,
			};
		}
		sendResponse(response);
	}

	override function stepBackRequest(response:StepBackResponse, args:StepBackArguments) { debug("Unhandled request"); }
	override function restartFrameRequest(response:RestartFrameResponse, args:RestartFrameArguments) { debug("Unhandled request"); }
	override function gotoRequest(response:GotoResponse, args:GotoArguments) { debug("Unhandled request"); }
	override function stepInTargetsRequest(response:StepInTargetsResponse, args:StepInTargetsArguments) { debug("Unhandled request"); }
	override function gotoTargetsRequest(responses:GotoTargetsResponse, args:GotoTargetsArguments) { debug("Unhandled request"); }
	override function completionsRequest(response:CompletionsResponse, args:CompletionsArguments) { debug("Unhandled request"); }
	override function setExpressionRequest(response:SetExpressionResponse, args:SetExpressionArguments) { debug("Unhandled request"); }

	override function dispose() {
		super.dispose();
		debug("Dispose");
		inst = null;
		return null;
	}

	function errorMessage( msg : String ) {
		sendEvent(new OutputEvent(msg+"\n", Stderr));
	}

	// Runtime communication with extension

	override function customRequest<T>(command:String, response:vscode.debugAdapter.Messages.Response<T>, args:Dynamic):Void {
		// Value in response.body will be received by the extension in .then
		var response : vscode.debugProtocol.DebugProtocol.Response<String> = cast response;
		switch( command ) {
		case OnSessionActive:
			isSessionActive = true;
		case OnSessionInactive:
			isSessionActive = false;
		default:
		}
		sendResponse(cast response);
	}

	// Standalone adapter.js

	static function main() {
		function paramError( msg ) {
			Sys.stderr().writeString(msg + "\n");
			// Sys.exit(1); // Ignore error
		}

		var args = Sys.args();
		while( args.length > 0 && args[0].charCodeAt(0) == '-'.code ) {
			var param = args.shift();
			switch( param ) {
				case "--verbose":
					HLAdapter.DEBUG = true;
				case "--defaultPort":
					param = args.shift();
					var port : Int;
					if( param != null && (port = Std.parseInt(param)) != 0 )
						HLAdapter.DEFAULT_PORT = port;
					paramError("--defaultPort requires int value (port number)");
				case "--connectionTimeout":
					param = args.shift();
					var timeout : Float;
					if( param != null && (timeout = Std.parseFloat(param)) != 0 )
						HLAdapter.CONNECTION_TIMEOUT = timeout;
					paramError("--connectionTimeout requires float value (seconds)");
				default:
					paramError("Unsupported parameter " + param);
			}
		}
		if( HLAdapter.DEBUG ) {
			js.Node.process.on("uncaughtException", function(e:js.lib.Error) {
				if( inst != null ) inst.sendEvent(new OutputEvent("*** ERROR *** " +e.message+"\n"+e.stack, Stderr));
				Sys.exit(1);
			});
		}
		DebugSession.run( HLAdapter );
	}

}

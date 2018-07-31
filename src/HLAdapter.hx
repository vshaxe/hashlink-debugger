import protocol.debug.Types;
import adapter.DebugSession;
import js.node.ChildProcess;
import js.node.Buffer;
import js.node.child_process.ChildProcess as ChildProcessObject;

enum VarValue {
	VScope( k : Int );
	VValue( v : hld.Value );
	VUnkownFile( file : String );
	VObjFields( v : hld.Value, o : format.hl.Data.ObjPrototype );
	VMapPair( key : hld.Value, value : hld.Value );
	VStatics( cl : String );
}

class HLAdapter extends adapter.DebugSession {

	static var UID = 0;

	var proc : ChildProcessObject;
	var workspaceDirectory : String;
	var classPath : Array<String>;

	var debugPort = 6112;
	var doDebug = true;
	var dbg : hld.Debugger;
	var startTime = haxe.Timer.stamp();
	var timer : haxe.Timer;

	var varsValues : Map<Int,VarValue>;

	static var DEBUG = false;
	static var isWindow = Sys.systemName() == "Windows";

	override function initializeRequest(response:InitializeResponse, args:InitializeRequestArguments) {


		haxe.Log.trace = function(v:Dynamic, ?p:haxe.PosInfos) {
			var str = haxe.Log.formatOutput(v, p);
			sendEvent(new OutputEvent(Std.int((haxe.Timer.stamp() - startTime)*10) / 10 + "> " + str+"\n"));
		};

		debug("initialize");

		response.body.supportsConfigurationDoneRequest = true;
		response.body.supportsFunctionBreakpoints = false;
		response.body.supportsConditionalBreakpoints = true;
		response.body.supportsEvaluateForHovers = true;
		response.body.supportsStepBack = false;
		response.body.supportsSetVariable = true;
		response.body.exceptionBreakpointFilters = [{ filter : "all", label : "Stop on all exceptions" }];

		sendResponse( response );
	}

	function debug(v:Dynamic, ?pos:haxe.PosInfos) {
		if( DEBUG ) haxe.Log.trace(v, pos);
	}

	override function launchRequest(response:LaunchResponse, args:LaunchRequestArguments) {

		debug("launch");

		workspaceDirectory = Reflect.field(args, "cwd");
		Sys.setCwd(workspaceDirectory);
		var port = Reflect.field(args,"port");
		if( port == null ) port = debugPort;

		try {
			var program = launch(cast args, response);
			if( doDebug && !startDebug(program, port) ) {
				proc.kill();
				dbg = null;
				throw "Could not initialize debugger";
			}
			sendEvent(new InitializedEvent());
		} catch( e : Dynamic ) {
			error(cast response, e);
			sendEvent(new TerminatedEvent());
		}
		sendResponse(response);
	}

	override function setExceptionBreakPointsRequest(response:SetExceptionBreakpointsResponse, args:SetExceptionBreakpointsArguments) {
		dbg.breakOnThrow = args.filters.indexOf("all") >= 0;
		sendResponse(response);
	}


	override function attachRequest(response:AttachResponse, args:AttachRequestArguments) {
		debug("attach");
		workspaceDirectory = Reflect.field(args, "cwd");
		Sys.setCwd(workspaceDirectory);
		var program = readHXML(Reflect.field(args,"hxml"));
		try {
			if( !startDebug(program,Reflect.field(args,"port")) )
				throw "Failed to start debugging";
			sendEvent(new InitializedEvent());
		} catch( e : Dynamic ) {
			error(cast response, e);
			sendEvent(new TerminatedEvent());
		}
		sendResponse(response);
	}

	function error<T>(response:Response<T>, message:Dynamic) {
		sendErrorResponse(cast response, 3000, "" + message);
		sendToOutput("ERROR : " + message, OutputEventCategory.stderr);
	}

	/**
		Translate a classpath-relative file into a workspace-relative (or absolute) path.
		Returns null if not found
	**/
	function getFilePath( file : String ) {
		for( c in classPath )
			if( sys.FileSystem.exists(c + file) )
				return c + file;
		return null;
	}

	var r_trace = ~/^([A-Za-z0-9_.\/]+):([0-9]+): /;
	var r_call = ~/^Called from [^(]+\(([A-Za-z0-9_.\/\\:]+) line ([0-9]+)\)/;

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

	function readHXML( hxml : String ) {
		classPath = [];

		var hxContent = try sys.io.File.getContent(hxml) catch( e : Dynamic ) throw "Missing HXML file '"+hxml+"'";
		var program = null;
		var libs = [];

		var hxArgs = hxContent.split("\n");

		function flushLibs() {
			if( libs.length == 0 ) return;
			var p = ChildProcess.spawnSync("haxelib", ["path"].concat(libs));
			if( p.status != 0 ) return;
			for( line in (p.stdout:Buffer).toString().split("\n") ) {
				var line = StringTools.trim(line);
				if( line == "" ) continue;
				if( line.charCodeAt(0) == "-".code ) {
					hxArgs.push(line);
					continue;
				}
				classPath.push(line);
			}
		}

		while( hxArgs.length > 0 ) {
			var args = StringTools.trim(hxArgs.shift()).split(" ");
			if( args.length == 0 ) continue;
			var arg = args.shift();
			var value = args.join(" ");
			switch( arg ) {
			case "-lib":
				libs.push(value);
			case "-cp":
				flushLibs();
				classPath.push(value);
			case "-hl":
				program = value;
			default:
				if( StringTools.endsWith(arg, ".hxml") && value == "" )
					hxArgs = sys.io.File.getContent(arg).split("\n").concat(hxArgs);
			}
		}

		flushLibs();

		// TODO : we need locate haxe std (and std/hl/_std) class path

		classPath.reverse();
		classPath.push("./"); // default path
		for( i in 0...classPath.length ) {
			var c = sys.FileSystem.fullPath(classPath[i]);
			c = c.split("\\").join("/");
			if( !StringTools.endsWith(c, "/") ) c += "/";
			classPath[i] = c;
		}
		classPath.push(""); // for absolute paths

		return program;
	}

	function launch( args : { cwd: String, hxml: String, ?args: Array<String>, ?argsFile : String }, response : LaunchResponse ) {

		var program = readHXML(args.hxml);
		if( program == null )
			throw args.hxml + " file does not contain -hl output";

		var hlArgs = ["--debug", "" + debugPort, program];

		if( doDebug )
			hlArgs.unshift("--debug-wait");

		debug("start process");

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
		proc = ChildProcess.spawn("hl", hlArgs, {env: {}, cwd: args.cwd});
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
				processLine(str, stdout);
			}
			// remaining data ?, wait a little before sending -- if it's really a progressive trace
			if( prev != "" ) {
				var cur = prev;
				var t = new haxe.Timer(200);
				t.run = function() {
					if( prev == cur ) {
						sendEvent(new OutputEvent(prev, stdout));
						prev = "";
					}
				};
			}
		} );
		proc.stderr.setEncoding('utf8');
		proc.stderr.on('data', function(buf){
			sendEvent(new OutputEvent(buf.toString(), OutputEventCategory.stderr));
		} );
		proc.on('close', function(code) {
			var exitedEvent:ExitedEvent = {type:MessageType.event, event:"exited", seq:0, body : { exitCode:code}};
			debug("Exit code " + code);
			sendEvent(exitedEvent);
			sendEvent(new TerminatedEvent());
			stopDebug();
		});
		proc.on('error', function(err) {
			error(cast response, 'Failed to start hl process ($err)');
		});

		return program;
	}


	function startDebug( program : String, port : Int ) {
		dbg = new hld.Debugger();

		// TODO : load & validate after run() -- save some precious time
		debug("load module");
		dbg.loadModule(sys.io.File.getBytes(program));

		debug("connecting");
		if( !dbg.connect("127.0.0.1", port) )
			throw "Failed to connect on debug port";

		var pid = @:privateAccess dbg.jit.pid;
		if( pid == 0 ) {
			if( proc == null ) throw "Process attach requires HL 1.7+";
			pid = proc.pid;
		}
		var api : hld.Api;
		if( isWindow )
			api = new hld.NodeDebugApi(pid, dbg.is64);
		else
			api = new hld.NodeDebugApiLinux(pid, dbg.is64);

		if( !dbg.init(api) )
			throw "Failed to initialize debugger";

		debug("connected");
		return true;
	}

	override function configurationDoneRequest(response:ConfigurationDoneResponse, args:ConfigurationDoneArguments) {
		run();
		debug("init done");
		timer = new haxe.Timer(16);
		timer.run = function() {
			if( dbg.stoppedThread != null )
				return;
			run();
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
		while( true ) {
			var msg = dbg.run();
			handleMessage(msg);
			switch( msg ) {
			case Timeout:
				break;
			case Error, Breakpoint, Exit, Watchbreak:
				ret = true;
				break;
			case Handled, SingleStep:
				// wait a bit (prevent locking the process until next tick when many events are pending)
				dbg.customTimeout = 0.1;
			}
		}
		if( dbg != null )
			dbg.customTimeout = null;
		return ret;
	}

	function handleMessage( msg : hld.Api.WaitResult ) {
		switch( msg ) {
		case Breakpoint:
			//debug("Thread " + dbg.currentThread + " paused " + frameStr(dbg.getStackFrame()));
			var exc = dbg.getException();
			var str = null;
			if( exc != null ) {
				str = switch( exc.v ) {
				case VString(str, _): str;
				default: dbg.eval.valueStr(exc);
				};
				debug("Exception: " + str);
			}
			beforeStop();
			var ev = new StoppedEvent(exc == null ? "breakpoint" : "exception", dbg.currentThread, str);
			ev.allThreadsStopped = true;
			sendEvent(ev);
		case Error:
			debug("*** ERROR ***");
			beforeStop();
			var ev = new StoppedEvent(
				"error",
				dbg.stoppedThread
			);
			ev.allThreadsStopped = true;
			sendEvent(ev);
		case Exit:
			debug("Exit event");
			dbg.resume();
			stopDebug();
			sendEvent(new TerminatedEvent());
		case Watchbreak:
			debug("Watch "+dbg.watchBreak.ptr.toString());
		default:
		}
	}

	function beforeStop() {
		varsValues = new Map();
	}

	function getLocalFiles( file : String ) {
		file = file.split("\\").join("/");
		var filePath = file.toLowerCase();
		var matches = [];
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
		for( f in files )
			dbg.clearBreakpoints(f);
		var bps = [];
		response.body = { breakpoints : bps };
		for( bp in args.breakpoints ) {
			var line = -1;
			for( f in files ) {
				line = dbg.addBreakpoint(f, bp.line);
				if( line >= 0 ) break;
			}
			if( line >= 0 )
				bps.push({ line : line, verified : true, message : null });
			else
				bps.push({ line : bp.line, verified : false, message : "No code found here" });
		}
		sendResponse(response);
	}

	override function threadsRequest(response:ThreadsResponse) {
		//debug("Threads request");
		var threads = [];
		if( dbg != null ) {
			for( t in dbg.getThreads() )
				threads.push({
					name : threads.length == 0 ? "Main thread" : "Thread "+t,
					id : t,
				});
		}
		response.body = {
			threads : threads,
		};
		sendResponse(response);
	}

	override function stackTraceRequest(response:StackTraceResponse, args:StackTraceArguments) {
		//debug("Stacktrace Request");
		var bt = dbg.getBackTrace();
		var start = args.startFrame;
		var count = args.levels + start > bt.length ? bt.length - start : args.levels;
		response.body = {
			stackFrames : [for( i in 0...count ) {
				var f = bt[start + i];
				var file = getFilePath(f.file);
				{
					id : start + i,
					name : stackStr(f),
					source : {
						name : f.file.split("/").pop(),
						path : file == null ? null : (isWindow ? file.split("/").join("\\") : file),
						sourceReference : file == null ? allocValue(VUnkownFile(f.file)) : 0,
					},
					line : f.line,
					column : 1
				};
			}],
			totalFrames : bt.length,
		};
		sendResponse(response);
	}

	function allocValue( v ) {
		var id = ++UID;
		varsValues.set(id, v);
		return id;
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
				response.body.scopes.push({
					name : "Members",
					variablesReference : allocValue(VValue(vthis)),
					expensive : false,
					namedVariables : dbg.eval.getFields(vthis).length,
				});
			} catch( e : Dynamic ) {
				trace(e);
			}
		}
		var cl = dbg.getCurrentClass();
		if( cl != null ) {
			try {
				var fields = dbg.getClassStatics(cl);
				for( f in fields.copy() ) {
					var v = dbg.getValue(cl+"."+f);
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
				trace(e);
			}
		}
		sendResponse(response);
	}

	function makeVar( name : String, value : hld.Value ) : protocol.debug.Types.Variable {
		if( value == null )
			return { name : name, value : "Unknown variable", variablesReference : 0 };
		var tstr = dbg.eval.typeStr(value.t);
		switch( value.v ) {
		case VPointer(_), VEnum(_):
			var fields = dbg.eval.getFields(value);
			if( fields != null && fields.length > 0 )
				return { name : name, type : tstr, value : tstr, variablesReference : allocValue(VValue(value)), namedVariables : fields.length };
		case VArray(_, len, _, _), VMap(_, len, _, _):
			return { name : name, type : tstr, value : dbg.eval.valueStr(value), variablesReference : allocValue(VValue(value)), indexedVariables : len };
		case VBytes(len, _):
			return { name : name, type : tstr, value : tstr+":"+len, variablesReference : allocValue(VValue(value)), indexedVariables : (len+15)>>4 };
		default:
		}
		return { name : name, type : tstr, value : dbg.eval.valueStr(value), variablesReference : 0 };
	}

	override function variablesRequest(response:VariablesResponse, args:VariablesArguments) {
		//debug("Variables Request " + args);
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
					vars.push(makeVar(v, value));
				} catch( e : Dynamic ) {
					vars.push({
						name : v,
						value : Std.string(e),
						variablesReference : 0,
					});
				}
			}
		case VValue(v), VObjFields(v,_):
			switch( v.v ) {
			case VPointer(_):

				var fields;
				switch( [vref, v.t] ) {
				case [VObjFields(_, p), _]:
					fields = [for( f in p.fields ) if( f.name != "" ) f.name];
				case [_,HObj(o)]:
					var p = o.tsuper;
					while( p != null )
						switch( p ) {
						case HObj(o):
							if( o.fields.length > 0 )
								vars.unshift({ name : o.name, type : "", value : "", variablesReference : allocValue(VObjFields(v, o)) });
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
						vars.push(makeVar(f, value));
					} catch( e : Dynamic ) {
						vars.push({
							name : f,
							value : Std.string(e),
							variablesReference : 0,
						});
					}
				}
			case VArray(_, len, get, _):
				for( i in 0...len ) {
					try {
						var value = get(i);
						vars.push(makeVar("" + i, value));
					} catch( e : Dynamic ) {
						vars.push({
							name : "" + i,
							value : Std.string(e),
							variablesReference : 0,
						});
					}
				}
			case VBytes(len, read, _):
				var count = (len + 15) >> 4;
				for( i in 0...count ) {
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
						vars.push(makeVar("" + i, value));
					} catch( e : Dynamic ) {
						vars.push({
							name : "" + i,
							value : Std.string(e),
							variablesReference : 0,
						});
					}
			case VMap(tkey, len, getKey, getValue, _):
				if( len > 0 ) getKey(len - 1); // fetch all
				for( i in 0...len ) {
					try {
						var key = getKey(i);
						var value = getValue(i);
						if( tkey == HDyn ) {
							vars.push({
								name : "" + i,
								value : "",
								variablesReference : allocValue(VMapPair(key,value)),
							});
						} else
							vars.push(makeVar(dbg.eval.valueStr(key), value));
					} catch( e : Dynamic ) {
						vars.push({
							name : "" + i,
							value : Std.string(e),
							variablesReference : 0,
						});
					}
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
				var v = dbg.getValue(cl+"."+f);
				if( v.t.match(HFun(_)) ) continue;
				vars.push(makeVar(f,v));
			}
		case VMapPair(key, value):
			vars.push(makeVar("key", key));
			vars.push(makeVar("value", value));
		case VUnkownFile(_):
			throw "assert";
		}
		sendResponse(response);
	}

	override function pauseRequest(response:PauseResponse, args:PauseArguments):Void {
		debug("Pause Request");
		handleMessage(dbg.pause());
		sendResponse(response);
	}

	override function disconnectRequest(response:DisconnectResponse, args:DisconnectArguments) {
		if( proc != null ) proc.kill("SIGINT");
		sendResponse(response);
		stopDebug();
	}

	override function nextRequest(response:NextResponse, args:NextArguments) {
		handleMessage(dbg.step(Next));
		sendResponse(response);
	}

	override function stepInRequest(response:StepInResponse, args:StepInArguments) {
		handleMessage(dbg.step(Into));
		sendResponse(response);
	}

	override function stepOutRequest(response:StepOutResponse, args:StepOutArguments) {
		handleMessage(dbg.step(Out));
		sendResponse(response);
	}

	override function continueRequest(response:ContinueResponse, args:ContinueArguments) {
		dbg.resume();
		sendResponse(response);
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

	override function evaluateRequest(response:EvaluateResponse, args:EvaluateArguments) {
		//debug("Eval " + args);
		dbg.currentStackFrame = args.frameId;
		try {
			// ?ident => hover on optional param (most likely)
			if( ~/^\?[A-Za-z0-9_]+$/.match(args.expression) )
				args.expression = args.expression.substr(1);
			var value = dbg.getValue(args.expression);
			var v = makeVar("", value);
			response.body = {
				result : v.value,
				type : v.type,
				variablesReference : v.variablesReference,
				namedVariables : v.namedVariables,
				indexedVariables : v.indexedVariables,
			};
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
			var v = dbg.setValue(args.name, args.value);
			if( v == null )
				throw "Can't set "+args.name+" to "+args.value;
			response.body = makeVar(args.name, v);
		} catch( e : Dynamic ) {
			errorMessage(""+e);
		}
		sendResponse(response);
	}

	override function setFunctionBreakPointsRequest(response:SetFunctionBreakpointsResponse, args:SetFunctionBreakpointsArguments) {
		debug("Unhandled request");
		sendResponse(response);
	}

	override function stepBackRequest(response:StepBackResponse, args:StepBackArguments) { debug("Unhandled request"); }
	override function restartFrameRequest(response:RestartFrameResponse, args:RestartFrameArguments) { debug("Unhandled request"); }
	override function gotoRequest(response:GotoResponse, args:GotoArguments) { debug("Unhandled request"); }
	override function stepInTargetsRequest(response:StepInTargetsResponse, args:StepInTargetsArguments) { debug("Unhandled request"); }
	override function gotoTargetsRequest(responses:GotoTargetsResponse, args:GotoTargetsArguments) { debug("Unhandled request"); }
	override function completionsRequest(response:CompletionsResponse, args:CompletionsArguments) { debug("Unhandled request"); }

	function sendToOutput(output:String, category:OutputEventCategory = OutputEventCategory.console) {
		sendEvent(new OutputEvent(output + "\n", category));
	}

	function errorMessage( msg : String ) {
		sendEvent(new OutputEvent(msg+"\n", stderr));
	}

	static function main() {
		DebugSession.run( HLAdapter );
	}

}

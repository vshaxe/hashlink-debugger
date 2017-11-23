import protocol.debug.Types;
import adapter.DebugSession;
import js.node.ChildProcess;
import js.node.Buffer;
import js.node.child_process.ChildProcess as ChildProcessObject;

class HLAdapter extends adapter.DebugSession {

    var proc : ChildProcessObject;
	var workspaceDirectory : String;
	var classPath : Array<String>;

	var debugPort = 6112;

    override function initializeRequest(response:InitializeResponse, args:InitializeRequestArguments) {

		haxe.Log.trace = function(v:Dynamic, ?p:haxe.PosInfos) {
			var str = haxe.Log.formatOutput(v, p);
			sendEvent(new OutputEvent("> " + str));
		};


        response.body.supportsConfigurationDoneRequest = true;
        response.body.supportsFunctionBreakpoints = false;
        response.body.supportsConditionalBreakpoints = false;
        response.body.supportsEvaluateForHovers = false;
        response.body.supportsStepBack = false;
        sendResponse( response );
    }

    override function launchRequest(response:LaunchResponse, args:LaunchRequestArguments) {
		workspaceDirectory = Reflect.field(args, "cwd");
		Sys.setCwd(workspaceDirectory);

		try {
			launch(cast args);
			sendEvent( new InitializedEvent() );
		} catch( e : Dynamic ) {
			sendEvent(new OutputEvent("ERROR : " + e, OutputEventCategory.stderr));
			sendEvent(new TerminatedEvent());
		}
		sendResponse(response);
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

	function launch( args : { cwd: String, hxml: String, ?args: Array<String> } ) {
		classPath = [];

		var hxContent = try sys.io.File.getContent(args.hxml) catch( e : Dynamic ) throw "Missing HXML file '"+args.hxml+"'";
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
		for( i in 0...classPath.length ) {
			var c = sys.FileSystem.fullPath(classPath[i]);
			c = c.split("\\").join("/");
			if( !StringTools.endsWith(c, "/") ) c += "/";
			classPath[i] = c;
		}

		if( program == null )
			throw args.hxml+" file does not contain -hl output";

        var hlArgs = ["--debug",""+debugPort,program];

        if( args.args != null ) hlArgs = hlArgs.concat(args.args);
        proc = ChildProcess.spawn("hl", hlArgs, {env: {}, cwd: args.cwd});

        proc.stdout.setEncoding('utf8');
		var prev = "";
        proc.stdout.on('data', function(buf) {
			prev += (buf:Buffer).toString();
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
        proc.on('close',function(code){
            var exitedEvent:ExitedEvent = {type:MessageType.event, event:"exited", seq:0, body : { exitCode:code}};
            sendEvent(exitedEvent);
            sendEvent(new TerminatedEvent());
        });
    }

    override function disconnectRequest(response:DisconnectResponse, args:DisconnectArguments) {
        proc.kill("SIGINT");
        sendResponse(response);
    }

    function sendToOutput(output:String, category:OutputEventCategory = OutputEventCategory.console) {
        sendEvent(new OutputEvent(output + "\n", category));
    }

    static function main() {
        DebugSession.run( HLAdapter );
    }

}

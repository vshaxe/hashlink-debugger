package;

import protocol.debug.Types;
import adapter.DebugSession;
import js.node.ChildProcess;
import js.node.child_process.ChildProcess as ChildProcessObject;
import js.node.Buffer;
import HLReader;

class HLAdapter extends adapter.DebugSession {

    var proc : ChildProcessObject;
    var dbgProc : ChildProcessObject;

    var buffer : Buffer;
    var waitingStackBuf : Array<StackTraceResponse>;
    var code : HLCode;
    var functionNames : Array<String>;

    public function new() {
        super();
        buffer = Buffer.alloc(0);
        waitingStackBuf = [];
    }

    override function initializeRequest(response:InitializeResponse, args:InitializeRequestArguments) {
        response.body.supportsConfigurationDoneRequest = true;
        response.body.supportsFunctionBreakpoints = false;
        response.body.supportsConditionalBreakpoints = false;
        response.body.supportsEvaluateForHovers = false;
        response.body.supportsStepBack = false;
        sendResponse( response );
    }

    override function launchRequest(response:LaunchResponse, args:LaunchRequestArguments) {
        var args:{cwd: String, program: String, ?args: Array<String>, ?port: Int} = cast args;
        var port : Int = args.port == null ? 5001 : args.port;
        var hlArgs = ["--debug",""+port,"--debug-wait",args.program];
        if( args.args != null )
            for( a in args.args ) hlArgs.push(a);

        proc = ChildProcess.spawn("hl", hlArgs, {env: {}, cwd: args.cwd});

        proc.stdout.setEncoding('utf8');
        proc.stdout.on('data', function(buf){
            sendEvent(new OutputEvent(buf.toString(), OutputEventCategory.stdout));
        } );
        proc.stderr.setEncoding('utf8');
        proc.stderr.on('data', function(buf){
            sendEvent(new OutputEvent(buf.toString(), OutputEventCategory.stderr));
        } );
        proc.on('close',onProcClose.bind(true));

        dbgProc = ChildProcess.spawn("hl",[js.Node.__dirname+"/debugger.hl","-attach",""+proc.pid,"-port",""+port,args.program]);
        dbgProc.stdout.on('data',onDebugData);
        dbgProc.on('close',onProcClose.bind(false));

        sendEvent( new InitializedEvent() );

        // Wait for breakpointsRequest before run
        js.Node.setTimeout(function(){
            send('run');
        },30);        

        /* 
        sock = new js.node.net.Socket();
        sock.connect(port,onConnect);
        sock.on('data',onSockData);

        var content = sys.io.File.getBytes(args.program);
        code = new HLReader(false).read( new haxe.io.BytesInput(content) );
        functionNames = [];
		for( t in code.types ){
			switch( t ){
				case HObj(obj):
					for( f in obj.fields ){
						switch( f.t ){
							case HFun(_):
								for( fun in code.functions )
									if( fun.t == f.t )
										functionNames[fun.findex] = obj.name+"."+f.name;
							case _:
						}
					}
					for( p in obj.proto )
						functionNames[p.findex] = obj.name+"."+p.name;
				case _:
			}
		}
        */

        sendResponse( response );
    }

    override function continueRequest(response:ContinueResponse, args:ContinueArguments) {
        /*
        send(Resume);
        response.body = {
            allThreadsContinued : true
        };
        sendResponse(response);
        */
    }

    override function pauseRequest(response:PauseResponse, args:PauseArguments) {
        /*
        send(Pause);
        sendResponse(response);
        sendEvent(new StoppedEvent(StopReason.pause, 1));
        */
    }

    override function threadsRequest(response:ThreadsResponse) {
        response.body = {
            threads: [new Thread(1, "thread 1")]
        };
        sendResponse(response);
    }

    override function stackTraceRequest(response:StackTraceResponse, args:StackTraceArguments) {
        send("backtrace");
        waitingStackBuf.push( response );
    }

    override function setBreakPointsRequest(response:SetBreakpointsResponse, args:SetBreakpointsArguments) {
        // TODO source.name or source.path?
        for( line in args.lines )
            send("break "+args.source.name+" "+line);
        sendResponse(response);
    }

    /*
    function onSockData(buf:Buffer){
        buffer = Buffer.concat([buffer,buf],buffer.length+buf.length);
        while( waitingStackBuf.length > 0  && buffer.length > 4 ){
            var size = buffer.readInt32LE(0);
            if( buffer.length < 4 + 8*size )
                break;
            var resp = waitingStackBuf.shift();
            resp.body = {
                totalFrames: size,
                stackFrames: []
            };
            var cur = 1; 
            for( i in 0...size ){
                var fidx = buffer.readInt32LE((cur++)*4);
                var fpos = buffer.readInt32LE((cur++)*4);
                var f = code.functions[fidx];
                var file = code.debugFiles[f.debug[fpos * 2]];
                var line = f.debug[fpos * 2 + 1];
                resp.body.stackFrames.push({
                    id: i,
                    line: line,
                    column: 1,
                    name: functionNames[f.findex],
                    source: {path: file}
                });
            }
            sendResponse(resp);
            buffer = buffer.slice(4+8*size);
        }
    }
    */

    override function disconnectRequest(response:DisconnectResponse, args:DisconnectArguments) {
        clean();
        sendResponse(response);
    }

    function onProcClose( isMain : Bool, code : Int ){
        if( isMain ){
            if( proc == null ) return;
            proc = null;
        }else{
            if( dbgProc == null ) return;
            dbgProc = null;
        }
        clean();
        var exitedEvent:ExitedEvent = {type:MessageType.event, event:"exited", seq:0, body : {exitCode:code}};
        sendEvent(exitedEvent);
        sendEvent(new TerminatedEvent());
    }

    function clean(){
        if( proc != null ){
            proc.kill("SIGINT");
            proc = null;
        }
        if( dbgProc != null ){
            dbgProc.kill("SIGINT");
            dbgProc = null;
        }
    }

/*
    function onConnect(){
        send(Run);
        sendEvent( new InitializedEvent() );
    }
    */


    function onDebugData(buf:Buffer){
        sendEvent(new OutputEvent(buf.toString(), OutputEventCategory.console));
    }


    function send( cmd : String ){
        dbgProc.stdin.write( cmd+"\n" );
    }

    function debug( v : Dynamic ){
        trace( v );
        sendEvent(new OutputEvent(Std.string(v), OutputEventCategory.console));
    }

    static function main() {
        DebugSession.run( HLAdapter );
    }

}

package;

import protocol.debug.Types;
import adapter.DebugSession;
import js.node.ChildProcess;
import js.node.child_process.ChildProcess as ChildProcessObject;
import js.node.net.Socket;
import js.node.Buffer;
import HLReader;

@:enum abstract Command(Int) {
	public var Run = 0;
	public var Pause = 1;
	public var Resume = 2;
	public var Stop = 3;
	public var Stack = 4;
	public inline function new(v:Int) {
		this = v;
	}
	public inline function toInt() : Int {
		return this;
	}
}

class HLAdapter extends adapter.DebugSession {

    var proc : ChildProcessObject; 
    var sock : Socket;
    var buffer : Buffer;
    var waitingStackBuf : Array<StackTraceResponse>;
    var code : HLCode;

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
        proc.on('close',function(code){
            var exitedEvent:ExitedEvent = {type:MessageType.event, event:"exited", seq:0, body : { exitCode:code}}; 
            sendEvent(exitedEvent);
            sendEvent(new TerminatedEvent());
        });

        sock = new js.node.net.Socket();
        sock.connect(port,onConnect);
        sock.on('data',onSockData);

        var content = sys.io.File.getBytes(args.program);
        code = new HLReader(false).read( new haxe.io.BytesInput(content) );

        sendResponse( response );
    }

    override function continueRequest(response:ContinueResponse, args:ContinueArguments) {
        sendEvent(new OutputEvent("continueRequest!", OutputEventCategory.console));
        send(Resume);
        response.body = {
            allThreadsContinued : true
        };
        sendResponse(response);
    }

    override function pauseRequest(response:PauseResponse, args:PauseArguments) {
        send(Pause);
        sendResponse(response);
        sendEvent(new StoppedEvent(StopReason.pause, 1));
    }

    override function threadsRequest(response:ThreadsResponse) {
        response.body = {
            threads: [new Thread(1, "thread 1")]
        };
        sendResponse(response);
    }

    override function stackTraceRequest(response:StackTraceResponse, args:StackTraceArguments) {
        send(Stack);
        waitingStackBuf.push( response );
    }

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
                    name: "#"+f.findex,
                    source: {path: file}
                });
            }
            sendResponse(resp);
            buffer = buffer.slice(4+8*size);
        }
    }

    override function disconnectRequest(response:DisconnectResponse, args:DisconnectArguments) {
        proc.kill("SIGINT");
        sendResponse(response);
    }

    function sendToOutput(output:String, category:OutputEventCategory = OutputEventCategory.console) {
        sendEvent(new OutputEvent(output + "\n", category));
    }

    function onConnect(){
        send(Run);
        sendEvent( new InitializedEvent() );
    }

    function send( cmd : Command ){
        sock.write( String.fromCharCode(cmd.toInt()) );
    }

    static function main() {
        DebugSession.run( HLAdapter );
    }

}

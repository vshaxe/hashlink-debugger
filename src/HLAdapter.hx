package;

import protocol.debug.Types;
import adapter.DebugSession;
import js.node.ChildProcess;
import js.node.child_process.ChildProcess as ChildProcessObject;
import js.node.Buffer;

class HLAdapter extends adapter.DebugSession {

    var launchArgs : {cwd: String, program: String, ?args: Array<String>, ?port: Int}; 
    var proc : ChildProcessObject;
    var dbgProc : ChildProcessObject;

    var buffer : Buffer;
    var waitingResp : Array<protocol.debug.Response<Dynamic>>;
    var breakpoints : Map<String,Array<Int>>;

    public function new() {
        super();
        buffer = Buffer.alloc(0);
        waitingResp = [];
        breakpoints = new Map();
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
        launchArgs = cast args;
        var port : Int = launchArgs.port == null ? 5001 : launchArgs.port;
        var hlArgs = ["--debug",""+port,"--debug-wait",launchArgs.program];
        if( launchArgs.args != null )
            for( a in launchArgs.args ) hlArgs.push(a);

        proc = ChildProcess.spawn("hl", hlArgs, {env: {}, cwd: launchArgs.cwd});

        proc.stdout.setEncoding('utf8');
        proc.stdout.on('data', function(buf){
            sendEvent(new OutputEvent(buf.toString(), OutputEventCategory.stdout));
        } );
        proc.stderr.setEncoding('utf8');
        proc.stderr.on('data', function(buf){
            sendEvent(new OutputEvent(buf.toString(), OutputEventCategory.stderr));
        } );
        proc.on('close',onProcClose.bind(true));

        dbgProc = ChildProcess.spawn("hl",[js.Node.__dirname+"/debugger.hl","-attach",""+proc.pid,"-port",""+port,launchArgs.program]);
        dbgProc.stdout.on('data',onDebugData);
        dbgProc.on('close',onProcClose.bind(false));

        sendEvent( new InitializedEvent() );

        sendResponse( response );
    }

    override function configurationDoneRequest(response:ConfigurationDoneResponse, args:ConfigurationDoneArguments){
        send('run');
        sendResponse(response);
    }

    override function continueRequest(response:ContinueResponse, args:ContinueArguments) {
        send("continue");
        response.body = {
            allThreadsContinued : true
        };
        sendResponse(response);
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
        waitingResp.push(response);
    }

    override function setBreakPointsRequest(response:SetBreakpointsResponse, args:SetBreakpointsArguments) {
        var existing = breakpoints.get(args.source.path);
        if( existing == null )
            breakpoints.set(args.source.path,existing=[]);
        var old = existing.copy();
        for( b in args.breakpoints ){
            if( old.remove(b.line) )
                continue;
            send("break "+args.source.name+" "+b.line);
            existing.push(b.line);
        }
        for( line in old ){
            send("clear "+args.source.name+" "+line);
            existing.remove(line);
        }
        sendResponse(response);
    }

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
            proc.kill("SIGTERM");
            proc = null;
        }
        if( dbgProc != null ){
            dbgProc.kill("SIGTERM");
            dbgProc = null;
        }
    }

    function onDebugData(buf:Buffer){
        buffer = buffer.length > 0 ? Buffer.concat([buffer,buf]) : buf;

        if( buffer.length >= 2 && buffer.toString('utf8',buffer.length-2,buffer.length) == '> ' ){
            if( buffer.length > 3 ){
                // removes last \n
                readData(buffer.toString('utf8',0,buffer.length-3));
            }
            buffer = new Buffer(0);
        }
    }

    function readData( d : String ){
        if( ~/^Breakpoint set/.match(d) ){
        }else if( ~/^No breakpoint set/.match(d) ){
        }else if( ~/^([0-9]+) breakpoints removed/.match(d) ){
        }else if( ~/^Thread ([0-9]+) paused/.match(d) ){
            sendEvent(new StoppedEvent(StopReason.breakpoint, 1)); // TODO threadId
        }else if( ~/^\*\*\* an error has occured, paused \*\*\*/.match(d) ){
            sendEvent(new StoppedEvent(StopReason.exception, 1)); // TODO threadId
        }else{
            // Should be backtrace
            var resp = waitingResp.shift();
            if( resp == null )
                return;
            switch( resp.command ){
            case "stackTrace":
                var lines = d.split("\n");
                resp.body = {
                    totalFrames: lines.length,
                    stackFrames: []
                };
                var idx = 0;
                for( l in lines ){
                    var p = l.lastIndexOf(':');
                    var n = l.substr(0,p);
                    resp.body.stackFrames.push({
                        id: idx,
                        line: Std.parseInt(l.substr(p+1)),
                        column: 1,
                        name: "??",
                        source: {
                            name: n,
                            path: launchArgs.cwd+"/"+n // TODO 
                        }
                    });
                    idx++;
                }
            }
            sendResponse(resp);
            
        }
    }

    function send( cmd : String ){
        dbgProc.stdin.write( cmd+"\n" );
    }

    function debug( v : Dynamic ){
        sendEvent(new OutputEvent(Std.string(v)+"\n", OutputEventCategory.console));
    }

    static function main() {
        DebugSession.run( HLAdapter );
    }

}

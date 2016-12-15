package;

import protocol.debug.Types;
import adapter.DebugSession;
import js.node.ChildProcess;
import js.node.child_process.ChildProcess as ChildProcessObject;

typedef LaunchArguments = {
    cwd: String,
    program: String,
    ?args: Array<String>,
    ?port: Int
};

class HLAdapter extends adapter.DebugSession {

    var launchArgs : LaunchArguments;
    var proc : ChildProcessObject;
    var dbg : HLDebugger;

    var breakpoints : Map<String,Array<Int>>;

    public function new() {
        super();
        breakpoints = new Map();
        haxe.Log.trace = function(v,?i){
            sendEvent(new OutputEvent(Std.string(v)+"\n", OutputEventCategory.console));
        }
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
        proc.on('close',function(code){
            proc = null;
            onClose( code );
        });

        dbg = new HLDebugger();
        dbg.attach( proc.pid, launchArgs.program, port, port+1, this);
        
        sendResponse( response );
    }

    override function configurationDoneRequest(response:ConfigurationDoneResponse, args:ConfigurationDoneArguments){
        dbg.send('run');
        sendResponse(response);
    }

    override function continueRequest(response:ContinueResponse, args:ContinueArguments) {
        dbg.send("continue");
        response.body = {
            allThreadsContinued : true
        };
        sendResponse(response);
    }

    override function pauseRequest(response:PauseResponse, args:PauseArguments) {
        dbg.send("pause");
        sendResponse(response);
    }

    override function threadsRequest(response:ThreadsResponse) {
        dbg.send("threads",function(r){
            if( r.result == Threads ){
                response.body = {
                    threads: []
                };
                for( t in r.data )
                    response.body.threads.push( new Thread(Std.parseInt(t), "thread "+t) );
            }else{
                response.success = false;
            }
            sendResponse(response);
        });
    }

    override function stackTraceRequest(response:StackTraceResponse, args:StackTraceArguments) {
        dbg.send("backtrace",function(r){
            var lines = r.data;
            response.body = {
                totalFrames: lines.length,
                stackFrames: []
            };
            var idx = 0;
            for( l in lines ){
                var p = l.lastIndexOf(':');
                var n = l.substr(0,p);
                response.body.stackFrames.push({
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
            sendResponse(response);
        });
    }

    override function scopesRequest(response:ScopesResponse, args:ScopesArguments) {
        dbg.send("frame "+args.frameId,function(r){
            response.body = {
                scopes: []
            };
            response.body.scopes.push(new Scope("test",0,false));
            sendResponse(response);
        });
    } 

    override function setBreakPointsRequest(response:SetBreakpointsResponse, args:SetBreakpointsArguments) {
        var existing = breakpoints.get(args.source.path);
        if( existing == null )
            breakpoints.set(args.source.path,existing=[]);
        var old = existing.copy();

        var waiting = 0;
        function btSend( cmd, ?onData : HLDebugger.Result -> Void ){
            waiting++;
            dbg.send(cmd,function(d){
                if( onData != null )
                    onData(d.result);
                waiting--;
                if( waiting == 0 )
                    sendResponse(response);
            });
        }

        response.body = {
            breakpoints: []
        };
        for( b in args.breakpoints ){
            if( old.remove(b.line) )
                continue;
            var b = b;
            btSend("break "+args.source.name+" "+b.line,function(r){
                if( r == Ok ){
                    response.body.breakpoints.push({
                        line: b.line,
                        verified: true
                    });
                }else{
                    trace('Error setting breakpoint on '+args.source.name+' line '+b.line);
                }
            });
            existing.push(b.line);
        }
        for( line in old ){
            btSend("unbreak "+args.source.name+" "+line,function(r){
                if( r != Ok )
                    trace( "Failed to remove breakpoint" );
            });
            existing.remove(line);
        }
    }

    override function disconnectRequest(response:DisconnectResponse, args:DisconnectArguments) {
        clean();
        sendResponse(response);
    }

    public function onClose( exitCode : Int ){
        var exitedEvent:ExitedEvent = {type:MessageType.event, event:"exited", seq:0, body : {exitCode:exitCode}};
        sendEvent(exitedEvent);
        sendEvent(new TerminatedEvent());
        clean();
    }

    function clean(){
        if( proc != null ){
            proc.removeAllListeners('close');
            proc.kill("SIGTERM");
            proc = null;
        }
        dbg.close();
    }

    static function main() {
        DebugSession.run( HLAdapter );
    }

}

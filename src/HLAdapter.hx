package;

import protocol.debug.Types;
import adapter.DebugSession;
import js.node.ChildProcess;
import js.node.stream.Readable.ReadableEvent;
import js.node.child_process.ChildProcess as ChildProcessObject;
import js.node.Buffer;

class HLAdapter extends adapter.DebugSession {

    var proc : ChildProcessObject; 

    public function new() {
        super();
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
        var args:{cwd: String, program: String} = cast args;

        proc = ChildProcess.spawn("hl", [args.program], {env: {}, cwd: args.cwd});

        var buffer = new Buffer(0);
        proc.stdout.setEncoding('utf8');
        proc.stdout.on('data', function(buf){
            var str = buf.toString();
            var lines = ~/\r?\n/g.split(str);
            for( i in 0...lines.length )
                sendEvent(new OutputEvent(lines[i]+"\n", OutputEventCategory.stdout));
        } );
        proc.stderr.setEncoding('utf8');
        proc.stderr.on('data', function(buf){
            var str = buf.toString();
            var lines = ~/\r?\n/g.split(str);
            for( i in 0...lines.length )
                sendEvent(new OutputEvent(lines[i]+"\n", OutputEventCategory.stderr));
        } );
        proc.on('close',function(code){
            var exitedEvent:ExitedEvent = {type:MessageType.event, event:"exited", seq:0, body : { exitCode:code}}; 
            sendEvent(exitedEvent);
            sendEvent(new TerminatedEvent());
        });

        sendEvent( new InitializedEvent() );

        sendResponse( response );
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

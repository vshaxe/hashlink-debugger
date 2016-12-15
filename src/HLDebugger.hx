
import js.node.ChildProcess;
import js.node.child_process.ChildProcess as ChildProcessObject;
import js.node.Buffer;
import js.node.net.Socket;
import protocol.debug.Types;
import adapter.DebugSession;

enum Result {
	Ok;
	Error;
	Exited;
	Paused;
    Breakpoint;
	Stdout;
	Stderr;
	ErrorOccured;
	Backtrace;
	Frame;
	Variable;
	UnknownVar;
    Threads;
}

typedef Response = {
    result: Result,
    ?data: Array<String>,
}

class HLDebugger {

    var proc : ChildProcessObject;
    var buffer : Buffer;
    var queue : Array<Response -> Void>;
    var sess : HLAdapter;
    var sock : Socket;
    var initDone = false;

    public function new(){
        buffer = Buffer.alloc(0);
        queue = [];
    }

    public function attach( pid : Int, program : String, port : Int, listen : Int, sess : HLAdapter ){
        this.sess = sess;
        proc = ChildProcess.spawn("hl",[js.Node.__dirname+"/debugger.hl","-attach",""+pid,"-port",""+port,"-listen",""+listen,program]);
        proc.stdout.on('data',function(data){
            trace('HL Debugger error: '+data);
        });
        proc.stderr.on('data',function(data){
            trace('HL Debugger error: '+data);
        });
        proc.on('close',onProcClose);

        sock = new js.node.net.Socket();
        sock.connect(listen,onInit);
        sock.on('data',onData);
        sock.on('close',onSockClose);
    }

    function onInit(){
        initDone = true;
        sess.sendEvent( new InitializedEvent() );
    }

    public function send( command : String, ?onResponse : Response->Void ){
        if( !initDone || proc == null || sock == null ) return;
        trace("send "+command);
        sock.write( command+"\n" );
        queue.push( onResponse );
    }

    function onResponse( r : Result, d : Array<String> ){
        if( sess == null )
            return;
        switch( r ){
            case Exited:
                // TODO
            case Paused:
                sess.sendEvent(new StoppedEvent(StopReason.pause, Std.parseInt(d[0])));
            case Breakpoint:
                sess.sendEvent(new StoppedEvent(StopReason.breakpoint, Std.parseInt(d[0])));
            case ErrorOccured:
                sess.sendEvent(new StoppedEvent(StopReason.exception, Std.parseInt(d[0])));
            case Stdout:
                sess.sendEvent(new OutputEvent(d[0], OutputEventCategory.stdout));
            case Stderr:
                sess.sendEvent(new OutputEvent(d[0], OutputEventCategory.stderr));
            default:
        }
    }

    function onData(buf:Buffer){
        buffer = buffer.length > 0 ? Buffer.concat([buffer,buf]) : buf;

        while( buffer.length >= 2 ){
            var r = buffer.readInt8(0);
            var na = buffer.readInt8(1);
            var p = 2;
            var d = [];
            var complete = true;
            for( i in 0...na ){
                if( buffer.length < p + 3 ){
                    complete = false;
                    break;
                }
                var l = buffer.readUInt16LE(p);
                p += 2;
                if( buffer.length < p + l ){
                    complete = false;
                    break;
                }
                d.push(buffer.toString("utf8",p,p+l));
                p += l;
            }
            if( !complete )
                return;
            var isCmdResp = (r&1) == 1;
            var res = Type.createEnumIndex(Result,r>>1);
            trace('isCmdResp=$isCmdResp res=$res data=$d');
            if( isCmdResp ){
                var cb = queue.shift();
                if( cb != null )
                    cb({result: res,data: d});
            }else{
                onResponse(res,d);
            }
            buffer = buffer.slice(p);
        }
    }


    public function close(){
        sess = null;
        if( proc != null )
            proc.kill("SIGTERM");
        proc = null;
        if( sock != null )
            sock.destroy();
        sock = null;
    }

    function onProcClose( code : Int ){
        proc = null;
        if( sess != null )
            sess.onClose( code );
        sess = null;
        if( sock != null )
            sock.destroy();
        sock = null;
    }

    function onSockClose(_){
        sock = null;
        if( sess != null )
            sess.onClose(-1);
        sess = null;
        if( proc != null )
            proc.kill("SIGTERM");
        proc = null;
    }

}
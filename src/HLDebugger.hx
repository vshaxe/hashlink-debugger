
import js.node.ChildProcess;
import js.node.child_process.ChildProcess as ChildProcessObject;
import js.node.Buffer;


class HLDebugger {

    var proc : ChildProcessObject;
    var buffer : Buffer;
    var queue : Array<String -> Void>;
    var sess : HLAdapter;

    public function new(){
        buffer = Buffer.alloc(0);
    }

    public function attach( pid : Int, program : String, port : Int, sess : HLAdapter, onInit : String->Void ){
        this.sess = sess;
        queue = [onInit];
        proc = ChildProcess.spawn("hl",[js.Node.__dirname+"/debugger.hl","-attach",""+pid,"-port",""+port,program]);
        proc.stdout.on('data',onData);
        proc.stderr.on('data',function(data){
            trace('HL Debugger error: '+data);
        });
        proc.on('close',onClose);
    }

    public function close(){
        sess = null;
        if( proc != null )
            proc.kill("SIGTERM");
        proc = null;
    }

    public function send( command : String, ?onResponse : String->Void ){
        if( proc == null ) return;
        trace('send: $command ($onResponse)');
        proc.stdin.write( command+"\n" );
        queue.push( onResponse );
    }

    function onData(buf:Buffer){
        buffer = buffer.length > 0 ? Buffer.concat([buffer,buf]) : buf;

        if( buffer.length >= 2 && buffer.toString('utf8',buffer.length-2,buffer.length) == '> ' ){
            for( m in buffer.toString('utf8',0,buffer.length-2).split("\n> ") ){
                var cb = queue.shift();
                if( cb != null ) 
                    cb( m );
            }
            buffer = new Buffer(0);
        }
    }

    function onClose( code : Int ){
        proc = null;
        if( sess != null )
            sess.onClose( code );
        sess = null;
    }

}
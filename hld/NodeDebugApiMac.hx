package hld;
import hld.Api;
import hld.NodeFFI;
import hld.NodeFFI.makeDecl in FDecl;


class NodeDebugApiMac implements Api {

	var pid : Int;
	var tmp : Buffer;
	var tmpByte : Buffer;
	var is64 : Bool;
	var isNode64 : Bool;

	var libdebug : {
		function hl_debug_start(pid:Int):Bool;
		function hl_debug_stop(pid:Int):Void;
		function hl_debug_breakpoint(pid:Int):Bool;
		function hl_debug_read(pid:Int,ptr:CValue,buffer:Buffer,size:Int):Bool;
		function hl_debug_write(pid:Int,ptr:CValue,buffer:Buffer,size:Int):Bool;
		function hl_debug_flush(pid:Int,ptr:CValue,size:Int):Bool;
		function hl_debug_wait(pid:Int,threadId:Buffer,timeout:Int):Int;
		function hl_debug_resume(pid:Int,tid:Int):Bool;
		function hl_debug_read_register(pid:Int,tid:Int,register:Int,is64:Bool):CValue;
		function hl_debug_write_register(pid:Int,tid:Int,register:Int,v:CValue,is64:Bool):Bool;
	};

	public function new( pid : Int, is64 : Bool ) {
		this.pid = pid;
		this.is64 = is64;
		this.isNode64 = (untyped process.arch) == 'x64';

		if( !isNode64 || !is64 )
			throw "Can't debug when HL or Node is 32 bit";

		tmp = new Buffer(8);
		tmpByte = new Buffer(4);

		libdebug = NodeFFI.Library("/usr/local/lib/libhldebug",{
			hl_debug_start : FDecl(bool, [int]),
			hl_debug_stop : FDecl(bool, [int]),
			hl_debug_breakpoint : FDecl(bool, [int]),
			hl_debug_read : FDecl(bool, [int,pointer,pointer,int]),
			hl_debug_write : FDecl(bool, [int,pointer,pointer,int]),
			hl_debug_flush : FDecl(bool, [int,pointer,int]),
			hl_debug_wait : FDecl(int, [int,pointer,int]),
			hl_debug_resume : FDecl(bool, [int,int]),
			hl_debug_read_register : FDecl(pointer, [int,int,int,bool]),
			hl_debug_write_register : FDecl(bool, [int,int,int,pointer,bool])
		});
	}

	public function start() : Bool {
		return libdebug.hl_debug_start(pid);
	}

	public function stop() {
		return libdebug.hl_debug_stop(pid);
	}

	public function breakpoint() {
		throw "BREAK";
		return false;
	}

	function makePointer( ptr : Pointer ) : CValue {
		tmp.setI32(0, ptr.i64.low);
		tmp.setI32(4, ptr.i64.high);
		return Ref.readPointer(tmp, 0);
	}

	function intPtr( i : Int ) : CValue {
		return makePointer(Pointer.ofPtr(i));
	}

	public function read( ptr : Pointer, buffer : Buffer, size : Int ) : Bool {
		return libdebug.hl_debug_read(pid, makePointer(ptr), buffer, size);
	}

	public function readByte( ptr : Pointer, pos : Int ) : Int {
		if( !read(ptr.offset(pos), tmpByte, 1) )
			throw "Failed to read process memory";
		return tmpByte.getUI8(0);
	}

	public function write( ptr : Pointer, buffer : Buffer, size : Int ) : Bool {
		return libdebug.hl_debug_write(pid, makePointer(ptr), buffer, size);
	}

	public function writeByte( ptr : Pointer, pos : Int, value : Int ) : Void {
		tmpByte.setI32(0, value);
		if( !write(ptr.offset(pos), tmpByte, 1) )
			throw "Failed to write process memory";
	}

	public function flush( ptr : Pointer, size : Int ) : Bool {
		return true;
	}

	public function wait( timeout : Int ) : { r : WaitResult, tid : Int } {
		var kind : WaitResult = libdebug.hl_debug_wait(pid, tmp, timeout);
		var tid = tmp.getI32(0);
		return { r : kind, tid : tid };
	}

	public function resume( tid : Int ) : Bool {
		return libdebug.hl_debug_resume(pid, tid);
	}

	public function readRegister( tid : Int, register : Register ) : Pointer {
		var v = libdebug.hl_debug_read_register(pid, tid, register, true);
		var a = v.ref();
		return Pointer.make(a.readInt32LE(0), a.readInt32LE(4));
	}

	public function writeRegister( tid : Int, register : Register, v : Pointer ) : Bool {
		return libdebug.hl_debug_write_register(pid, tid, register, makePointer(v), true);
	}

}
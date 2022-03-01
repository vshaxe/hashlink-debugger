package hld;
import hld.Api;
import hld.NodeFFI;

@:jsRequire("hldebug")
extern class Native {
	static function echo( n : String, len : Int ) : String;
	static function debugStart( pid : Int ) : Bool;
	static function debugStop( pid : Int ) : Void;
	static function debugBreakpoint( pid : Int ) : Bool;
	static function debugRead( pid : Int, ptr : String, size : Int ) : String;
	static function debugWrite( pid : Int, ptr : String, buffer : String, size : Int ) : Bool;
	static function debugFlush( pid : Int, ptr : String, size : Int ) : Bool;
	static function debugWait( pid : Int, timeout : Int ) : js.node.Buffer;
	static function debugResume( pid : Int, tid : Int ) : Bool;
	static function debugReadRegister( pid : Int, tid : Int, register : Register, is64 : Bool ) : String;
	static function debugWriteRegister( pid : Int, tid : Int, register : Register, v : String, is64 : Bool ) : Bool;
}

class NodeDebugApiNative implements Api {
	var pid : Int;
	var tmp : Buffer;
	var tmpByte : Buffer;
	var is64 : Bool;

	public function new( pid : Int, is64 : Bool ) {
		/*if( is64 && untyped(js.Node).arch != "x64" )
			throw "You can't debug a 64 bit process from a 32 bit nodejs";*/
		this.pid = pid;
		this.is64 = is64;
		tmp = new Buffer(8);
		tmpByte = new Buffer(4);
	}

	function makePointer( ptr : Pointer ) : hld.Buffer {
		tmp.setI32(0, ptr.i64.low);
		tmp.setI32(4, ptr.i64.high);
		return tmp;
	}

	public function start() {
		return Native.debugStart(pid);
	}

	public function stop() {
		Native.debugStop(pid);
	}

	public function breakpoint() {
		return Native.debugBreakpoint(pid);
	}

	public function read( ptr : Pointer, buffer : Buffer, size : Int ) : Bool {
		var b = Buffer.fromBinaryString(Native.debugRead(pid, makePointer(ptr).toBinaryString(), size));
		@:privateAccess buffer.buf = b.buf;
		return true;
	}

	function internalRead( ptr : Pointer, size : Int ) : Buffer {
		return Buffer.fromBinaryString(Native.debugRead(pid, makePointer(ptr).toBinaryString(), size));
	}

	public function readByte( ptr : Pointer, pos : Int ) : Int {
		var b = internalRead(ptr.offset(pos), 1);
		return b.getUI8(0);
	}

	public function write( ptr : Pointer, buffer : Buffer, size : Int ) : Bool {
		return Native.debugWrite(pid, makePointer(ptr).toBinaryString(), buffer.toBinaryString(), size);
	}

	public function writeByte( ptr : Pointer, pos : Int, value : Int ) : Void {
		tmpByte.setUI8(0, value & 0xFF);
		if( !write(ptr.offset(pos), tmpByte, 1) )
			throw "Failed to write @" + ptr.toString();
	}

	public function flush( ptr : Pointer, size : Int ) : Bool {
		return Native.debugFlush(pid, makePointer(ptr).toBinaryString(), size);
	}

	public function wait( timeout : Int ) : { r : WaitResult, tid : Int } {
		var buf = Native.debugWait(pid, timeout);
		var r = buf.readInt32LE(0);
		var tid = buf.readInt32LE(4);
		return { r: cast r, tid: tid };
	}

	public function resume( tid : Int ) : Bool {
		return Native.debugResume(pid, tid);
	}

	public function readRegister( tid : Int, register : Register ) : Pointer {
		var buf = Buffer.fromBinaryString(Native.debugReadRegister(pid, tid, register, is64));
		if(buf == null)
			return null;
		if( register == EFlags )
			return Pointer.make(buf.getUI16(0), 0);
		if( !is64 )
			return Pointer.make(buf.getI32(0), 0);
		return Pointer.make(buf.getI32(0), buf.getI32(4));
	}

	public function writeRegister( tid : Int, register : Register, v : Pointer ) : Bool {
		return Native.debugWriteRegister(pid, tid, register, makePointer(v).toBinaryString(), is64);
	}
}

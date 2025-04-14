package hld;

private enum DebugFlag {
	Is64; // runs in 64 bit mode
	Bool4; // bool = 4 bytes (instead of 1)
	Threads; // was compiled with threads support
	IsWinCall;
}

class JitInfo {

	public var is64(default, null) : Bool;
	public var isWinCall(default, null) : Bool;
	public var align(default,null) : Align;
	public var hasThreads(get,never) : Bool;
	public var pid(default,null) : Int = 0;

	var flags : haxe.EnumFlags<DebugFlag>;
	var input : haxe.io.Input;

	public var oldThreadInfos : { id : Int, stackTop : Pointer, debugExc : Pointer };

	public var hlVersion : Float;
	public var globals : Pointer;
	var codeStart : Pointer;
	var codeEnd : Pointer;
	public var threads : Pointer;
	var codeSize : Int;
	var allTypes : Pointer;

	var functions : Array<{ start : Pointer, large : Bool, offsets : haxe.io.Bytes }>;
	var functionByCodePos : Int64Map<Int>;
	var module : Module;

	public function new() {
	}

	function get_hasThreads() {
		return oldThreadInfos != null || flags.has(Threads);
	}

	private function readPointer() : Pointer {
		if( is64 )
			return Pointer.make(input.readInt32(), input.readInt32());
		return Pointer.make(input.readInt32(),0);
	}

	public function read( input : haxe.io.Input, module : Module ) {
		this.input = input;
		this.module = module;

		if( input.readString(3) != "HLD" )
			return false;
		var version = input.readByte() - "0".code;
		if( version > 1 )
			return false;
		flags = haxe.EnumFlags.ofInt(input.readInt32());
		is64 = flags.has(Is64);
		align = new Align(is64, flags.has(Bool4)?4:1);
		isWinCall = flags.has(IsWinCall) || Sys.systemName() == "Windows" /* todo : disable this for cross platform remote debug */;

		if( version == 0 ) {
			var mainThread = input.readInt32();
			globals = readPointer();
			var debugExc = readPointer();
			var stackTop = readPointer();
			oldThreadInfos = { id : mainThread, stackTop : stackTop, debugExc : debugExc };
			hlVersion = 1.05;
		} else {
			var ver = input.readInt32();
			hlVersion = (ver >> 16) + ((ver >> 8) & 0xFF) / 100;
			if( hlVersion >= 1.07 )
				pid = input.readInt32();
			threads = readPointer();
			globals = readPointer();
		}
		codeStart = readPointer();
		codeSize = input.readInt32();
		codeEnd = codeStart.offset(codeSize);
		allTypes = readPointer();
		functions = [];

		var structSizes = [0];
		for( i in 1...9 )
			structSizes[i] = input.readInt32();
		@:privateAccess align.structSizes = structSizes;

		var nfunctions = input.readInt32();
		if( nfunctions != module.code.functions.length )
			return false;

		functionByCodePos = new Int64Map();
		for( i in 0...nfunctions ) {
			var nops = input.readInt32();
			if( module.code.functions[i].debug.length >> 1 != nops )
				return false;
			var start = codeStart.offset(input.readInt32());
			var large = input.readByte() != 0;
			var offsets = input.read((nops + 1) * (large ? 4 : 2));
			functionByCodePos.set(start.i64, i);
			functions.push({
				start : start,
				large : large,
				offsets : offsets,
			});
		}
		return true;
	}

	public function getFunctionPos( fidx : Int ) : Pointer {
		return functions[fidx].start;
	}

	public function getCodePos( fidx : Int, pos : Int ) : Pointer {
		var dbg = functions[fidx];
		return dbg.start.offset(dbg.large ? dbg.offsets.getInt32(pos << 2) : dbg.offsets.getUInt16(pos << 1));
	}

	public function isCodePtr( codePtr : Pointer ) : Bool {
		if( codePtr < codeStart || codePtr > codeEnd )
			return false;
		return true;
	}

	public function codePtrToString( codePtr : Pointer ) : String {
		if( codePtr < codeStart || codePtr > codeEnd )
			return '$codePtr';
		return '$codePtr(${codePtr.sub(codeStart)})';
	}

	public function resolveAsmPos( codePtr : Pointer ) : Null<Debugger.StackRawInfo> {
		if( !isCodePtr(codePtr) )
			return null;
		var min = 0;
		var max = functions.length;
		while( min < max ) {
			var mid = (min + max) >> 1;
			var p = functions[mid];
			if( p.start <= codePtr )
				min = mid + 1;
			else
				max = mid;
		}
		if( min == 0 )
			return null;
		var fidx = (min - 1);
		var dbg = functions[fidx];
		var fdebug = module.code.functions[fidx];
		min = 0;
		max = fdebug.debug.length>>1;
		var relPos = codePtr.sub(dbg.start);
		while( min < max ) {
			var mid = (min + max) >> 1;
			var offset = dbg.large ? dbg.offsets.getInt32(mid * 4) : dbg.offsets.getUInt16(mid * 2);
			if( offset <= relPos )
				min = mid + 1;
			else
				max = mid;
		}
		return { fidx : fidx, fpos : min - 1, codePos : codePtr, ebp : null };
	}

	public function functionFromAddr( p : Pointer ) {
		return functionByCodePos.get(p.i64);
	}

}

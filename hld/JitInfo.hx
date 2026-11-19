package hld;

private enum DebugFlag {
	Is64; // runs in 64 bit mode
	Bool4; // bool = 4 bytes (instead of 1)
	Threads; // was compiled with threads support
	IsWinCall;
	TypesArray;
	Modules; // per module build id, bytecode and globals, command socket
}

typedef JitFunction = {
	var start : Pointer;
	var large : Bool;
	var offsets : haxe.io.Bytes;
	var ?vars : haxe.io.Bytes;
	var mod : JitModule;
}

class JitModule {
	public var index : Int;
	public var base : Int;
	public var globals : Pointer;
	public var codeStart : Pointer;
	public var codeEnd : Pointer;
	public var codeSize : Int;
	public var types : Pointer;
	public var functions : Array<JitFunction>;
	public var buildId : haxe.io.Bytes;
	public var rawPtr : Pointer;
	public var rawSize : Int = 0;
	public var globalsOffsets : Array<Int>;
	public var module : Module;
	public function new() {
	}
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

	public var trampoline(default,null) : Null<{ marker : Pointer, regsOffset : Int, rbpOffset : Int, callOffset : Int, regs : Array<Eval.NativeReg> }>;
	var trampolinePos : Int = -1;

	public var hlVersion : Float;
	public var globals : Pointer;
	public var threads : Pointer;
	public var registry(default, null) : Pointer;
	public var modules(default, null) : Array<JitModule> = [];
	public var lastModule(get, never) : Module;

	var functions : Array<JitFunction> = [];
	var functionByCodePos : Int64Map<Int> = new Int64Map();
	var protoOwners : haxe.ds.ObjectMap<Dynamic, Module> = new haxe.ds.ObjectMap();

	public function new() {
	}

	public function hasTypesArray() {
		return flags.has(TypesArray);
	}

	public function hasModulesInfos() {
		return flags.has(Modules);
	}

	function get_hasThreads() {
		return oldThreadInfos != null || flags.has(Threads);
	}

	function get_lastModule() {
		return modules[modules.length - 1].module;
	}

	private function readPointer() : Pointer {
		if( is64 )
			return Pointer.make(input.readInt32(), input.readInt32());
		return Pointer.make(input.readInt32(),0);
	}

	function readStructSizes() {
		var structSizes = [0];
		for( i in 1...9 )
			structSizes[i] = input.readInt32();
		for( i in 9...HGUID.getIndex() + 1 )
			structSizes[i] = structSizes[HBytes.getIndex()];
		structSizes[HGUID.getIndex()] = structSizes[HI64.getIndex()];
		@:privateAccess align.structSizes = structSizes;
	}

	public function read( input : haxe.io.Input ) : Array<JitModule> {
		this.input = input;

		if( input.readString(3) != "HLD" )
			return null;
		var version = input.readByte() - "0".code;
		if( version <= 0 || version > 2 )
			return null;
		flags = haxe.EnumFlags.ofInt(input.readInt32());
		is64 = flags.has(Is64);
		align = new Align(is64, flags.has(Bool4)?4:1);
		isWinCall = flags.has(IsWinCall) || Sys.systemName() == "Windows" /* todo : disable this for cross platform remote debug */;

		var ver = input.readInt32();
		hlVersion = (ver >> 16) + ((ver >> 8) & 0xFF) / 100;
		if( hlVersion >= 1.07 )
			pid = input.readInt32();
		threads = readPointer();

		var mods = [];
		if( version == 1 ) {
			var m = new JitModule();
			m.globals = readPointer();
			m.codeStart = readPointer();
			m.codeSize = input.readInt32();
			m.types = readPointer();
			readStructSizes();
			readFunctions(m);
			mods.push(m);
		} else {
			readStructSizes();
			trampolinePos = input.readInt32();
			var nmodules = input.readInt32();
			if( nmodules != 1 && !flags.has(Modules) )
				return null;
			for( i in 0...nmodules )
				mods.push(readModule());
			if( flags.has(Modules) ) {
				for( m in mods )
					readModuleExtra(m);
				registry = readPointer();
			}
		}
		for( i in 0...mods.length )
			mods[i].index = i;
		return mods;
	}

	function readModule() {
		var m = new JitModule();
		m.globals = readPointer();
		m.codeStart = readPointer();
		m.codeSize = input.readInt32();
		m.types = readPointer();
		readFunctions(m);
		return m;
	}

	function readFunctions( m : JitModule ) {
		var nfunctions = input.readInt32();
		m.functions = [];
		m.codeEnd = m.codeStart.offset(m.codeSize);
		for( i in 0...nfunctions ) {
			var nops = input.readInt32();
			var start = m.codeStart.offset(input.readInt32());
			var varsSize = hlVersion >= 2 ? input.readInt32() : 0;
			var large = input.readByte() != 0;
			var offsets = input.read((nops + 1) * (large ? 4 : 2));
			var vars = hlVersion >= 2 ? input.read(varsSize) : null;
			m.functions.push({
				start : start,
				large : large,
				offsets : nops == 0 ? null : offsets,
				vars : vars,
				mod : m,
			});
		}
	}

	function readModuleExtra( m : JitModule ) {
		m.buildId = input.read(16);
		m.rawPtr = readPointer();
		m.rawSize = input.readInt32();
		var nglobals = input.readInt32();
		m.globalsOffsets = [for( i in 0...nglobals ) input.readInt32()];
	}

	public function readModuleData( data : haxe.io.Bytes, index : Int ) {
		input = new haxe.io.BytesInput(data);
		var m = readModule();
		m.index = index;
		readModuleExtra(m);
		return m;
	}

	public function addModule( m : JitModule, module : Module ) {
		var code = module.code;
		if( m.functions.length != code.functions.length )
			return false;
		for( i in 0...m.functions.length ) {
			var f = m.functions[i];
			if( f.offsets != null && code.functions[i].debug.length >> 1 != (f.offsets.length >> (f.large ? 2 : 1)) - 1 )
				return false;
		}
		m.module = module;
		m.base = functions.length;
		module.base = m.base;
		if( m.globalsOffsets != null )
			module.setGlobalsOffsets(m.globalsOffsets);
		if( globals == null )
			globals = m.globals;
		for( i in 0...m.functions.length ) {
			var f = m.functions[i];
			functions.push(f);
			if( f.offsets != null )
				functionByCodePos.set(f.start.i64, m.base + i);
		}
		for( t in code.types )
			switch( t ) {
			case HObj(o), HStruct(o): protoOwners.set(o, module);
			case HEnum(e): protoOwners.set(e, module);
			default:
			}
		modules.push(m);
		if( modules.length == 1 && trampolinePos >= 0 )
			trampoline = makeTrampoline(m.codeStart.offset(trampolinePos));
		return true;
	}

	static inline var TRAMPOLINE_STACK_ARGS = 32;

	function makeTrampoline( marker : Pointer ) {
		var regs : Array<Eval.NativeReg> = isWinCall ? [Esi, Edi, Ebx, R12, R13, R14, R15] : [Ebx, R12, R13, R14, R15];
		if( isWinCall )
			for( i in 6...16 ) regs.push(Eval.NativeReg.XMM(i));
		var regsSize = regs.length * align.ptr;
		if( regsSize & 15 != 0 ) regsSize += 16 - (regsSize & 15);
		var regsOffset = align.ptr + (isWinCall ? 0x20 : 0) + TRAMPOLINE_STACK_ARGS;
		return {
			marker : marker,
			regsOffset : regsOffset,
			rbpOffset : regsOffset + regsSize,
			callOffset : regsOffset + regsSize + align.ptr,
			regs : regs,
		};
	}

	public function getModule( fidx : Int ) : Module {
		var f = functions[fidx];
		return f == null ? lastModule : f.mod.module;
	}

	public function getProtoModule( p : Dynamic ) : Module {
		var m = protoOwners.get(p);
		return m == null ? lastModule : m;
	}

	public function hasCode( fidx : Int ) {
		var f = functions[fidx];
		return f != null && f.offsets != null;
	}

	public function getFunctionVars( fidx : Int ) {
		return functions[fidx].vars;
	}

	public function getFunctionPos( fidx : Int ) : Pointer {
		return functions[fidx].start;
	}

	public function getCodePos( fidx : Int, pos : Int ) : Pointer {
		var dbg = functions[fidx];
		return dbg.start.offset(dbg.large ? dbg.offsets.getInt32(pos << 2) : dbg.offsets.getUInt16(pos << 1));
	}

	function getCodeModule( codePtr : Pointer ) : JitModule {
		for( m in modules )
			if( codePtr >= m.codeStart && codePtr <= m.codeEnd )
				return m;
		return null;
	}

	public function isCodePtr( codePtr : Pointer ) : Bool {
		return getCodeModule(codePtr) != null;
	}

	public function getNativeCodePos( codePtr : Pointer ) {
		var m = getCodeModule(codePtr);
		return codePtr.sub((m == null ? modules[0] : m).codeStart);
	}

	public function codePtrToString( codePtr : Pointer ) : String {
		var m = getCodeModule(codePtr);
		if( m == null )
			return '$codePtr';
		return '$codePtr(${m.index}:${codePtr.sub(m.codeStart)})';
	}

	public function resolveAsmPos( codePtr : Pointer ) : Null<Debugger.StackRawInfo> {
		var m = getCodeModule(codePtr);
		if( m == null )
			return null;
		var min = 0;
		var max = m.functions.length;
		while( min < max ) {
			var mid = (min + max) >> 1;
			var p = m.functions[mid];
			if( p.start <= codePtr )
				min = mid + 1;
			else
				max = mid;
		}
		while( min > 0 && m.functions[min - 1].offsets == null )
			min--;
		if( min == 0 )
			return null;
		var fidx = (min - 1);
		var dbg = m.functions[fidx];
		var fdebug = m.module.code.functions[fidx];
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
		return { fidx : m.base + fidx, fpos : min - 1, codePos : codePtr, ebp : null };
	}

	public function functionFromAddr( p : Pointer ) {
		return functionByCodePos.get(p.i64);
	}

}

package hld;
import hld.Value;

enum abstract NativeReg(Int) from Int {
	var Eax = 0;
	var Ecx = 1;
	var Edx = 2;
	var Ebx = 3;
	var Esp = 4;
	var Ebp = 5;
	var Esi = 6;
	var Edi = 7;
	var R8 = 8;
	var R9 = 9;
	var R10	= 10;
	var R11	= 11;
	var R12	= 12;
	var R13	= 13;
	var R14	= 14;
	var R15	= 15;
	public static function XMM(v:Int) return v + 16;
	public inline function toInt() return this;
	public inline function isFpu() return this >= 16;
	public inline function is64() return this >= 8 && this < 16;
}

enum VarAddress {
	ANone;
	AUndef( t : HLType );
	AAddr( ptr : Pointer, t : HLType );
	AMethod( v : Value, ptr : Pointer, t : HLType );
	AEvaled( v : Value );
	AInlined( fields : Array<InlinedField> );
}

class Eval {

	var align : Align;
	var api : Api;
	var jit : JitInfo;
	var module : Module;
	var sizeofVArray : Int;
	var parser : hscript.Parser;

	var t_string : HLType;

	var funIndex : Int;
	var codePos : Int;
	var ebp : Pointer;

	public var maxArrLength : Int = 10;
	public var maxBytesLength : Int = 128;
	public var globalContext = false;
	public var currentThread : Int;
	public var allowEvalGetters = true;

	static var HASH_PREFIX = "$_h$";

	public function new(module,api,jit) {
		this.module = module;
		this.api = api;
		this.jit = jit;
		this.align = jit.align;
		parser = new hscript.Parser();
		parser.identChars += "$";
		sizeofVArray = align.ptr * 2 + align.typeSize(HI32) * 2;
		for( t in module.code.types )
			switch( t ) {
			case HObj(o):
				switch( o.name ) {
				case "String":
					t_string = t;
				default:
				}
			default:
			}
	}

	public function setContext( funIndex : Int, codePos : Int, ebp : Pointer ) {
		this.funIndex = funIndex;
		this.codePos = codePos;
		this.ebp = ebp;
	}

	public function eval( expr : String ) : Value {
		if( expr == null || expr == "" )
			return null;
		var exprs = expr.split(":");
		var hint = HNone;
		if( exprs.length > 1 ) {
			hint = Value.parseHint(exprs.pop()); // content after the last ":" is considered as a display hint
			expr = exprs.join(":");
		}
		var expr = try parser.parseString(expr) catch( e : hscript.Expr.Error ) throw hscript.Printer.errorToString(e);
		var v = evalExpr(expr);
		v.hint = hint;
		return v;
	}

	public function setValue( expr : String, value : String ) {
		var v = eval(value);
		if( v == null ) return null;
		setPtr(ref(expr),v);
		return v;
	}

	public function setPtr( ref : { ptr : Pointer, t : HLType }, value : Value ) : Void {
		if( ref.ptr.isNull() )
			throw "Can't set null ptr";
		value = castTo(value, ref.t);
		switch( [ref.t, value.v] ) {
		case [HI32, VInt(i)]:
			writeI32(ref.ptr, i);
		case [HBool, VBool(flag)]:
			var b = new Buffer(1);
			b.setUI8(0, flag ? 1 : 0);
			writeMem(ref.ptr, b, 1);
		case [HF64,VInt(i)]:
			writeF64(ref.ptr, i);
		case [HF64,VFloat(f)]:
			writeF64(ref.ptr, f);
		default:
			if( ref.t.isPtr() ) {
				var ptr = getPtr(value);
				if( ptr != null || value.v == VNull ) {
					writePointer(ref.ptr, ptr);
					return;
				}
			}
			throw "Don't know how to set "+ref.t.toString();
		}
	}

	function getPtr( v : Value ) {
		return switch (v.v) {
		case VNull: Pointer.make(0,0);
		case VPointer(p), VString(_, p), VClosure(_,_,p), VArray(_, _, _, p), VMap(_, _, _, _, p), VEnum(_, _, p), VBytes(_,_,p): p;
		default: null;
		}
	}

	function castTo( v : Value, t : HLType ) {
		if( v == null )
			return null;
		if( safeCastTo(v.t, t) )
			return v;
		switch( [v.v, t] ) {
		case [VInt(i), HF64|HF32]:
			return { v : VFloat(i), t : t };
		case [VNull, _] if( t.isPtr() ):
			return { v : VNull, t : t };
		default:
		}
		throw "Don't know how to cast "+v.t.toString()+" to "+t.toString();
	}

	function safeCastTo( t : HLType, to : HLType ) {
		if( t == to )
			return true;
		if( to == HDyn )
			return t.isDynamic();
		switch( [t,to] ) {
		case [HObj(p), HObj(_)], [HStruct(p), HStruct(_)] if( p.tsuper != null ):
			return safeCastTo(p.tsuper, to);
		default:
		}
		return false;
	}

	public function ref( exprSrc : String ) : Debugger.Address {
		if( exprSrc == null || exprSrc == "" )
			return null;
		var expr = try parser.parseString(exprSrc) catch( e : hscript.Expr.Error ) throw hscript.Printer.errorToString(e);
		var addr = switch( expr ) {
		case EField(obj, f):
			var v = evalExpr(obj);
			readFieldAddress(v, f);
		case EIdent(i):
			getVarAddress(i);
		default:
			throw "Can't get ref for " + hscript.Printer.toString(expr);
		}
		switch( addr ) {
		case AAddr(ptr, t):
			return { ptr : ptr, t : t };
		default:
			throw "Can't reference " + exprSrc;
		}
	}

	function getClosureStack( v : ValueRepr ) : Array<Pointer> {
		switch( v ) {
		case VClosure(_, context, p) if( align.is64 && context != null ):
			var stackCount = readI32(p.offset(20));
			return [for( i in 0...stackCount ) readPointer(p.offset(32 + i * 8))];
		default:
		}
		return [];
	}

	function evalExpr( e : hscript.Expr ) : Value {
		switch( e ) {
		case EConst(c):
			switch( c ) {
			case CInt(v):
				return { v : VInt(v), t : HI32 };
			case CFloat(f):
				return { v : VFloat(f), t : HF64 };
			case CString(s):
				return { v : VString(s, null), t : t_string };
			}
		case EIdent(i):
			var v = getVar(i);
			if( v == null ) throw "Unknown identifier "+i;
			return v;
		case EArray(v, i):
			var v = evalExpr(v);
			var i = evalExpr(i);
			switch( v.v ) {
			case VArray(t, len, read, _):
				var i = toInt(i);
				return i < 0 || i >= len ? defVal(t) : read(i);
			default:
			}
			throw "Can't access " + valueStr(v) + "[" + valueStr(i) + "]";
		case EArrayDecl(vl):
			var vl = [for( v in vl ) evalExpr(v)];
			return { v : VArray(HDyn, vl.length, function(i) return vl[i], null), t : HDyn };
		case EBinop(op, e1, e2):
			switch( op ) {
			case "&&":
				return mkBool(toBool(evalExpr(e1)) && toBool(evalExpr(e2)));
			case "||":
				return mkBool(toBool(evalExpr(e1)) || toBool(evalExpr(e2)));
			default:
				return evalBinop(op, evalExpr(e1), evalExpr(e2));
			}
		case EBlock(el):
			var v : Value = { v : VNull, t : HDyn };
			for( e in el )
				v = evalExpr(e);
			return v;
		case EField(e, f):
			var e = e;
			var path = [f];
			var v = null;
			while( true ) {
				switch( e ) {
				case EIdent(i):
					path.unshift(i);
					v = evalPath(path);
					break;
				case EField(e2, f):
					path.unshift(f);
					e = e2;
				default:
					v = evalExpr(e);
					break;
				}
			}
			for( f in path ) {
				var vf = readField(v, f);
				if( vf == null ) throw valueStr(v)+" has no field "+f;
				v = vf;
			}
			return v;
		case EIf(econd, e1, e2), ETernary(econd, e1, e2):
			if( toBool(evalExpr(econd)) )
				return evalExpr(e1);
			return e2 == null ? { v : VNull, t : HDyn } : evalExpr(e2);
		case EParent(e):
			return evalExpr(e);
		case EThrow(e):
			throw valueStr(evalExpr(e));
		case EUnop(op, prefix, e):
			return evalUnop(op, prefix, evalExpr(e));
		case EMeta(_, _, e):
			return evalExpr(e);
		case ECall(efun, eargs):
			var vargs = [for( e in eargs ) evalExpr(e)];
			var vfun = evalExpr(efun);
			switch( vfun.v ) {
			case VMethod(_, obj, _):
				vargs.unshift(obj);
			case VFunction(_):
			default:
				throw hscript.Printer.toString(e)+" is not a function";
			}
			var ft = switch( vfun.t ) {
			case HFun(ft): ft;
			default: throw "assert";
			}
			for( i => v in vargs ) {
				var at = ft.args[i];
				if( at == null )
					throw "Too many arguments";
				vargs[i] = castTo(v,at);
			}
			while( vargs.length < ft.args.length ) {
				var at = ft.args[vargs.length];
				if( at.isPtr() )
					vargs.push({ v : VNull, t : at });
				else
					throw "Missing argument";
			}
			if( Debugger.DEBUG )
				trace("EVAL "+hscript.Printer.toString(e));
			return evalCall(vfun, vargs);
		default:
			throw "Unsupported expression `" + hscript.Printer.toString(e) + "`";
		}
	}

	inline function isFloat(t:HLType) {
		return t == HF32 || t == HF64;
	}

	function evalCall( vfun : Value, vargs : Array<Value> ) {
		if( !jit.is64 )
			throw "Can't call function in x32 mode : not implemented";
		var tret = switch( vfun.t ) {
		case HFun(f), HMethod(f): f.ret;
		default: throw "Not a function";
		}
		var addr = switch( vfun.v ) {
		case VFunction(_, p), VClosure(_,_,p): readPointer(p.offset(align.ptr));
		case VMethod(_, _, p): p;
		default: throw "Not a function";
		}
		// align stack
		var stackValue = api.readRegister(currentThread, Esp);
		var oldStack = stackValue;
		stackValue = stackValue.offset(-100);
		stackValue = stackValue.offset((-stackValue.toInt() & 0xFF));
		// set registers
		var asmOut = new haxe.io.BytesBuffer();

		function pushReg(r:NativeReg) {
			if( r.isFpu() ) {
				asmOut.addInt32(0x10EC8348); // sub rsp, 16
				// movsd [rsp], xmm?
				asmOut.addByte(0xF2);
				asmOut.addByte(0x0F);
				asmOut.addByte(0x11);
				asmOut.addByte(0x04 + (r.toInt() & 7) * 8);
				asmOut.addByte(0x24);
				return;
			}
			if( r.is64() ) asmOut.addByte(0x41);
			asmOut.addByte(0x50 + (r.toInt()&7));
		}

		function popReg(r:NativeReg) {
			if( r.isFpu() ) {
				// movsd xmm?, [rsp]
				asmOut.addByte(0xF2);
				asmOut.addByte(0x0F);
				asmOut.addByte(0x10);
				asmOut.addByte(0x04 + (r.toInt() & 7) * 8);
				asmOut.addByte(0x24);
				// add rsp, 16
				asmOut.addInt32(0x10C48348); // add rsp, 16
				return;
			}
			if( r.is64() ) asmOut.addByte(0x41);
			asmOut.addByte(0x58 + (r.toInt()&7));
		}

		function setReg(r:NativeReg, ptr:Pointer) {
			if( r.isFpu() ) {
				setReg(Eax, ptr);
				pushReg(Eax);
				popReg(r);
				return;
			}
			var r64 = 8;
			if( r.is64() ) r64 |= 1;
			asmOut.addByte(0x40 | r64);
			asmOut.addByte(0xB8 + (r.toInt()&7));
			asmOut.addInt64(ptr.i64);
		}

		var nextCpu = 0, nextFpu = 0;
		var callRegs = jit.isWinCall ? [Ecx, Edx, R8, R9] : [Edi, Esi, Edx, Ecx, R8, R9];
		for( i => r in callRegs ) {
			pushReg(r);
			pushReg(NativeReg.XMM(i));
		}
		var regs = [];
		for( v in vargs ) {
			var isCpu = !isFloat(v.t);
			var r : Null<NativeReg> = if( isCpu )
				callRegs[nextCpu++]
			else if( jit.isWinCall )
				nextCpu >= callRegs.length ? null : NativeReg.XMM(nextCpu++)
			else
				nextFpu >= callRegs.length ? null : NativeReg.XMM(nextFpu++);
			if( r == null )
				throw "TODO : stack arguments";
			regs.push(r);
		}

		for( i in 0...vargs.length ) {
			var v = vargs[vargs.length - i - 1];
			var r = regs[vargs.length - i - 1];
			switch( [v.t, v.v] ) {
			case [HI32, VInt(i)]:
				setReg(r, Pointer.make(i,0));
			case [HBool, VBool(b)]:
				setReg(r, Pointer.make(b?1:0,0));
			case [HF32, VFloat(f)]:
				var v = haxe.io.FPHelper.floatToI32(f);
				setReg(r, Pointer.make(v,0));
			case [HF64, VFloat(f)]:
				var v = haxe.io.FPHelper.doubleToI64(f);
				setReg(r, Pointer.make(v.low, v.high));
			case _ if( v.t.isPtr() ):
				setReg(r, getPtr(v));
			default:
				throw "Unsupported arg "+valueStr(v)+":"+typeStr(v.t);
			}
		}
		// insert call asm
		var prevEax = api.readRegister(currentThread, Eax);
		setReg(Eax, addr);
		asmOut.addByte(0xFF); // call eax
		asmOut.addByte(0xD0);
		switch( tret ) {
		case HF32:
			// movss [rsp], xmm0
			asmOut.addInt32(0x04110FF3);
			asmOut.addByte(0x24);
			popReg(Eax);
		case HF64:
			// movsd [rsp], xmm0
			asmOut.addInt32(0x04110FF2);
			asmOut.addByte(0x24);
			popReg(Eax);
		default:
			// use RAX
		}
		for( i in 0...callRegs.length ) {
			var i = callRegs.length - 1 - i;
			popReg(NativeReg.XMM(i));
			popReg(callRegs[i]);
		}
		asmOut.addByte(0xCC); // break
		// patch the code
		var asmOut = asmOut.getBytes();
		var asmSize = asmOut.length;
		if( Debugger.DEBUG )
			trace("ASM Eval code ["+asmSize+"] = "+asmOut.toHex());
		var eip = api.readRegister(currentThread, Eip);
		var prevAsm = new Buffer(asmSize);
		if( !api.read(eip, prevAsm, asmSize) )
			throw "assert";
		var buffer = new Buffer(asmSize);
		for( i in 0...asmSize )
			buffer.setUI8(i, asmOut.get(i));
		if( !api.write(eip, buffer, asmSize) )
			throw "assert";
		api.flush(eip, asmSize);
		resumeDebug();
		// restore
		api.write(eip, prevAsm, asmSize);
		api.flush(eip, asmSize);
		var ptr = api.readRegister(currentThread, Eax);
		var nip = api.readRegister(currentThread, Eip).sub(eip);
		var hasError = nip != asmSize;
		if( hasError )
			throw "Exception has occured";
		api.writeRegister(currentThread, Eax, prevEax);
		api.writeRegister(currentThread, Eip, eip);
		api.writeRegister(currentThread, Esp, oldStack);
		return convertVal(ptr, tret);
	}

	public dynamic function resumeDebug() {
		throw "Not implemented";
	}

	function getNum( v : Value ) : Float {
		return switch( v.v ) {
		case VInt(i): i;
		case VFloat(f): f;
		default: throw valueStr(v)+" should be a number";
		}
	}

	function getInt( v : Value ) : Int {
		return switch( v.v ) {
		case VInt(i): i;
		default: throw valueStr(v)+" should be a number";
		}
	}

	function compare(a:Value,b:Value) : Int {
		switch [a.v, b.v] {
		case [VString(as,_), VString(bs,_)]:
			return Reflect.compare(as, bs);
		default:
			var d = getNum(a) - getNum(b);
			return d == 0 ? 0 : d > 0 ? 1 : -1;
		}
	}

	function mkBool(b) : Value {
		return { v : VBool(b), t : HBool };
	}

	function evalBinop(op, v1:Value, v2:Value) : Value {
		inline function numOp(f:Float->Float->Float) : Value {
			var f1 = getNum(v1);
			var f2 = getNum(v2);
			var ret = f(f1,f2);
			var iret = Std.int(ret);
			return iret == ret ? { v : VInt(iret), t : HI32 } : { v : VFloat(ret), t : HF64 };
		}
		inline function iop(f:Int->Int->Int) : Value {
			var f1 = getInt(v1);
			var f2 = getInt(v2);
			var ret = f(f1,f2);
			return { v : VInt(ret), t : HI32 };
		}
		return switch( op ) {
		case "+": numOp((a,b)->a+b);
		case "-": numOp((a,b)->a-b);
		case "*": numOp((a,b)->a*b);
		case "/": numOp((a,b)->a/b);
		case "%": numOp((a,b)->a%b);
		case ">>": iop((a,b)->a>>b);
		case ">>>": iop((a,b)->a>>>b);
		case "<<": iop((a,b)->a<<b);
		case "|": iop((a,b)->a|b);
		case "&": iop((a,b)->a&b);
		case "^": iop((a,b)->a^b);
		case "==": mkBool(compare(v1,v2) == 0);
		case "!=": mkBool(compare(v1,v2) != 0);
		case ">": mkBool(compare(v1,v2) > 0);
		case "<": mkBool(compare(v1,v2) < 0);
		case ">=": mkBool(compare(v1,v2) >= 0);
		case "<=": mkBool(compare(v1,v2) <= 0);
		default:
			throw "Can't eval " + valueStr(v1) + " " + op + " " + valueStr(v2);
		}
	}

	function evalUnop(op, prefix:Bool, v:Value) : Value {
		return switch( op ) {
		case "-":
			switch( v.v ) {
			case VInt(i): { v : VInt(-i), t : v.t };
			case VFloat(f): { v : VFloat(-f), t : v.t };
			default: getNum(v); throw "assert";
			}
		case "!":
			switch( v.v ) {
			case VBool(b): mkBool(!b);
			case VNull: mkBool(true);
			default: throw "Can't do !"+valueStr(v);
			}
		default:
			throw "Can't eval " + (prefix ? op + valueStr(v) : valueStr(v) + op);
		}
	}

	function defVal( t : HLType ) : Value {
		return switch( t ) {
		case HUi8, HUi16, HI32, HI64: { v : VInt(0), t : t };
		case HF32, HF64: { v : VFloat(0.), t : t };
		case HBool: { v : VBool(false), t : t };
		default: { v : VNull, t : t };
		}
	}

	function toInt( v : Value ) {
		switch( v.v ) {
		case VNull, VUndef:
			return 0;
		case VInt(i):
			return i;
		case VFloat(f):
			return Std.int(f);
		default:
			throw "Can't case " + valueStr(v) + " to int";
		}
	}

	function toBool( v : Value ) {
		switch( v.v ) {
		case VNull, VUndef:
			return false;
		case VBool(b):
			return b;
		default:
			throw "Can't case " + valueStr(v) + " to int";
		}
	}

	function getVar( name : String ) : Value {
		return switch( name ) {
		case "true": mkBool(true);
		case "false": mkBool(false);
		case "null": { v : VNull, t : HDyn };
		case "$ret":
			var t = module.getGraph(funIndex).getReturnReg(codePos);
			if( t == null )
				return null;
			return convertVal(api.readRegister(currentThread,t == HF64 || t == HF32 ? Xmm0 : Eax), t);
		default:
			fetchAddr(getVarAddress(name));
		}
	}

	function getVarAddress( name : String, ?prefix : String, ?localsRaw : Array<String>, localOnly = false ) : VarAddress {
		var fullname = prefix == null ? name : prefix + "." + name;
		var a = getVarAddressRaw(fullname, localOnly);
		if( a != ANone )
			return a;

		if( localsRaw == null )
			localsRaw = module.getGraph(funIndex).getLocalsRaw(codePos);

		// Inlined constructor variables
		var relatedLocals = [];
		for( r in localsRaw ) {
			var names = r.split(".");
			if( names.length <= 1 || names[0] != name ) continue;
			relatedLocals.push(r.substr(name.length+1));
		}
		if( relatedLocals.length == 0 )
			return ANone;

		var fnames = [];
		for( r in relatedLocals ) {
			var name = r.split(".")[0];
			if( fnames.contains(name) ) continue;
			fnames.push(name);
		}
		var fields = [for( n in fnames ) { name : n, addr : getVarAddress(n, fullname, relatedLocals, true) }];
		return AInlined(fields);
	}

	function getVarAddressRaw( name : String, localOnly : Bool ) : VarAddress {
		// locals
		var loc = module.getGraph(funIndex).getLocal(name, codePos);
		if( loc != null && !globalContext ) {
			var v = readRegAddress(loc.rid);
			if( loc.index != null ) {
				switch( v ) {
				case AUndef(_):
					return AUndef(loc.t);
				case AAddr(ptr, t):
					var ptr = readPointer(ptr);
					return AAddr(ptr.offset(module.getEnumProto(loc.container)[0].params[loc.index].offset), loc.t);
				default:
					throw "assert";
				}
			}
			return v;
		}
		if( localOnly )
			return ANone;

		// register
		if( ~/^\$[0-9]+$/.match(name) )
			return readRegAddress(Std.parseInt(name.substr(1)));

		// this variable
		if( module.getGraph(funIndex).getLocal("this", codePos) != null && !globalContext ) {
			var vthis = getVar("this");
			if( vthis != null ) {
				var f = readFieldAddress(vthis, name);
				if( f != ANone )
					return f;
				// static var
				switch( vthis.t ) {
				case HObj(o) if( o.globalValue != null ):
					var path = o.name.split(".");
					path.push(name);
					var f = getGlobalAddress(path);
					if( f != ANone )
						return f;
				default:
				}
			}
		}

		// static
		var ctx = module.getMethodContext(funIndex);
		var tpack = null;
		if( ctx != null && !globalContext ) {
			var t = ctx.obj;
			if( t.globalValue != null )
				t = switch( module.code.globals[t.globalValue] ) {
				case HObj(p): p;
				default: null;
				}
			if( t != null ) {
				var path = t.name.split(".");
				var tname = path.pop();
				if( tname.charCodeAt(0) == '$'.code ) {
					path.push(tname.substr(1));
					for( f in t.fields )
						if( f.name == name ) {
							path.push(name);
							return getGlobalAddress(path);
						}
					path.pop();
					tpack = path;
				}
			}
		}

		// global (current package)
		if( tpack != null && tpack.length > 0 ) {
			tpack.push(name);
			var g = getGlobalAddress(tpack);
			if( g != null )
				return g;
		}

		// global
		return getGlobalAddress([name]);
	}

	function evalPath( path : Array<String> ) {
		var v = getVar(path[0]);
		if( v != null ) {
			path.shift();
			return v;
		}
		var v = getGlobalAddress(path);
		if( v == ANone ) throw "Unknown value "+path.join(".");
		return fetchAddr(v);
	}

	function getGlobalAddress( path : Array<String> ) : VarAddress {
		var g = module.resolveGlobal(path);
		if( g == null )
			return ANone;
		var addr = AAddr(jit.globals.offset(g.offset), g.type);
		while( addr != ANone && path.length > 0 )
			addr = readFieldAddress(fetchAddr(addr), path.shift());
		return addr;
	}

	function escape( s : String ) {
		s = s.split("\\").join("\\\\");
		s = s.split("\n").join("\\n");
		s = s.split("\r").join("\\r");
		s = s.split("\t").join("\\t");
		s = s.split('"').join('\\"');
		return s;
	}

	public function typeStr( t : HLType ) {
		switch( t ) {
		case HDynObj, HVirtual(_):
			return "{...}";
		case HAbstract(name):
			return "#"+name;
		case HNull(t):
			return typeStr(t);
		default:
			return t.toString();
		}
	}

	public function valueStr( v : Value, maxStringRec = 3 ) {
		if( maxStringRec < 0 && v.t.isPtr() )
			return "<...>";
		maxStringRec--;
		var str = switch( v.v ) {
		case VUndef: "undef"; // null read / outside bounds
		case VNull: "null";
		case VInt(i):
			switch( v.hint ) {
			case HHex: Value.intStr(i, 16);
			case HBin: Value.intStr(i, 2);
			case HEnumFlags(t):
				var eproto = module.resolveEnum(t);
				if( eproto == null )
					throw "Can't resolve enum " + t;
				Value.intEnumFlags(i, eproto);
			case HEnumIndex(t):
				var eproto = module.resolveEnum(t);
				if( eproto == null )
					throw "Can't resolve enum " + t;
				Value.intEnumIndex(i, eproto);
			case HCdbEnum(t):
				var enames = eval(t + ".NAMES");
				if( enames == null )
					throw "Can't resolve CDB " + t + ".NAMES";
				switch( enames.v ) {
				case VArray(_, _, read, _):
					valueStr(read(i));
				default:
					throw "Can't resolve CDB " + t + ".NAMES array";
				}
			default: "" + i;
			}
		case VInt64(i):
			switch( v.hint ) {
			case HHex: Value.int64Hex(i);
			default: "" + i;
			}
		case VFloat(i):
			switch( v.hint ) {
			case HHex: Value.intStr(Std.int(i), 16);
			default: "" + i;
			}
		case VBool(b): b ? "true" : "false";
		case VPointer(_):
			switch( v.t ) {
			case HObj(p), HStruct(p): p.name.split(".").pop(); // short form (no package)
			default: typeStr(v.t);
			}
		case VString(s,_): "\"" + escape(s) + "\"";
		case VClosure(f, d, _), VMethod(f, d, _): funStr(f) + "[" + valueStr(d,maxStringRec) + "]";
		case VFunction(f,_): funStr(f);
		case VArray(_, length, read, _):
			var hasDispValue = false;
			for( i in 0...length ) {
				var v = read(i);
				if( !v.t.match(HDynObj | HVirtual(_)) ) {
					hasDispValue = true;
					break;
				}
			}
			if( !hasDispValue && length > 0 )
				"[...]"+(length > maxArrLength ? ":" + length : "");
			else if( length <= maxArrLength )
				"["+[for(i in 0...length) valueStr(read(i),maxStringRec)].join(", ")+"]";
			else {
				var arr = [for(i in 0...maxArrLength) valueStr(read(i),maxStringRec)];
				arr.push("...");
				"["+arr.join(",")+"]:"+length;
			}
		case VBytes(length, read, _):
			var blen = length < maxBytesLength ? length : maxBytesLength;
			var bytes = haxe.io.Bytes.alloc(blen);
			for( i in 0...blen )
				bytes.set(i, read(i));
			var str = length+":0x" + bytes.toHex().toUpperCase();
			if( length > maxBytesLength )
				str += "...";
			str;
		case VMap(_, 0, _):
			"{}";
		case VMap(_, nkeys, readKey, readValue, _):
			var max = nkeys < maxArrLength ? nkeys : maxArrLength;
			var content = [for( i in 0...max ) { var k = readKey(i); valueStr(k,maxStringRec) + "=>" + valueStr(readValue(i),maxStringRec); }];
			if( max != nkeys ) {
				content.push("...");
				content.toString() + ":" + nkeys;
			} else
				content.toString();
		case VType(t):
			typeStr(t);
		case VEnum(c, values, _):
			if( values.length == 0 )
				c
			else
				c + "(" + [for( v in values ) valueStr(v,maxStringRec)].join(", ") + ")";
		case VInlined(_):
			"inlined";
		}
		return str;
	}

	public function funStr( f : FunRepr ) {
		return switch( f ) {
		case FUnknown(p): "fun(" + p.toString() + ")";
		case FIndex(i): "fun(" + getFunctionName(i) + ")";
		}
	}

	function getFunctionName( idx : Int ) {
		var s = module.resolveSymbol(idx, 0);
		return s.file+":" + s.line;
	}

	function readRegAddress(index) : VarAddress {
		var r = module.getFunctionRegs(funIndex)[index];
		if( r == null )
			return ANone;
		if( !module.getGraph(funIndex).isRegisterWritten(index, codePos) )
			return AUndef(r.t);
		return AAddr(ebp.offset(r.offset), r.t);
	}

	function readReg(index) {
		return fetchAddr(readRegAddress(index));
	}

	function convertVal( p : Pointer, t : HLType ) : Value {
		var v = switch( t ) {
		case HVoid:
			VNull;
		case HUi8, HUi16, HI32:
			VInt(p.i64.low);
		case HI64:
			throw "TODO:"+t;
		case HF64, HF32:
			VFloat(haxe.io.FPHelper.i64ToDouble(p.i64.low,p.i64.high));
		case HBool:
			VBool(p.toInt() != 0);
		default:
			return valueCast(p, t);
		};
		return { v : v, t : t };
	}

	public function readVal( p : Pointer, t : HLType ) : Value {
		var v = switch( t ) {
		case HVoid:
			VNull;
		case HUi8:
			var m = readMem(p, 1);
			VInt(m.getUI8(0));
		case HUi16:
			var m = readMem(p, 2);
			VInt(m.getUI16(0));
		case HI32:
			VInt(readI32(p));
		case HI64:
			VInt64(haxe.Int64.make(readI32(p.offset(4)),readI32(p)));
		case HF32:
			var m = readMem(p, 4);
			VFloat(m.getF32(0));
		case HF64:
			var m = readMem(p, 8);
			VFloat(m.getF64(0));
		case HBool:
			var m = readMem(p, 1);
			VBool(m.getUI8(0) != 0);
		case HPacked(t):
			return { v : VPointer(p), t : t.v };
		default:
			p = readPointer(p);
			return valueCast(p, t);
		};
		return { v : v, t : t };
	}

	public function readArrayAddress( value : Value, index : Int ) {
		return switch( value.v ) {
		case VArray(t,len,_,ptr) if( index >= 0 && index < len ):
			var content = readPointer(ptr.offset(align.ptr * 2));
			var offset = align.typeSize(t) * index;
			if( t.isPtr() ) offset += sizeofVArray;
			return AAddr(content.offset(offset),t);
		default:
			return ANone;
		}
	}

	function valueCast( p : Pointer, t : HLType ) : Value {
		if( p.isNull() )
			return { v : VNull, t : t };
		var v = VPointer(p);
		switch( t ) {
		case HObj(o):
			t = readType(p);
			switch( t ) {
			case HObj(o2): o = o2;
			default:
			}
			switch( o.name ) {
			case "String":
				var bytes = readPointer(p.offset(align.ptr));
				var length = readI32(p.offset(align.ptr * 2));
				var str = readUCS2(bytes, length);
				v = VString(str, p);
			case "hl.types.ArrayObj":
				var length = readI32(p.offset(align.ptr));
				var nativeArray = readPointer(p.offset(align.ptr * 2));
				var type = readType(nativeArray.offset(align.ptr));
				v = VArray(type, length, function(i) return readVal(nativeArray.offset(sizeofVArray + i * align.ptr), type), p);
			case "hl.types.ArrayBytes_Int":
				v = makeArrayBytes(p, HI32);
			case "hl.types.ArrayBytes_Float":
				v = makeArrayBytes(p, HF64);
			case "hl.types.ArrayBytes_Single":
				v = makeArrayBytes(p, HF32);
			case "hl.types.ArrayBytes_hl_UI16":
				v = makeArrayBytes(p, HUi16);
			case "hl.types.ArrayDyn":
				// hide implementation details, substitute underlying array
				v = readField({ v : v, t : t }, "array").v;
			case "haxe.ds.StringMap":
				v = makeMap(readPointer(p.offset(align.ptr)), HBytes);
			case "haxe.ds.IntMap":
				v = makeMap(readPointer(p.offset(align.ptr)), HI32);
			case "haxe.ds.ObjectMap":
				v = makeMap(readPointer(p.offset(align.ptr)), HDyn);
			case "haxe.io.Bytes":
				var length = readI32(p.offset(align.ptr));
				var bytes = readPointer(p.offset(align.ptr * 2));
				v = VBytes(length, function(i) return readMem(bytes.offset(i),1).getUI8(0), p);
			default:
			}
		case HVirtual(_):
			var v = readPointer(p.offset(align.ptr));
			if( !v.isNull() )
				return valueCast(v, HDyn);
		case HDyn:
			t = readType(p);
			if( t.isDynamic() )
				return valueCast(p, t);
			v = readVal(p.offset(8), t).v;
		case HNull(t):
			v = readVal(p.offset(8), t).v;
		case HRef(t):
			v = readVal(p, t).v;
		case HFun(_):
			var funPtr = readPointer(p.offset(align.ptr));
			var hasValue = readI32(p.offset(align.ptr * 2));
			var fidx = jit.functionFromAddr(funPtr);
			var fval = fidx == null ? FUnknown(funPtr) : FIndex(fidx);
			if( hasValue == 1 ) {
				var value = readVal(p.offset(align.ptr * 3), HDyn);
				v = VClosure(fval, value, p);
			} else
				v = VFunction(fval, p);
		case HType:
			v = VType(readType(p,true));
		case HBytes:
			var len = 0;
			var buf = new StringBuf();
			while( true ) {
				var c = try readI32(p.offset(len<<1)) & 0xFFFF catch( e : Dynamic ) 0;
				if( c == 0 ) break;
				buf.addChar(c);
				len++;
				if( len > 50 ) {
					buf.add("...");
					break;
				}
			}
			v = VString(buf.toString(), p);
		case HEnum(e):
			var index = readI32(p.offset(align.ptr));
			var c = module.getEnumProto(e)[index];
			v = VEnum(c.name,[for( a in c.params ) readVal(p.offset(a.offset),a.t)], p);
		case HAbstract("hl_int64_map"):
			v = makeMap(p, HI64);
		default:
		}
		return { v : v, t : t };
	}

	function makeArrayBytes( p : Pointer, t : HLType ) {
		var length = readI32(p.offset(align.ptr));
		var bytes = readPointer(p.offset(align.ptr * 2));
		var size = align.typeSize(t);
		return VArray(t, length, function(i) return readVal(bytes.offset(i * size), t), p);
	}

	function makeMap( p : Pointer, tkey : HLType ) {
		var isV13 = jit.hlVersion >= 1.13;
		var cells = readPointer(p);
		var nexts = isV13 ? readPointer(p.offset(align.ptr)) : null;
		var offset = isV13 ? align.ptr * 2 : align.ptr;
		var entries = readPointer(p.offset(offset));
		var values = readPointer(p.offset(offset + align.ptr));
		var freelist_size = align.ptr + 4 + 4;
		var pos = offset + align.ptr * 2 + freelist_size;
		var ncells = readI32(p.offset(pos));
		var nentries = readI32(p.offset(pos + 4));
		var maxEntries = readI32(p.offset(pos + 8));
		var keyInValue;
		var valuePos, keyStride, valueStride, keyPadding = 0;
		switch( tkey ) {
		case HBytes:
			keyInValue = true;
			valuePos = align.ptr;
			keyStride = isV13 ? 4 : 8;
			valueStride = align.ptr * 2;
		case HI32:
			keyInValue = false;
			valuePos = 0;
			keyStride = isV13 ? 4 : 8;
			valueStride = align.ptr;
		case HDyn:
			keyInValue = true;
			valuePos = align.ptr;
			keyStride = isV13 ? 0 : 4;
			valueStride = align.ptr * 2;
		case HI64:
			keyInValue = false;
			valuePos = 0;
			keyStride = isV13 ? 8 : 16;
			keyPadding = 4;
			valueStride = align.ptr;
		default:
			throw "Unsupported map " + tkey.toString();
		}

		var isSmall = isV13 && nentries < 128;

		var content : Array<{ key : Value, value : Value }> = [];
		var curCell = 0;

		function fetch(k) {
			while( content.length <= k ) {
				if( curCell == ncells ) throw "assert";
				var c = isSmall ? readByte(cells.offset(curCell++)) : readI32(cells.offset((curCell++) << 2));
				while( c >= 0 ) {
					if( isSmall && c == 255 )
						break;
					var value = readVal(values.offset(c * valueStride + valuePos), HDyn);
					var keyPtr = keyInValue ? values.offset(c * valueStride) : entries.offset(c * keyStride);
					var key : Value = switch( tkey ) {
					case HBytes:
						{ v : VString(readUCSBytes(readPointer(keyPtr)), null), t : t_string };
					case HI32:
						{ v : VInt(readI32(keyPtr)), t : HI32 };
					case HI64:
						{ v : VInt64(readI64(keyPtr)), t : HI64 };
					case HDyn:
						readVal(keyPtr,HDyn);
					default:
						throw "Unsupported map " + tkey.toString();
					}
					content.push({ key : key, value : value });
					if( isV13 )
						c = isSmall ? readByte(nexts.offset(c)) : readI32(nexts.offset(c<<2));
					else
						c = readI32(entries.offset(c * keyStride + keyStride - 4 - keyPadding));
				}
			}
			return content[k];
		}

		function getKey(k):Value return k < 0 || k >= nentries ? { v : VUndef, t : tkey } : fetch(k).key;
		function getValue(k):Value return k < 0 || k >= nentries ? { v : VUndef, t : HDyn } : fetch(k).value;

		return VMap(tkey == HBytes ? t_string : tkey,nentries,getKey, getValue, p);
	}

	public function getFields( v : Value ) : Array<String> {
		var ptr = switch( v.v ) {
		case VPointer(p): p;
		case VEnum(_,values,_):
			// only list the pointer fields (others are displayed in enum anyway)
			return [for( i in 0...values.length ) if( values[i].t.isPtr() ) "$"+i];
		case VInlined(fields):
			return [for( f in fields ) f.name];
		default:
			return null;
		}
		switch( v.t ) {
		case HObj(o), HStruct(o):
			function getRec(o:format.hl.Data.ObjPrototype) {
				var fields = o.tsuper == null ? [] : getRec(switch( o.tsuper ) { case HObj(o), HStruct(o): o; default: throw "assert"; });
				for( f in o.fields )
					if( f.name != "" )
						fields.push(f.name);
				return fields;
			}
			return getRec(o);
		case HVirtual(fields):
			return [for( f in fields ) f.name];
		case HDynObj:
			var lookup = readPointer(ptr.offset(align.ptr));
			var nfields = readI32(ptr.offset(align.ptr * 4));
			var fields = [];
			var hasIndex = false;
			for( i in 0...nfields ) {
				var l = lookup.offset(i * (align.ptr + 8));
				var h = readI32(l.offset(align.ptr)); // hashed_name
				var index = readI32(l.offset(align.ptr+4)) >>> 17;
				if( index > 0 )
					hasIndex = true;
				var name = module.reverseHash(h);
				if( name == null ) name = HASH_PREFIX + h;
				if( hasIndex )
					fields[index] = name;
				else
					fields.push(name);
			}
			return fields;
		default:
			return null;
		}
	}

	public function readField( v : Value, name : String ) {
		switch( v.v ) {
		case VEnum(_,values,_) if( name.charCodeAt(0) == "$".code ):
			return values[Std.parseInt(name.substr(1))];
		default:
		}
		var a = readFieldAddress(v, name);
		return fetchAddr(a);
	}

	public function fetch( addr : Debugger.Address ) {
		return fetchAddr(addr == null ? ANone : addr.ptr == null ? AUndef(addr.t) : AAddr(addr.ptr, addr.t));
	}

	function fetchAddr( addr : VarAddress ) : Value {
		switch( addr ) {
		case ANone:
			return null;
		case AUndef(t):
			return { v : VUndef, t : t };
		case AAddr(ptr,t):
			return readVal(ptr, t);
		case AMethod(v, p, t):
			var fidx = jit.functionFromAddr(p);
			var fval = fidx == null ? FUnknown(p) : FIndex(fidx);
			return { v : VMethod(fval,v,p), t : t };
		case AEvaled(v):
			return v;
		case AInlined(fields):
			return { v : VInlined(fields), t : HDyn };
		}
	}

	public function readFieldAddress( v : Value, name : String ) : VarAddress {
		var ptr = switch( v.v ) {
		case VUndef, VNull: null;
		case VPointer(p): p;
		case VArray(_, _, _, p): p;
		case VString(_, p): p;
		case VMap(_, _, _, _, p): p;
		case VInlined(fields):
			for( f in fields )
				if( f.name == name )
					return f.addr;
			return ANone;
		default:
			return ANone;
		}
		switch( v.t ) {
		case HObj(o), HStruct(o):
			var p = module.getObjectProto(o,v.t.match(HStruct(_)));
			var f = p.fields.get(name);
			if( f != null ) {
				var offset = f.offset;
				return ptr == null ? AUndef(f.t) : AAddr(ptr.offset(offset), f.t);
			}
			var f = p.methods.get(name);
			if( f != null && ptr != null ) {
				// HMethod
				var vt = readPointer(ptr);
				if( f.pindex >= 0 ) {
					var vp = readPointer(vt.offset(align.ptr*2));
					return AMethod(v, readPointer(vp.offset(f.index * align.ptr)), f.t);
				}
				var vobj = readPointer(vt.offset(align.ptr));
				var vrt = readPointer(vobj.offset(4 * 2 + align.ptr + align.ptr * 7));
				var vmethods = readPointer(vrt.offset(align.ptr + 4 * 6));
				return AMethod(v, readPointer(vmethods.offset(f.index * align.ptr)), f.t);
			}
			var f = p.methods.get("get_"+name);
			if( f != null && ptr != null && allowEvalGetters ) {
				var f = readFieldAddress(v, "get_"+name);
				switch( f ) {
				case AMethod(obj, ptr, HFun(ft)) if( ft.args.length == 1 ):
					if( Debugger.DEBUG )
						trace("EVAL "+valueStr(v)+".get_"+name+"()");
					return AEvaled(evalCall(fetchAddr(f),[obj]));
				default:
				}
			}
			return ANone;
		case HVirtual(fl):
			for( i in 0...fl.length )
				if( fl[i].name == name ) {
					var t = fl[i].t;
					if( ptr == null )
						return AUndef(t);
					var addr = readPointer(ptr.offset(align.ptr * (3 + i)));
					if( addr != null )
						return AAddr(addr, t);
				}
			if( ptr == null )
				return ANone;
			var realValue = readPointer(ptr.offset(align.ptr));
			if( realValue.isNull() )
				return ANone;
			return readFieldAddress({ v : VPointer(realValue), t : HDyn }, name);
		case HDynObj:
			if( ptr == null )
				return AUndef(HDyn);
			var lookup = readPointer(ptr.offset(align.ptr * 1));
			var raw_data = readPointer(ptr.offset(align.ptr * 2));
			var values = readPointer(ptr.offset(align.ptr * 3));
			var nfields = readI32(ptr.offset(align.ptr * 4));
			// lookup, similar to hl_lookup_find
			var hash = StringTools.startsWith(name,HASH_PREFIX) ? Std.parseInt(name.substr(HASH_PREFIX.length)) : name.hash();
			var min = 0;
			var max = nfields;
			while( min < max ) {
				var mid = (min + max) >> 1;
				var lid = lookup.offset(mid * (align.ptr + 8));
				var h = readI32(lid.offset(align.ptr)); // hashed_name
				if( h < hash )
					min = mid + 1;
				else if( h > hash )
					max = mid;
				else {
					var t = readType(lid);
					var offset = readI32(lid.offset(align.ptr + 4)) & ((1 << 17) - 1);
					return AAddr(t.isPtr() ? values.offset(offset * align.ptr) : raw_data.offset(offset), t);
				}
			}
			return ANone;
		case HDyn:
			if( ptr == null )
				return AUndef(HDyn);
			return readFieldAddress({ v : v.v, t : readType(ptr) }, name);
		default:
			return ANone;
		}
	}

	public function readPointer( p : Pointer ) {
		if( align.is64 ) {
			var m = readMem(p, 8);
			return m.getPointer(0,align);
		}
		return Pointer.make(readI32(p), 0);
	}

	public function writePointer( p : Pointer, v : Pointer ) {
		if( align.is64 ) {
			var buf = new Buffer(8);
			buf.setPointer(0, v, align);
			writeMem(p, buf, 8);
		} else
			writeI32(p, v.toInt());
	}

	function readMem( p : Pointer, size : Int ) {
		var b = new Buffer(size);
		if( !api.read(p, b, size) )
			throw "Failed to read @" + p.toString() + ":" + size;
		return b;
	}

	function readUCS2( ptr : Pointer, length : Int ) {
		var mem = readMem(ptr, (length + 1) << 1);
		return mem.readStringUCS2(0,length);
	}

	function readUCSBytes( ptr : Pointer ) {
		var len = 0;
		while( true ) {
			var v = readI32(ptr.offset(len << 1));
			var low = v & 0xFFFF;
			var high = v >>> 16;
			if( low == 0 ) break;
			len++;
			if( high == 0 ) break;
			len++;
		}
		return readUCS2(ptr, len);
	}

	public function readByte( p : Pointer ) {
		return readMem(p, 1).getUI8(0);
	}

	public function readI32( p : Pointer ) {
		return readMem(p, 4).getI32(0);
	}

	public function readI64( p : Pointer ) {
		var mem = readMem(p, 8);
		return haxe.Int64.make(mem.getI32(4),mem.getI32(0));
	}

	public function writeI32( p : Pointer, v : Int ) {
		var buf = new Buffer(4);
		buf.setI32(0,v);
		writeMem(p, buf, 4);
	}

	public function writeF64( p : Pointer, v : Float ) {
		var buf = new Buffer(8);
		buf.setF64(0,v);
		writeMem(p, buf, 8);
	}

	function writeMem( p : Pointer, b : Buffer, size : Int ) {
		if( !api.write(p, b, size) )
			throw "Failed to write @" + p.toString() + ":" + size;
	}

	function readType( p : Pointer, direct = false ) {
		if( !direct )
			p = readPointer(p);
		switch( readI32(p) ) {
		case 0:
			return HVoid;
		case 1:
			return HUi8;
		case 2:
			return HUi16;
		case 3:
			return HI32;
		case 4:
			return HI64;
		case 5:
			return HF32;
		case 6:
			return HF64;
		case 7:
			return HBool;
		case 8:
			return HBytes;
		case 9:
			return HDyn;
		case 10:
			var t = typeFromAddr(p);
			if( t != null )
				return t;
			// vclosure !
			var tfun = readPointer(p.offset(align.ptr));
			var pparent = tfun.offset(align.ptr * 3);
			if( p.i64 == readPointer(pparent).i64 )
				return HFun({args:[],ret:HDyn}); // varargs !
			var tparent = readType(pparent);
			return switch( tparent ) {
			case HFun(f): var args = f.args.copy(); args.shift(); HFun({ args : args, ret: f.ret });
			default: throw "assert";
			}
		case 12:
			return HArray;
		case 13:
			return HType;
		case 14:
			return HRef(readType(p.offset(align.ptr)));
		case 16:
			return HDynObj;
		case 11, 15, 17, 18, 21: // HObj, HVirtual, HAbstract, HEnum, HStruct
			return typeFromAddr(p);
		case 19:
			return HNull(readType(p.offset(align.ptr)));
		case x:
			throw "Unknown type #" + x;
		}
	}

	inline function typeStructSize() {
		return align.ptr * 4;
	}

	function typeFromAddr( p : Pointer ) : HLType {
		var tid = Std.int( p.sub(@:privateAccess jit.allTypes) / typeStructSize() );
		return module.code.types[tid];
	}

}


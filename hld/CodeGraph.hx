package hld;

private enum Control {
	CNo;
	CJCond( d : Int );
	CJAlways( d : Int );
	CTry( d : Int );
	CCatch;
	CSwitch( arr : Array<Int> );
	CRet;
	CThrow;
	CLabel;
	CCall( fidx : Int );
}

typedef LocalAccess = { rid : Int, ?index : Int, ?container : format.hl.Data.EnumPrototype, t : format.hl.Data.HLType };

class CodeBlock {

	public var start : Int;

	public var end : Int; // inclusive
	public var loop : Bool;
	public var prev : Array<CodeBlock>;
	public var next : Array<CodeBlock>;
	public var trap : Array<Int>;

	public var writtenRegs : Map<Int,Int>;
	public var writtenVars : Map<String, Array<Int>>;

	public var visitTag : Int = 0;
	public var visitResult : LocalAccess;

	public function new(pos, trapl) {
		start = pos;
		prev = [];
		next = [];
		trap = trapl;
		writtenRegs = new Map();
		writtenVars = new Map();
	}

}

class CodeGraph {

	var module : format.hl.Data;
	var fun : format.hl.Data.HLFunction;
	var blockPos : Map<Int,CodeBlock>;
	var allBlocks : Map<Int,Bool>;
	var assigns : Map<Int, Array<String>>;
	var args : Array<{ hasIndex : Bool, vars : Array<String> }>;
	var nargs : Int;
	var currentTag : Int = 0;

	var localsRawCache : Array<String> = [];
	var localsRawCachePos : Int = -1;

	public function new(md, f) {
		this.module = md;
		this.fun = f;
		blockPos = new Map();
		allBlocks = new Map();
		nargs = switch( fun.t ) {
		case HFun(f): f.args.length;
		default: throw "assert";
		};
		// build graph
		for( i in 0...f.ops.length )
			switch( control(i) ) {
			case CJAlways(d), CJCond(d):
				allBlocks.set(i + 1 + d, true);
			default:
			}
		makeBlock(0, []);

		// init assign args (slightly complicated, let's handle complex logic here)
		args = [];
		var r0used = false;
		for( a in fun.assigns ) {
			if( a.position >= 0 ) break;
			if( a.position == -2 && args.length == 0 ) {
				r0used = true;
			}
			if( a.position == -1 ) {
				var vname = module.strings[a.varName];
				args.push({ hasIndex : false, vars : [vname] });
			}
		}
		if( args.length == nargs - 1 )
			if( r0used )
				args.unshift({ hasIndex : true, vars : [] });
			else
				args.unshift({ hasIndex : false, vars : ["this"] });
		for( a in fun.assigns ) {
			if( a.position >= -1 ) break;
			var vname = module.strings[a.varName];
			var r = -a.position - 2;
			args[r].vars.push(vname);
		}

		// single captured pointer => passed directly
		if( args.length >= 1 && args[0].hasIndex && !f.regs[0].match(HEnum({constructs:[{name:""}]})) )
			args[0].hasIndex = false;

		// init assigns
		assigns = new Map();
		for( a in fun.assigns ) {
			if( a.position < 0 ) continue;
			var vname = module.strings[a.varName];
			var vl = assigns.get(a.position);
			if( vl == null ) {
				vl = [];
				assigns.set(a.position, vl);
			}
			vl.push(vname);
		}

		// calculate written registers
		for( b in blockPos )
			checkWrites(b);
		// absolutes
		while( true ) {
			var changed = false;
			for( b in blockPos )
				for( b2 in b.prev ) {
					for( rid in b2.writtenRegs.keys() ) {
						var pos = b2.writtenRegs.get(rid);
						var cur = b.writtenRegs.get(rid);
						if( cur == null || cur > pos ) {
							b.writtenRegs.set(rid, pos);
							changed = true;
						}
					}
				}
			if( !changed ) break;
		}
	}

	function getBlock( pos : Int ) {
		var bpos = pos;
		var b;
		while( (b = blockPos.get(bpos)) == null ) bpos--;
		return b;
	}

	public function getNextPos( pos : Int ) : Array<Int> {
		var b = getBlock(pos);
		if( pos == b.end )
			return b.next.map(bn -> bn.start);
		return b.trap.concat([pos+1]);
	}

	public function isRegisterWritten( rid : Int, pos : Int ) {
		if( rid < nargs )
			return true;
		var b = getBlock(pos);
		var rpos = b.writtenRegs.get(rid);
		return rpos != null && rpos < pos;
	}

	public function getArgs() : Array<String> {
		return filterRaw(getArgsRaw());
	}

	public function getLocals( pos : Int ) : Array<String> {
		return filterRaw(getLocalsRaw(pos));
	}

	function filterRaw( raw : Array<String> ) {
		var arr = [];
		for( a in raw ) {
			var name = a.split(".")[0];
			if( arr.indexOf(name) >= 0 ) continue;
			arr.push(name);
		}
		return arr;
	}

	function getArgsRaw() : Array<String> {
		var arr = [];
		for( a in args )
			for( v in a.vars )
				arr.push(v);
		return arr;
	}

	function getLocalsRaw( pos : Int ) : Array<String> {
		if( pos == localsRawCachePos )
			return localsRawCache;
		var arr = [];
		for( a in fun.assigns ) {
			if( a.position > pos ) break;
			if( a.position < 0 ) continue; // arg
			if( arr.indexOf(a.varName) >= 0 ) continue;
			if( getLocal(module.strings[a.varName],pos) == null ) continue; // not written
			arr.push(a.varName);
		}
		localsRawCachePos = pos;
		localsRawCache = [for( a in arr ) module.strings[a]];
		return localsRawCache;
	}

	public function getReturnReg( pos : Int ) : Null<HLType> {
		switch( fun.ops[pos] ) {
		case OCallClosure(dst,_,_), OCallMethod(dst,_,_), OCallThis(dst,_,_), OCall0(dst,_), OCall1(dst,_,_), OCall2(dst,_,_,_), OCall3(dst,_,_,_,_), OCall4(dst,_,_,_,_), OCallN(dst,_,_):
			if( fun.regs[dst] != HVoid ) return fun.regs[dst];
		default:
		}
		return null;
	}

	public function getLocal( name : String, pos : Int ) : LocalAccess {
		var b = getBlock(pos);
		currentTag++;
		var l = lookupLocal(b, name, pos);
		if( l != null )
			return l;
		for( i in 0...args.length ) {
			var a = args[i];
			for( k in 0...a.vars.length )
				if( a.vars[k] == name ) {
					if( !a.hasIndex )
						return { rid : i, t : fun.regs[i] };
					var en = null;
					var t = switch( fun.regs[i] ) {
					case HEnum(e):
						en = e;
						e.constructs[0].params[k];
					default:
						throw "assert";
					};
					return { rid : i, index : k, container : en, t : t };
				}
		}
		return null;
	}

	function lookupLocal( b : CodeBlock, name : String, pos : Int ) : LocalAccess {
		if( b.visitTag == currentTag )
			return b.visitResult;
		b.visitTag = currentTag;
		var v = b.writtenVars.get(name);
		if( v != null ) {
			var last = -1;
			for( p in v )
				if( p < pos )
					last = p;
				else if( last < 0 )
					break;
			if( last >= 0 ) {
				var rid = -1;
				opFx(fun.ops[last], function(_) {}, function(w) rid = w);
				return b.visitResult = { rid : rid, t : fun.regs[rid] };
			}
		}
		var found : LocalAccess = null;
		for( b2 in b.prev )
			if( b2.start < b.start ) {
				var l = lookupLocal(b2, name, pos);
				// make sure that all branches have written the same register
				// if not it's out of scope
				if( found != null && (l == null || l.rid != found.rid) )
					return b.visitResult = null;
				found = l;
			}
		return b.visitResult = found;
	}

	function checkWrites( b : CodeBlock ) {
		for( i in b.start...b.end+1 ) {
			opFx(fun.ops[i], function(_) {}, function(rid) if( !b.writtenRegs.exists(rid) ) b.writtenRegs.set(rid, i));
			var vl = assigns.get(i);
			if( vl == null ) continue;
			for( v in vl ) {
				var wl = b.writtenVars.get(v);
				if( wl == null ) {
					wl = [];
					b.writtenVars.set(v, wl);
				}
				wl.push(i);
			}
		}
	}

	function makeBlock( pos : Int, trapl : Array<Int> ) {
		var b = blockPos.get(pos);
		if( b != null )
			return b;
		var b = new CodeBlock(pos, trapl);
		blockPos.set(pos, b);
		var i = pos;
		while( true ) {
			inline function goto(d, ?tl : Array<Int>) {
				var b2 = makeBlock(i + 1 + d, tl == null ? b.trap : tl);
				b2.prev.push(b);
				return b2;
			}
			if( i > pos && allBlocks.exists(i) ) {
				b.end = i - 1;
				b.next = [goto(-1)];
				break;
			}
			switch( control(i) ) {
			case CNo, CCall(_):
				i++;
				continue;
			case CRet:
				if( b.trap.length != 0 )
					throw "assert";
				b.end = i;
			case CJAlways(d):
				b.end = i;
				b.next = [goto(d)];
			case CSwitch(pl):
				b.end = i;
				b.next.push(goto(0));
				for( p in pl )
					b.next.push(goto(p));
			case CJCond(d):
				b.end = i;
				b.next = [goto(0), goto(d)];
			case CTry(d):
				b.end = i;
				var tl = b.trap.copy();
				tl.push(i+1+d);
				b.next = [goto(0, tl), goto(d)];
			case CThrow:
				b.end = i;
				if( b.trap.length > 0 ) {
					var tl = b.trap.copy();
					var p = tl.pop();
					b.next = [goto(p-1-i, tl)];
				}
			case CCatch:
				if( b.trap.length == 0 )
					throw "assert";
				var tl = b.trap.copy();
				var p = tl.pop();
				b.end = i;
				b.next = [goto(0, tl), goto(p-1-i, tl)];
			case CLabel:
				i++;
				b.loop = true;
				continue;
			}
			break;
		}
		return b;
	}

	public function control( i ) {
		return switch( fun.ops[i] ) {
		case OJTrue (_,d), OJFalse (_,d), OJNull (_,d), OJNotNull (_,d),
			OJSLt (_, _, d), OJSGte (_, _, d), OJSGt (_, _, d), OJSLte (_, _, d),
			OJULt (_, _, d), OJUGte (_, _, d), OJEq (_, _, d), OJNotEq (_, _, d),
			OJNotLt (_,_,d), OJNotGte (_,_,d):
				CJCond(d);
		case OJAlways(d):
			CJAlways(d);
		case OLabel:
			CLabel;
		case ORet(_):
			CRet;
		case OThrow(_), ORethrow(_):
			CThrow;
		case OSwitch(_,cases,_):
			CSwitch(cases);
		case OTrap(_,d):
			CTry(d);
		case OEndTrap(_):
			CCatch;
		case OCallClosure(_), OCallMethod(_), OCallThis(_):
			CCall(-1);
		case OCall0(_,idx), OCall1(_,idx,_), OCall2(_,idx,_,_), OCall3(_,idx,_,_,_), OCall4(_,idx,_,_,_), OCallN(_,idx,_):
			CCall(idx);
		default:
			CNo;
		}
	}

	inline function opFx( op : format.hl.Data.Opcode, read, write ) {
		switch( op ) {
		case OMov(d,a), ONeg(d,a), ONot(d,a):
			read(a); write(d);
		case OInt(d,_), OFloat(d,_), OBool(d,_), OBytes(d,_), OString(d,_), ONull(d):
			write(d);
		case OAdd(d,a,b), OSub(d,a,b), OMul(d,a,b), OSDiv(d,a,b), OUDiv(d,a,b), OSMod(d,a,b), OUMod(d,a,b), OShl(d,a,b), OSShr(d,a,b), OUShr(d,a,b), OAnd(d,a,b), OOr(d,a,b), OXor(d,a,b):
			read(a); read(b); write(d);
		case OIncr(a), ODecr(a):
			read(a); write(a);
		case OCall0(d,_):
			write(d);
		case OCall1(d,_,a):
			read(a); write(d);
		case OCall2(d,_,a,b):
			read(a); read(b); write(d);
		case OCall3(d,_,a,b,c):
			read(a); read(b); read(c); write(d);
		case OCall4(d,_,a,b,c,k):
			read(a); read(b); read(c); read(k); write(d);
		case OCallN(d,_,rl), OCallMethod(d,_,rl), OCallThis(d,_,rl):
			for( r in rl ) read(r); write(d);
		case OCallClosure(d,f,rl):
			read(f); for( r in rl ) read(r); write(d);
		case OStaticClosure(d,_):
			write(d);
		case OInstanceClosure(d, _, a), OVirtualClosure(d,a,_):
			read(a); write(d);
		case OGetGlobal(d,_):
			write(d);
		case OSetGlobal(_,a):
			read(a);
		case OField(d,a,_), ODynGet(d,a,_):
			read(a); write(d);
		case OSetField(a,_,b), ODynSet(a,_,b):
			read(a); read(b);
		case OGetThis(d,_):
			write(d);
		case OSetThis(_,a):
			read(a);
		case OJTrue(r,_), OJFalse(r,_), OJNull(r,_), OJNotNull(r,_):
			read(r);
		case OJSLt(a,b,_), OJSGte(a,b,_), OJSGt(a,b,_), OJSLte(a,b,_), OJULt(a,b,_), OJUGte(a,b,_), OJNotLt(a,b,_), OJNotGte(a,b,_), OJEq(a,b,_), OJNotEq(a,b,_):
			read(a); read(b);
		case OJAlways(_), OLabel:
			// nothing
		case OToDyn(d, a), OToSFloat(d,a), OToUFloat(d,a), OToInt(d,a), OSafeCast(d,a), OUnsafeCast(d,a), OToVirtual(d,a):
			read(a); write(d);
		case ORet(r), OThrow(r), ORethrow(r), OSwitch(r,_,_), ONullCheck(r):
			read(r);
		case OTrap(r,_):
			write(r);
		case OEndTrap(_):
			// nothing
		case OGetUI8(d,a,b), OGetUI16(d,a,b), OGetMem(d,a,b), OGetArray(d,a,b):
			read(a); read(b); write(d);
		case OSetUI8(a,b,c), OSetUI16(a,b,c), OSetMem(a,b,c), OSetArray(a,b,c):
			read(a); read(b); read(c);
		case ONew(d):
			write(d);
		case OArraySize(d, a), OGetType(d,a), OGetTID(d,a), ORef(d, a), OUnref(d,a), OSetref(d, a), OEnumIndex(d, a), OEnumField(d,a,_,_):
			read(a);
			write(d);
		case OType(d,_), OEnumAlloc(d,_):
			write(d);
		case OMakeEnum(d,_,rl):
			for( r in rl ) read(r);
			write(d);
		case OSetEnumField(a,_,b):
			read(a); read(b);
		case OAssert:
			// nothing
		case ORefData(r,d):
			read(d);
			write(r);
		case ORefOffset(r,r2,off):
			read(r2);
			read(off);
			write(r);
		case ONop:
			// nothing
		case OPrefetch(r,_,_):
			read(r);
		case OAsm(_,_,ropt):
			var r = ropt.getReg();
			if (r != null) {
				read(r);
				write(r);
			}
		}
	}

}

package hld;
import format.hl.Data;

private typedef GlobalAccess = {
	var sub : Map<String,GlobalAccess>;
	var gid : Null<Int>;
}

typedef ModuleProto = {
	var name : String;
	var size : Int;
	var padSize : Int;
	var largestField : Int;
	var fieldNames : Array<String>;
	var parent : ModuleProto;
	var fields : Map<String,{
		var name : String;
		var t : HLType;
		var offset : Int;
	}>;
	var methods : Map<String,{ t : HLType, index : Int, pindex : Int }>;
}

typedef ModuleEProto = Array<{ name : String, size : Int, params : Array<{ offset : Int, t : HLType }> }>;

class Module {

	public var code : format.hl.Data;
	var fileIndexes : Map<String, Int>;
	var functionsByFile : Map<Int, Array<{ f : HLFunction, ifun : Int, lmin : Int, lmax : Int }>>;
	var globalsOffsets : Array<Int>;
	var globalTable : GlobalAccess;
	var typeCache : Map<String, HLType>;
	var protoCache : Map<String,ModuleProto>;
	var eprotoCache : Map<String,ModuleEProto>;
	var functionRegsCache : Array<Array<{ t : HLType, offset : Int }>>;
	var align : Align;
	var reversedHashes : Map<Int,String>;
	var graphCache : Map<Int, CodeGraph>;
	var methods : Array<{ obj : ObjPrototype, field : String }>;
	var functionsIndexes : Map<Int,Int>;
	var isWindows : Bool;
	var closureContextId : Int = 0;

	public function new() {
		protoCache = new Map();
		eprotoCache = new Map();
		graphCache = new Map();
		functionsIndexes = new Map();
		functionRegsCache = [];
		methods = [];
		isWindows = Sys.systemName() == "Windows";
	}

	public function getMethodContext( fidx : Int ) {
		var f = code.functions[fidx];
		if( f == null ) return null;
		return methods[f.findex];
	}

	public function load( data : haxe.io.Bytes ) {
		code = new format.hl.Reader().read(new haxe.io.BytesInput(data));

		if( code.debugFiles == null )
			throw "Debug info not available in the bytecode";

		for( t in code.types )
			switch( t ) {
			case HObj(o), HStruct(o):
				for( f in o.proto )
					methods[f.findex] = { obj : o, field : f.name };
				for( b in o.bindings )
					methods[b.mid] = { obj : o, field : fetchField(o, b.fid).name };
			default:
			}

		// init files
		fileIndexes = new Map();
		for( i in 0...code.debugFiles.length ) {
			var f = code.debugFiles[i];
			fileIndexes.set(f, i);
			var low = f.split("\\").join("/").toLowerCase();
			fileIndexes.set(low, i);
			var fileOnly = low.split("/").pop();
			if( !fileIndexes.exists(fileOnly) ) {
				fileIndexes.set(fileOnly, i);
				if( StringTools.endsWith(fileOnly,".hx") )
					fileIndexes.set(fileOnly.substr(0, -3), i);
			}
		}

		functionsByFile = new Map();
		for( ifun in 0...code.functions.length ) {
			var f = code.functions[ifun];
			var files = new Map();
			functionsIndexes.set(f.findex, ifun);
			for( i in 0...f.debug.length >> 1 ) {
				var ifile = f.debug[i << 1];
				var dline = f.debug[(i << 1) + 1];
				var inf = files.get(ifile);
				if( inf == null ) {
					inf = { f : f, ifun : ifun, lmin : 1000000, lmax : -1 };
					files.set(ifile, inf);
					var fl = functionsByFile.get(ifile);
					if( fl == null ) {
						fl = [];
						functionsByFile.set(ifile, fl);
					}
					fl.push(inf);
				}
				if( dline < inf.lmin ) inf.lmin = dline;
				if( dline > inf.lmax ) inf.lmax = dline;
			}
		}
		for( i in 0...code.natives.length )
			functionsIndexes.set(code.natives[i].findex, code.functions.length + i);
	}

	function fetchField( o : ObjPrototype, fid : Int ) {
		var pl = [];
		var fcount = 0;
		while( true ) {
			pl.push(o);
			fcount += o.fields.length;
			if( o.tsuper == null ) break;
			switch( o.tsuper ) {
			case HObj(s): o = s;
			default: throw "assert";
			}
		}
		if( fid < 0 || fid >= fcount )
			return null;
		for( i in 0...pl.length ) {
			var o = pl[pl.length - i - 1];
			if( fid < o.fields.length )
				return o.fields[fid];
			fid -= o.fields.length;
		}
		return null;
	}

	public function init( align : Align ) {
		this.align = align;

		// init globals
		var globalsPos = 0;
		globalsOffsets = [];
		for( g in code.globals ) {
			globalsPos += align.padSize(globalsPos, g);
			globalsOffsets.push(globalsPos);
			globalsPos += align.typeSize(g);
		}

		globalTable = {
			sub : new Map(),
			gid : null,
		};
		function addGlobal( path : Array<String>, gid : Int ) {
			var t = globalTable;
			for( p in path ) {
				if( t.sub == null )
					t.sub = new Map();
				var next = t.sub.get(p);
				if( next == null ) {
					next = { sub : null, gid : null };
					t.sub.set(p, next);
				}
				t = next;
			}
			t.gid = gid;
		}
		typeCache = [];
		for( t in code.types )
			switch( t ) {
			case HObj(o), HStruct(o):
				typeCache.set(o.name, t);
				if( o.globalValue == null )
					continue;
				var path = o.name.split(".");
				addGlobal(path, o.globalValue);
				// Add abstract type's original name as alias
				var hasAlias = false;
				var apath = [path[0]];
				for( i in 1...path.length ) {
					var n0 = apath[apath.length-1];
					var n1 = path[i];
					if( n0.charCodeAt(0) == "_".code && StringTools.endsWith(n1, "_Impl_") ) {
						hasAlias = true;
						n1 = n1.substring(0, n1.length - 6);
						apath.pop();
					}
					apath.push(n1);
				}
				if( hasAlias ) addGlobal(apath, o.globalValue);
			case HEnum(e):
				if( e.name != null )
					typeCache.set(e.name, t);
				if( e.globalValue == null )
					continue;
				addGlobal(e.name.split("."), e.globalValue);
			default:
			}
	}

	public function getObjectProto( o : ObjPrototype, isStruct : Bool ) : ModuleProto {

		var p = protoCache.get(o.name);
		if( p != null )
			return p;

		var parent = o.tsuper == null ? null : switch( o.tsuper ) { case HObj(o), HStruct(o): getObjectProto(o,isStruct); default: throw "assert"; };
		var size = parent == null ? (isStruct ? 0 : align.ptr) : parent.size - parent.padSize;
		var largestField = parent == null ? size : parent.largestField;
		var fields = parent == null ? new Map() : [for( k in parent.fields.keys() ) k => parent.fields.get(k)];
		var mindex = 0;
		var methods = parent == null ? new Map() : [for( k => v in parent.methods ) k => {
			mindex++;
			v;
		}];

		for( f in o.fields ) {
			var pad = f.t;
			switch( pad ) {
			case HPacked(t):
				// align on packed largest field
				switch( t.v ) {
				case HStruct(o):
					var large = getObjectProto(o,true).largestField;
					var pad = size % large;
					if( pad != 0 )
						size += large - pad;
					if( large > largestField )
						largestField = large;
				default: throw "assert";
				}
			default:
				size += align.padStruct(size, pad);
			}
			fields.set(f.name, { name : f.name, t : f.t, offset : size });
			size += switch( f.t ) {
			case HPacked({ v : HStruct(o) }): getObjectProto(o,true).size;
			case HPacked(_): throw "assert";
			default:
				var sz = align.typeSize(f.t);
				if( sz > largestField ) largestField = sz;
				sz;
			}
		}

		var padSize = 0;
		if( largestField > 0 ) {
			var pad = size % largestField;
			if( pad != 0 ) {
				padSize = largestField - pad;
				size += padSize;
			}
		}

		for( m in o.proto ) {
			var idx = functionsIndexes.get(m.findex);
			var f = code.functions[idx];
			// parent methods are placed before child
			if( parent != null && m.pindex >= 0 ) {
				var v = parent.methods.get(m.name);
				if( v != null )
					methods.set(m.name, { t : f.t, index : v.index, pindex : m.pindex });
				else
					methods.set(m.name, { t : f.t, index : mindex++, pindex : m.pindex });
			} else {
				methods.set(m.name, { t : f.t, index : mindex++, pindex : m.pindex });
			}
		}

		p = {
			name : o.name,
			size : size,
			padSize : padSize,
			largestField: largestField,
			parent : parent,
			fields : fields,
			methods : methods,
			fieldNames : [for( o in o.fields ) o.name],
		};
		protoCache.set(p.name, p);

		return p;
	}

	public function getEnumProto( e : EnumPrototype ) : ModuleEProto {
		if( e.name == null )
			e.name = "$Closure:"+closureContextId++;
		var p = eprotoCache.get(e.name);
		if( p != null )
			return p;
		p = [];
		for( c in e.constructs ) {
			var size = align.ptr;
			size += align.padStruct(size, HI32);
			size += 4; // index
			var params = [];
			for( t in c.params ) {
				size += align.padStruct(size, t);
				params.push({ offset : size, t : t });
				size += align.typeSize(t);
			}
			p.push({ name : c.name, size : size, params : params });
		}
		eprotoCache.set(e.name, p);
		return p;
	}

	public function resolveGlobal( path : Array<String> ) {
		var g = globalTable;
		while( path.length > 0 ) {
			if( g.sub == null ) break;
			var p = path[0];
			var n = g.sub.get(p);
			if( n == null ) break;
			path.shift();
			g = n;
		}
		return g == globalTable || g.gid == null ? null : { type : code.globals[g.gid], offset : globalsOffsets[g.gid] };
	}

	public function resolveType( path : String ) {
		return typeCache.get(path);
	}

	public function resolveEnum( path : String ) {
		var et = typeCache.get(path);
		return switch( et ) {
		case HEnum(e): e;
		default: null;
		}
	}

	public function getFileFunctions( file : String ) {
		var ifile = fileIndexes.get(file);
		if( ifile == null )
			ifile = fileIndexes.get(file.split("\\").join("/").toLowerCase());
		if( ifile == null )
			return null;
		var functions = functionsByFile.get(ifile);
		if( functions == null )
			return null;
		return { functions : functions, fidx : ifile };
	}

	public function getBreaks( file : String, line : Int ) {
		var ffuns = getFileFunctions(file);
		if( ffuns == null )
			return null;

		var breaks = [];
		var funs = ffuns.functions;
		var matched = [];

		while( breaks.length == 0 && funs.length > 0 ) {
			for( f in funs ) {
				if( f.lmin > line || f.lmax < line ) continue;
				matched.push(f);
				var ifun = f.ifun;
				var f = f.f;
				var i = 0;
				var len = f.debug.length >> 1;
				var first = -1;
				/**
					Because of inlining or switch compilation we might have several instances
					of the same code duplicated within the same method, let's match continous
					groups
				**/
				while( i < len ) {
					var dfile = f.debug[i << 1];
					if( dfile != ffuns.fidx ) {
						i++;
						continue;
					}
					var dline = f.debug[(i << 1) + 1];
					if( dline != line ) {
						i++;
						continue;
					}
					var op = f.ops[i].getIndex();
					if( first == -1 || first == op ) {
						first = op;
						breaks.push({ ifun : ifun, pos : i });
					}
					// skip
					i++;
					while( i < len ) {
						var dfile = f.debug[i << 1];
						var dline = f.debug[(i << 1) + 1];
						if( dfile == ffuns.fidx && dline != line )
							break;
						i++;
					}
				}
			}
			// breakpoint not found ? move to the next line
			if( breaks.length == 0 ) {
				funs = matched;
				matched = [];
				line++;
			}
		}
		return { breaks : breaks, line : line };
	}

	public function isValid( fidx : Int, fpos : Int ) {
		var f = code.functions[fidx];
		var fid = f.debug[fpos << 1];
		return code.debugFiles[fid] != "?";
	}

	public function resolveSymbol( fidx : Int, fpos : Int ) {
		var f = code.functions[fidx];
		var fid = f.debug[fpos << 1];
		var fline = f.debug[(fpos << 1) + 1];
		return { file : code.debugFiles[fid], line : fline };
	}

	public function getFunctionRegs( fidx : Int ) {
		var regs = functionRegsCache[fidx];
		if( regs != null )
			return regs;
		var f = code.functions[fidx];
		var nargs = switch( f.t ) { case HFun(f): f.args.length; default: throw "assert"; };
		regs = [];

		var argsSize = 0;
		var size = 0;
		var floatRegs = 0, intRegs = 0;
		for( i in 0...nargs ) {
			var t = f.regs[i];
			if( align.is64 && !isWindows ) {
				var isFloat = t.match(HF32 | HF64);
				if( (isFloat ? ++floatRegs : ++intRegs) <= 6 ) {
					// stored in locals
					size += align.typeSize(t);
					size += align.padSize(size, t);
					regs[i] = { t : t, offset : -size };
					continue;
				}
			}
			regs[i] = { t : t, offset : argsSize + align.ptr * 2 };
			argsSize += align.stackSize(t);
		}
		for( i in nargs...f.regs.length ) {
			var t = f.regs[i];
			size += align.typeSize(t);
			size += align.padSize(size, t);
			regs[i] = { t : t, offset : -size };
		}
		functionRegsCache[fidx] = regs;
		return regs;
	}

	public function reverseHash( h : Int ) {
		if( reversedHashes == null ) {
			reversedHashes = new Map();
			for( s in code.strings )
				reversedHashes.set(s.hash(), s);
		}
		return reversedHashes.get(h);
	}

	public function getGraph( fidx : Int ) {
		var g = graphCache.get(fidx);
		if( g != null )
			return g;
		g = new CodeGraph(code, code.functions[fidx]);
		graphCache.set(fidx, g);
		return g;
	}

}

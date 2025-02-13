package hld;

enum ValueRepr {
	VUndef;
	VNull;
	VInt( i : Int );
	VInt64( i : haxe.Int64 );
	VFloat( v : Float );
	VBool( b : Bool );
	VPointer( v : Pointer );
	VString( v : String, p : Pointer );
	VClosure( f : FunRepr, d : Value, p : Pointer );
	VFunction( f : FunRepr, p : Pointer );
	VMethod( f : FunRepr, obj : Value, p : Pointer );
	VArray( t : HLType, length : Int, read : Int -> Value, p : Pointer );
	VMap( tkey : HLType, nkeys : Int, readKey : Int -> Value, readValue : Int -> Value, p : Pointer );
	VType( t : HLType );
	VEnum( c : String, values : Array<Value>, p : Pointer );
	VBytes( length : Int, read : Int -> Int, p : Pointer );
	VInlined( fields : Array<InlinedField> );
	VGuid( i : haxe.Int64, name : String );
}

enum FunRepr {
	FUnknown( p : Pointer );
	FIndex( i : Int, p : Pointer );
}

typedef InlinedField = { name : String, addr : Eval.VarAddress }

enum Hint {
	HNone;
	HHex; // v:h
	HBin; // v:b
	HPointer; // v:p
	HEscape; // v:s
	HReadBytes(t : HLType, pos : String); // v:UI8(0), v:UI16(0), v:I32(0), v:I64(0), v:F32(0), v:F64(0)
	HEnumFlags(t : String); // v:EnumFlags<T>, v:haxe.EnumFlags<T>
	HEnumIndex(t : String); // v:EnumIndex<T>
	HCdbEnum(t : String); // v:CDB<T>, v:CDBEnum<T> -- for CastleDB
}

@:structInit class Value {
	public var v : ValueRepr;
	public var t : HLType;
	@:optional public var hint : Hint = HNone;

	public static function parseHint( s : String ) : Hint {
		if( s == "h" )
			return HHex;
		if( s == "b" )
			return HBin;
		if( s == "p" )
			return HPointer;
		if( s == "s" )
			return HEscape;
		if( StringTools.startsWith(s,"UI8(") && StringTools.endsWith(s,")") )
			return HReadBytes(HUi8, s.substr(4, s.length - 5));
		if( StringTools.startsWith(s,"UI16(") && StringTools.endsWith(s,")") )
			return HReadBytes(HUi16, s.substr(5, s.length - 6));
		if( StringTools.startsWith(s,"I32(") && StringTools.endsWith(s,")") )
			return HReadBytes(HI32, s.substr(4, s.length - 5));
		if( StringTools.startsWith(s,"I64(") && StringTools.endsWith(s,")") )
			return HReadBytes(HI64, s.substr(4, s.length - 5));
		if( StringTools.startsWith(s,"F32(") && StringTools.endsWith(s,")") )
			return HReadBytes(HF32, s.substr(4, s.length - 5));
		if( StringTools.startsWith(s,"F64(") && StringTools.endsWith(s,")") )
			return HReadBytes(HF64, s.substr(4, s.length - 5));
		if( StringTools.startsWith(s,"EnumFlags<") && StringTools.endsWith(s,">") )
			return HEnumFlags(s.substr(10, s.length - 11));
		if( StringTools.startsWith(s,"haxe.EnumFlags<") && StringTools.endsWith(s,">") )
			return HEnumFlags(s.substr(15, s.length - 16));
		if( StringTools.startsWith(s,"EnumIndex<") && StringTools.endsWith(s,">") )
			return HEnumIndex(s.substr(10, s.length - 11));
		if( StringTools.startsWith(s,"CDB<") && StringTools.endsWith(s,">") )
			return HCdbEnum(s.substr(4, s.length - 5));
		if( StringTools.startsWith(s,"CDBEnum<") && StringTools.endsWith(s,">") )
			return HCdbEnum(s.substr(8, s.length - 9));
		return HNone;
	}

	static final INTBASE = "0123456789ABCDEF";
	public static function intStr( value : Int, base : Int ) : String {
		return int64Str(value, base, true);
	}

	public static function int64Str( value : haxe.Int64, base : Int, is32bit : Bool = false ) : String {
		if( base != 2 && base != 16 )
			throw "Unsupported int base " + base;
		var prefix = base == 2 ? "0b" : "0x";
		if( value == haxe.Int64.make(0,0) )
			return prefix + "0";
		var mask = base - 1;
		var shift = base == 2 ? 1 : 4;
		var maxlen = base == 2 ? (is32bit ? 32 : 64) : (is32bit ? 8 : 16);
		var s = "";
		var positive = value >= haxe.Int64.make(0,0);
		var abs = positive ? value : -(value+1); // 2's complement
		while( abs > 0 ) {
			var cur = positive ? (abs.low & mask) : (mask - abs.low & mask);
			s = INTBASE.charAt(cur) + s;
			abs = abs >> shift;
		}
		if( s.length < maxlen ) {
			var lchar = positive ? "0" : (base == 2 ? "1" : "F");
			s = StringTools.lpad(s, lchar, maxlen);
		}
		return prefix + s;
	}

	public static function parseInt64( str : String ) : haxe.Int64 {
		var value = haxe.Int64.make(0, 0);
		var base = 16;
		var shift = 4;
		var i = 0;
		if( StringTools.startsWith(str,"0x") ) {
			i += 2;
		}
		while( i < str.length ) {
			var c = str.charCodeAt(i);
			var cval = if( c >= '0'.code && c <= '9'.code ) c - '0'.code
				else if( c >= 'A'.code && c <= 'F'.code ) c - 'A'.code + 10
				else if( c >= 'a'.code && c <= 'f'.code ) c - 'a'.code + 10
				else
					break;
			value = (value << shift) + cval;
			i++;
		}
		return value;
	}

	static final GUIDBASE = "#&0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
	public static function int64GuidStr( value : haxe.Int64 ) : String {
		if( value == 0 )
			return "0";
		var s = "";
		for( i in 0...11 ) {
			if( i == 3 || i == 7 )
				s = '-' + s;
			s = GUIDBASE.charAt(value.low&63) + s;
			value = value >> 6;
		}
		return s;
	}

	public static function intEnumFlags( value : Int, eproto : format.hl.Data.EnumPrototype ) : String {
		var f = "";
		for( i in 0...eproto.constructs.length ) {
			if( (value >> i) % 2 == 1 )
				f += " | " + eproto.constructs[i].name;
		}
		if( f.length == 0 )
			f = "(noflag)";
		else
			f = f.substr(3);
		return f;
	}

	public static function intEnumIndex( value : Int, eproto : format.hl.Data.EnumPrototype ) : String {
		if( value < 0 || value >= eproto.constructs.length )
			throw "Out of range [0," + eproto.constructs.length + ")";
		return eproto.constructs[value].name;
	}

}

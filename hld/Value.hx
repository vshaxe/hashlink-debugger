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
}

enum FunRepr {
	FUnknown( p : Pointer );
	FIndex( i : Int );
}

typedef InlinedField = { name : String, addr : Eval.VarAddress }

enum Hint {
	HNone;
	HHex; // v:h
	HBin; // v:b
	HEnumFlags(t : String); // v:EnumFlags<T>
	HEnumIndex(t : String); // v:EnumIndex<T>
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
		if( StringTools.startsWith(s,"EnumFlags<") && StringTools.endsWith(s,">") )
			return HEnumFlags(s.substr(10, s.length - 11));
		if( StringTools.startsWith(s,"EnumIndex<") && StringTools.endsWith(s,">") )
			return HEnumIndex(s.substr(10, s.length - 11));
		return HNone;
	}

	static final INTBASE = "0123456789ABCDEF";
	public static function intStr( value : Int, base : Int ) : String {
		if( base < 2 || base > INTBASE.length )
			throw "Unsupported int base";
		var prefix = base == 2 ? "0b" : base == 16 ? "0x" : "";
		if( base == 10 || value == 0 )
			return prefix + value;
		var s = "";
		var abs = value >= 0 ? value : -value;
		while( abs > 0 ) {
			s = INTBASE.charAt(abs % base) + s;
			abs = Std.int(abs / base);
		}
		return (value < 0 ? "-" : "") + prefix + s;
	}

	public static function int64Hex( value : haxe.Int64 ) : String {
		var s = "";
		var abs = value >= haxe.Int64.make(0,0) ? value : -value;
		while( abs > 0 ) {
			s = INTBASE.charAt(abs.low & 15) + s;
			abs = abs >> 4;
		}
		return (value < 0 ? "-" : "") + "0x" + s;
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

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
	HHex;
	HBin;
	HEnumFlags(t : String);
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
		return HNone;
	}

	static final INTBASE = "0123456789ABCDEF";
	public static function int2Str( value : Int, base : Int ) : String {
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

	public static function int2EnumFlags( value : Int, eproto : format.hl.Data.EnumPrototype ) : String {
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

}

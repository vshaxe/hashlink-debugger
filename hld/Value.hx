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
	VInlined( fields : Array<{ name : String, addr : Eval.VarAddress }> );
}

enum FunRepr {
	FUnknown( p : Pointer );
	FIndex( i : Int );
}

@:structInit class Value {
	public var v : ValueRepr;
	public var t : HLType;
}

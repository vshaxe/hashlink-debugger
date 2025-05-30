package hld;

#if hl
abstract Pointer(hl.Bytes) to hl.Bytes {

	public var i64(get, never) : haxe.Int64;

	public inline function new(b) {
		this = b;
	}

	public inline function offset(pos:Int) : Pointer {
		return new Pointer(this.offset(pos));
	}

	public inline function sub( p : Pointer ) : Int {
		return this.subtract(p);
	}

	public function toInt() {
		return this.address().low;
	}

	inline function addr() {
		return this.address();
	}

	inline function get_i64() return this.address();

	public inline function isNull() {
		return this == null;
	}

	@:op(a > b) static function opGt( a : Pointer, b : Pointer ) : Bool {
		return a.addr() > b.addr();
	}
	@:op(a >= b) static function opGte( a : Pointer, b : Pointer ) : Bool {
		return a.addr() >= b.addr();
	}
	@:op(a < b) static function opLt( a : Pointer, b : Pointer ) : Bool {
		return a.addr() < b.addr();
	}
	@:op(a <= b) static function opLte( a : Pointer, b : Pointer ) : Bool {
		return a.addr() <= b.addr();
	}
	@:op(a == b) static function opEq( a : Pointer, b : Pointer ) : Bool {
		return a.addr() == b.addr();
	}
	@:op(a != b) static function opNeq( a : Pointer, b : Pointer ) : Bool {
		return a.addr() != b.addr();
	}

	public function toString() {
		var i = this.address();
		if( i.high == 0 )
			return "0x" + StringTools.hex(i.low);
		return "0x" + StringTools.hex(i.high) + StringTools.hex(i.low, 8);
	}

	public static function ofPtr( p : hl.Bytes ) : Pointer {
		return cast p;
	}

	public static function make( low : Int, high : Int ) {
		return new Pointer(hl.Bytes.fromAddress(haxe.Int64.make(high, low)));
	}

}
#else
abstract Pointer(haxe.Int64) to haxe.Int64 {

	public var i64(get, never) : haxe.Int64;

	public inline function new(b) {
		this = b;
	}

	inline function get_i64() return this;

	public inline function offset(pos:Int) : Pointer {
		return new Pointer(this + pos);
	}

	public function sub( p : Pointer ) : Int {
		var d = this - p.i64;
		if( d.high != d.low >> 31 )
			return d.high > 0 ? 0x7FFFFFFF : 0x80000000; // overflow
		return d.low;
	}

	public function toInt() {
		return this.low;
	}

	public inline function isNull() {
		return this == null || (this.low == 0 && this.high == 0);
	}

	@:op(a > b) static function opGt( a : Pointer, b : Pointer ) : Bool {
		return a.i64 > b.i64;
	}
	@:op(a >= b) static function opGte( a : Pointer, b : Pointer ) : Bool {
		return a.i64 >= b.i64;
	}
	@:op(a < b) static function opLt( a : Pointer, b : Pointer ) : Bool {
		return a.i64 < b.i64;
	}
	@:op(a <= b) static function opLte( a : Pointer, b : Pointer ) : Bool {
		return a.i64 <= b.i64;
	}
	@:op(a == b) static function opEq( a : Pointer, b : Pointer ) : Bool {
		return a.i64 == b.i64;
	}
	@:op(a != b) static function opNeq( a : Pointer, b : Pointer ) : Bool {
		return a.i64 != b.i64;
	}

	public function toString() {
		if( this.high == 0 )
			return "0x" + StringTools.hex(this.low);
		return "0x" + StringTools.hex(this.high) + StringTools.hex(this.low, 8);
	}

	public static function ofPtr( p : haxe.Int64 ) : Pointer {
		return cast p;
	}

	public static function make( low : Int, high : Int ) {
		return new Pointer(haxe.Int64.make(high, low));
	}

}
#end

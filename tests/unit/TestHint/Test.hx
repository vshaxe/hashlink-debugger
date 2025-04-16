class Test {
	static function main() {
		new Test(10);
	}

	public function new(count : Int) {
		var i : Int = 7764;
		var multilineString : String  = "AAA\nBBB";
		var bytes = new hl.Bytes(count);
		for( i in 0...count ) {
			bytes.setUI8(i, 1 + i);
		}
		var flags = new haxe.EnumFlags<MyFlag>();
		flags.set(BFlag);
		flags.set(CFlag);
		var ef = MyFlag.CFlag;
		var cArr = hl.CArray.alloc(Point, count);
		for( i in 0...count ) {
			cArr[i].x = 30+i;
			cArr[i].y = 130+i;
		}

		trace(i, multilineString, bytes, flags, ef, cArr);
	}
}

@:struct class Point {
	public var x : Int;
	public var y : Int;
	public function new( x : Int ) { this.x = x; this.y = x + 100; }
	public function toString() : String { return 'Point(x=$x, y=$y)'; }
}

enum MyFlag {
	AFlag;
	BFlag;
	CFlag;
	DFlag;
}

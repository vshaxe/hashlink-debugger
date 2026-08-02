class Test {
	static function main() {
		compute();
	}

	static function compute() {
		var a = id(11);
		var b = id(22);
		var c = id(33);
		var d = id(44);
		var e = id(55);
		var f = id(66);
		var g = id(77);
		var h = boom(1);
		trace(a + b + c + d + e + f + g + h);
	}

	static function boom( v : Int ) : Int {
		var x = id(v + 100);
		var y = id(v + 200);
		var z = id(v + 300);
		var fx = idf(v + 0.5);
		var fy = idf(v + 1.5);
		var fz = idf(v + 2.5);
		if( v > 0 ) throw "boom";
		return x + y + z + Std.int(fx + fy + fz);
	}

	static function id( v : Int ) {
		return v;
	}

	static function idf( v : Float ) {
		return v;
	}
}

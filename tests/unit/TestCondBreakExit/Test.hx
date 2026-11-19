class Test {
	static function twice( x : Int ) {
		var y = x * 2;
		return y;
	}

	static function inc( i : Int ) {
		return i + 1;
	}

	static function fail() {
		throw "err";
	}

	static function catchHere() {
		var x = 1;
		try {
			throw "err2";
		} catch( e : String ) {
			x = 2;
		}
		trace(x);
	}

	static function main() {
		var d = twice(2) + twice(4);
		try {
			fail();
		} catch( e : String ) {
		}
		var i = 0;
		while( i < 3 ) i = inc(i);
		catchHere();
		trace(d + i);
	}
}

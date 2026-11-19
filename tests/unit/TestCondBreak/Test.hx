class Test {
	static function rec( x : Int ) {
		if( x > 0 ) {
			trace(x);
			rec(x-1);
			trace(x);
		}
	}

	static function baz( x : Int ) {
		trace(x);
	}

	static function bar( x : Int ) {
		baz(x);
		trace(x);
		return x * 2;
	}

	static function down( x : Int ) {
		if( x > 0 )
			down(x-1);
		trace(x);
	}

	static function sameFrame() {
		var sum = 0;
		for( k in 0...3 ) {
			sum += k;
			trace(sum);
		}
		var i = 0;
		while( i < 3 ) i++;
		trace(sum + i);
	}

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
		rec(3);
		var a = bar(1);
		var b = bar(2);
		var c = bar(3);
		down(1);
		rec(2);
		sameFrame();
		var d = twice(a) + twice(b);
		try {
			fail();
		} catch( e : String ) {
		}
		var i = 0;
		while( i < 3 ) i = inc(i);
		catchHere();
		loopExit();
		trace(a + b + c + d + i);
	}

	static function loopExit() {
		var j = 0;
		while( j < 3 ) j = inc(j);
		trace(j + twice(99));
	}
}

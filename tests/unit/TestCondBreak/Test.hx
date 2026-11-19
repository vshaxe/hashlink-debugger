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

	static function main() {
		rec(3);
		var a = bar(1);
		var b = bar(2);
		var c = bar(3);
		down(1);
		trace(a + b + c);
	}
}

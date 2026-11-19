class Test {
	static function rec( x : Int ) {
		if( x > 0 ) {
			trace(x);
			rec(x-1);
			trace(x);
		}
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

	static function loopExit() {
		var j = 0;
		while( j < 3 ) j = inc(j);
		trace(j + twice(99));
	}

	static function main() {
		rec(2);
		sameFrame();
		loopExit();
	}
}

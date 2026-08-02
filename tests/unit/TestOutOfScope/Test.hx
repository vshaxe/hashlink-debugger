class Test {

	static var cond = false;

	static function main() {
		trace(pick(1) + shadow(1));
	}

	// `inner` and `other` are out of scope at the stop : they are only written on one of the
	// two paths reaching it, so they must not be listed - a listed one reads `undef`
	static function pick( v : Int ) {
		var total = v;
		if( cond ) {
			var inner = v * 2;
			total += inner;
		} else {
			var other = v * 3;
			total += other;
		}
		stop();
		return total + v;
	}

	// the loop shadows `id` : the break and the loop exit reach the stop with a different
	// register under that name, but the outer `id` is written on both paths and stays readable
	static function shadow( v : Int ) {
		var id = v + 10;
		for( i in 0...4 ) {
			var id = i * 100;
			if( id > 50 ) break;
		}
		stop();
		return id;
	}

	static function stop() {
	}
}

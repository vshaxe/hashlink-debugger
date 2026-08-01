class Test {
	static function inner( k : Int ) {
		var z = k * 2;
		trace(z); // our caller registers have been pushed by this frame
		return z;
	}
	static function middle( a : Int, b : Float ) {
		trace(inner(a + 1), a, b); // keep the call and the use of a/b on a single line
	}
	static function main() {
		middle(10, 1.5);
	}
}

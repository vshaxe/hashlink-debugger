class Test {
	static function foo( x : Int ) {
		if( x > 0 ) {
			trace(x);
			foo(x-1);
			trace(x);
		}
	}

	static function main() {
		foo(3);
	}
}

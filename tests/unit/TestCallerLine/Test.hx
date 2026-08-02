class Test {
	static function main() {
		outer();
	}

	static function outer() {
		inner();
	}

	static function inner() {
		stop();
	}

	static function stop() {
		use(0);
	}

	static function use( v : Int ) {
	}
}

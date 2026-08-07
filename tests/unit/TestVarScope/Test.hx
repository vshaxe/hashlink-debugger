class Test {
	static function main() {
		var a = get(1);
		trace(a);
		var b = get(2);
		trace(b);
		var c = get(3);
		trace(c);
		var d = get(4);
		trace(d);
		var e = get(5);
		trace(e);
		stop();
	}

	static function get( v : Int ) {
		return v * 10;
	}

	static function stop() {
	}
}

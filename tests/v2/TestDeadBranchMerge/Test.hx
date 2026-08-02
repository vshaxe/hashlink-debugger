class Test {

	static var shared : Test;

	public var parent : Test;

	function new() {
	}

	static function main() {
		shared = new Test();
		update();
		shared.parent = new Test();
		update();
	}

	// `fromRef` is assigned on both sides of a branch and never read afterwards : it is still in
	// scope at the stop, so it must resolve to what the branch that ran left, on either path
	static function update() {
		var fromRef = shared.parent != null;
		var n = get(7);
		stop();
		trace(n);
	}

	static function get( v : Int ) {
		return v * 10;
	}

	static function stop() {
	}

}

class Test {
	var classvar = 5;

	public function new() {
	}

	// `run` has no named argument, so `this` has no assign entry and the first local
	// is assigned at op 0 : the very position the argument is stored at
	function run() {
		var x = 12;
		var y = x + 1;
		trace(x, y, classvar);
	}

	static function main() {
		new Test().run();
	}
}

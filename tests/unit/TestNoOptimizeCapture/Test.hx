class Test {
	var classvar = 10;

	public function new() {
		var functionvar = 15;
		function bar(x) {
			classvar = functionvar + x;
			functionvar = x + 1;
		}
		bar(7);
		trace(functionvar);
		trace(classvar);
	}

	static function main() {
		new Test();
	}
}

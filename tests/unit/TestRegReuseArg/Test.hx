class Test {
	public function new() {
		foo(10, 11);
		var functionvar = 15;
		function bar(x, y) {
			var pt = new Point(x, y);
			trace(functionvar, pt.x, pt.y); // nargs=3, captured functionvar at r0, x=pt.x=r1, y=pt.y=r2
		}
		bar(12, 13);
		function bar2(x, y) {
			var pt = new Point(x, y);
			trace(pt.x, pt.y); // nargs=2, x=pt.x=r0, y=pt.y=r1
		}
		bar2(14, 15);
	}
	function foo(x : Int, y : Int) {
		var pt = new Point(x, y);
		trace(pt.x, pt.y);  // nargs=3, this at r0, x=pt.x=r1, y=pt.y=r2
	}

	static function main() {
		new Test();
	}
}

class Point {
	public var x : Int;
	public var y : Int;
	public inline function new(x = 0, y = 0) {
		this.x = x;
		this.y = y;
	}
}

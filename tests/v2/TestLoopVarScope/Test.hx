class Test {

	var values = new Map<String,Int>();
	var run : Void -> Void;

	function new() {
		values.set("a", 1);
		run = function() {
			var total = 0;
			for( key in values.keys() )
				total += values.get(key);
			{
				var scoped = total * 10;
				total += scoped;
			}
			var doubled = total * 2;
			stop();
			trace(total);
			trace(doubled);
		}
		run();
	}

	static function main() {
		new Test();
	}

	static function stop() {
	}
}

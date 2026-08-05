class Test {
	static function inner( k : Int ) {
		var z = k * 2;
		trace(z);
		return z;
	}
	static function outer( s : String, n : Int ) {
		var v = s + "!";
		var w = v + "?";
		var x = w + ".";
		var y = x + ",";
		var f : Int -> Dynamic = cast @:privateAccess hl.Api.makeVarArgs(function(args) return inner(args[0]));
		f(n);
		trace(v, w, x, y, s, n);
	}
	static function main() {
		outer("hello", 10);
	}
}

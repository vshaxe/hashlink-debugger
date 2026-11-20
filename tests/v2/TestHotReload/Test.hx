class Test {
	static function compute( x : Int ) {
		var y = x * #if reload2 100 #elseif reload 10 #else 2 #end;
		return y + #if reload 1 #else 0 #end;
	}

	static function main() {
		var a = compute(1);
		Sys.println(a);
		sys.io.File.copy("test-reload1.hl", "test.hl");
		Sys.println(hl.Api.checkReload());
		var b = compute(2);
		Sys.println(b);
		Sys.println(hl.Api.checkReload(@:privateAccess Sys.getPath("test-reload2.hl")));
		var c = compute(3);
		Sys.println(c);
	}
}

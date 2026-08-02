class Test {
	static function main() {
		var a = id(11);
		var b = id(22);
		var c = id(33);
		var d = id(44);
		var e = id(55);
		var f = id(66);
		var g = id(77);
		var dyn : Dynamic = inner;
		dyn(1);
		var bytes = new hl.Bytes(12);
		bytes.setI32(0, id(3));
		bytes.setI32(4, id(1));
		bytes.setI32(8, id(2));
		bytes.sortI32(0, 3, cmp);
		trace(a + b + c + d + e + f + g + bytes.getI32(0));
	}

	static function inner( v : Int ) {
		stop(v);
	}

	static function stop( v : Int ) {
		id(v);
	}

	static function cmp( x : Int, y : Int ) {
		id(x);
		return x - y;
	}

	static function id( v : Int ) {
		return v;
	}
}

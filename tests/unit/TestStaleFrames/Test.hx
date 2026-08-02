class Test {
	static var sum = 0;
	static var never : Bool;
	static var recurse : Int -> Void;

	static function deep( n : Int ) {
		if( n > 0 ) recurse(n - 1) else throw "unwind";
		sum += n;
	}

	static function wide( a0 : Int, a1 : Int, a2 : Int, a3 : Int, a4 : Int, a5 : Int, a6 : Int, a7 : Int, a8 : Int, a9 : Int, a10 : Int, a11 : Int, a12 : Int, a13 : Int, a14 : Int, a15 : Int, a16 : Int, a17 : Int, a18 : Int, a19 : Int, a20 : Int, a21 : Int, a22 : Int, a23 : Int, a24 : Int, a25 : Int, a26 : Int, a27 : Int, a28 : Int, a29 : Int ) {
		sum += a0 + a29;
	}

	static function scanned( n : Int ) {
		if( never ) wide(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29);
		use(n);
		sum += n;
	}

	static function use( n : Int ) {
		sum += n;
	}

	static function main() {
		recurse = deep;
		try deep(30) catch( e : Dynamic ) {}
		scanned(7);
	}
}

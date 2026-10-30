class Test {
	static var limit = 0;
	static var last : String;

	static function log( game : String, version : String, e : Dynamic ) {
		if( limit > 0 )
			return;
		var msg = game + version + Std.string(e);
		if( last == msg ) return;
		last = msg;
	}

	static function main() {
		log("game", "1.0", "a");
		limit = 1;
		log("game", "1.0", "b");
	}
}

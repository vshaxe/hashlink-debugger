class Test {
	static function main() {
		var thenOnly = getf(1.0);
		if( geti(1) > 0 ) {
			thenOnly = getf(7.0);
		}
		usef(thenOnly);
		var bothArms = getf(3.0);
		if( geti(0) > 0 ) {
			bothArms = getf(6.0);
		} else {
			bothArms = getf(8.0);
		}
		usef(bothArms);
		churn(1);
		stop();
	}

	static function churn( v : Int ) {
		var a = geti(v);
		var b = getf(v);
		use(a);
		usef(b);
	}

	static function geti( v : Int ) return v * 10;
	static function getf( v : Float ) return v * 1.5;
	static function use( v : Int ) {}
	static function usef( v : Float ) {}
	static function stop() {}
}

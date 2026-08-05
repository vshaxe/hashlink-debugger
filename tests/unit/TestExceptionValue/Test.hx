enum MyError {
	Failed( code : Int );
}

class Test {
	static var obj : { x : Int } = null;
	static function main() {
		try {
			throw Failed(42);
		} catch( e : MyError ) {
		}
		trace(obj.x);
	}
}

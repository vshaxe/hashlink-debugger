class Test {
	static function doThrow() {
		throw "from doThrow";
	}
	static function main() {
		try {
			doThrow();
		} catch(e:String) {
			trace(e); // break here should diaplay e
		}
	}
}

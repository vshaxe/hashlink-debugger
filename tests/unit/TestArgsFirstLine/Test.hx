class Test {
	static function main() {
		setField("obj", "x", 12);
	}

	static function setField( o : String, field : String, value : Int ) {
		var hash = field.length;
		trace(o, hash, value);
	}
}

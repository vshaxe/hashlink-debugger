class Test {
	static function main() {
		var raw = new hl.Bytes(200);
		for( i in 0...200 )
			raw.setUI8(i, i & 0xFF);
		raw.setUI8(0, 0x4D);
		raw.setUI8(1, 0xDB);
		raw.setUI8(2, 0);
		raw.setUI8(3, 0);
		var text = "hello";
		var buf = haxe.io.Bytes.ofString("hi");
		var count = 3;
		trace(raw.getUI8(0), text, buf.length, count);
	}
}

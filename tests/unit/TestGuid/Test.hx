class Test {
	static function main() {
		var id : hl.GUID = makeGUID(0xF1561985,0xF15008);
		var id2 : hl.GUID = makeGUID(0xF1561985,0xF15009);
		hl.Api.registerGUIDName(id, "SomeName");
		Sys.println(Std.string(id));
		Sys.println(Std.string(id2));
	}

	static function makeGUID(high,low) : hl.GUID {
		return haxe.Int64.make(high,low);
	}
}

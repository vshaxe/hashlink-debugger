enum SkillTarget {
	Target( s : String );
	Point( s : String );
}

class Test {
	static function make( k : Int, a : String, b : String ) : SkillTarget {
		return a != null ? Target(a) : b != null ? Point(b) : null;
	}

	static function main() {
		make(0, null, null);
		make(0, null, null);
	}
}

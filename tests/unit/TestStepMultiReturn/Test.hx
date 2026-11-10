enum SkillTarget {
	Target( s : String );
	Point( s : String );
}

class Test {
	static function make( a : String, b : String, c : String ) : SkillTarget {
		return a != null ? Target(a) : b != null ? Point(b) : c != null ? Point(c) : null;
	}

	static function main() {
		make(null, null, null);
		make(null, null, null);
	}
}

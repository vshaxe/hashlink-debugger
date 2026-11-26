class Node {
	public var id : Int;
	public var next : Node;
	public var name : String;
	public function new( id : Int, name : String ) {
		this.id = id;
		this.name = name;
	}
}

class Test {
	static function main() {
		var n = new Node(1, "first");
		same(n, 1);
		deep1(n);
	}

	static function same( a : Dynamic, b : Dynamic ) {
		return a == b;
	}

	static function deep1( n : Node ) {
		return deep2(n);
	}

	static function deep2( n : Node ) {
		return deep3(n);
	}

	static function deep3( n : Node ) {
		return boom(n);
	}

	static function boom( n : Node ) {
		var s = n.name;
		var a = n.id + 11;
		var b = n.id + 22;
		var o = n.next;
		var f = n.id + 0.5;
		var r = o.id;
		return s != null && a + b + r + o.id > 0 && f > 0;
	}
}

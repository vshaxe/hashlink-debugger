class Node {
	public var id : Int;
	public function new( id : Int ) {
		this.id = id;
	}
}

class Test {
	static function main() {
		var a = new Node(1);
		var b = new Node(2);
		var byName = new Map<String, Node>();
		byName.set("a", a);
		var refs = new Map<Node, Node>();
		refs.set(a, b);
		trace(byName.get("a").id + refs.get(a).id + a.id + b.id);
	}
}

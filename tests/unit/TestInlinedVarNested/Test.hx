// a scalarized value holding another one is reported as nested dotted locals ("ray.pos.x"), and its
// synthesized type has to nest the same way
class Vec {
	public var x : Float;
	public var y : Float;
	public var z : Float;
	public inline function new( x : Float, y : Float, z : Float ) {
		this.x = x;
		this.y = y;
		this.z = z;
	}
}

class Ray {
	public var pos : Vec;
	public var dir : Vec;
	public var len : Int;
	public inline function new( pos : Vec, dir : Vec, len : Int ) {
		this.pos = pos;
		this.dir = dir;
		this.len = len;
	}
}

class Test {

	static var total = 0.;

	static function main() {
		var ray = new Ray(new Vec(1., 2., 3.), new Vec(4., 5., 6.), 7);
		total += ray.pos.x + ray.dir.z + ray.len;
		total += ray.pos.y + ray.pos.z + ray.dir.x + ray.dir.y;
		trace(total);
	}
}

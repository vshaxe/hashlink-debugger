// an inline constructor makes the compiler scalarize the object into one local per field, named
// "pos.x", "pos.y", "pos.z" in the debug info: the debugger has to present them back as `pos`
class Vec {
	public var x : Float;
	public var y : Float;
	public var z : Float;
	public inline function new( x : Float, y : Float, z : Float ) {
		this.x = x;
		this.y = y;
		this.z = z;
	}
	public inline function length() {
		return Math.sqrt(x * x + y * y + z * z);
	}
	public inline function scaled( k : Float ) {
		return new Vec(x * k, y * k, z * k);
	}
}

class Test {

	static var total = 0.;

	static function main() {
		var potentialMove = new Vec(1., 2., 3.);
		// an inline call on a local introduces a `_this` temp that must not hide `potentialMove`
		var len = potentialMove.length();
		var scaled = potentialMove.scaled(2.);
		total += len + scaled.x;
		trace(total);
	}
}

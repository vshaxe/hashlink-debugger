class Vec {
	public var x : Float;
	public var y : Float;
	public var z : Float;
	public inline function new( x : Float, y : Float, z : Float ) {
		this.x = x;
		this.y = y;
		this.z = z;
	}
	public inline function sum() {
		var self = this;
		return self.x + self.y + self.z;
	}
}

class Test {

	static var total = 0.;

	static function usef( f : Float ) {
		total += f;
	}

	static inline function alias( v : Vec ) {
		var tmp = v;
		return tmp.x + tmp.y + tmp.z;
	}

	static function main() {
		var potentialMove = new Vec(1., 2., 3.);
		var viaArg = alias(potentialMove);
		var viaThis = potentialMove.sum();
		usef(viaArg + viaThis);
		trace(total);
	}
}

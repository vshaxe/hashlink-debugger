class Vec {
	public var x : Float;
	public var y : Float;
	public var z : Float;
	public function new( x : Float, y : Float, z : Float ) {
		this.x = x;
		this.y = y;
		this.z = z;
	}
	public function clone() {
		return new Vec(x, y, z);
	}
	public function add( v : Vec ) {
		return new Vec(x + v.x, y + v.y, z + v.z);
	}
	public function distanceSq( v : Vec ) {
		return (x - v.x) * (x - v.x) + (y - v.y) * (y - v.y) + (z - v.z) * (z - v.z);
	}
	public function load( v : Vec ) {
		x = v.x;
		y = v.y;
		z = v.z;
	}
}

class Test {

	static var usingLadder = false;
	static var ladderInvalid = false;
	static var ladderYaw = 1.;
	static var total = 0.;

	static function main() {
		update(0.5);
		trace(total);
	}

	// `pos` is assigned before a branch and twice inside a branch that is not taken here : each
	// assign stays live until the end of the scope, so at the merge the debugger must resolve
	// `pos` to the merged value and not to one of the branches
	static function update( dt : Float ) {
		var pos = getPosition();
		var prevPos = pos.clone();

		if( usingLadder ) {
			if( !ladderInvalid ) {
				var front = getDirection(1);
				pos = pos.add(front);
				var right = getDirection(2);
				pos = pos.add(right);
			}
		} else if( ladderYaw != 0 ) {
			ladderYaw = 0;
		}

		var front = getDirection(3);
		var up = getDirection(4);
		stop(); // breakpoint here : `pos` is still the value from getPosition()
		throttle(() -> orient(front.x, up.y));

		for( i in 0...2 )
			pos = pos.add(getDirection(5));

		if( pos.distanceSq(prevPos) < 1e-7 )
			pos.load(prevPos);

		throttle(() -> orient(pos.x, pos.y));
	}

	static function getPosition() {
		return new Vec(10., 20., 30.);
	}

	static function getDirection( v : Int ) {
		return new Vec(v, v * 2., v * 3.);
	}

	static function orient( a : Float, b : Float ) {
		total += a + b;
	}

	static function throttle( f : Void -> Void ) {
		f();
	}

	static function stop() {
	}
}

class Vec {
	public var x : Float;
	public function new( x : Float ) {
		this.x = x;
	}
}

class Test {

	static var total = 0.;

	static function main() {
		// two passes, so a register still holding the value of the first pass cannot pass for the
		// second one
		run(true);
		run(false);
	}

	// every local here is assigned in both arms of an `if`: the VM reports the merged value in a
	// single location, and the `noise` call in between may clobber it. Reading them on the line
	// after the call must still give the value of the arm that ran. Enough of them are live across
	// the call to exhaust the callee-saved registers, so some merged value has to land in a
	// call-clobbered one.
	static function run( pick : Bool ) {
		var o1 : Vec, o2 : Vec, o3 : Vec, o4 : Vec, o5 : Vec, o6 : Vec;
		var i1 : Int, i2 : Int, i3 : Int, i4 : Int, i5 : Int, i6 : Int;
		var f1 : Float, f2 : Float, f3 : Float, f4 : Float, f5 : Float, f6 : Float;
		var flag : Bool;
		if( pick ) {
			o1 = new Vec(1.); o2 = new Vec(2.); o3 = new Vec(3.);
			o4 = new Vec(4.); o5 = new Vec(5.); o6 = new Vec(6.);
			i1 = 11; i2 = 12; i3 = 13; i4 = 14; i5 = 15; i6 = 16;
			f1 = 0.1; f2 = 0.2; f3 = 0.3; f4 = 0.4; f5 = 0.5; f6 = 0.6;
			flag = true;
		} else {
			o1 = new Vec(101.); o2 = new Vec(102.); o3 = new Vec(103.);
			o4 = new Vec(104.); o5 = new Vec(105.); o6 = new Vec(106.);
			i1 = 111; i2 = 112; i3 = 113; i4 = 114; i5 = 115; i6 = 116;
			f1 = 1.1; f2 = 1.2; f3 = 1.3; f4 = 1.4; f5 = 1.5; f6 = 1.6;
			flag = false;
		}
		noise(3., 4., 5.);
		total += o1.x + o2.x + o3.x + o4.x + o5.x + o6.x;
		total += i1 + i2 + i3 + i4 + i5 + i6;
		total += f1 + f2 + f3 + f4 + f5 + f6 + (flag ? 1 : 0);
	}

	// enough arguments and arithmetic to use the volatile registers
	static function noise( a : Float, b : Float, c : Float ) {
		total += Math.sqrt(a * a + b * b + c * c);
	}
}

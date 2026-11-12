// Exercises the new-JIT (HLD2) variable tracking: jit->regs_track records
// (hl register, start, end, native reg) tuples that Eval.decodeNativeReg
// turns back into a CPU register / XMM register / RBP stack offset.
//
// IMPORTANT - what this test may and may not assert:
//
// A local is only recoverable while it is live. Once its last read has passed,
// the register is reclaimed and its tracking range ends, so the debugger
// correctly reports `undef`. Keeping locals readable until the end of their
// *lexical scope* needs an .hl format change (an end-of-scope index in the
// debug infos, so that in debug mode reg liveness can force a pseudo-read) and
// is compiler-side work that is not done yet.
//
// So every value probed below is kept genuinely live across its breakpoint by
// being consumed *after* the bp() call as well as before. `use()` is the sink
// that keeps them alive. Nothing here asserts on an out-of-liveness value.
//
// Breakpoints go on a dedicated bp() call rather than on a trace(), so the
// frame is observed at a stable point and not mid-expression.
class Test {

	static function bp() {}

	// sink: keeps values live past the breakpoint without printing anything
	static var sink : Float = 0;
	static function use( v : Float ) { sink += v; }

	// Ints in CPU registers.
	static function cpuRegs( a : Int, b : Int ) : Int {
		var sum = a + b;
		var diff = a - b;
		bp(); // BP1: expect a=10 b=3 sum=13 diff=7
		use(a); use(b); use(sum); use(diff);
		return sum + diff;
	}

	// Floats in XMM registers (native reg >= 0x40 on the VM side).
	static function fpuRegs( x : Float, y : Float ) : Float {
		var mul = x * y;
		var add = x + y;
		bp(); // BP2: expect x=1.5 y=4 mul=6 add=5.5
		use(x); use(y); use(mul); use(add);
		return mul + add;
	}

	// Mixed int / float / object live in the same frame at the same time.
	static function mixed( i : Int, f : Float, s : String ) : Int {
		var len = s.length;
		var scaled = f * 2.0;
		bp(); // BP3: expect i=5 f=2.5 s="hello" len=5 scaled=5
		use(i); use(f); use(s.length); use(len); use(scaled);
		return i + len + Std.int(scaled);
	}

	// Enough simultaneously-live ints to exhaust the register file, forcing some
	// locals into RBP-relative stack slots (the AAddr path of decodeNativeReg).
	static function spilled( n : Int ) : Int {
		var v0=n+0, v1=n+1, v2=n+2, v3=n+3, v4=n+4, v5=n+5;
		var v6=n+6, v7=n+7, v8=n+8, v9=n+9, v10=n+10, v11=n+11;
		var v12=n+12, v13=n+13, v14=n+14, v15=n+15, v16=n+16, v17=n+17;
		var v18=n+18, v19=n+19;
		bp(); // BP4: expect v0=100 v9=109 v15=115 v19=119
		use(v0); use(v9); use(v15); use(v19);
		return v0+v1+v2+v3+v4+v5+v6+v7+v8+v9
			+v10+v11+v12+v13+v14+v15+v16+v17+v18+v19;
	}

	// Two locals, each probed while live. `early` is still consumed after BP5
	// and `late` after BP6, so both are in range at their own breakpoint.
	static function liveRange( a : Int ) : Int {
		var early = a * 10;
		bp(); // BP5: expect early=30
		use(early);
		var late = a * 20;
		bp(); // BP6: expect late=60
		use(late);
		return late;
	}

	// Captured variable: the closure context lives in a native register and the
	// debugger must dereference it to reach the captured field.
	static function captured() {
		var outer = 42;
		var fn = function(x:Int) {
			bp(); // BP7: expect outer=42
			use(outer); use(x);
		};
		fn(7);
	}

	static function main() {
		trace(cpuRegs(10, 3));
		trace(fpuRegs(1.5, 4.0));
		trace(mixed(5, 2.5, "hello"));
		trace(spilled(100));
		trace(liveRange(3));
		captured();
		trace(sink);
	}
}

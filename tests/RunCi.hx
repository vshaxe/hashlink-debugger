class RunCi {
	static var MAX_TIME_PER_TEST : Float = 10;

	static function main() {
		var basePath = Sys.getCwd();
		var hlBin = "hl";
		var hlVer : String = null;
		var args = Sys.args();
		while( args.length > 0 ) {
			var a = args.shift();
			switch( a ) {
			case "--hl": hlBin = args.shift();
			case "--hl-ver": hlVer = args.shift();
			default:
				log('[ERROR] unknown argument $a');
				log("usage: hl RunCi.hl [--hl-ver <version>] [--hl <path to hl>]");
				Sys.exit(1);
			}
		}
		// targeting an older VM requires compiling everything, debugger included, against it
		var versionFlags = hlVer == null ? [] : ["-D", "hl-ver=" + hlVer];
		var debuggerHL = sys.FileSystem.absolutePath(basePath + "../debugger/debug" + (hlVer == null ? "" : "-" + hlVer) + ".hl");
		if( hlVer != null )
			buildDebugger(basePath, debuggerHL, versionFlags);
		// the v2 gate follows the VM that will run the tests, which without --hl-ver is whatever is on PATH
		var vmVer = hlVer != null ? hlVer : getVMVersion(hlBin);
		var errorCount = 0;

		for( dir in ["unit", "v2"] ) {
			var dirFlags = versionFlags;
			if( dir == "v2" ) {
				if( vmVer != null && compareVersion(vmVer, "2.0.0") < 0 ) {
					log('[SKIP] $dir tests (require hl 2, found $vmVer)');
					continue;
				}
				dirFlags = ["-D", "hl-ver=2.0.0"];
			}
			errorCount += runTests(basePath, dir, dirFlags, hlBin, debuggerHL);
		}

		changeDirectory(basePath);
		log('[INFO] all tests end, error count: $errorCount');
		if( errorCount > 0 ) {
			Sys.exit(1);
		}
	}

	static function runTests( basePath : String, dir : String, dirFlags : Array<String>, hlBin : String, debuggerHL : String ) {
		var errorCount = 0;
		var tests = sys.FileSystem.readDirectory(basePath + dir);
		for( test in tests ) {
			var fullPath = sys.FileSystem.absolutePath(basePath + dir + "/" + test);
			var platforms = try [for( p in sys.io.File.getContent(fullPath + "/platform.txt").split("\n") ) StringTools.trim(p)].filter(p -> p != "") catch( e ) null;
			if( platforms != null && platforms.indexOf(Sys.systemName()) < 0 ) {
				log('[SKIP] $test (runs on ${platforms.join(", ")})');
				continue;
			}
			log('[INFO] $test begin');
			changeDirectory(fullPath);
			var compileargs = ["--main", "Test", "-hl", "test.hl"].concat(dirFlags);
			try {
				var flags = sys.io.File.getContent(fullPath + "/compile.txt").split(" ");
				compileargs = compileargs.concat(flags);
			} catch( e ) {
			}
			trace("run haxe with " + compileargs);
			Sys.command("haxe", compileargs);
			// --cmd : the debuggee must run on the VM under test, not the `hl` on PATH
			var process = new sys.io.Process(hlBin, [debuggerHL, "--cmd", hlBin, "--input", "input.txt"]);
			var expectedOutput = normalize(sys.io.File.getContent(fullPath + "/output.txt"));
			var startingTime = haxe.Timer.stamp();
			var exitCode : Null<Int> = 0;
			while( true ) {
				exitCode = process.exitCode(false);
				var currentTime = haxe.Timer.stamp();
				if( exitCode != null || currentTime - startingTime > MAX_TIME_PER_TEST )
					break;
			}
			var output = normalize(process.stdout.readAll().toString());
			process.kill();
			process.close();
			if( exitCode == null ) {
				errorCount ++;
				log('[ERROR] $test: not terminated in $MAX_TIME_PER_TEST seconds, output:\n$output');
			} else if( exitCode != 0 ) {
				errorCount ++;
				log('[ERROR] $test: exitCode:$exitCode');
				log('[STDOUT] $output');
			} else if( output != expectedOutput ) {
				errorCount ++;
				log('[ERROR] $test: output:\n$output');
			} else {
				log('[SUCCESS] $test');
			}
		}
		return errorCount;
	}

	// reuse debugger.hxml so libs and class paths stay in sync, but retarget the output
	static function buildDebugger( basePath : String, output : String, versionFlags : Array<String> ) {
		var debuggerPath = sys.FileSystem.absolutePath(basePath + "../debugger");
		var args = [];
		for( a in ~/[ \t\r\n]+/g.split(sys.io.File.getContent(debuggerPath + "/debugger.hxml")) )
			if( a != "" ) args.push(a);
		var hl = args.indexOf("-hl");
		if( hl < 0 ) throw "no -hl target found in debugger.hxml";
		args.splice(hl, 2);
		args = args.concat(versionFlags).concat(["-hl", output]);
		changeDirectory(debuggerPath);
		trace("run haxe with " + args);
		if( Sys.command("haxe", args) != 0 ) {
			log('[ERROR] could not build the debugger for that version');
			Sys.exit(1);
		}
		changeDirectory(basePath);
	}

	static function getVMVersion( hlBin : String ) : Null<String> {
		return try {
			var p = new sys.io.Process(hlBin, ["--version"]);
			var v = StringTools.trim(p.stdout.readAll().toString());
			p.close();
			v == "" ? null : v;
		} catch( e ) null;
	}

	static function compareVersion( v1 : String, v2 : String ) {
		var p1 = v1.split(".");
		var p2 = v2.split(".");
		for( i in 0...3 ) {
			var d = (Std.parseInt(p1[i]) ?? 0) - (Std.parseInt(p2[i]) ?? 0);
			if( d != 0 ) return d;
		}
		return 0;
	}

	// the debugger prints CRLF on windows, and output.txt files have mixed line endings
	static function normalize(str : String) {
		return StringTools.replace(str, "\r\n", "\n");
	}

	static public function changeDirectory(path : String) {
		log('[CWD] Changing directory to $path');
		Sys.setCwd(path);
	}

	static public inline function log(msg : String) {
		Sys.println(msg);
	}
}

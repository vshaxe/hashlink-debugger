class RunCi {
	static var MAX_TIME_PER_TEST : Float = 2;

	static function main() {
		var basePath = Sys.getCwd();
		var debuggerHL = sys.FileSystem.absolutePath(basePath + "../debugger/debug.hl");
		var errorCount = 0;

		var tests = sys.FileSystem.readDirectory(basePath + "unit");
		for( test in tests ) {
			var fullPath = sys.FileSystem.absolutePath(basePath + "unit/" + test);
			log('[INFO] $test begin');
			changeDirectory(fullPath);
			var compileargs = ["--main", "Test", "-hl", "test.hl"];
			try {
				var flags = sys.io.File.getContent(fullPath + "/compile.txt").split(" ");
				compileargs = compileargs.concat(flags);
			} catch( e ) {
			}
			trace("run haxe with " + compileargs);
			Sys.command("haxe", compileargs);
			var process = new sys.io.Process("hl", [debuggerHL, "--input", "input.txt"]);
			var expectedOutput = sys.io.File.getContent(fullPath + "/output.txt");
			var startingTime = haxe.Timer.stamp();
			var exitCode : Null<Int> = 0;
			while( true ) {
				exitCode = process.exitCode(false);
				var currentTime = haxe.Timer.stamp();
				if( exitCode != null || currentTime - startingTime > MAX_TIME_PER_TEST )
					break;
			}
			var output = process.stdout.readAll().toString();
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

		changeDirectory(basePath);
		log('[INFO] all tests end, error count: $errorCount');
		if( errorCount > 0 ) {
			Sys.exit(1);
		}
	}

	static public function changeDirectory(path : String) {
		log('[CWD] Changing directory to $path');
		Sys.setCwd(path);
	}

	static public inline function log(msg : String) {
		Sys.println(msg);
	}
}

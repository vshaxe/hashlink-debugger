import js.lib.Promise;
import vscode.*;
import Utils;

class Extension {
	@:expose("activate")
	static function main(context:ExtensionContext) {
		Vscode.debug.registerDebugConfigurationProvider("hl", {resolveDebugConfiguration: resolveDebugConfiguration});
		Vscode.debug.registerDebugAdapterDescriptorFactory("hl", {createDebugAdapterDescriptor: createDebugAdapterDescriptor});
		Vscode.debug.onDidChangeActiveDebugSession(onDidChangeActiveDebugSession);
		context.subscriptions.push(Vscode.commands.registerCommand("hldebug.var.formatInt", args -> formatInt(args)));
	}

	static function resolveDebugConfiguration(folder:Null<WorkspaceFolder>, config:DebugConfiguration,
			?token:CancellationToken):ProviderResult<DebugConfiguration> {
		var config:DebugConfiguration & Arguments = cast config;

		if (Sys.systemName() == "Mac") {
			final hl = config.hl != null ? config.hl : 'hl';

			var hlVersion:String = js.node.ChildProcess.execSync('$hl --version');
			if(hlVersion <= "1.11.0") {
				final visitButton = "Get from GitHub";
				Vscode.window.showErrorMessage('Your version of Hashlink (${hlVersion}) does not support debugging on Mac. Install a newer version from here:', null, visitButton).then(function(choice) {
					if (choice == visitButton) {
						Vscode.env.openExternal(Uri.parse("https://github.com/HaxeFoundation/hashlink"));
					}
				});
				return null;
			}
			var validSignature = false;
			try {
				var entitlements:String = js.node.ChildProcess.execSync('codesign -d --entitlements - "$$(which $hl)"');
				validSignature = entitlements.indexOf("com.apple.security.get-task-allow") >= 0;
			} catch(ex: Dynamic) {}
			if(!validSignature) {
				Vscode.window.showErrorMessage('Your Hashlink executable is not properly codesigned. Run `make codesign_osx` during Hashlink installation.\n\nPath: ${hl}');
				return null;
			}
		}

		if (config.type == null) {
			return null; // show launch.json
		}
		return new Promise(function(resolve:DebugConfiguration->Void, reject) {
			var vshaxe:Vshaxe = Vscode.extensions.getExtension("nadako.vshaxe").exports;
			vshaxe.getActiveConfiguration().then(function(haxeConfig) {
				switch haxeConfig.target {
					case Hl(file):
						if (config.program == null) {
							config.program = file;
						}
						if (StringTools.endsWith(config.program, ".c")) {
							reject('Plase use a HashLink/JIT configuration (found "${config.program}" instead).');
							return;
						}
						config.classPaths = haxeConfig.classPaths.map(cp -> cp.path);
						resolve(config);

					case _:
						reject('Please use a Haxe configuration that targets HashLink (found target "${haxeConfig.target.getName().toLowerCase()}" instead).');
				}
			}, function(error) {
				reject("Unable to retrieve active Haxe configuration: " + error);
			});
		});
	}

	static function createDebugAdapterDescriptor(session: DebugSession, ?executable:DebugAdapterExecutable): ProviderResult<vscode.DebugAdapterDescriptor> {
		var config = Vscode.workspace.getConfiguration("hldebug");
		var isVerbose = config.get("verbose", false);
		var defaultPort = config.get("defaultPort", 6112);
		var connectionTimeout = config.get("connectionTimeout", 2);

		/*
		// Can be used to communicate with one built-in adapter during execution. Build with -lib format -lib hscript.
		if( HLAdapter.inst == null ) {
			HLAdapter.DEBUG = isVerbose;
			HLAdapter.DEFAULT_PORT = defaultPort;
			var adapter = new HLAdapter();
			return new vscode.DebugAdapterInlineImplementation(cast adapter);
		}
		*/

		if( executable == null )
			Vscode.window.showErrorMessage("No executable specified. Please check your configuration.");
		if( isVerbose )
			executable.args.push("--verbose");
		executable.args.push("--defaultPort");
		executable.args.push("" + defaultPort);
		executable.args.push("--connectionTimeout");
		executable.args.push("" + connectionTimeout);
		return executable;
	}

	static var currentSession : DebugSession = null;
	static function onDidChangeActiveDebugSession(session: Null<DebugSession>) {
		currentSession?.customRequest(CustomRequestCommand.OnSessionInactive);
		session?.customRequest(CustomRequestCommand.OnSessionActive);
		currentSession = session;
	}

	static function formatInt( args:VariableContext ) {
		var i = Std.parseInt(args.variable.value);
		if (i == null)
			return;
		var msg = args.variable.name + "(" + i + ") = 0x" + Utils.toString(i,16) + " = 0b" + Utils.toString(i,2);
		msg += "\n\n(You can also add `:h` `:b` suffix to variables in the watch section.)";
		Vscode.window.showInformationMessage(msg);
	}
}

import js.lib.Promise;
import vscode.*;
import Utils;

class Extension {
	@:expose("activate")
	static function main(context:ExtensionContext) {
		Vscode.debug.registerDebugConfigurationProvider("hl", {resolveDebugConfiguration: resolveDebugConfiguration});
		Vscode.debug.registerDebugAdapterDescriptorFactory("hl", {createDebugAdapterDescriptor: createDebugAdapterDescriptor});
		context.subscriptions.push(Vscode.commands.registerCommand("hldebug.var.formatInt", args -> HLAdapter.inst?.formatInt(args)));
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
				var entitlements:String = js.node.ChildProcess.execSync('codesign -d --entitlements - $$(which $hl)');
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
		HLAdapter.DEBUG = config.get("verbose", false);
		var adapter = new HLAdapter(config.get("defaultPort", 6112));
		return new vscode.DebugAdapterInlineImplementation(cast adapter);
	}
}

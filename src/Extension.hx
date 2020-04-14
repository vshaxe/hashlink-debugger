import js.lib.Promise;
import js.node.Fs;
import vscode.*;

class Extension {
	@:expose("activate")
	static function main(context:ExtensionContext) {
		Vscode.debug.registerDebugConfigurationProvider("hl", {resolveDebugConfiguration: resolveDebugConfiguration});
	}

	static function resolveDebugConfiguration(folder:Null<WorkspaceFolder>, config:DebugConfiguration,
			?token:CancellationToken):ProviderResult<DebugConfiguration> {
		var config:DebugConfiguration & Arguments = cast config;

		if (Sys.systemName() == "Mac" && !Fs.existsSync('/usr/local/lib/libhldebug.dylib')) {
			final visitButton = "Get from GitHub";
			Vscode.window.showErrorMessage("Your version of Hashlink does not support debugging on Mac. Install a newer version from here:", visitButton).then(function(choice) {
				if (choice == visitButton) {
					Vscode.env.openExternal(Uri.parse("https://github.com/HaxeFoundation/hashlink"));
				}
			});
			return null;
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
}

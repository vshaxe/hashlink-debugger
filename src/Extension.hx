import vscode.*;

class Extension {
	@:expose("activate")
	static function main(context:ExtensionContext) {
		Vscode.debug.registerDebugConfigurationProvider("hl", {resolveDebugConfiguration: resolveDebugConfiguration});
	}

	static function resolveDebugConfiguration(folder:Null<WorkspaceFolder>, config:DebugConfiguration,
			?token:CancellationToken):ProviderResult<DebugConfiguration> {
		if (Sys.systemName() == "Mac") {
			final visitButton = "Visit GitHub Issue";
			Vscode.window.showErrorMessage("HashLink debugging on macOS is not supported yet.", visitButton).then(function(choice) {
				if (choice == visitButton) {
					Vscode.env.openExternal(Uri.parse("https://github.com/vshaxe/hashlink-debugger/issues/28"));
				}
			});
			return null;
		}
		if (config.type == null) {
			return null; // show launch.json
		}
		return config;
	}
}

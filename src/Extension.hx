import vscode.*;

class Extension {
	@:expose("activate")
	static function main(context:ExtensionContext) {
		Vscode.debug.registerDebugConfigurationProvider("hl", {resolveDebugConfiguration: resolveDebugConfiguration});
	}

	static function resolveDebugConfiguration(folder:Null<WorkspaceFolder>, config:DebugConfiguration,
			?token:CancellationToken):ProviderResult<DebugConfiguration> {
		if (config.type == null) {
			return null; // show launch.json
		}
		return config;
	}
}

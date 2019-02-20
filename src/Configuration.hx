import vscode.*;

class Configuration {

	static function main() {
		Vscode.debug.registerDebugConfigurationProvider("hashlink", {resolveDebugConfiguration: resolveDebugConfiguration});
	}

	static function resolveDebugConfiguration(folder:Null<WorkspaceFolder>, config:DebugConfiguration, ?token:CancellationToken):ProviderResult<DebugConfiguration> {
		return config;
	}
	
}
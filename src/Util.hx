typedef Container = {
	var name : String;
	var variablesReference : Int;
	var ?expensive : Bool;
	var ?value : String;
}

typedef VariableContextCommandArg = {
	var sessionId : String;
	var container : Container;
	var variable : vscode.debugProtocol.DebugProtocol.Variable;
}

class Util {

	inline public static function toString(value:Int, base:Int):String {
		#if js
		return untyped value.toString(base);
		#end
	}
}

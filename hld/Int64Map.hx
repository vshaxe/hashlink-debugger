package hld;

// Map<Int64, V> does not work on JS, see https://github.com/HaxeFoundation/haxe/issues/9872
class Int64Map<T> extends haxe.ds.BalancedTree<haxe.Int64, T> {
	override function compare(k1:haxe.Int64, k2:haxe.Int64):Int {
		return if( k1 == k2 ) {
			0;
		} else if( k1 > k2 ) {
			1;
		} else {
			-1;
		}
	}
}

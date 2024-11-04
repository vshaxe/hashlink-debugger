class Test {
	static function main() {
		var iig = new InventoryItemGroup();
		var it = new Item();
		var data = {count : 1, k : it};
		var icon = iig.makeIcon(data);
		trace(icon);
	}
}
class SlotGroup<T> {
	public function new() {}
	public function makeIcon( item : SlotItem<T> ) : String {
		return "" + item;
	}
}
class InventoryItemGroup extends SlotGroup<Item> {
	override function makeIcon(item : SlotItem<Item>) {
		trace(item); // break here should diaplay _tmp_item
		return super.makeIcon(item); // break here should display item
	}
}
class Item {
	public function new() {}
}
abstract SlotItem<T>({ count : Int, k : T }) {
	@:from public inline static function from<T>( data : { count : Int, k : T } ) : SlotItem<T> {
		return cast data;
	}
}

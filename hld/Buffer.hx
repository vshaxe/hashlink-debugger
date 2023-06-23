package hld;

#if hl

@:forward(getI32, getUI8, setI32, setUI8, getUI16, getF32, getF64, setF64)
abstract Buffer(hl.Bytes) {

	public function new(size) {
		this = new hl.Bytes(size);
	}

	public function readStringUCS2( pos : Int, length : Int ) {
		return @:privateAccess String.fromUCS2(this.sub(pos,(length + 1) << 1));
	}

	public function readStringUTF8() {
		return @:privateAccess String.fromUTF8(this);
	}

	public function getPointer( pos : Int, align : Align ) {
		if( align.is64 )
			return Pointer.make(this.getI32(pos), this.getI32(pos + 4));
		return Pointer.make(this.getI32(pos), 0);
	}

	public function setPointer( pos : Int, v : Pointer, align : Align ) {
		if( align.is64 ) {
			var a = v.i64;
			this.setI32(pos, a.low);
			this.setI32(pos + 4, a.high);
		} else
			this.setI32(pos, v.toInt());
	}

}

#else


class Buffer {
	var buf : js.node.Buffer;

	public function new(?size : Int) {
		if(size != null)
			buf = js.node.Buffer.alloc(size);
	}

	public static function fromNodeBuffer(buffer : js.node.Buffer) : Buffer {
		var b = new Buffer();
		b.buf = buffer;
		return b;
	}

	public static function fromArrayBuffer(buffer : js.lib.ArrayBuffer) : Buffer {
		var b = new Buffer();
		b.buf = js.node.Buffer.from(buffer);
		return b;
	}

	public function getPointer( pos : Int, align : Align ) {
		if( align.is64 )
			return Pointer.make(getI32(pos), getI32(pos + 4));
		return Pointer.make(getI32(pos), 0);
	}

	public function setPointer( pos : Int, v : Pointer, align : Align ) {
		if( align.is64 ) {
			var a = v.i64;
			setI32(pos, a.low);
			setI32(pos + 4, a.high);
		} else
			setI32(pos, v.toInt());
	}

	public inline function getI32(pos) {
		return buf.readInt32LE(pos);
	}

	public inline function getUI8(pos) {
		return buf.readUInt8(pos);
	}

	public inline function getUI16(pos) {
		return buf.readUInt16LE(pos);
	}

	public inline function getF32(pos) {
		return buf.readFloatLE(pos);
	}

	public inline function getF64(pos) {
		return buf.readDoubleLE(pos);
	}

	public inline function setI32(pos,value) {
		buf.writeInt32LE(value, pos);
	}

	public inline function setF64(pos,value) {
		buf.writeDoubleLE(value, pos);
	}

	public inline function setUI16(pos,value) {
		buf.writeUInt16LE(value, pos);
	}

	public inline function setUI8(pos,value) {
		buf.writeUInt8(value, pos);
	}

	public function toBinaryString() : String {
		if( buf.length%2 == 1 ) {
			// bugfix with utf16 with odd size (1 char gets ignored)
			var nbuf = new js.node.Buffer(buf.length+1);
			buf.copy(nbuf);
			return nbuf.toString("utf16le");
		}
		return buf.toString("utf16le");
	}

	public function toNodeBuffer() : js.node.Buffer {
		return buf;
	}

	public static function fromBinaryString(str : String) : Buffer {
		var b = new Buffer();
		b.buf = js.node.Buffer.from(str, 'utf16le');
		return b;
	}

	public function readStringUCS2(pos, length) {
		var str = "";
		for( i in 0...length ) {
			var c = getUI16(pos);
			str += String.fromCharCode(c);
			pos += 2;
		}
		return str;
	}

	public function readStringUTF8() {
		var b = new haxe.io.BytesBuffer();
		var pos = 0;
		while( true ) {
			var c = getUI8(pos++);
			if( c == 0 ) break;
			b.addByte(c);
		}
		return b.getBytes().toString();
	}

}

#end
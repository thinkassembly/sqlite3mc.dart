// ignore_for_file: constant_identifier_names

import 'dart:typed_data';



const LOCK_TYPES_NONE = 0;
const LOCK_TYPES_SHARED = 1;
const LOCK_TYPES_RESERVED = 2;
const LOCK_TYPES_PENDING = 3;
const LOCK_TYPES_EXCLUSIVE = 4;

enum LockTypes {
  none(0),
  shared(1),
  reserved(2),
  pending(3),
  exclusive(4);

  final int _value;

  const LockTypes(this._value);

  @override
  String toString() {
    return _value.toString();
  }

  int toInt() {
    return _value;
  }
}

class Block {
  int pos;
  Uint8List data;
  int? offset;
  int? length;
  Block(this.pos,this.data);
}

extension LockTypesComparisonOperators on LockTypes {
  bool operator <(LockTypes other) {
    return _value < other._value;
  }

  bool operator <=(LockTypes other) {
    return _value <= other._value;
  }

  bool operator >(LockTypes other) {
    return _value > other._value;
  }

  bool operator >=(LockTypes other) {
    return _value >= other._value;
  }
}
int closestNumber(num n, num m) {
  return (m * (n / m).ceil()).toInt();
}
int getPageSize(Uint8List bufferView) {
  // See 1.3.2 on https://www.sqlite.org/fileformat.html The page size
  // is stored as a 2 byte integer at the 16th byte. It's stored as
  // big-endian so the first byte is the larger one. Combine it into a
  // single integer.
  var int1 = bufferView[16];
  var int2 = bufferView[17];
  return (int1 << 8) + int2;
//  return 4096;
}

bool isSafeToWrite(ByteBuffer? localData, ByteBuffer? diskData) {
  if (localData != null && diskData != null) {
    var localView = localData.asUint8List();
    var diskView = diskData.asUint8List();

    // See
    // https://github.com/sqlite/sqlite/blob/master/src/pager.c#L93-L96
    // (might be documented somewhere? I didn't see it this clearly in
    // the docs). At least one of these bytes change when sqlite3 writes
    // data. We can check this against our in-memory data to see if it's
    // safe to write (if something changes underneath us, it's not)
    for (var i = 24; i < 40; i++) {
      if (localView[i] != diskView[i]) {
        return false;
      }
    }
    return true;
  }

  // One of them is null, so it's only safe if to write if both are
  // null, otherwise they are different
  return localData == null && diskData == null;
}

class FileMeta {
  int blockSize =4096;
  int size;
  int? mode;

  FileMeta( this.size, this.blockSize);
}

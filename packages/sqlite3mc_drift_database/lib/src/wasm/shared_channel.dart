// ignore_for_file: constant_identifier_names

import 'dart:html';
import 'dart:typed_data';
import 'dart:convert';
import 'utils.dart';
import 'atomics.dart';

const FINALIZED = 0xdeadbeef;

const WRITEABLE = 0;
const READABLE = 1;

class Reader {
  final SharedArrayBuffer buffer;
  int initialOffset;
  bool useAtomics;
  bool stream;
  bool debug;
  String? name;
  int offset = 0;
  int? peekOffset;
  late Int32List _atomicView;

  Reader(this.buffer, {this.initialOffset = 4, this.useAtomics = true, this.stream = true, this.debug = false, this.name}) {
    _atomicView = createSharedArray(buffer);

    offset = initialOffset;
  }

  void waitWrite(String name, { num? timeout}) {
    if (useAtomics) {
      //this.log(`waiting for ${name}`);

      while (Atomics.load(_atomicView, 0) == WRITEABLE) {
        if (timeout != null) {
          if (Atomics.wait(_atomicView, 0, WRITEABLE, timeout) == 'timed-out') {
            throw Exception('timeout');
          }
        }

        Atomics.wait(_atomicView, 0, WRITEABLE, 500);
      }

      //this.log(`resumed for ${name}`);
    } else {
      if (_atomicView[0] != READABLE) {
        throw Exception('`waitWrite` expected array to be readable');
      }
    }
  }

  void flip() {
    if (useAtomics) {
      var prev = Atomics.compareExchange(_atomicView, 0, READABLE, WRITEABLE);

      if (prev != READABLE) {
        throw Exception('Read data out of sync! This is disastrous');
      }

      Atomics.notify(_atomicView, 0);
    } else {
      _atomicView[0] = WRITEABLE;
    }

    offset = 4;
  }

  bool done() {
    waitWrite('done');

    // var dataView =  DataView(this.buffer, this.offset);

    var done = Atomics.load(_atomicView.buffer.asUint32List(offset), 0) == FINALIZED;

    if (done) {
      //   this.log('done');
      flip();
    }

    return done;
  }

  String? string({num? timeout}) {
    waitWrite('string', timeout: timeout);
    var byteLength = _int32();
    var uint8StringBytes = _atomicView.buffer.asUint8List(8, byteLength);
    var str = utf8.decode(uint8StringBytes);
    offset += closestNumber(byteLength, 4);

    if (peekOffset == null) {
      flip();
    }
    return str;
  }

  int _int32() {
    var byteLength = 4;

    var num = Atomics.load(_atomicView.buffer.asInt32List(offset), 0);

    offset += byteLength;
    return num;
  }

  int int32() {
    waitWrite('int32');
    var num = _int32();
    //this.log('int32', num);

    if (peekOffset == null) {
      flip();
    }
    return num;
  }

  Uint8List bytes() {
    waitWrite('bytes');

    var byteLength = _int32();

    var bytes = Uint8List(byteLength);
    bytes.setAll(0, _atomicView.buffer.asUint8List(offset, byteLength));
    /*bytes.buffer.asUint8List().setAll(0,  );
    new Uint8Array(bytes).set(
        new Uint8Array(this.buffer, this.offset, byteLength)
    );*/ //    this.log('bytes', bytes);

    offset += byteLength;

    if (peekOffset == null) {
      flip();
    }
    return bytes;
  }
}

class Writer {
  SharedArrayBuffer buffer;
  int initialOffset;
  bool useAtomics;
  bool stream;
  bool debug;
  String? name;
  int offset = 0;
  int? peekOffset;
  late Int32List _atomicView;

  Writer(this.buffer, {this.initialOffset = 4, this.useAtomics = true, this.stream = true, this.debug = false, this.name}) {
    offset = initialOffset;
    _atomicView = createSharedArray(buffer);

    if (useAtomics) {
      // The buffer starts out as writeable
      Atomics.store(_atomicView, 0, WRITEABLE);
    } else {
      _atomicView[0] = WRITEABLE;
    }
  }

  void waitRead(String name) {
    if (useAtomics) {
      var prev = Atomics.compareExchange(createSharedArray(buffer), 0, WRITEABLE, READABLE);

      if (prev != WRITEABLE) {
        throw Exception('Wrote something into unwritable buffer! This is disastrous');
      }
      Atomics.notify(_atomicView.buffer.asInt32List(), 0);

      while (Atomics.load(_atomicView, 0) == READABLE) {
        Atomics.wait(_atomicView, 0, READABLE, 500);
      }
    } else {
      _atomicView[0] = READABLE;
    }

    offset = 4;
  }

  void finalize() {
    Atomics.store(_atomicView.buffer.asUint32List(offset), 0, FINALIZED);
    waitRead('finalize');
  }

  void string(String str) {
    var stringBuffer = utf8.encode(str);
    _int32(stringBuffer.length);
    _atomicView.buffer.asUint8List(8).setAll(0, stringBuffer);
    offset += closestNumber(stringBuffer.length, 4);
    waitRead('string');
  }

  void _int32(int num) {
    var byteLength = 4;

    Atomics.store(_atomicView.buffer.asInt32List(offset), 0, num);

    offset += byteLength;
  }

  void int32(int num) {
    _int32(num);
    waitRead('int32');
  }

  void bytes(Uint8List inBuffer) {
    var byteLength = inBuffer.length;
    _int32(byteLength);
    _atomicView.buffer.asUint8List(offset).setAll(0, inBuffer);

    offset += byteLength;
    waitRead('bytes');
  }
}

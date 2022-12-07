import 'dart:html';
import 'dart:typed_data';

import 'package:js/js.dart';

import 'utils.dart';

import 'atomics.dart';
import 'shared_channel.dart';

@JS("startWorkerJsShim")
external  MessagePort startWorkerJsShim(Object reader, Object writer, Object initSemaphore);



MessagePort startWorker(Reader reader, Writer writer, SharedArrayBuffer initSemaphore) {
  return  startWorkerJsShim(reader.buffer, writer.buffer, initSemaphore);
}

int positionToKey(int pos, int blockSize) {
  // We are forced to round because of floating point error. `pos`
  // should always be divisible by `blockSize`
  return (pos / blockSize).round();
}

class FileOps {
  String filename;
  late final Writer writer;
  late final Reader reader;
  late final SharedArrayBuffer initSemaphore;
  late final Int32List initSemaphoreArray;
  final bool debug;
  FileOps({this.filename = "app.db", this.debug = false}) {
    SharedArrayBuffer argBuffer = SharedArrayBuffer(4096 * 9);
    writer = Writer(argBuffer, name: 'args (main worker)', debug: debug);

    SharedArrayBuffer resultBuffer = SharedArrayBuffer(4096 * 9);
    reader = Reader(resultBuffer, name: 'results (main worker)', debug:debug);

    initSemaphore = SharedArrayBuffer(4);
    initSemaphoreArray = createSharedArray(initSemaphore);
    initSemaphoreArray[0] = 0;
  }


  // TODO: This should be renamed to `getDatabaseName`
  String getStoreName() {
    return filename.replaceAll(RegExp(r'///g'), '-');
  }

  void open() {
    // TODO: We could pool workers and reuse them so opening files
    // isn't as slow
     startWorker(reader, writer, initSemaphore);
    Atomics.wait(initSemaphoreArray, 0, 0);
  }

  dynamic invokeWorker(String method, dynamic args) {
    /*  if (reader == null || writer == null) {
      throw Exception('Attempted ${method} on ${filename} but file not open');
    }*/

    switch (method) {
      case 'readBlocks':
        {
          var name = args["name"] as String;
          List<int> positions = args["positions"] as List<int>;
          int blockSize = args["blockSize"] as int;
          var res = <Block>[];
          for (var pos in positions) {
            writer.string('readBlock');
            writer.string(name);
            writer.int32(positionToKey(pos, blockSize));
            writer.finalize();
            var data = reader.bytes();
            reader.done();
            res.add(Block(pos, data.isEmpty == true ? Uint8List(blockSize) : data));
          }

          return res;
        }

      case 'writeBlocks':
        {
          var name = args["name"] as String;
          List<Block> writes = args["writes"] as List<Block>;
          int blockSize = args["blockSize"] as int;
          writer.string('writeBlocks');
          writer.string(name);
          for (var write in writes) {
            writer.int32(positionToKey(write.pos, blockSize));
            writer.bytes(write.data);
          }
          writer.finalize();

          var res = reader.int32();
          reader.done();
          return res;
        }

      case 'readMeta':
        {
          writer.string('readMeta');

          writer.string(args["name"] as String);

          writer.finalize();

          var size = reader.int32();

          var blockSize = reader.int32();
          reader.done();
          return size == -1 ? null : FileMeta(size, blockSize); // {"size": size, "blockSize": blockSize};
        }

      case 'writeMeta':
        {
          String name = args["name"] as String;
          Map<String, dynamic> meta = args["meta"] as Map<String, dynamic>;
          writer.string('writeMeta');
          writer.string(name);
          writer.int32(meta["size"] as int);
          // writer.int32(meta.blockSize);
          writer.finalize();

          var res = reader.int32();
          reader.done();
          return res;
        }

      case 'closeFile':
        {
          writer.string('closeFile');
          writer.string(args["name"] as String);
          writer.finalize();

          var res = reader.int32();
          reader.done();
          return res;
        }

      case 'lockFile':
        {
          writer.string('lockFile');
          writer.string(args["name"] as String);
          writer.int32(args["lockType"] as int);
          writer.finalize();

          var res = reader.int32();
          reader.done();
          return res == 0;
        }

      case 'unlockFile':
        {
          writer.string('unlockFile');
          writer.string(args["name"] as String);
          writer.int32(args["lockType"] as int);
          writer.finalize();

          var res = reader.int32();
          reader.done();
          return res == 0;
        }
    }

    return null;
  }

  bool lock(int lockType) {
    return invokeWorker('lockFile', {"name": getStoreName(), "lockType": lockType}) as bool;
  }

  bool unlock(int lockType) {
    return invokeWorker('unlockFile', {"name": getStoreName(), "lockType": lockType}) as bool;
  }

  dynamic delete() {
    // Close the file if it's open
    //  if (reader != null || writer != null) {
    close();
    //  }
    final self = DedicatedWorkerGlobalScope.instance;

    // We delete it here because we can't do it in the worker; the
    // worker is stopped when the file closes. If we didn't do that,
    // workers would leak in the case of closing a file but not
    // deleting it. We could potentially restart the worker here if
    // needed, but for now just assume that the deletion is a success
    var req = self.indexedDB?.deleteDatabase(getStoreName());
    req?.then((value) => null).onError((error, stackTrace) {});
  }

  void close() {
    invokeWorker('closeFile', {"name": getStoreName()});

    //   worker = null;
  }

  FileMeta? readMeta() {
    return invokeWorker('readMeta', {"name": getStoreName()}) as FileMeta?;
  }

  dynamic writeMeta(Map<String, dynamic> meta) {
    return invokeWorker('writeMeta', {"name": getStoreName(), "meta": meta});
  }

  List<Block> readBlocks(List<int> positions, int blockSize) {
    return invokeWorker('readBlocks', {"name": getStoreName(), "positions": positions, "blockSize": blockSize}) as List<Block>;
  }

  dynamic writeBlocks(List<Block> writes, int blockSize) {
    return invokeWorker('writeBlocks', {"name": getStoreName(), "writes": writes, "blockSize": blockSize});
  }
}

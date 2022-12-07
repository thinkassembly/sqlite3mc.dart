import 'dart:math';
import 'dart:typed_data';

import 'utils.dart';
import 'package:collection/collection.dart';

import 'file_ops.dart';

List<int> range(int start, int end, int step) {
  List<int> r = [];
  for (var i = start; i <= end; i += step) {
    r.add(i);
  }
  return r;
}

List<int> getBoundaryIndexes(int blockSize, int start, int end) {
  var startC = start - (start % blockSize);
  var endC = end - 1 - ((end - 1) % blockSize);

  return range(startC, endC, blockSize);
}

Uint8List readChunks(List<Block> chunks, int start, int end) {
  var buffer = Uint8List(end - start);
  var bufferView = buffer.buffer.asUint8List();

  var cursor = 0;
  for (var i = 0; i < chunks.length; i++) {
    var chunk = chunks[i];

    var pos = chunk.pos;
    var data = chunk.data;

    var cstart = 0;
    var cend = data.lengthInBytes;

    if (start > pos) {
      cstart = start - pos;
    }
    if (end < pos + data.lengthInBytes) {
      cend = end - pos;
    }

    if (cstart > data.lengthInBytes || cend < 0) {
      continue;
    }

    var len = cend - cstart;

    bufferView.setAll(pos - start + cstart, data.buffer.asUint8List(cstart, len));
    cursor += len;
  }
  return buffer;
}

List<Block> writeChunks(Uint8List bufferView, int blockSize, int start, int end) {
  List<int> indexes = getBoundaryIndexes(blockSize, start, end);

  int cursor = 0;

  return indexes
      .map<Block?>((index) {
        var cstart = 0;
        var cend = blockSize;
        if (start > index && start < index + blockSize) {
          cstart = start - index;
        }
        if (end > index && end < index + blockSize) {
          cend = end - index;
        }

        var len = cend - cstart;
        var chunkBuffer = Uint8List(blockSize);

        if (start > index + blockSize || end <= index) {
          return null;
        }

        var off = bufferView.offsetInBytes + cursor;

        var available = bufferView.buffer.lengthInBytes - off;
        if (available <= 0) {
          return null;
        }
        var readLength = min(len, available);

        chunkBuffer.setAll(cstart, Uint8List.fromList(bufferView.buffer.asUint8List(off, readLength)));

        cursor += readLength;
        var block = Block(index, chunkBuffer);
        block.offset = cstart;
        block.length = readLength;
        return block;
      })
      .whereNotNull()
      .toList();
}

class File {
  String filename;
  Map<int, Block> buffer = {};
  FileOps ops;
  FileMeta? meta;
  bool _metaDirty = false;
  bool writeLock = false;
  int openHandles = 0;

  File(this.filename, this.ops, this.meta);

  void bufferChunks(List<Block> chunks) {
    for (var i = 0; i < chunks.length; i++) {
      var chunk = chunks[i];
      buffer.update(chunk.pos, (value) => chunk, ifAbsent: () => chunk);
    }
  }

  FileMeta? open() {
    openHandles++;

    // Don't open the file again if it's already open
    if (openHandles == 1) {
      ops.open();
      FileMeta? newMeta = ops.readMeta();
      // It's possible that `setattr` has already been called if opening
      // the file in a mode that truncates it to 0
      if (newMeta == null) {
        newMeta ??= FileMeta(0,0);

        meta = newMeta;
      } else {
        meta = newMeta;
      }
    }

    return meta;
  }

  void close() {
    fsync();

    openHandles = max(openHandles - 1, 0);

    // Only close it if there are no existing open handles
    if (openHandles == 0) {
      ops.close();
    }
  }

  void delete() {
    ops.delete();
  }

  List<Block>? load(List<int> indexes) {
    Map<String, dynamic> status = indexes.fold(
      {"chunks": <Block>[], "missing": <int>[]},
      (Map<String, dynamic> acc, int b) {
        var inMemory = buffer[b];
        if (inMemory != null) {
          acc["chunks"].add(inMemory);
        } else {
          acc["missing"].add(b);
        }
        return acc;
      },
    );

    List<Block> missingChunks = [];

    if ((status["missing"] as List<int>).isNotEmpty) {
      missingChunks = ops.readBlocks(status["missing"] as List<int>, meta!.blockSize);
    }

    (status["chunks"] as List<Block>).addAll(missingChunks);

    return status["chunks"] as List<Block>;
  }

  int read(Uint8List bufferView, int offset, int length, int position) {

    if (length <= 0) {
      return 0;
    }
    if (position < 0) {
      // TODO: is this right?
      return 0;
    }
    if (position >= (meta!.size)) {
      var view = bufferView.buffer.asUint8List(offset);
      for (var i = 0; i < length; i++) {
        view[i] = 0;
      }
      return 0;
      //return length;
    }

    position = max(position, 0);
    var dataLength = min(length, (meta!.size) - position);

    var start = position;
    var end = position + dataLength;

    List<int> indexes = getBoundaryIndexes(meta!.blockSize, start, end);
    List<Block>? chunks = load(indexes);
    var readBuffer = readChunks(chunks!, start, end);
    if (bufferView.lengthInBytes - offset < readBuffer.lengthInBytes) {
      throw Exception('Buffer given to `read` is too small');
    }
    //   var view = bufferView.asUint8List();

    bufferView.setRange(0, readBuffer.length, readBuffer);

    return length;
  }

  int write(Uint8List bufferView, int offset, int length, int position) {
    // console.log('writing', this.filename, offset, length, position);

    if (meta?.blockSize == 0) {
      // We don't have a block size yet (an empty file). The first
      // write MUST be the beginning of the file. This is a new file
      // and the first block contains the page size which we need.
      // sqlite will write this block first, and if you are directly
      // writing a db file to disk you can't write random parts of it.
      // Just write the whole thing and we'll get the first block
      // first.

      var pageSize = getPageSize(bufferView.buffer.asUint8List(bufferView.offsetInBytes + offset));

      // Page sizes must be a power of 2 between 512 and 65536.
      // These was generated by doing `Math.pow(2, N)` where N >= 9
      // and N <= 16.
      if (![512, 1024, 2048, 4096, 8192, 16384, 32768, 65536].contains(pageSize)) {
        throw Exception('File has invalid page size. (the first block of a new file must be written first)');
      }

      setattr({"blockSize": 4096});
    }

    var buffer = bufferView;

    if (length <= 0) {
      return 0;
    }
    if (position < 0) {
      return 0;
    }
    if (buffer.lengthInBytes == 0) {
      return 0;
    }

    length = min(length, buffer.lengthInBytes - offset);

    var writes = writeChunks(buffer, meta!.blockSize, position, position + length);
    // Find any partial chunks and read them in and merge with
    // existing data
    var partialWrites = <Block>[];
    var fullWrites = <Block>[];
    for (var i = 0; i < writes.length; i++) {
      if (writes[i].length != meta?.blockSize) {
        partialWrites.add(writes[i]);
      } else {
        fullWrites.add(writes[i]);
      }
    }
    var reads = <Block>[];

    if (partialWrites.isNotEmpty) {
      reads = load(partialWrites.map((w) {
        return w.pos;
      }).toList())!;
    }

    var allWrites = <Block>[
      ...fullWrites,
      ...reads.map((read) {
        var write = partialWrites.firstWhere((w) => w.pos == read.pos);

        // MuTatIoN!
        (read.data).setRange(write.offset!, write.length!, (write.data).buffer.asUint8List(write.offset!, write.length!));

        return read;
      })
    ];

    bufferChunks(allWrites);

    if (position + length > meta!.size) {
      setattr({"size": position + length});
    }
    return length;
  }

  void readIfFallback() async {
    /*  if (ops.readIfFallback) {
      // Reset the meta
      var meta = await ops.readIfFallback();
      this.meta = meta || { "size": 0 };
    } */
  }

  bool lock(int lockType) {
    if (ops.lock(lockType)) {
      if (lockType >= LOCK_TYPES_RESERVED) {
        writeLock = true;
      }
      return true;
    }
    return false;
  }

  bool unlock(int lockType) {
    if (writeLock == true) {
      // In certain cases (I saw this while running VACUUM after
      // changing page size) sqlite changes the size of the file
      // _after_ `fsync` for some reason. In our case, this is
      // critical because we are relying on fsync to write everything
      // out. If we just did some writes, do another fsync which will
      // check the meta and make sure it's persisted if dirty (all
      // other writes should already be flushed by now)
      fsync();
      writeLock = false;
    }

    return ops.unlock(lockType);
  }

  void fsync() {
    if (buffer.isNotEmpty) {
      // We need to handle page size changes which restructures the
      // whole db. We check if the page size is being written and
      // handle it
      var first = buffer[0];
      if (first != null) {
        var pageSize = getPageSize(first.data);

        if (pageSize != meta?.blockSize) {
          // The page size changed! We need to reflect that in our
          // storage. We need to restructure all pending writes and
          // change our page size so all future writes reflect the new
          // size.
          var newBuffer = Map<int, Block>.from(buffer);
          buffer = {};

          // We take all pending writes, concat them into a single
          // buffer, and rewrite it out with the new size. This would
          // be dangerous if the page size could be changed at any
          // point in time since we don't handle partial reads here.
          // However sqlite only ever actually changes the page size
          // in 2 cases:
          //
          // * The db is empty (no data yet, so nothing to read)
          // * A VACUUM command is rewriting the entire db
          //
          // In both cases, we can assume we have _all_ the needed
          // data in the pending buffer, and we don't have to worry
          // about overwriting anything.

          var writes = [...newBuffer.values];
          var totalSize = writes.length * meta!.blockSize;
          var buf = Uint8List(totalSize);
          var view = buf.buffer;

          for (var write in writes) {
            buf.setAll(write.pos, write.data);
          }

          // Rewrite the buffer with the new page size
          bufferChunks(writeChunks(view.asUint8List(), pageSize, 0, totalSize));

          // Change our page size
          setattr({"blockSize": pageSize});
        }
      }
      ops.writeBlocks([...buffer.values], meta!.blockSize);
    }

    if (_metaDirty) {
      // We only store the size right now. Block size is already
      // stored in the sqlite file and we don't need the rest
      //
      // TODO: Currently we don't delete any extra blocks after the
      // end of the file. This isn't super important, and in fact
      // could cause perf regressions (sqlite doesn't compress files
      // either!) but what we probably should do is detect a VACUUM
      // command (the whole db is being rewritten) and at that point
      // delete anything after the end of the file
      ops.writeMeta({"size": meta?.size});
      _metaDirty = false;
    }

    buffer = {};
  }

  void setattr(Map<String, dynamic> attr) {
    meta ??= FileMeta(0,0);

    // Size is the only attribute we actually persist. The rest are
    // stored in memory

    if (attr["mode"] != null) {
      meta?.mode = attr["mode"] as int;
    }

    if (attr["blockSize"] != null) {
         meta?.blockSize = attr["blockSize"] as int;
    }

    if (attr["size"] != null) {
      meta?.size = attr["size"] as int;
      _metaDirty = true;
    }
  }

  FileMeta? getattr() {
    return meta;
  }
}

import 'dart:html' hide File;
import 'dart:typed_data';

import 'file_ops.dart';
import 'utils.dart';
import 'package:sqlite3/common.dart';

import 'file.dart';
import 'file_system_base.dart';

enum ErrnoCodes {
  ePerm(63),
  eNoEnt(44);

  final int _value;

  const ErrnoCodes(this._value);

  @override
  String toString() {
    return _value.toString();
  }

  int toInt() {
    return _value;
  }
}

int closestNumber(num n, num m) {
  return (m * (n / m).ceil()).toInt();
}

class AbsurdIndexedDbFileSystem implements FileSystem {
  final String dbname;
  late Worker fsWorker;
  late MessagePort messagePort;
  Map<String, File> fileList = {};

  AbsurdIndexedDbFileSystem._(String dbName) : dbname = dbName;

  /// Loads an IndexedDB file system identified by the [dbName].
  ///
  /// Each file system with a different name will store an independent file
  /// system.
  static Future<AbsurdIndexedDbFileSystem> open({required String dbName}) async {
    final fs = AbsurdIndexedDbFileSystem._(dbName);

    return Future.delayed(Duration(milliseconds: 3), () => fs);
  }

  /// Returns all IndexedDB database names accessible from the current context.
  ///
  /// This may return `null` if `IDBFactory.databases()` is not supported by the
  /// current browser.
  static Future<List<String>?> databases() async {
    throw UnimplementedError("databases");
  }

  /// Deletes an IndexedDB database.
  static Future<void> deleteDatabase([String dbName = 'sqlite3_databases']) async {
    throw UnimplementedError("deleteDatabase");
  }

  Future<void> close() async {
    throw UnimplementedError("close");
  }

  @override
  void createFile(
    String path, {
    bool errorIfNotExists = false,
    bool errorIfAlreadyExists = false,
  }) {
    fileList.putIfAbsent(path, () => File(path, FileOps(), FileMeta(0, 0)));
    fileList[path]?.open();
  }

  @override
  int lock(String path, int flags) {
    return fileList[path]?.lock(flags) == true ? 0 : 1;
  }

  @override
  int unlock(String path, int flags) {
    return fileList[path]?.unlock(flags) == true ? 0 : 1;
  }

  @override
  int fsync(String path, int flags) {
    fileList[path]?.fsync();
    return SqlError.SQLITE_OK;
  }

  @override
  String createTemporaryFile() {
    throw UnimplementedError("createTemporaryFile");
  }

  @override
  void deleteFile(String path) {
    fileList[path]?.delete();
    //  throw UnimplementedError("deleteFile");
  }

  @override
  Future<void> clear() async {
    throw UnimplementedError("clear");
  }

  @override
  bool exists(String path) {
    return fileList[path] != null;
  }

  @override
  List<String> get files {
    throw UnimplementedError("files");
  }

  @override
  int read(String path, Uint8List target, int offset) {
    var whatweread = fileList[path]!.read(target, 0, target.length, offset);
    return whatweread;
  }

  @override
  int sizeOfFile(String path) {
    return fileList[path]!.meta!.size;
  }

  @override
  void truncateFile(String path, int length) {
    throw UnimplementedError("truncateFile");
  }

  @override
  void write(String path, Uint8List bytes, int offset) {
    fileList[path]?.write(bytes, 0, bytes.length, offset);
  }
}

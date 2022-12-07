/// A (very!) experimental web-compatible version of drift that doesn't depend
/// on external JavaScript sources.
///
/// This library is highly experimental and not production ready at the moment.
/// It exists for development and testing purposes for interested users.
///
/// While this library is marked as [experimental], it is not subject to
/// semantic versioning. Future drift updates with a minor update might break
/// APIs defined in this package or change the way data is persisted in
/// backwards-incompatible ways.
///
/// To use drift on the web, use the `package:drift/web.dart` library as
/// described in the [documentation](https://drift.simonbinder.eu/web/).

import 'dart:html';

import 'package:drift/drift.dart';
import 'package:drift/remote.dart';
import 'package:drift/web.dart';
import 'package:js/js.dart';
import 'package:sqlite3/common.dart';
import 'package:drift/backends.dart';
import 'package:http/http.dart' as http;

import 'package:drift/src/sqlite3/database.dart';
import 'package:sqlite3mc_drift_database/src/wasm/sqlite3.dart';

import 'environment.dart';
import 'file_system.dart';

@JS("startFileWorkerJsShim")
external void startFileWorkerJsShim(Object worker, Object argBuffer, Object resultBuffer, Object initSemaphore);

@JS("initFileWorkerJsShim")
external void initFileWorkerJsShim(Object worker);

void startJsFileWorker(
    Worker worker, MessagePort port, SharedArrayBuffer argBuffer, SharedArrayBuffer resultBuffer, SharedArrayBuffer initSemaphore) {
  startFileWorkerJsShim(worker, argBuffer, resultBuffer, initSemaphore);
}

/// Signature of a function that can perform setup work on a [database] before
/// drift is fully ready.
///
/// This could be used to, for instance, set encryption keys for SQLCipher
/// implementations.
typedef Sqlite3MCWasmDatabaseSetup = void Function(CommonDatabase database);

/// An experimental, WebAssembly based implementation of a drift sqlite3
/// database.
///
/// Using this database requires adding a WebAssembly file for sqlite3 to your
/// app. Details for that are available [here](https://github.com/simolus3/sqlite3.dart/).
class Sqlite3MCWasmDatabase extends DelegatedDatabase {
  Sqlite3MCWasmDatabase._(DatabaseDelegate delegate, bool logStatements)
      : super(delegate, isSequential: true, logStatements: logStatements);

  /// Creates a wasm database at [path] in the virtual file system of the
  /// [sqlite3] module.
  /// If [fileSystem] provided, the data is guaranteed to be
  /// stored in the IndexedDB when the request is complete. Attention!
  /// Insert/update queries may be slower when this option enabled. If you want
  /// to insert more than one rows, be sure you run in a transaction if
  /// possible.
  factory Sqlite3MCWasmDatabase({
    required CommmonSqlite3 sqlite3,
    required String path,
    String key = "",
    Sqlite3MCWasmDatabaseSetup? setup,
    AbsurdIndexedDbFileSystem? fileSystem,
    bool logStatements = false,
  }) {
    print("Sqlite3MCWasmDatabase factory");
    setupWrapper(CommonDatabase db) {
      print("setupWrapper");
      if (key != '') {
        print("key? $key");
        db.execute("pragma key = '$key';", []);
      }
      var val2 = db.select("SELECT sqlite_version() AS version;");

      for (var element in val2) {
        print(element);
      }
      setup!(db);
    }

    return Sqlite3MCWasmDatabase._(_Sqlite3MCWasmDelegate(sqlite3, path, setupWrapper, fileSystem), logStatements);
  }

  static Future<Sqlite3MCWasmDatabase> create({
    String fileSystemName = "sql_fs",
    String key = "",
    String path = "default.db",
    Sqlite3MCWasmDatabaseSetup? setup,
    bool logStatements = false,
    String wasmImage = "sqlite3mc.wasm",
  }) async {
    print("create");
    final response = await http.get(Uri.parse(wasmImage));
    final fs = await AbsurdIndexedDbFileSystem.open(dbName: fileSystemName);
    final sqlite3 = await WasmSqlite3.load(
      response.bodyBytes,
      SqliteEnvironment(fileSystem: fs),
    );
    return Sqlite3MCWasmDatabase(sqlite3: sqlite3, key: key, path: path, setup: setup);
  }

  ///  This is where we create a new database
  ///  and set up the listener to create file_ops workers
  static DatabaseConnection createWorker({String key = ""}) {
    final worker = Worker('worker.dart.js');
    final ports = MessageChannel();
    worker.postMessage({'port': ports.port1,"key":key}, [ports.port1]);
    Worker? aWorker;
    worker.onMessage.listen((e) {
      if (e.data["type"] == '__absurd:spawn-idb-worker') {
        aWorker = Worker("file.worker.js");
        startFileWorkerJsShim(aWorker!, e.data["argBuffer"] as SharedArrayBuffer, e.data["resultBuffer"] as SharedArrayBuffer,
            e.data["initSemaphore"] as SharedArrayBuffer);
      }
    });

    return remote(ports.port2.channel());
  }

  /// Creates an in-memory database in the loaded [sqlite3] database.
  factory Sqlite3MCWasmDatabase.inMemory(
    CommmonSqlite3 sqlite3, {
    Sqlite3MCWasmDatabaseSetup? setup,
    bool logStatements = false,
  }) {
    return Sqlite3MCWasmDatabase._(_Sqlite3MCWasmDelegate(sqlite3, null, setup, null), logStatements);
  }
}

class _Sqlite3MCWasmDelegate extends Sqlite3Delegate<CommonDatabase> {
  final CommmonSqlite3 _sqlite3;
  final String? _path;
  final AbsurdIndexedDbFileSystem? _fileSystem;

  _Sqlite3MCWasmDelegate(this._sqlite3, this._path, Sqlite3MCWasmDatabaseSetup? setup, this._fileSystem) : super(setup);

  @override
  CommonDatabase openDatabase() {
    final path = _path;
    if (path == null) {
      return _sqlite3.openInMemory();
    } else {
      return _sqlite3.open(path);
    }
  }

  @override
  Future<void> runCustom(String statement, List<Object?> args) {
    return Future.sync(() => runWithArgsSync(statement, args));
  }

  @override
  Future<int> runInsert(String statement, List<Object?> args) {
    return Future.sync(() {
      runWithArgsSync(statement, args);
      return database.lastInsertRowId;
    });
  }

  @override
  Future<int> runUpdate(String statement, List<Object?> args) {
    return Future.sync(() {
      runWithArgsSync(statement, args);
      return database.getUpdatedRows();
    });
  }
}

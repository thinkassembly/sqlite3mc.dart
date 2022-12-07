// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html';
import 'dart:js_util';
import 'package:drift/drift.dart';
import 'package:sqlite3mc_drift_database/src/wasm/sqlite3mc_wasm_database.dart';


bool isWorker() {
  return (globalThis is WorkerGlobalScope);
}


/// Obtains a database connection for running drift on the web.
DatabaseConnection connect({bool isInWebWorker = false, String key = ''}) {
  if (!isInWebWorker) {
    return Sqlite3MCWasmDatabase.createWorker(key:key);
  } else {
    return DatabaseConnection.delayed(
      Future.sync(
            () async {
          final databaseImpl = await Sqlite3MCWasmDatabase.create(
              path: 'app.db',
              logStatements: true,
              key:key,
              setup: (db) {
                db.execute("pragma page_size=8192;");
                db.select("PRAGMA journal_mode=MEMORY;");
                db.execute("pragma cache_size=16384");
              });
          return DatabaseConnection(databaseImpl);
        },
      ),
    );
  }
}

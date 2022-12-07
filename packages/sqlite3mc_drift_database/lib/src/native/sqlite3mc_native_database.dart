/// A drift database implementation built on `package:sqlite3/`.
///
/// The [Sqlite3MCNativeDatabase] class uses `dart:ffi` to access `sqlite3` APIs.
///
/// When using a [Sqlite3MCNativeDatabase], you need to ensure that `sqlite3mc` is
/// available when running your app. For mobile Flutter apps, you can simply
/// depend on the `sqlite3_flutter_libs` package to ship the latest sqlite3mc
/// version with your app.
/// For more information other platforms, see [other engines](https://drift.simonbinder.eu/docs/other-engines/vm/).

import 'dart:io';

import 'package:drift/backends.dart';
import 'package:meta/meta.dart';
import 'package:sqlite3/common.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:drift/src/sqlite3/database.dart';

import 'package:drift/src/sqlite3/database_tracker.dart';

export 'package:sqlite3/sqlite3.dart' show SqliteException;

/// Signature of a function that can perform setup work on a [database] before
/// drift is fully ready.
///
/// This could be used to, for instance, set encryption keys for SQLCipher
/// implementations.
typedef DatabaseSetup = void Function(Database database);

/// A drift database implementation based on `dart:ffi`, running directly in a
/// Dart VM or an AOT compiled Dart/Flutter application.
class Sqlite3MCNativeDatabase extends DelegatedDatabase {
  Sqlite3MCNativeDatabase._(DatabaseDelegate delegate, bool logStatements)
      : super(delegate, isSequential: true, logStatements: logStatements);

  /// Creates a database that will store its result in the [file], creating it
  /// if it doesn't exist.
  ///
  /// {@template drift_vm_database_factory}
  /// If [logStatements] is true (defaults to `false`), generated sql statements
  /// will be printed before executing. This can be useful for debugging.
  /// The optional [setup] function can be used to perform a setup just after
  /// the database is opened, before drift is fully ready. This can be used to
  /// add custom user-defined sql functions or to provide encryption keys in
  /// SQLCipher implementations.
  /// {@endtemplate}
  factory Sqlite3MCNativeDatabase(File file, {String key = "", bool logStatements = false, DatabaseSetup? setup}) {
    setupWrapper(Database db) {
      if (key != '') {
        db.execute("pragma key = '$key';", []);
      }

      setup!(db);
    }
    return Sqlite3MCNativeDatabase._(_Sqlite3MCNativeDelegate(file, setupWrapper, key), logStatements);
  }

  /// Creates an in-memory database won't persist its changes on disk.
  ///
  /// {@macro drift_vm_database_factory}
  factory Sqlite3MCNativeDatabase.memory({String key = "", bool logStatements = false, DatabaseSetup? setup}) {
    print("Sqlite3MCNativeDatabase.memory factory");
    return Sqlite3MCNativeDatabase._(_Sqlite3MCNativeDelegate(null, setup, key), logStatements);
  }

  /// Creates a drift executor for an opened [database] from the `sqlite3`
  /// package.
  ///
  /// When the [closeUnderlyingOnClose] argument is set (which is the default),
  /// calling [QueryExecutor.close] on the returned [Sqlite3MCNativeDatabase] will also
  /// [CommonDatabase.dispose] the [database] passed to this constructor.
  ///
  /// Using [Sqlite3MCNativeDatabase.opened] may be useful when you want to use the same
  /// underlying [Database] in multiple drift connections. Drift uses this
  /// internally when running [integration tests for migrations](https://drift.simonbinder.eu/docs/advanced-features/migrations/#verifying-migrations).
  ///
  /// {@macro drift_vm_database_factory}
  factory Sqlite3MCNativeDatabase.opened(Database database,
      {String key = "", bool logStatements = false, DatabaseSetup? setup, bool closeUnderlyingOnClose = true}) {

    return Sqlite3MCNativeDatabase._(_Sqlite3MCNativeDelegate.opened(database, setup, key, closeUnderlyingOnClose), logStatements);
  }

  /// Disposes resources allocated by all `VmDatabase` instances of this
  /// process.
  ///
  /// This method will call `sqlite3_close_v2` for every `VmDatabase` that this
  /// process has opened without closing later.
  ///
  /// __Warning__: This functionality appears to cause crashes on iOS, and it
  /// does nothing on Android. It's mainly intended for Desktop operating
  /// systems, so try to avoid calling it where it's not necessary.
  /// For safety measures, avoid calling [closeExistingInstances] in release
  /// builds.
  ///
  /// Ideally, all databases should be closed properly in Dart. In that case,
  /// it's not necessary to call [closeExistingInstances]. However, features
  /// like hot (stateless) restart can make it impossible to reliably close
  /// every database. In that case, we leak native sqlite3 database connections
  /// that aren't referenced by any Dart object. Drift can track those
  /// connections across Dart VM restarts by storing them in an in-memory sqlite
  /// database.
  /// Calling this method can cleanup resources and database locks after a
  /// restart.
  ///
  /// Note that calling [closeExistingInstances] when you're still actively
  /// using a [Sqlite3MCNativeDatabase] can lead to crashes, since the database would
  /// then attempt to use an invalid connection.
  /// This, this method should only be called when you're certain that there
  /// aren't any active [Sqlite3MCNativeDatabase]s, not even on another isolate.
  ///
  /// A suitable place to call [closeExistingInstances] is at an early stage
  /// of your `main` method, before you're using drift.
  ///
  /// ```dart
  /// void main() {
  ///   // Guard against zombie database connections caused by hot restarts
  ///   assert(() {
  ///     VmDatabase.closeExistingInstances();
  ///     return true;
  ///   }());
  ///
  ///   runApp(MyApp());
  /// }
  /// ```
  ///
  /// For more information, see [issue 835](https://github.com/simolus3/drift/issues/835).
  @experimental
  static void closeExistingInstances() {
    tracker.closeExisting();
  }
}

class _Sqlite3MCNativeDelegate extends Sqlite3Delegate<Database> {
  final File? file;
  final String key;

  _Sqlite3MCNativeDelegate(this.file, DatabaseSetup? setup, this.key) : super(setup);

  _Sqlite3MCNativeDelegate.opened(Database db, DatabaseSetup? setup, this.key, bool closeUnderlyingWhenClosed)
      : file = null,
        super.opened(db, setup, closeUnderlyingWhenClosed);

  @override
  Future<void> open(QueryExecutorUser db) async {
    return super.open(db);

  }

  @override
  Database openDatabase() {

    final file = this.file;
    Database db;

    if (file != null) {
      // Create the parent directory if it doesn't exist. sqlite will emit
      // confusing misuse warnings otherwise
      final dir = file.parent;
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }

      db = sqlite3.open(file.path);

      tracker.markOpened(file.path, db);
    } else {
      db = sqlite3.openInMemory();
    }

    return db;
  }

  void beforeClose(Database database) {
    tracker.markClosed(database);
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

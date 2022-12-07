# sqlite3mc.dart


**Experimental**  dart packages implementing [Sqlite3 Multiple Ciphers](https://github.com/utelle/SQLite3MultipleCiphers) for use with [sqlite3.dart](https://github.com/simolus3/sqlite3.dart) and [Drift](https://github.com/simolus3/drift).

SQLite3 Multiple Ciphers is an extension to the public domain version of SQLite that allows applications to read and write encrypted database files.  Support is provided for Android, iOS, MacOS, Linux, Windows and the Web.  

Web support is provided by an adaptation of the filesystem created for [Absurd SQL](https://github.com/jlongster/absurd-sql).

| Package | Description  | Android | iOS | Windows | Linux | MacOS | Web | 
|---|---|:---:|:---:|:---:|:---:|:---:|:---:|  
| [`sqlite3mc_drift_database`](https://github.com/thinkassembly/sqlite3mc.dart/tree/main/packages/sqlite3mc_drift_database)         |  | ✔       | ✔   | ✔       | ✔     | ✔     |  ✔  |
| [`sqlite3mc_flutter_libs`](https://github.com/thinkassembly/sqlite3mc.dart/tree/main/packages/sqlite3mc_flutter_libs)               |  | ✔       | ✔   | ✔       | ✔     | ✔     |  ✔  |
| [`sqlite3mc_drift_dev`](https://github.com/thinkassembly/sqlite3mc.dart/tree/main/packages/sqlite3mc_drift_dev)                      |  | ✔       | ✔   | ✔       | ✔     | ✔     |  ✔  |
| [`sqlite3mc-android-native-lib`](https://github.com/thinkassembly/sqlite3mc.dart/tree/main/native_libs/sqlite3mc-android-native-lib)  |  | ✔       | N/A | N/A     | N/A   | N/A   | N/A |
| [`sqlite3mc podspec`](https://github.com/thinkassembly/sqlite3mc)                                                                    |  | N/A     | ✔   | N/A     | N/A   | ✔   | N/A |

## FAQ
### Why Sqlite3 Multiple Ciphers?
Sqlite3 Multiple Ciphers has no external dependencies unlike SqlCipher.  It can compile and run anywhere sqlite can run.




## Examples
[Live Examples](https://thinkassembly.github.io/sqlite3mc.dart/)
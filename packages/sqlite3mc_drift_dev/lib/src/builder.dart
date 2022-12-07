import 'dart:async';
import 'dart:io';

import 'package:build/build.dart';
import 'package:process_run/cmd_run.dart';
import 'package:sqlite3mc_drift_dev/src/one_to_many_builder.dart';




class WorkerGenerator extends OneToManyGenerator {
  @override
  FutureOr<String?> generate(BuildStep buildStep) async {
    // TODO: Don't remove this.  It seems if you don't read the input file it doesn't get saved to the asset graph so
    // it never rebuilds.  I'm not POSITIVE this is what is happening but I'm tired of fighting it so I'm going to leave it here
    // and figure it out later.
    await buildStep.readAsString(AssetId(buildStep.inputId.package, 'lib/database/connection/web.dart'));

    var fileWorkerContents = await buildStep.readAsString(AssetId("sqlite3mc_drift_database", "lib/assets/file.worker.js"));
    await buildStep.writeAsString(AssetId(buildStep.inputId.package, 'web/file.worker.js'), fileWorkerContents);
    var wasmContents = await buildStep.readAsBytes(AssetId("sqlite3mc_drift_database", "lib/assets/sqlite3mc.wasm"));
    await buildStep.writeAsBytes(AssetId(buildStep.inputId.package, 'web/sqlite3mc.wasm'), wasmContents);
    var wasmDebugContents = await buildStep.readAsBytes(AssetId("sqlite3mc_drift_database", "lib/assets/sqlite3mc.debug.wasm"));
    await buildStep.writeAsBytes(AssetId(buildStep.inputId.package, 'web/sqlite3mc.debug.wasm'), wasmDebugContents);
    var workerContents = await buildStep.readAsBytes(AssetId("sqlite3mc_drift_database", "lib/assets/worker.dart"));
    await buildStep.writeAsBytes(AssetId(buildStep.inputId.package, 'lib/database/connection/worker.dart'), workerContents);
    var shimContents1 = await buildStep.readAsBytes(AssetId("sqlite3mc_drift_database", "lib/assets/post_message_sab_shim.js"));
    await buildStep.writeAsBytes(AssetId(buildStep.inputId.package, 'web/post_message_sab_shim.js'), shimContents1);

    var cmd =  ProcessCmd("dart",["compile","js","-O3","-o","web/worker.dart.js","lib/database/connection/worker.dart"]);
    cmd.runInShell = true;
    await runCmd(cmd,stdout: stdout);
    return null;
  }


}

Builder sqlite3mcWebWorkersGenerator(BuilderOptions options) {
  final defaultOptions = BuilderOptions({
    'input_files': ['lib/database/connection/web.dart'],
    'output_files': ['web/sqlite3mc.wasm', 'web/sqlite3mc.debug.wasm', 'web/file.worker.js', 'web/worker.dart','lib/database/connection/worker.dart','web/post_message_sab_shim.js'],
    'root': ''
  });
  options = defaultOptions.overrideWith(options);
  return OneToManyBuilder(options, WorkerGenerator());
}

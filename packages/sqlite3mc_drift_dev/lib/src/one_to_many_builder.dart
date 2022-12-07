import 'package:build/build.dart';
import 'dart:async';
import 'dart:io';

abstract class OneToManyGenerator {
  FutureOr<void> generate(BuildStep buildStep);
}

class OneToManyBuilder extends Builder {
  /// input files pattern
  /// output files pattern
  /// index file location and name
  final BuilderOptions options;
  List<String> outputs = [];
  Map<String, List<String>> indexes = {};
  final OneToManyGenerator generator;

  OneToManyBuilder(this.options, this.generator) {
    outputs = mapOutput();
  }

  List<String> mapOutput() {
    List<String> outputPaths = [];
    outputPaths = List<String>.from(options.config["output_files"]);
    for (var outputPath in outputPaths) {
      if (File(outputPath).existsSync()) {
        //File(outputPath).deleteSync();
      }
    }

    return outputPaths;
  }

  @override
  FutureOr<void> build(BuildStep buildStep) async {
    await generator.generate(buildStep);
    return null;
  }

  @override
  Map<String, List<String>> get buildExtensions {
    return {
      r'lib/database/connection/web.dart': ['*.ok', ...outputs],
    };
  }
}

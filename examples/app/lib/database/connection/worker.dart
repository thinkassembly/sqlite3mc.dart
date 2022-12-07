// ignore: avoid_web_libraries_in_flutter
import 'dart:html';

import 'web.dart';
import 'package:drift/web.dart';
import 'package:drift/remote.dart';



void main() {
  final self = DedicatedWorkerGlobalScope.instance;
  self.importScripts("post_message_sab_shim.js");

  MessagePort port;
  self.onMessage.listen( (event) {
    final server = DriftServer(connect(isInWebWorker: true,key:event.data["key"]));
    port = event.data["port"];
    server.serve(port.channel());
  });
}



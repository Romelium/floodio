import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:drift/drift.dart';
import 'package:drift/isolate.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const String _dbIsolateName = 'floodio_db_isolate';

class _IsolateStartRequest {
  final SendPort sendPort;
  final String path;
  _IsolateStartRequest(this.sendPort, this.path);
}

void _databaseIsolateEntry(_IsolateStartRequest request) {
  final executor = NativeDatabase(File(request.path));
  final driftIsolate = DriftIsolate.inCurrent(
    () => DatabaseConnection(executor),
  );
  request.sendPort.send(driftIsolate);
}

Future<QueryExecutor> getSharedConnection() async {
  SendPort? port = IsolateNameServer.lookupPortByName(_dbIsolateName);

  if (port != null) {
    final isolate = DriftIsolate.fromConnectPort(port);
    return await isolate.connect();
  }

  final dir = await getApplicationDocumentsDirectory();
  final path = p.join(dir.path, 'floodio_db.sqlite');

  final receivePort = ReceivePort();
  await Isolate.spawn(
    _databaseIsolateEntry,
    _IsolateStartRequest(receivePort.sendPort, path),
  );

  final isolate = await receivePort.first as DriftIsolate;
  final registered = IsolateNameServer.registerPortWithName(isolate.connectPort, _dbIsolateName);

  if (!registered) {
    port = IsolateNameServer.lookupPortByName(_dbIsolateName);
    if (port != null) {
      return await DriftIsolate.fromConnectPort(port).connect();
    }
  }

  return await isolate.connect();
}

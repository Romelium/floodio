import 'dart:async';
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
  final executor = NativeDatabase(
    File(request.path),
    setup: (db) {
      db.execute('PRAGMA journal_mode=WAL;');
      db.execute('PRAGMA busy_timeout=5000;');
    },
  );
  final driftIsolate = DriftIsolate.inCurrent(
    () => DatabaseConnection(executor),
  );
  request.sendPort.send(driftIsolate);
}

Future<QueryExecutor> getSharedConnection() async {
  SendPort? port = IsolateNameServer.lookupPortByName(_dbIsolateName);

  if (port != null) {
    try {
      final isolate = DriftIsolate.fromConnectPort(port);
      return await isolate.connect().timeout(const Duration(seconds: 2));
    } catch (e) {
      IsolateNameServer.removePortNameMapping(_dbIsolateName);
    }
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
      final existingIsolate = DriftIsolate.fromConnectPort(port);
      return await existingIsolate.connect();
    }
  }

  return await isolate.connect();
}

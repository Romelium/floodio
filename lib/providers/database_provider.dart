import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../database/database.dart';

part 'database_provider.g.dart';

@Riverpod(keepAlive: true)
AppDatabase database(Ref ref) {
  throw UnimplementedError('databaseProvider must be overridden');
}

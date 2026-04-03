import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'battery_provider.g.dart';

class BatteryInfo {
  final int level;
  final BatteryState state;
  final bool isPowerSaveMode;

  BatteryInfo({
    required this.level,
    required this.state,
    required this.isPowerSaveMode,
  });
}

@Riverpod(keepAlive: true)
class BatteryController extends _$BatteryController {
  final _battery = Battery();
  Timer? _timer;

  @override
  BatteryInfo build() {
    ref.onDispose(() {
      _timer?.cancel();
    });

    _fetch();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _fetch());

    _battery.onBatteryStateChanged.listen((state) {
      _fetch();
    });

    return BatteryInfo(level: 100, state: BatteryState.unknown, isPowerSaveMode: false);
  }

  Future<void> _fetch() async {
    try {
      final level = await _battery.batteryLevel;
      final state = await _battery.batteryState;
      final isPowerSave = await _battery.isInBatterySaveMode;
      this.state = BatteryInfo(level: level, state: state, isPowerSaveMode: isPowerSave);
    } catch (_) {}
  }
}

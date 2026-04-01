import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import '../services/background_service.dart';

part 'settings_provider.g.dart';

enum MapStyle {
  street('Street', 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
  satellite('Satellite', 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}');

  final String label;
  final String url;
  const MapStyle(this.label, this.url);
}

class AppSettingsData {
  final MapStyle mapStyle;
  final int syncIntervalSeconds;
  final bool isOfficialMode;

  AppSettingsData({
    required this.mapStyle,
    required this.syncIntervalSeconds,
    required this.isOfficialMode,
  });

  AppSettingsData copyWith({
    MapStyle? mapStyle,
    int? syncIntervalSeconds,
    bool? isOfficialMode,
  }) {
    return AppSettingsData(
      mapStyle: mapStyle ?? this.mapStyle,
      syncIntervalSeconds: syncIntervalSeconds ?? this.syncIntervalSeconds,
      isOfficialMode: isOfficialMode ?? this.isOfficialMode,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettingsData &&
          runtimeType == other.runtimeType &&
          mapStyle == other.mapStyle &&
          syncIntervalSeconds == other.syncIntervalSeconds &&
          isOfficialMode == other.isOfficialMode;

  @override
  int get hashCode => Object.hash(mapStyle, syncIntervalSeconds, isOfficialMode);
}

@Riverpod(keepAlive: true)
SharedPreferences sharedPreferences(Ref ref) {
  throw UnimplementedError();
}

@Riverpod(keepAlive: true, dependencies: [sharedPreferences])
class AppSettings extends _$AppSettings {
  static const _keyMapStyle = 'settings_map_style';
  static const _keySyncInterval = 'settings_sync_interval';
  static const _keyIsOfficialMode = 'settings_is_official_mode';

  @override
  AppSettingsData build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final styleIndex = prefs.getInt(_keyMapStyle) ?? 0;
    final interval = prefs.getInt(_keySyncInterval) ?? 30;
    final isOfficial = prefs.getBool(_keyIsOfficialMode) ?? false;

    return AppSettingsData(
      mapStyle: MapStyle.values[styleIndex.clamp(0, MapStyle.values.length - 1)],
      syncIntervalSeconds: interval,
      isOfficialMode: isOfficial,
    );
  }

  Future<void> setMapStyle(MapStyle style) async {
    state = state.copyWith(mapStyle: style);
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setInt(_keyMapStyle, style.index);
    if (isBackgroundIsolate) {
      bgServiceInstance?.invoke('reloadSettings');
    } else {
      try { FlutterBackgroundService().invoke('reloadSettings'); } catch (_) {}
    }
  }

  Future<void> setSyncInterval(int seconds) async {
    state = state.copyWith(syncIntervalSeconds: seconds);
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setInt(_keySyncInterval, seconds);
    if (isBackgroundIsolate) {
      bgServiceInstance?.invoke('reloadSettings');
    } else {
      try { FlutterBackgroundService().invoke('reloadSettings'); } catch (_) {}
    }
  }

  Future<void> setOfficialMode(bool isOfficial) async {
    state = state.copyWith(isOfficialMode: isOfficial);
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool(_keyIsOfficialMode, isOfficial);
    if (isBackgroundIsolate) {
      bgServiceInstance?.invoke('reloadSettings');
    } else {
      try { FlutterBackgroundService().invoke('reloadSettings'); } catch (_) {}
    }
  }
}


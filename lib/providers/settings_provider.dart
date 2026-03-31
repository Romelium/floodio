import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
class AppSettings extends _$AppSettings {
  static const _keyMapStyle = 'settings_map_style';
  static const _keySyncInterval = 'settings_sync_interval';
  static const _keyIsOfficialMode = 'settings_is_official_mode';

  @override
  AppSettingsData build() {
    // Default values
    return AppSettingsData(
      mapStyle: MapStyle.street,
      syncIntervalSeconds: 30,
      isOfficialMode: false,
    );
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final styleIndex = prefs.getInt(_keyMapStyle) ?? 0;
    final interval = prefs.getInt(_keySyncInterval) ?? 30;
    final isOfficial = prefs.getBool(_keyIsOfficialMode) ?? false;

    state = AppSettingsData(
      mapStyle: MapStyle.values[styleIndex.clamp(0, MapStyle.values.length - 1)],
      syncIntervalSeconds: interval,
      isOfficialMode: isOfficial,
    );
  }

  Future<void> setMapStyle(MapStyle style) async {
    state = state.copyWith(mapStyle: style);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyMapStyle, style.index);
  }

  Future<void> setSyncInterval(int seconds) async {
    state = state.copyWith(syncIntervalSeconds: seconds);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keySyncInterval, seconds);
  }

  Future<void> setOfficialMode(bool isOfficial) async {
    state = state.copyWith(isOfficialMode: isOfficial);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIsOfficialMode, isOfficial);
  }
}

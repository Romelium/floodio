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

  AppSettingsData({
    required this.mapStyle,
    required this.syncIntervalSeconds,
  });

  AppSettingsData copyWith({
    MapStyle? mapStyle,
    int? syncIntervalSeconds,
  }) {
    return AppSettingsData(
      mapStyle: mapStyle ?? this.mapStyle,
      syncIntervalSeconds: syncIntervalSeconds ?? this.syncIntervalSeconds,
    );
  }
}

@Riverpod(keepAlive: true)
class AppSettings extends _$AppSettings {
  static const _keyMapStyle = 'settings_map_style';
  static const _keySyncInterval = 'settings_sync_interval';

  @override
  AppSettingsData build() {
    // Default values
    return AppSettingsData(
      mapStyle: MapStyle.street,
      syncIntervalSeconds: 30,
    );
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final styleIndex = prefs.getInt(_keyMapStyle) ?? 0;
    final interval = prefs.getInt(_keySyncInterval) ?? 30;

    state = AppSettingsData(
      mapStyle: MapStyle.values[styleIndex.clamp(0, MapStyle.values.length - 1)],
      syncIntervalSeconds: interval,
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
}

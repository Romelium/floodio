class PrefKeys {
  static const String userName = 'user_name';
  static const String userContact = 'user_contact';
  static const String heroDataCarried = 'hero_data_carried';
  static const String heroPeersSynced = 'hero_peers_synced';
  static const String heroReportsRelayed = 'hero_reports_relayed';
  static const String offlineRegions = 'offline_regions';
  static const String lastCloudSyncTime = 'last_cloud_sync_time';
  static const String lastSyncEventId = 'last_sync_event_id';
  static const String hasSeenTutorial = 'has_seen_tutorial';
  static const String onboardingShownCount = 'onboarding_shown_count';
  static const String mapStyle = 'settings_map_style';
  static const String syncInterval = 'settings_sync_interval';
  static const String isOfficialMode = 'settings_is_official_mode';
}

class AppConstants {
  static const double defaultLat = 10.7326718;
  static const double defaultLng = 122.5482846;
  static const String imagesBucket = 'images';
  static const String syncEventsTable = 'sync_events';
  static const String dbIsolateName = 'floodio_db_isolate';
  static const String bgServiceChannel = 'floodio_bg_service';
  static const String criticalAlertsChannel = 'floodio_critical_alerts';
}

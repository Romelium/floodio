class PrefKeys {
  static const String userName = 'user_name';
  static const String userContact = 'user_contact';
  static const String userPrivateKey = 'user_private_key';
  static const String heroDataCarried = 'hero_data_carried';
  static const String heroPeersSynced = 'hero_peers_synced';
  static const String heroReportsRelayed = 'hero_reports_relayed';
  static const String offlineRegions = 'offline_regions';
  static const String lastCloudSyncTime = 'last_cloud_sync_time';
  static const String lastSyncEventId = 'last_sync_event_id';
  static const String hasSeenTutorial = 'has_seen_tutorial';
  static const String hasSeenWifiWarning = 'has_seen_wifi_warning';
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
  static const String dbFileName = 'floodio_db.sqlite';
  static const String bgServiceChannel = 'floodio_bg_service';
  static const String criticalAlertsChannel = 'floodio_critical_alerts';
  static const String imagePrefix = 'img_';
  static const String mapExtension = '.fmap';
  static const String mapPrefix = 'map_';
}

class BgEvents {
  static const String p2pStateUpdate = 'p2pStateUpdate';
  static const String terminalLog = 'terminalLog';
  static const String reloadOfflineRegions = 'reloadOfflineRegions';
  static const String reloadSettings = 'reloadSettings';
  static const String reloadHeroStats = 'reloadHeroStats';
  static const String requestState = 'requestState';
  static const String setAsForeground = 'setAsForeground';
  static const String setAsBackground = 'setAsBackground';
  static const String stopService = 'stopService';
  static const String toggleAutoSync = 'toggleAutoSync';
  static const String startHosting = 'startHosting';
  static const String stopHosting = 'stopHosting';
  static const String startScanning = 'startScanning';
  static const String stopScanning = 'stopScanning';
  static const String disconnect = 'disconnect';
  static const String connectToDevice = 'connectToDevice';
  static const String requestMapRegion = 'requestMapRegion';
  static const String broadcastMapRegion = 'broadcastMapRegion';
  static const String triggerSync = 'triggerSync';
  static const String broadcastText = 'broadcastText';
  static const String broadcastFile = 'broadcastFile';
  static const String processPayload = 'processPayload';
  static const String processPayloadFromFile = 'processPayloadFromFile';
  static const String processPayloadComplete = 'processPayloadComplete';
  static const String mockDiscoveredDevice = 'mockDiscoveredDevice';
  static const String mockConnectedClient = 'mockConnectedClient';
  static const String mockReceivedHazard = 'mockReceivedHazard';
  static const String mockReceivedCriticalHazard = 'mockReceivedCriticalHazard';
  static const String mockHostState = 'mockHostState';
  static const String mockClientState = 'mockClientState';
  static const String mockSyncProgress = 'mockSyncProgress';
  static const String requestMapDownloadState = 'requestMapDownloadState';
  static const String startMapDownload = 'startMapDownload';
  static const String cancelMapDownload = 'cancelMapDownload';
  static const String mapDownloadProgress = 'mapDownloadProgress';
}

class SyncTypes {
  static const String manifest = 'manifest';
  static const String payloadChunk = 'payload_chunk';
  static const String payload = 'payload';
  static const String requestMap = 'request_map';
  static const String requestImage = 'request_image';
  static const String upToDate = 'up_to_date';
}

class FeedFilterTypes {
  static const String all = 'All';
  static const String hazards = 'Hazards';
  static const String news = 'News';
  static const String areas = 'Areas';
  static const String paths = 'Paths';
}

class HazardTypes {
  static const String flood = 'Flood';
  static const String floodedArea = 'Flooded Area';
  static const String fire = 'Fire';
  static const String fireZone = 'Fire Zone';
  static const String roadblock = 'Roadblock';
  static const String medical = 'Medical';
  static const String medicalTriage = 'Medical Triage';
  static const String evacuationZone = 'Evacuation Zone';
  static const String safeZone = 'Safe Zone';
  static const String supply = 'Supply';
  static const String custom = 'Custom';
  static const String other = 'Other';
  static const String evacuationRoute = 'Evacuation Route';
  static const String safePath = 'Safe Path';
  static const String blockedRoad = 'Blocked Road';
}

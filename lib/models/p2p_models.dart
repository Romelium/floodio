class AppHostState {
  final bool isActive;
  final String? ssid;
  final String? preSharedKey;
  final String? hostIpAddress;

  AppHostState({required this.isActive, this.ssid, this.preSharedKey, this.hostIpAddress});

  factory AppHostState.fromMap(Map<String, dynamic> map) {
    return AppHostState(
      isActive: map['isActive'] ?? false,
      ssid: map['ssid'],
      preSharedKey: map['preSharedKey'],
      hostIpAddress: map['hostIpAddress'],
    );
  }
}

class AppClientState {
  final bool isActive;
  final String? hostSsid;
  final String? hostGatewayIpAddress;
  final String? hostIpAddress;

  AppClientState({required this.isActive, this.hostSsid, this.hostGatewayIpAddress, this.hostIpAddress});

  factory AppClientState.fromMap(Map<String, dynamic> map) {
    return AppClientState(
      isActive: map['isActive'] ?? false,
      hostSsid: map['hostSsid'],
      hostGatewayIpAddress: map['hostGatewayIpAddress'],
      hostIpAddress: map['hostIpAddress'],
    );
  }
}

class AppDiscoveredDevice {
  final String deviceAddress;
  final String deviceName;

  AppDiscoveredDevice({required this.deviceAddress, required this.deviceName});

  factory AppDiscoveredDevice.fromMap(Map<String, dynamic> map) {
    return AppDiscoveredDevice(
      deviceAddress: map['deviceAddress'] ?? '',
      deviceName: map['deviceName'] ?? '',
    );
  }
}

class AppClientInfo {
  final String id;
  final String username;
  final bool isHost;

  AppClientInfo({required this.id, required this.username, required this.isHost});

  factory AppClientInfo.fromMap(Map<String, dynamic> map) {
    return AppClientInfo(
      id: map['id'] ?? '',
      username: map['username'] ?? '',
      isHost: map['isHost'] ?? false,
    );
  }
}

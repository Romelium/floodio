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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppHostState &&
          runtimeType == other.runtimeType &&
          isActive == other.isActive &&
          ssid == other.ssid &&
          preSharedKey == other.preSharedKey &&
          hostIpAddress == other.hostIpAddress;

  @override
  int get hashCode => Object.hash(isActive, ssid, preSharedKey, hostIpAddress);
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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppClientState &&
          runtimeType == other.runtimeType &&
          isActive == other.isActive &&
          hostSsid == other.hostSsid &&
          hostGatewayIpAddress == other.hostGatewayIpAddress &&
          hostIpAddress == other.hostIpAddress;

  @override
  int get hashCode => Object.hash(isActive, hostSsid, hostGatewayIpAddress, hostIpAddress);
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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppDiscoveredDevice &&
          runtimeType == other.runtimeType &&
          deviceAddress == other.deviceAddress &&
          deviceName == other.deviceName;

  @override
  int get hashCode => Object.hash(deviceAddress, deviceName);
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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppClientInfo &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          username == other.username &&
          isHost == other.isHost;

  @override
  int get hashCode => Object.hash(id, username, isHost);
}

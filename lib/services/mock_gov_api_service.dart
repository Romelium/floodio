import 'dart:async';
import 'dart:convert';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../crypto/crypto_service.dart';
import '../database/tables.dart';
import '../providers/admin_trusted_sender_provider.dart';
import '../providers/hazard_marker_provider.dart';
import '../providers/location_provider.dart';
import '../providers/news_item_provider.dart';
import '../providers/revoked_delegation_provider.dart';

part 'mock_gov_api_service.g.dart';

@Riverpod(keepAlive: true)
class MockGovApiService extends _$MockGovApiService {
  Timer? _timer;

  @override
  void build() {
    ref.onDispose(() {
      _timer?.cancel();
    });
  }

  void startMocking() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 2), (timer) {
      fetchAndInjectMockData();
    });
  }

  void stopMocking() {
    _timer?.cancel();
  }

  Future<void> fetchAndInjectMockData() async {
    await Future.delayed(const Duration(seconds: 2));

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final id = 'gov_$timestamp';
    
    final title = 'Gov API: Severe Weather Warning';
    final content = 'Automated alert from National Weather Service. Heavy rainfall expected in your area.';
    final expiresAt = timestamp + (24 * 3600000); // 24 hours TTL
    final payloadToSignNews = utf8.encode('$id$title$timestamp$expiresAt'); // imageId is empty
    final (senderId, signatureNews) = await generateOfficialMarkerSignature(payloadToSignNews);

    final newNews = NewsItemEntity(
      id: id,
      title: title,
      content: content,
      timestamp: timestamp,
      senderId: senderId,
      signature: signatureNews,
      trustTier: 1,
      expiresAt: expiresAt,
    );
    await ref.read(newsItemsControllerProvider.notifier).addNewsItem(newNews);

    double lat = 37.7749;
    double lng = -122.4194;
    
    try {
      final pos = await ref.read(locationControllerProvider.notifier).getCurrentPosition();
      if (pos != null) {
        lat = pos.latitude;
        lng = pos.longitude;
      }
    } catch (_) {}

    lat += (DateTime.now().second % 10 - 5) * 0.002;
    lng += (DateTime.now().second % 10 - 5) * 0.002;

    final type = 'Flood';
    final desc = 'Automated sensor detected rising water levels.';
    final payloadToSignMarker = utf8.encode('${id}_m$type$timestamp$expiresAt' '1');
    final (_, signatureMarker) = await generateOfficialMarkerSignature(payloadToSignMarker);

    final newMarker = HazardMarkerEntity(
      id: '${id}_m',
      latitude: lat,
      longitude: lng,
      type: type,
      description: desc,
      timestamp: timestamp,
      senderId: senderId,
      signature: signatureMarker,
      trustTier: 1,
      expiresAt: expiresAt,
      isCritical: true,
    );
    await ref.read(hazardMarkersControllerProvider.notifier).addMarker(newMarker);
  }
  
  Future<void> delegateAdminTrust(String delegateePublicKey) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final payloadToSign = utf8.encode('$delegateePublicKey$timestamp');
    final (delegatorId, signature) = await generateOfficialMarkerSignature(payloadToSign);
    
    final entity = AdminTrustedSenderEntity(
      publicKey: delegateePublicKey,
      delegatorPublicKey: delegatorId,
      timestamp: timestamp,
      signature: signature,
    );
    
    await ref.read(adminTrustedSendersControllerProvider.notifier).addAdminTrustedSender(entity);
  }

  Future<void> revokeAdminTrust(String delegateePublicKey) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final payloadToSign = utf8.encode('revoke_$delegateePublicKey$timestamp');
    final (delegatorId, signature) = await generateOfficialMarkerSignature(payloadToSign);

    final entity = RevokedDelegationEntity(
      delegateePublicKey: delegateePublicKey,
      delegatorPublicKey: delegatorId,
      timestamp: timestamp,
      signature: signature,
    );

    await ref.read(revokedDelegationsControllerProvider.notifier).addRevokedDelegation(entity);
  }
}

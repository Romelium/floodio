import 'dart:async';
import 'dart:convert';

import 'package:fixnum/fixnum.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../crypto/crypto_service.dart';
import '../database/tables.dart';
import '../providers/admin_trusted_sender_provider.dart';
import '../providers/hazard_marker_provider.dart';
import '../providers/location_provider.dart';
import '../providers/news_item_provider.dart';
import '../providers/revoked_delegation_provider.dart';
import '../providers/ui_p2p_provider.dart';
import '../protos/models.pb.dart' as pb;

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
    final isCriticalStr = "1";
    final payloadToSignNews = utf8.encode('$id$title$content$timestamp$expiresAt$isCriticalStr'); // imageId is empty
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
      isCritical: true,
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
    final payloadToSignMarker = utf8.encode('${id}_m$lat$lng$type$desc$timestamp$expiresAt' '1');
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

    final payload = pb.SyncPayload();
    payload.news.add(pb.NewsItem(
      id: newNews.id,
      title: newNews.title,
      content: newNews.content,
      timestamp: Int64(newNews.timestamp),
      senderId: newNews.senderId,
      signature: newNews.signature ?? '',
      trustTier: newNews.trustTier,
      expiresAt: Int64(newNews.expiresAt ?? 0),
      imageId: newNews.imageId ?? '',
      isCritical: newNews.isCritical,
    ));
    payload.markers.add(pb.HazardMarker(
      id: newMarker.id,
      latitude: newMarker.latitude,
      longitude: newMarker.longitude,
      type: newMarker.type,
      description: newMarker.description,
      timestamp: Int64(newMarker.timestamp),
      senderId: newMarker.senderId,
      signature: newMarker.signature ?? '',
      trustTier: newMarker.trustTier,
      imageId: newMarker.imageId ?? '',
      expiresAt: Int64(newMarker.expiresAt ?? 0),
      isCritical: newMarker.isCritical,
    ));
    final encoded = base64Encode(payload.writeToBuffer());
    ref.read(uiP2pServiceProvider.notifier).broadcastText(jsonEncode({'type': 'payload', 'data': encoded}));
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

    final payload = pb.SyncPayload();
    payload.delegations.add(pb.TrustDelegation(
      id: 'delg_$delegateePublicKey',
      delegatorPublicKey: delegatorId,
      delegateePublicKey: delegateePublicKey,
      timestamp: Int64(timestamp),
      signature: signature,
    ));
    final encoded = base64Encode(payload.writeToBuffer());
    ref.read(uiP2pServiceProvider.notifier).broadcastText(jsonEncode({'type': 'payload', 'data': encoded}));
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

    final payload = pb.SyncPayload();
    payload.revokedDelegations.add(pb.RevokedDelegation(
      delegateePublicKey: delegateePublicKey,
      delegatorPublicKey: delegatorId,
      timestamp: Int64(timestamp),
      signature: signature,
    ));
    final encoded = base64Encode(payload.writeToBuffer());
    ref.read(uiP2pServiceProvider.notifier).broadcastText(jsonEncode({'type': 'payload', 'data': encoded}));
  }
}

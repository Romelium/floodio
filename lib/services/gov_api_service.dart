import 'dart:async';
import 'dart:convert';

import 'package:fixnum/fixnum.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../crypto/crypto_service.dart';
import '../database/tables.dart';
import '../providers/admin_trusted_sender_provider.dart';
import '../providers/revoked_delegation_provider.dart';
import '../providers/ui_p2p_provider.dart';
import '../protos/models.pb.dart' as pb;

part 'gov_api_service.g.dart';

@Riverpod(keepAlive: true)
class GovApiService extends _$GovApiService {
  @override
  void build() {}

  Future<void> delegateAdminTrust(String delegateePublicKey) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final payloadToSign = utf8.encode('$delegateePublicKey$timestamp');
    final (delegatorId, signature) = await generateOfficialMarkerSignature(
      payloadToSign,
    );

    final entity = AdminTrustedSenderEntity(
      publicKey: delegateePublicKey,
      delegatorPublicKey: delegatorId,
      timestamp: timestamp,
      signature: signature,
    );

    await ref
        .read(adminTrustedSendersControllerProvider.notifier)
        .addAdminTrustedSender(entity);

    final payload = pb.SyncPayload();
    payload.delegations.add(
      pb.TrustDelegation(
        id: 'delg_$delegateePublicKey',
        delegatorPublicKey: delegatorId,
        delegateePublicKey: delegateePublicKey,
        timestamp: Int64(timestamp),
        signature: signature,
      ),
    );
    final encoded = base64Encode(payload.writeToBuffer());
    ref
        .read(uiP2pServiceProvider.notifier)
        .broadcastText(jsonEncode({'type': 'payload', 'data': encoded}));

    try {
      await Supabase.instance.client.from('sync_events').insert({
        'payload_base64': encoded,
      });
    } catch (_) {}
  }

  Future<void> revokeAdminTrust(String delegateePublicKey) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final payloadToSign = utf8.encode('revoke_$delegateePublicKey$timestamp');
    final (delegatorId, signature) = await generateOfficialMarkerSignature(
      payloadToSign,
    );

    final entity = RevokedDelegationEntity(
      delegateePublicKey: delegateePublicKey,
      delegatorPublicKey: delegatorId,
      timestamp: timestamp,
      signature: signature,
    );

    await ref
        .read(revokedDelegationsControllerProvider.notifier)
        .addRevokedDelegation(entity);

    final payload = pb.SyncPayload();
    payload.revokedDelegations.add(
      pb.RevokedDelegation(
        delegateePublicKey: delegateePublicKey,
        delegatorPublicKey: delegatorId,
        timestamp: Int64(timestamp),
        signature: signature,
      ),
    );
    final encoded = base64Encode(payload.writeToBuffer());
    ref
        .read(uiP2pServiceProvider.notifier)
        .broadcastText(jsonEncode({'type': 'payload', 'data': encoded}));

    try {
      await Supabase.instance.client.from('sync_events').insert({
        'payload_base64': encoded,
      });
    } catch (_) {}
  }
}

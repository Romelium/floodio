import 'dart:convert';
import 'dart:isolate';

import 'package:cryptography/cryptography.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'crypto_service.g.dart';

Future<(SimpleKeyPairData, SimplePublicKey, String?)> _initKeysLogic(
  String? privateKeyStr,
) async {
  final algorithm = Ed25519();
  SimpleKeyPair userKeyPair;
  String? newPrivKeyStr;

  if (privateKeyStr != null) {
    try {
      final privateKeyBytes = base64Decode(privateKeyStr);
      userKeyPair = await algorithm.newKeyPairFromSeed(privateKeyBytes);
    } catch (e) {
      // Fallback to generating new key if corrupted
      userKeyPair = await algorithm.newKeyPair();
      final privateKeyBytes = await userKeyPair.extractPrivateKeyBytes();
      newPrivKeyStr = base64Encode(privateKeyBytes);
    }
  } else {
    userKeyPair = await algorithm.newKeyPair();
    final privateKeyBytes = await userKeyPair.extractPrivateKeyBytes();
    newPrivKeyStr = base64Encode(privateKeyBytes);
  }

  final serverSeed = List<int>.filled(32, 1);
  final serverKeyPair = await algorithm.newKeyPairFromSeed(serverSeed);
  final serverPubKey = await serverKeyPair.extractPublicKey();

  final userKeyPairExtracted = await userKeyPair.extract();
  return (userKeyPairExtracted, serverPubKey, newPrivKeyStr);
}

Future<String> _signDataLogic(
  SimpleKeyPairData keyPairData,
  List<int> data,
) async {
  final algorithm = Ed25519();
  final signature = await algorithm.sign(data, keyPair: keyPairData);
  return base64Encode(signature.bytes);
}

Future<int> _verifyDataLogic(
  List<int> data,
  String signatureStr,
  String senderPublicKeyStr,
  List<int> serverPubKeyBytes,
  List<String> trustedPublicKeys,
  List<String> adminTrustedPublicKeys,
  List<String> untrustedPublicKeys,
) async {
  try {
    if (untrustedPublicKeys.contains(senderPublicKeyStr)) {
      print("[CryptoService] Dropping payload: Sender is in untrusted list.");
      return 5; // Drop
    }
    final signatureBytes = base64Decode(signatureStr);
    final senderPubKeyBytes = base64Decode(senderPublicKeyStr);

    final algorithm = Ed25519();
    final senderPubKey = SimplePublicKey(
      senderPubKeyBytes,
      type: KeyPairType.ed25519,
    );

    final isValid = await algorithm.verify(
      data,
      signature: Signature(signatureBytes, publicKey: senderPubKey),
    );
    if (!isValid) {
      print("[CryptoService] Dropping payload: Invalid Ed25519 signature.");
      return 5;
    }

    if (senderPublicKeyStr == base64Encode(serverPubKeyBytes)) {
      return 1;
    }

    if (adminTrustedPublicKeys.contains(senderPublicKeyStr)) {
      return 2;
    }

    return trustedPublicKeys.contains(senderPublicKeyStr) ? 3 : 4;
  } catch (e) {
    print("[CryptoService] Exception during signature verification: $e");
    return 5;
  }
}

Future<bool> _verifyDelegationLogic(
  String delegateePublicKeyStr,
  int timestamp,
  String signatureStr,
  String delegatorPublicKeyStr,
  List<int> serverPubKeyBytes,
) async {
  try {
    if (delegatorPublicKeyStr != base64Encode(serverPubKeyBytes)) {
      return false;
    }
    final data = utf8.encode('$delegateePublicKeyStr$timestamp');
    final signatureBytes = base64Decode(signatureStr);
    final senderPubKeyBytes = base64Decode(delegatorPublicKeyStr);
    final algorithm = Ed25519();
    final senderPubKey = SimplePublicKey(
      senderPubKeyBytes,
      type: KeyPairType.ed25519,
    );
    return await algorithm.verify(
      data,
      signature: Signature(signatureBytes, publicKey: senderPubKey),
    );
  } catch (e) {
    return false;
  }
}

Future<bool> _verifyRevocationLogic(
  String delegateePublicKeyStr,
  int timestamp,
  String signatureStr,
  String delegatorPublicKeyStr,
  List<int> serverPubKeyBytes,
) async {
  try {
    if (delegatorPublicKeyStr != base64Encode(serverPubKeyBytes)) {
      return false;
    }
    final data = utf8.encode('revoke_$delegateePublicKeyStr$timestamp');
    final signatureBytes = base64Decode(signatureStr);
    final senderPubKeyBytes = base64Decode(delegatorPublicKeyStr);
    final algorithm = Ed25519();
    final senderPubKey = SimplePublicKey(
      senderPubKeyBytes,
      type: KeyPairType.ed25519,
    );
    return await algorithm.verify(
      data,
      signature: Signature(signatureBytes, publicKey: senderPubKey),
    );
  } catch (e) {
    return false;
  }
}

Future<(String, String)> generateOfficialMarkerSignature(
  List<int> payloadToSign,
) async {
  final algorithm = Ed25519();
  final serverKeyPair = await algorithm.newKeyPairFromSeed(
    List<int>.filled(32, 1),
  );
  final serverPubKey = await serverKeyPair.extractPublicKey();
  final senderId = base64Encode(serverPubKey.bytes);

  final signatureObj = await algorithm.sign(
    payloadToSign,
    keyPair: serverKeyPair,
  );
  final signature = base64Encode(signatureObj.bytes);
  return (senderId, signature);
}

@Riverpod(keepAlive: true)
class CryptoService extends _$CryptoService {
  late SimpleKeyPairData _userKeyPair;
  late SimplePublicKey _serverPublicKey;

  @override
  Future<void> build() async {
    await _initKeys();
  }

  Future<void> _initKeys() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final privateKeyStr = prefs.getString('user_private_key');

    final (userKeyPairData, serverPublicKey, newPrivateKeyStr) =
        await Isolate.run(() => _initKeysLogic(privateKeyStr));

    if (newPrivateKeyStr != null) {
      await prefs.setString('user_private_key', newPrivateKeyStr);
    }

    _userKeyPair = userKeyPairData;
    _serverPublicKey = serverPublicKey;
  }

  Future<String> signData(List<int> data) async {
    return _signDataLogic(_userKeyPair, data);
  }

  Future<String> getPublicKeyString() async {
    final pubKey = await _userKeyPair.extractPublicKey();
    return base64Encode(pubKey.bytes);
  }

  Future<bool> verifyDelegation({
    required String delegateePublicKeyStr,
    required int timestamp,
    required String signatureStr,
    required String delegatorPublicKeyStr,
  }) async {
    final serverPubKeyBytes = _serverPublicKey.bytes;
    return _verifyDelegationLogic(
      delegateePublicKeyStr,
      timestamp,
      signatureStr,
      delegatorPublicKeyStr,
      serverPubKeyBytes,
    );
  }

  Future<bool> verifyRevocation({
    required String delegateePublicKeyStr,
    required int timestamp,
    required String signatureStr,
    required String delegatorPublicKeyStr,
  }) async {
    final serverPubKeyBytes = _serverPublicKey.bytes;
    return _verifyRevocationLogic(
      delegateePublicKeyStr,
      timestamp,
      signatureStr,
      delegatorPublicKeyStr,
      serverPubKeyBytes,
    );
  }

  Future<int> verifyAndGetTrustTier({
    required List<int> data,
    required String signatureStr,
    required String senderPublicKeyStr,
    required List<String> trustedPublicKeys,
    required List<String> adminTrustedPublicKeys,
    required List<String> untrustedPublicKeys,
    required List<String> revokedPublicKeys,
  }) async {
    final serverPubKeyBytes = _serverPublicKey.bytes;
    final myPubKey = await _userKeyPair.extractPublicKey();
    final myPubKeyStr = base64Encode(myPubKey.bytes);

    final effectiveTrustedKeys = [...trustedPublicKeys, myPubKeyStr];
    final effectiveAdminKeys = adminTrustedPublicKeys
        .where((k) => !revokedPublicKeys.contains(k))
        .toList();

    return _verifyDataLogic(
      data,
      signatureStr,
      senderPublicKeyStr,
      serverPubKeyBytes,
      effectiveTrustedKeys,
      effectiveAdminKeys,
      untrustedPublicKeys,
    );
  }
}

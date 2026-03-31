import 'dart:convert';
import 'dart:isolate';

import 'package:cryptography/cryptography.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'crypto_service.g.dart';

Future<(SimpleKeyPairData, SimplePublicKey, String?)> _isolateInitKeys(String? privateKeyStr) async {
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

Future<String> _isolateSignData(SimpleKeyPairData keyPairData, List<int> data) async {
  final algorithm = Ed25519();
  final signature = await algorithm.sign(data, keyPair: keyPairData);
  return base64Encode(signature.bytes);
}

Future<int> _isolateVerifyData(List<int> data, String signatureStr, String senderPublicKeyStr, List<int> serverPubKeyBytes, List<String> trustedPublicKeys, List<String> adminTrustedPublicKeys, List<String> untrustedPublicKeys) async {
  try {
    if (untrustedPublicKeys.contains(senderPublicKeyStr)) {
      return 5; // Drop
    }
    final signatureBytes = base64Decode(signatureStr);
    final senderPubKeyBytes = base64Decode(senderPublicKeyStr);

    final algorithm = Ed25519();
    final senderPubKey = SimplePublicKey(senderPubKeyBytes, type: KeyPairType.ed25519);

    final isValid = await algorithm.verify(
      data,
      signature: Signature(signatureBytes, publicKey: senderPubKey),
    );
    if (!isValid) return 5;

    if (senderPublicKeyStr == base64Encode(serverPubKeyBytes)) {
      return 1;
    }

    if (adminTrustedPublicKeys.contains(senderPublicKeyStr)) {
      return 2;
    }

    return trustedPublicKeys.contains(senderPublicKeyStr) ? 3 : 4;
  } catch (e) {
    return 5;
  }
}

Future<bool> _isolateVerifyDelegation(String delegateePublicKeyStr, int timestamp, String signatureStr, String delegatorPublicKeyStr, List<int> serverPubKeyBytes) async {
  try {
    if (delegatorPublicKeyStr != base64Encode(serverPubKeyBytes)) {
      return false;
    }
    final data = utf8.encode('$delegateePublicKeyStr$timestamp');
    final signatureBytes = base64Decode(signatureStr);
    final senderPubKeyBytes = base64Decode(delegatorPublicKeyStr);
    final algorithm = Ed25519();
    final senderPubKey = SimplePublicKey(senderPubKeyBytes, type: KeyPairType.ed25519);
    return await algorithm.verify(
      data,
      signature: Signature(signatureBytes, publicKey: senderPubKey),
    );
  } catch (e) {
    return false;
  }
}

Future<(SimpleKeyPairData, SimplePublicKey, String?)> _runInitKeys(String? privateKeyStr) {
  return Isolate.run(() => _isolateInitKeys(privateKeyStr));
}

Future<String> _runSignData(SimpleKeyPairData keyPair, List<int> data) {
  return Isolate.run(() => _isolateSignData(keyPair, data));
}

Future<int> _runVerifyData(List<int> data, String signatureStr, String senderPublicKeyStr, List<int> serverPubKeyBytes, List<String> trustedPublicKeys, List<String> adminTrustedPublicKeys, List<String> untrustedPublicKeys) {
  return Isolate.run(() => _isolateVerifyData(data, signatureStr, senderPublicKeyStr, serverPubKeyBytes, trustedPublicKeys, adminTrustedPublicKeys, untrustedPublicKeys));
}

Future<bool> _runVerifyDelegation(String delegateePublicKeyStr, int timestamp, String signatureStr, String delegatorPublicKeyStr, List<int> serverPubKeyBytes) {
  return Isolate.run(() => _isolateVerifyDelegation(delegateePublicKeyStr, timestamp, signatureStr, delegatorPublicKeyStr, serverPubKeyBytes));
}

Future<(String, String)> _generateOfficialMarkerSignature(List<int> payloadToSign) async {
  final algorithm = Ed25519();
  final serverKeyPair = await algorithm.newKeyPairFromSeed(List<int>.filled(32, 1));
  final serverPubKey = await serverKeyPair.extractPublicKey();
  final senderId = base64Encode(serverPubKey.bytes);

  final signatureObj = await algorithm.sign(payloadToSign, keyPair: serverKeyPair);
  final signature = base64Encode(signatureObj.bytes);
  return (senderId, signature);
}

Future<(String, String)> runGenerateOfficialMarkerSignature(List<int> payloadToSign) {
  return Isolate.run(() => _generateOfficialMarkerSignature(payloadToSign));
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
    
    final (userKeyPairData, serverPublicKey, newPrivateKeyStr) = await _runInitKeys(privateKeyStr);

    if (newPrivateKeyStr != null) {
      await prefs.setString('user_private_key', newPrivateKeyStr);
    }

    _userKeyPair = userKeyPairData;
    _serverPublicKey = serverPublicKey;
  }

  Future<String> signData(List<int> data) async {
    return _runSignData(_userKeyPair, data);
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
    return _runVerifyDelegation(delegateePublicKeyStr, timestamp, signatureStr, delegatorPublicKeyStr, serverPubKeyBytes);
  }

  Future<int> verifyAndGetTrustTier({
    required List<int> data,
    required String signatureStr,
    required String senderPublicKeyStr,
    required List<String> trustedPublicKeys,
    required List<String> adminTrustedPublicKeys,
    required List<String> untrustedPublicKeys,
  }) async {
    final serverPubKeyBytes = _serverPublicKey.bytes;
    final myPubKey = await _userKeyPair.extractPublicKey();
    final myPubKeyStr = base64Encode(myPubKey.bytes);

    final effectiveTrustedKeys = [...trustedPublicKeys, myPubKeyStr];

    return _runVerifyData(data, signatureStr, senderPublicKeyStr, serverPubKeyBytes, effectiveTrustedKeys, adminTrustedPublicKeys, untrustedPublicKeys);
  }
}

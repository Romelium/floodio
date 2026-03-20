import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'crypto_service.g.dart';

@Riverpod(keepAlive: true)
class CryptoService extends _$CryptoService {
  late final Ed25519 _algorithm;
  late SimpleKeyPair _userKeyPair;
  late SimplePublicKey _serverPublicKey;

  @override
  Future<void> build() async {
    _algorithm = Ed25519();
    await _initKeys();
  }

  Future<void> _initKeys() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 1. User Key Pair
    final privateKeyStr = prefs.getString('user_private_key');
    if (privateKeyStr != null) {
      final privateKeyBytes = base64Decode(privateKeyStr);
      _userKeyPair = await _algorithm.newKeyPairFromSeed(privateKeyBytes);
    } else {
      _userKeyPair = await _algorithm.newKeyPair();
      final privateKeyBytes = await _userKeyPair.extractPrivateKeyBytes();
      await prefs.setString('user_private_key', base64Encode(privateKeyBytes));
    }

    // 2. Server Public Key (Hardcoded for PoC)
    final serverSeed = List<int>.filled(32, 1); // Dummy seed
    final serverKeyPair = await _algorithm.newKeyPairFromSeed(serverSeed);
    _serverPublicKey = await serverKeyPair.extractPublicKey();
  }

  Future<String> signData(List<int> data) async {
    final signature = await _algorithm.sign(data, keyPair: _userKeyPair);
    return base64Encode(signature.bytes);
  }

  Future<String> getPublicKeyString() async {
    final pubKey = await _userKeyPair.extractPublicKey();
    return base64Encode(pubKey.bytes);
  }

  Future<int> verifyAndGetTrustTier({
    required List<int> data,
    required String signatureStr,
    required String senderPublicKeyStr,
    required List<String> trustedPublicKeys,
  }) async {
    try {
      final signatureBytes = base64Decode(signatureStr);
      final senderPubKeyBytes = base64Decode(senderPublicKeyStr);
      final senderPubKey = SimplePublicKey(senderPubKeyBytes, type: KeyPairType.ed25519);

      // 1. Verify the signature against the claimed sender's public key
      final isValid = await _algorithm.verify(
        data,
        signature: Signature(signatureBytes, publicKey: senderPubKey),
      );
      if (!isValid) return 5; // 5 = Invalid/Spoofed

      // 2. Check if the sender is the Official Server
      final serverPubKeyBytes = _serverPublicKey.bytes;
      if (senderPublicKeyStr == base64Encode(serverPubKeyBytes)) {
        return 1; // Tier 1: Official
      }

      // 3. Check if the sender is Personally-Trusted
      return trustedPublicKeys.contains(senderPublicKeyStr) ? 3 : 4;
      
    } catch (e) {
      // Catch FormatExceptions from invalid base64 or malformed keys
      return 5; 
    }
  }
}

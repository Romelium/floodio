import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:bip39/bip39.dart' as bip39;
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hex/hex.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../utils/constants.dart';
part 'crypto_service.g.dart';

List<int> _generate16BytesEntropy() {
  final random = Random.secure();
  return List<int>.generate(16, (_) => random.nextInt(256));
}

Future<(SimpleKeyPairData, SimplePublicKey, String?)> _initKeysLogic(
  String? storedDataStr,
) async {
  final algorithm = Ed25519();
  SimpleKeyPair userKeyPair;
  String? newDataStr;

  if (storedDataStr != null) {
    try {
      final bytes = base64Decode(storedDataStr);
      if (bytes.length == 32) {
        // Legacy 32-byte seed
        userKeyPair = await algorithm.newKeyPairFromSeed(bytes);
      } else if (bytes.length == 16) {
        // 16-byte entropy
        final mnemonic = bip39.entropyToMnemonic(HEX.encode(bytes));
        final seed32 = bip39.mnemonicToSeed(mnemonic).sublist(0, 32);
        userKeyPair = await algorithm.newKeyPairFromSeed(seed32);
      } else {
        throw Exception('Invalid stored data length');
      }
    } catch (e) {
      final entropy = _generate16BytesEntropy();
      final mnemonic = bip39.entropyToMnemonic(HEX.encode(entropy));
      final seed32 = bip39.mnemonicToSeed(mnemonic).sublist(0, 32);
      userKeyPair = await algorithm.newKeyPairFromSeed(seed32);
      newDataStr = base64Encode(entropy);
    }
  } else {
    final entropy = _generate16BytesEntropy();
    final mnemonic = bip39.entropyToMnemonic(HEX.encode(entropy));
    final seed32 = bip39.mnemonicToSeed(mnemonic).sublist(0, 32);
    userKeyPair = await algorithm.newKeyPairFromSeed(seed32);
    newDataStr = base64Encode(entropy);
  }

  final serverSeed = List<int>.filled(32, 1);
  final serverKeyPair = await algorithm.newKeyPairFromSeed(serverSeed);
  final serverPubKey = await serverKeyPair.extractPublicKey();

  final userKeyPairExtracted = await userKeyPair.extract();
  return (userKeyPairExtracted, serverPubKey, newDataStr);
}

Future<String> signDataLogic(
  SimpleKeyPairData keyPairData,
  List<int> data,
) async {
  final algorithm = Ed25519();
  final signature = await algorithm.sign(data, keyPair: keyPairData);
  return base64Encode(signature.bytes);
}

Future<int> verifyDataLogic(
  List<int> data,
  String signatureStr,
  String senderPublicKeyStr,
  List<int> serverPubKeyBytes,
  Set<String> trustedPublicKeys,
  Set<String> adminTrustedPublicKeys,
  Set<String> untrustedPublicKeys,
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

Future<bool> verifyDelegationLogic(
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
    print("[CryptoService] Exception during delegation verification: $e");
    return false;
  }
}

Future<bool> verifyRevocationLogic(
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
    print("[CryptoService] Exception during revocation verification: $e");
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
    const secureStorage = FlutterSecureStorage(
      aOptions: AndroidOptions(resetOnError: true),
    );
    final privateKeyStr = await secureStorage.read(key: PrefKeys.userPrivateKey);

    final (userKeyPairData, serverPublicKey, newPrivateKeyStr) =
        await Isolate.run(() => _initKeysLogic(privateKeyStr));

    if (newPrivateKeyStr != null) {
      await secureStorage.write(
        key: PrefKeys.userPrivateKey,
        value: newPrivateKeyStr,
      );
    }

    _userKeyPair = userKeyPairData;
    _serverPublicKey = serverPublicKey;
  }

  List<int> get serverPublicKeyBytes => _serverPublicKey.bytes;

  Future<String> signData(List<int> data) async {
    return signDataLogic(_userKeyPair, data);
  }

  Future<String> getPublicKeyString() async {
    final pubKey = await _userKeyPair.extractPublicKey();
    return base64Encode(pubKey.bytes);
  }

  Future<String> getSeedPhrase() async {
    const secureStorage = FlutterSecureStorage(
      aOptions: AndroidOptions(resetOnError: true),
    );
    final storedDataStr = await secureStorage.read(key: PrefKeys.userPrivateKey);
    if (storedDataStr != null) {
      final bytes = base64Decode(storedDataStr);
      return bip39.entropyToMnemonic(HEX.encode(bytes));
    }
    return '';
  }

  Future<bool> restoreFromSeedPhrase(String mnemonic) async {
    try {
      final cleanMnemonic = mnemonic.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (!bip39.validateMnemonic(cleanMnemonic)) return false;

      final hexEntropy = bip39.mnemonicToEntropy(cleanMnemonic);
      final bytes = HEX.decode(hexEntropy);

      const secureStorage = FlutterSecureStorage(
        aOptions: AndroidOptions(resetOnError: true),
      );
      await secureStorage.write(
        key: PrefKeys.userPrivateKey,
        value: base64Encode(bytes),
      );

      await _initKeys();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> verifyDelegation({
    required String delegateePublicKeyStr,
    required int timestamp,
    required String signatureStr,
    required String delegatorPublicKeyStr,
  }) async {
    final serverPubKeyBytes = _serverPublicKey.bytes;
    return verifyDelegationLogic(
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
    return verifyRevocationLogic(
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

    final effectiveTrustedKeys = {...trustedPublicKeys, myPubKeyStr};
    final effectiveAdminKeys = adminTrustedPublicKeys
        .where((k) => !revokedPublicKeys.contains(k))
        .toSet();

    return verifyDataLogic(
      data,
      signatureStr,
      senderPublicKeyStr,
      serverPubKeyBytes,
      effectiveTrustedKeys,
      effectiveAdminKeys,
      untrustedPublicKeys.toSet(),
    );
  }
}

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../crypto/crypto_service.dart';
import '../utils/constants.dart';

part 'local_user_provider.g.dart';

class LocalUser {
  final String name;
  final String contact;
  final String publicKey;

  LocalUser({
    required this.name,
    required this.contact,
    required this.publicKey,
  });
}

@Riverpod(keepAlive: true)
class LocalUserController extends _$LocalUserController {
  @override
  Future<LocalUser> build() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final name = prefs.getString(PrefKeys.userName) ?? 'Unknown';
    final contact = prefs.getString(PrefKeys.userContact) ?? '';

    await ref.watch(cryptoServiceProvider.future);
    final pubKey = await ref
        .read(cryptoServiceProvider.notifier)
        .getPublicKeyString();

    return LocalUser(name: name, contact: contact, publicKey: pubKey);
  }

  Future<void> updateProfile(String name, String contact) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefKeys.userName, name);
    await prefs.setString(PrefKeys.userContact, contact);

    final pubKey =
        state.value?.publicKey ??
        await ref.read(cryptoServiceProvider.notifier).getPublicKeyString();
    state = AsyncData(
      LocalUser(name: name, contact: contact, publicKey: pubKey),
    );
  }
}

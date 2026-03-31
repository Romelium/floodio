import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../crypto/crypto_service.dart';
import '../database/tables.dart';
import '../providers/user_profile_provider.dart';
import 'home_screen.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _nameController = TextEditingController();
  final _contactController = TextEditingController();

  Future<void> _saveProfile() async {
    final name = _nameController.text.trim();
    final contact = _contactController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Name is required')));
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_name', name);
    await prefs.setString('user_contact', contact);

    await ref.read(cryptoServiceProvider.future);
    final cryptoService = ref.read(cryptoServiceProvider.notifier);
    final publicKey = await cryptoService.getPublicKeyString();
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    final payloadToSign = utf8.encode('$publicKey$name$contact$timestamp');
    final signature = await cryptoService.signData(payloadToSign);

    final profile = UserProfileEntity(
      publicKey: publicKey,
      name: name,
      contactInfo: contact,
      timestamp: timestamp,
      signature: signature,
    );

    await ref
        .read(userProfilesControllerProvider.notifier)
        .saveProfile(profile);

    if (mounted) {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Welcome to Floodio')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Personal Information',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              'This information will be shared with nearby devices to help coordinate relief efforts.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Full Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _contactController,
              decoration: const InputDecoration(
                labelText: 'Contact Number / Info (Optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: _saveProfile,
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }
}

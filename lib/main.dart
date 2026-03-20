import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'crypto/crypto_service.dart';
import 'database/tables.dart';
import 'providers/hazard_marker_provider.dart';
import 'providers/trusted_sender_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: FloodioApp()));
}

class FloodioApp extends ConsumerWidget {
  const FloodioApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Floodio',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final markersAsync = ref.watch(hazardMarkersControllerProvider);
    final cryptoState = ref.watch(cryptoServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Floodio PoC'),
      ),
      body: switch (markersAsync) {
        AsyncData(:final value) => value.isEmpty
            ? const Center(child: Text('No hazard markers found.'))
            : ListView.builder(
                itemCount: value.length,
                itemBuilder: (context, index) {
                  final marker = value[index];
                  return ListTile(
                    leading: Icon(
                      Icons.warning,
                      color: marker.trustTier == 1
                          ? Colors.blue
                          : marker.trustTier == 3
                              ? Colors.green
                              : Colors.grey,
                    ),
                    title: Text(marker.type),
                    subtitle: Text(marker.description),
                    trailing: Text('Tier: ${marker.trustTier}'),
                    onLongPress: () {
                      ref.read(trustedSendersControllerProvider.notifier).addTrustedSender(
                            marker.senderId,
                            'Trusted User',
                          );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Sender marked as trusted!')),
                      );
                    },
                  );
                },
              ),
        AsyncError(:final error) => Center(child: Text('Error: $error')),
        _ => const Center(child: CircularProgressIndicator()),
      },
      floatingActionButton: cryptoState.when(
        data: (_) => Column(
              mainAxisAlignment: MainAxisAlignment.end,
              mainAxisSize: MainAxisSize.min, // Prevents the column from blocking the ListView touches
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FloatingActionButton(
                  heroTag: 'official',
                  onPressed: () async {
                    final cryptoService = ref.read(cryptoServiceProvider.notifier);
                    
                    // Simulate server signing
                    final serverSeed = List<int>.filled(32, 1);
                    final algorithm = Ed25519();
                    final serverKeyPair = await algorithm.newKeyPairFromSeed(serverSeed);
                    final serverPubKey = await serverKeyPair.extractPublicKey();
                    final senderId = base64Encode(serverPubKey.bytes);

                    final id = DateTime.now().millisecondsSinceEpoch.toString();
                    final type = 'Official Evacuation';
                    final description = 'Move to higher ground immediately.';
                    final timestamp = DateTime.now().millisecondsSinceEpoch;

                    final payloadToSign = utf8.encode('$id$type$timestamp');
                    final signatureObj = await algorithm.sign(payloadToSign, keyPair: serverKeyPair);
                    final signature = base64Encode(signatureObj.bytes);

                    final trustedSenders = await ref.read(trustedSendersControllerProvider.future);
                    final trustedKeys = trustedSenders.map((e) => e.publicKey).toList();

                    final trustTier = await cryptoService.verifyAndGetTrustTier(
                      data: payloadToSign,
                      signatureStr: signature,
                      senderPublicKeyStr: senderId,
                      trustedPublicKeys: trustedKeys,
                    );

                    final newMarker = HazardMarkerEntity(
                      id: id,
                      latitude: 37.7749,
                      longitude: -122.4194,
                      type: type,
                      description: description,
                      timestamp: timestamp,
                      senderId: senderId,
                      signature: signature,
                      trustTier: trustTier,
                    );
                    ref.read(hazardMarkersControllerProvider.notifier).addMarker(newMarker);
                  },
                  backgroundColor: Colors.blue,
                  child: const Icon(Icons.security, color: Colors.white),
                ),
                const SizedBox(height: 16),
                FloatingActionButton(
                  heroTag: 'user',
                  onPressed: () async {
                    final cryptoService = ref.read(cryptoServiceProvider.notifier);

                    final id = DateTime.now().millisecondsSinceEpoch.toString();
                    final type = 'Flood';
                    final description = 'Water level rising rapidly';
                    final timestamp = DateTime.now().millisecondsSinceEpoch;
                    final senderId = await cryptoService.getPublicKeyString();

                    final payloadToSign = utf8.encode('$id$type$timestamp');
                    final signature = await cryptoService.signData(payloadToSign);

                    final trustedSenders = await ref.read(trustedSendersControllerProvider.future);
                    final trustedKeys = trustedSenders.map((e) => e.publicKey).toList();

                    final trustTier = await cryptoService.verifyAndGetTrustTier(
                      data: payloadToSign,
                      signatureStr: signature,
                      senderPublicKeyStr: senderId,
                      trustedPublicKeys: trustedKeys,
                    );

                    final newMarker = HazardMarkerEntity(
                      id: id,
                      latitude: 37.7749,
                      longitude: -122.4194,
                      type: type,
                      description: description,
                      timestamp: timestamp,
                      senderId: senderId,
                      signature: signature,
                      trustTier: trustTier,
                    );
                    ref.read(hazardMarkersControllerProvider.notifier).addMarker(newMarker);
                  },
                  child: const Icon(Icons.add),
                ),
              ],
            ),
        loading: () => const FloatingActionButton(
          onPressed: null,
          child: CircularProgressIndicator(),
        ),
        error: (e, st) => const FloatingActionButton(
          onPressed: null,
          child: Icon(Icons.error),
        ),
      ),
    );
  }
}

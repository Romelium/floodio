import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../providers/location_provider.dart';

class CompassScreen extends ConsumerStatefulWidget {
  final LatLng target;
  final String title;

  const CompassScreen({super.key, required this.target, required this.title});

  @override
  ConsumerState<CompassScreen> createState() => _CompassScreenState();
}

class _CompassScreenState extends ConsumerState<CompassScreen> {
  @override
  Widget build(BuildContext context) {
    final locationAsync = ref.watch(locationControllerProvider);
    final currentPosition = locationAsync.value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline Compass'),
      ),
      body: currentPosition == null
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Acquiring GPS location...'),
                ],
              ),
            )
          : StreamBuilder<CompassEvent>(
              stream: FlutterCompass.events,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final double? heading = snapshot.data?.heading;
                if (heading == null) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text(
                        "Device does not have compass sensors.",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 18),
                      ),
                    ),
                  );
                }

                final bearing = Geolocator.bearingBetween(
                  currentPosition.latitude,
                  currentPosition.longitude,
                  widget.target.latitude,
                  widget.target.longitude,
                );

                final distance = Geolocator.distanceBetween(
                  currentPosition.latitude,
                  currentPosition.longitude,
                  widget.target.latitude,
                  widget.target.longitude,
                );

                // Calculate direction to point
                final direction = (bearing - heading) * (math.pi / 180);

                String distanceText;
                if (distance < 1000) {
                  distanceText = '${distance.toStringAsFixed(0)} m';
                } else {
                  distanceText = '${(distance / 1000).toStringAsFixed(2)} km';
                }

                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.title,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      distanceText,
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 60),
                    Center(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Compass background
                          Container(
                            width: 250,
                            height: 250,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Theme.of(context).colorScheme.outlineVariant,
                                width: 4,
                              ),
                              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                            ),
                          ),
                          // North indicator (rotates with heading)
                          Transform.rotate(
                            angle: -heading * (math.pi / 180),
                            child: SizedBox(
                              width: 250,
                              height: 250,
                              child: Align(
                                alignment: Alignment.topCenter,
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Text(
                                    'N',
                                    style: TextStyle(
                                      color: Colors.red.shade700,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 20,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // Arrow pointing to target
                          Transform.rotate(
                            angle: direction,
                            child: Icon(
                              Icons.navigation,
                              size: 120,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 60),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.explore, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Heading: ${heading.toStringAsFixed(0)}°',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 16),
                          const Icon(Icons.track_changes, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Bearing: ${bearing.toStringAsFixed(0)}°',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

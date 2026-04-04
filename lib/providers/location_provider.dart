import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'location_provider.g.dart';

@Riverpod(keepAlive: true)
class LocationController extends _$LocationController {
  @override
  Stream<Position?> build() async* {
    final serviceStatusSub = Geolocator.getServiceStatusStream().listen((
      status,
    ) {
      ref.invalidateSelf();
    });
    ref.onDispose(serviceStatusSub.cancel);

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      yield null;
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      yield null;
      return;
    }

    bool isPowerSave = false;
    try {
      isPowerSave = await Battery().isInBatterySaveMode;
    } catch (e) {
      print("[LocationController] Error checking battery save mode: $e");
    }

    yield* Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: isPowerSave ? LocationAccuracy.medium : LocationAccuracy.high,
        distanceFilter: isPowerSave ? 20 : 5,
      ),
    );
  }

  Future<Position?> getCurrentPosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return null;
    }
    if (permission == LocationPermission.deniedForever) return null;

    bool isPowerSave = false;
    try {
      isPowerSave = await Battery().isInBatterySaveMode;
    } catch (e) {
      print("[LocationController] Error checking battery save mode: $e");
    }

    return await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: isPowerSave ? LocationAccuracy.medium : LocationAccuracy.high,
      ),
    );
  }
}

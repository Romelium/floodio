import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:torch_light/torch_light.dart';

part 'sos_flashlight_provider.g.dart';

@riverpod
class SosFlashlightController extends _$SosFlashlightController {
  Timer? _timer;
  int _sequenceIndex = 0;

  // Dot = 200ms
  // Dash = 600ms
  // Gap between symbols = 200ms
  // Gap between letters = 600ms
  // Gap between words = 1400ms

  // Sequence of (isOn, durationMs)
  final List<(bool, int)> _sosSequence = const [
    // S (...)
    (true, 200), (false, 200),
    (true, 200), (false, 200),
    (true, 200), (false, 600),
    // O (---)
    (true, 600), (false, 200),
    (true, 600), (false, 200),
    (true, 600), (false, 600),
    // S (...)
    (true, 200), (false, 200),
    (true, 200), (false, 200),
    (true, 200), (false, 1400),
  ];

  @override
  bool build() {
    ref.onDispose(() {
      _stopFlashing();
    });
    return false;
  }

  Future<bool> toggle() async {
    if (state) {
      state = false;
      await _stopFlashing();
      return false;
    } else {
      return await _startFlashing();
    }
  }

  Future<bool> _startFlashing() async {
    try {
      // Bypass isTorchAvailable() as it can be unreliable on some devices.
      // Directly attempt to enable the torch.
      await TorchLight.enableTorch();
    } on Exception catch (e) {
      print("Torch error: $e");
      return false;
    }

    state = true;
    _sequenceIndex = 0;

    // Since we just turned it on, wait for the first step's duration
    final duration = _sosSequence[0].$2;
    _timer = Timer(Duration(milliseconds: duration), () {
      if (!state) return;
      _sequenceIndex = 1;
      _processNextStep();
    });

    return true;
  }

  void _processNextStep() async {
    if (!state) return;

    final step = _sosSequence[_sequenceIndex];
    final isOn = step.$1;
    final duration = step.$2;

    try {
      if (isOn) {
        await TorchLight.enableTorch();
      } else {
        await TorchLight.disableTorch();
      }
    } on Exception catch (_) {
      // Ignore errors if torch is interrupted
    }

    _timer = Timer(Duration(milliseconds: duration), () {
      if (!state) return;
      _sequenceIndex = (_sequenceIndex + 1) % _sosSequence.length;
      _processNextStep();
    });
  }

  Future<void> _stopFlashing() async {
    _timer?.cancel();
    try {
      await TorchLight.disableTorch();
    } on Exception catch (_) {
      // Ignore
    }
  }
}

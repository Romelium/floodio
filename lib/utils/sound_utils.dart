import 'dart:math';
import 'dart:typed_data';

Uint8List generateWalkieTalkieChirp() {
  // Quick high-tech triple chirp
  return _generateTones(const [(2000.0, 0.03), (2500.0, 0.03), (3000.0, 0.04)]);
}

Uint8List generateSuccessChirp() {
  // Ascending major third (C5 -> E5)
  return _generateTones(const [(523.25, 0.08), (659.25, 0.15)]);
}

Uint8List generateErrorChirp() {
  // Descending minor third (Eb4 -> C4)
  return _generateTones(const [(311.13, 0.12), (261.63, 0.25)]);
}

Uint8List generateConnectionChirp() {
  // Quick double chirp (A5 -> A6)
  return _generateTones(const [(880.0, 0.04), (0.0, 0.02), (1760.0, 0.08)]);
}

Uint8List generateNotificationChirp() {
  // Soft bell-like tone (G5)
  return _generateTones(const [(783.99, 0.15)]);
}

Uint8List _generateTones(List<(double freq, double duration)> tones) {
  const sampleRate = 44100;
  int totalSamples = 0;
  for (var tone in tones) {
    totalSamples += (sampleRate * tone.$2).toInt();
  }

  final byteData = ByteData(44 + totalSamples * 2);

  // RIFF header
  byteData.setUint32(0, 0x52494646, Endian.big); // 'RIFF'
  byteData.setUint32(4, 36 + totalSamples * 2, Endian.little);
  byteData.setUint32(8, 0x57415645, Endian.big); // 'WAVE'

  // fmt chunk
  byteData.setUint32(12, 0x666D7420, Endian.big); // 'fmt '
  byteData.setUint32(16, 16, Endian.little);
  byteData.setUint16(20, 1, Endian.little); // PCM
  byteData.setUint16(22, 1, Endian.little); // Mono
  byteData.setUint32(24, sampleRate, Endian.little);
  byteData.setUint32(28, sampleRate * 2, Endian.little); // Byte rate
  byteData.setUint16(32, 2, Endian.little); // Block align
  byteData.setUint16(34, 16, Endian.little); // Bits per sample

  // data chunk
  byteData.setUint32(36, 0x64617461, Endian.big); // 'data'
  byteData.setUint32(40, totalSamples * 2, Endian.little);

  int offset = 44;
  for (final tone in tones) {
    final freq = tone.$1;
    final duration = tone.$2;
    final numSamples = (sampleRate * duration).toInt();

    final attackSamples = (sampleRate * 0.01).toInt(); // 10ms attack
    final releaseSamples = (sampleRate * 0.02).toInt(); // 20ms release

    for (int i = 0; i < numSamples; i++) {
      if (freq == 0.0) {
        byteData.setInt16(offset, 0, Endian.little);
      } else {
        final t = i / sampleRate;
        double envelope = 1.0;

        if (i < attackSamples) {
          envelope = i / attackSamples;
        } else if (i > numSamples - releaseSamples) {
          envelope = (numSamples - i) / releaseSamples;
        }

        // Add a slight harmonic (e.g., 1st overtone at half amplitude) to make it sound less harsh
        final fundamental = sin(2 * pi * freq * t);
        final harmonic = 0.3 * sin(2 * pi * (freq * 2) * t);

        final sample = ((fundamental + harmonic) * 32767 * 0.25 * envelope)
            .toInt();
        byteData.setInt16(offset, sample, Endian.little);
      }
      offset += 2;
    }
  }

  return byteData.buffer.asUint8List();
}

import 'dart:math';
import 'dart:typed_data';

Uint8List generateWalkieTalkieChirp() {
  return _generateTones(const [(1200.0, 0.06), (1600.0, 0.06), (2000.0, 0.06)]);
}

Uint8List generateSuccessChirp() {
  return _generateTones(const [(800.0, 0.08), (1200.0, 0.12)]);
}

Uint8List generateErrorChirp() {
  return _generateTones(const [(400.0, 0.1), (250.0, 0.15)]);
}

Uint8List generateConnectionChirp() {
  return _generateTones(const [(1500.0, 0.05), (0.0, 0.02), (1500.0, 0.05), (0.0, 0.02), (1500.0, 0.05)]);
}

Uint8List generateNotificationChirp() {
  return _generateTones(const [(1000.0, 0.1)]);
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
    for (int i = 0; i < numSamples; i++) {
      if (freq == 0.0) {
        byteData.setInt16(offset, 0, Endian.little);
      } else {
        final t = i / sampleRate;
        double envelope = 1.0;
        if (i < 100) envelope = i / 100;
        if (i > numSamples - 100) envelope = (numSamples - i) / 100;

        final sample = (sin(2 * pi * freq * t) * 32767 * 0.3 * envelope).toInt();
        byteData.setInt16(offset, sample, Endian.little);
      }
      offset += 2;
    }
  }
  
  return byteData.buffer.asUint8List();
}

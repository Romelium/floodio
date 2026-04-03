import 'dart:math';
import 'dart:typed_data';

Uint8List generateWalkieTalkieChirp() {
  const sampleRate = 44100;
  const frequencies = [1200.0, 1600.0, 2000.0];
  const durationPerTone = 0.06; // 60ms per tone
  
  int totalSamples = 0;
  for (var _ in frequencies) {
    totalSamples += (sampleRate * durationPerTone).toInt();
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
  for (final freq in frequencies) {
    final numSamples = (sampleRate * durationPerTone).toInt();
    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      // Add a slight envelope to avoid clicks
      double envelope = 1.0;
      if (i < 100) envelope = i / 100;
      if (i > numSamples - 100) envelope = (numSamples - i) / 100;
      
      final sample = (sin(2 * pi * freq * t) * 32767 * 0.3 * envelope).toInt();
      byteData.setInt16(offset, sample, Endian.little);
      offset += 2;
    }
  }
  
  return byteData.buffer.asUint8List();
}

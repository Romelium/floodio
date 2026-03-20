import 'dart:typed_data';

class BloomFilter {
  final int size;
  final int hashFunctions;
  late final Uint32List _bits;

  BloomFilter(this.size, this.hashFunctions) {
    _bits = Uint32List((size / 32).ceil());
  }

  BloomFilter.fromList(List<int> list, this.size, this.hashFunctions) {
    final expectedLength = (size / 32).ceil();
    if (list.length == expectedLength) {
      _bits = Uint32List.fromList(list);
    } else {
      _bits = Uint32List(expectedLength); // Fallback to empty if invalid
    }
  }

  void add(String item) {
    for (int i = 0; i < hashFunctions; i++) {
      int hash = _hash(item, i) % size;
      _bits[hash ~/ 32] |= (1 << (hash % 32));
    }
  }

  bool mightContain(String item) {
    for (int i = 0; i < hashFunctions; i++) {
      int hash = _hash(item, i) % size;
      if ((_bits[hash ~/ 32] & (1 << (hash % 32))) == 0) {
        return false;
      }
    }
    return true;
  }

  int _hash(String item, int seed) {
    // FNV-1a hash variant
    int hash = 0x811c9dc5 ^ seed;
    for (int i = 0; i < item.length; i++) {
      hash ^= item.codeUnitAt(i);
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  List<int> get bits => _bits.toList();
}

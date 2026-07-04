class MasterKeyProvider {
  MasterKeyProvider._();

  static final MasterKeyProvider _instance = MasterKeyProvider._();
  static MasterKeyProvider get instance => _instance;

  List<int>? _key;

  List<int>? get key => _key;

  void setKey(List<int> key) {
    _key = List<int>.from(key);
  }

  void clearKey() {
    final k = _key;
    _key = null;
    // Overwrite key bytes in memory before releasing for GC
    if (k != null) {
      for (var i = 0; i < k.length; i++) {
        k[i] = 0;
      }
    }
  }

  bool get isUnlocked => _key != null;
}

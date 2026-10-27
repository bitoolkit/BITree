/// Reuses recent reads and shares requests that are already in progress.
/// Failed reads and null results are not cached.
class ReadCache<K, V> {
  ReadCache({required this._maxAge});

  final Duration _maxAge;
  final _entries = <K, _ReadEntry<V>>{};

  Future<V> read(K key, Future<V> Function() load, {bool refresh = false}) {
    final now = DateTime.now();
    _entries.removeWhere((_, entry) {
      final saved = entry.saved;
      return entry.pending == null &&
          (saved == null || !saved.expiresAt.isAfter(now));
    });

    final entry = _entries.putIfAbsent(key, _ReadEntry<V>.new);
    final pending = entry.pending;
    if (pending != null) return pending;

    final saved = entry.saved;
    if (!refresh && saved != null) return Future.value(saved.value);

    return entry.pending = _load(entry, load);
  }

  Future<V> _load(_ReadEntry<V> entry, Future<V> Function() load) async {
    try {
      final value = await Future<V>.sync(load);
      if (value != null) {
        entry.saved = (value: value, expiresAt: DateTime.now().add(_maxAge));
      }
      return value;
    } finally {
      entry.pending = null;
    }
  }

  // A detached in-flight entry cannot repopulate the cache after clearing it.
  void clear() => _entries.clear();
}

class _ReadEntry<V> {
  ({V value, DateTime expiresAt})? saved;
  Future<V>? pending;
}

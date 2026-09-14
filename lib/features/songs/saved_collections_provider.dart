import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/settings_store.dart';
import 'saved_collections_store.dart';

export 'saved_collections_store.dart' show SavedCollection;

final savedCollectionsStoreProvider = Provider<SavedCollectionsStore>((ref) {
  return SavedCollectionsStore(ref.read(sharedPreferencesProvider));
});

/// 有序列表（新收藏在前），toggle 时同时写盘，UI watch 即实时响应。
final savedCollectionsProvider =
    StateNotifierProvider<SavedCollectionsController, List<SavedCollection>>(
      (ref) => SavedCollectionsController(ref.read(savedCollectionsStoreProvider)),
    );

class SavedCollectionsController
    extends StateNotifier<List<SavedCollection>> {
  SavedCollectionsController(this._store) : super(_store.read());

  final SavedCollectionsStore _store;

  bool isSaved(String dedupKey) =>
      state.any((entry) => entry.dedupKey == dedupKey);

  void toggle(SavedCollection collection) {
    final key = collection.dedupKey;
    final List<SavedCollection> next;
    if (state.any((entry) => entry.dedupKey == key)) {
      next = state
          .where((entry) => entry.dedupKey != key)
          .toList(growable: false);
    } else {
      next = [collection, ...state];
    }
    state = next;
    unawaited(_store.write(next));
  }
}

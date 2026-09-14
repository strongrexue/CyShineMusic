import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/music_info.dart';
import '../../core/storage/settings_store.dart';
import 'play_history_store.dart';

final playHistoryStoreProvider = Provider<PlayHistoryStore>((ref) {
  return PlayHistoryStore(ref.read(sharedPreferencesProvider));
});

final playHistoryProvider =
    StateNotifierProvider<PlayHistoryController, List<MusicInfo>>((ref) {
      return PlayHistoryController(ref.read(playHistoryStoreProvider));
    });

class PlayHistoryController extends StateNotifier<List<MusicInfo>> {
  PlayHistoryController(this._store) : super(_store.read());

  final PlayHistoryStore _store;

  /// 在播放器切歌时调用：同 id 去重移到最前，上限 50 条。
  void add(MusicInfo music) {
    final id = '${music.source.code}:${music.id}';
    final next = [
      music,
      ...state.where((m) => '${m.source.code}:${m.id}' != id),
    ];
    if (next.length > PlayHistoryStore.maxEntries) {
      next.removeRange(PlayHistoryStore.maxEntries, next.length);
    }
    state = next;
    unawaited(_store.write(next));
  }

  void clear() {
    state = const [];
    unawaited(_store.write(const []));
  }
}

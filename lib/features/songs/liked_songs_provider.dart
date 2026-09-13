import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/music_info.dart';
import '../../core/storage/settings_store.dart';
import 'liked_songs_store.dart';

export 'liked_songs_store.dart' show LikedSongEntry;

/// 收藏键：'${source.code}:${music.id}'，与播放页由 track.id 去掉
/// ':remote' 后缀得到的键一致。
String likedSongId(MusicInfo music) => '${music.source.code}:${music.id}';

final likedSongsStoreProvider = Provider<LikedSongsStore>((ref) {
  return LikedSongsStore(ref.read(sharedPreferencesProvider));
});

/// 有序列表（新收藏在前），toggle 时同时写盘，UI watch 即实时响应。
final likedSongsProvider =
    StateNotifierProvider<LikedSongsController, List<LikedSongEntry>>((ref) {
      return LikedSongsController(ref.read(likedSongsStoreProvider));
    });

class LikedSongsController extends StateNotifier<List<LikedSongEntry>> {
  LikedSongsController(this._store) : super(_store.read());

  final LikedSongsStore _store;

  bool isLiked(String id) => state.any((entry) => entry.id == id);

  void toggle(MusicInfo music) {
    final id = likedSongId(music);
    final List<LikedSongEntry> next;
    if (state.any((entry) => entry.id == id)) {
      next = state.where((entry) => entry.id != id).toList(growable: false);
    } else {
      next = [
        LikedSongEntry(
          id: id,
          likedAt: DateTime.now().millisecondsSinceEpoch,
          music: music,
        ),
        ...state,
      ];
    }
    state = next;
    unawaited(_store.write(next));
  }
}

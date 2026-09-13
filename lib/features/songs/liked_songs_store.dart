import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/music_info.dart';

/// 单曲收藏的一条记录：id 形如 'kw:123456'，同时保存收藏时刻的完整
/// MusicInfo 快照（序列化为 JSON），保证「喜欢」Tab 能离线还原并播放。
class LikedSongEntry {
  const LikedSongEntry({
    required this.id,
    required this.likedAt,
    required this.music,
  });

  final String id;
  final int likedAt;
  final MusicInfo music;
}

class LikedSongsStore {
  LikedSongsStore(this._prefs);

  static const _storageKey = 'liked_song_ids';

  final SharedPreferences _prefs;

  List<LikedSongEntry> read() {
    final raw = _prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final out = <LikedSongEntry>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final id = map['id'] as String?;
        final musicJson = map['music'];
        if (id == null || id.isEmpty || musicJson is! Map) continue;
        out.add(
          LikedSongEntry(
            id: id,
            likedAt: (map['at'] as num?)?.toInt() ?? 0,
            music: MusicInfo.fromJson(Map<String, dynamic>.from(musicJson)),
          ),
        );
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<void> write(List<LikedSongEntry> entries) {
    return _prefs.setString(
      _storageKey,
      jsonEncode([
        for (final entry in entries)
          {'id': entry.id, 'at': entry.likedAt, 'music': entry.music.toJson()},
      ]),
    );
  }
}

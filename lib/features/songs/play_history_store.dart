import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/music_info.dart';

class PlayHistoryStore {
  PlayHistoryStore(this._prefs);

  static const _storageKey = 'play_history';
  static const maxEntries = 50;

  final SharedPreferences _prefs;

  List<MusicInfo> read() {
    final raw = _prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final out = <MusicInfo>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        try {
          out.add(MusicInfo.fromJson(Map<String, dynamic>.from(item)));
        } catch (_) {
          // skip malformed
        }
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<void> write(List<MusicInfo> entries) {
    return _prefs.setString(
      _storageKey,
      jsonEncode([for (final m in entries) m.toJson()]),
    );
  }
}

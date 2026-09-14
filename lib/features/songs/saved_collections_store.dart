import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/enums.dart';
import '../../core/models/online_collection_kind.dart';

/// 用户通过红心收藏的歌单/榜单。type 区分 playlist / leaderboard，
/// payload 保存原请求参数（source code + boardId/playlistId），点击可直接
/// 跳回详情页。去重键：'${source.code}:$type:$id'。
class SavedCollection {
  const SavedCollection({
    required this.kind,
    required this.id,
    required this.source,
    required this.title,
    this.cover,
    this.subtitle,
    required this.savedAt,
    required this.payload,
  });

  final OnlineCollectionKind kind;
  final String id;
  final MusicSource source;
  final String title;
  final String? cover;
  final String? subtitle;
  final int savedAt;
  final Map<String, dynamic> payload;

  String get dedupKey => '${source.code}:${kind.name}:$id';

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'id': id,
    'source': source.code,
    'title': title,
    'cover': cover,
    'subtitle': subtitle,
    'at': savedAt,
    'payload': payload,
  };

  static SavedCollection? fromJson(Map<String, dynamic> map) {
    final kindStr = map['kind'] as String?;
    if (kindStr == null) return null;
    final kind = OnlineCollectionKind.values.firstWhere(
      (k) => k.name == kindStr,
      orElse: () => OnlineCollectionKind.playlist,
    );
    final source = MusicSource.tryFromCode(map['source'] as String? ?? '') ??
        MusicSource.kw;
    final id = map['id'] as String?;
    if (id == null || id.isEmpty) return null;
    final payloadRaw = map['payload'];
    final payload = payloadRaw is Map
        ? Map<String, dynamic>.from(payloadRaw)
        : <String, dynamic>{};
    return SavedCollection(
      kind: kind,
      id: id,
      source: source,
      title: (map['title'] as String?) ?? '',
      cover: map['cover'] as String?,
      subtitle: map['subtitle'] as String?,
      savedAt: (map['at'] as num?)?.toInt() ?? 0,
      payload: payload,
    );
  }
}

class SavedCollectionsStore {
  SavedCollectionsStore(this._prefs);

  static const _storageKey = 'saved_collections';

  final SharedPreferences _prefs;

  List<SavedCollection> read() {
    final raw = _prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final out = <SavedCollection>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final entry = SavedCollection.fromJson(Map<String, dynamic>.from(item));
        if (entry != null) out.add(entry);
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<void> write(List<SavedCollection> entries) {
    return _prefs.setString(
      _storageKey,
      jsonEncode([for (final entry in entries) entry.toJson()]),
    );
  }
}

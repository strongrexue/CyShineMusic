import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum SongSortMode {
  title('title', '标题', Icons.sort_by_alpha_rounded),
  artist('artist', '歌手', Icons.person_outline_rounded),
  added('added', '添加时间', Icons.schedule_rounded);

  const SongSortMode(this.code, this.label, this.icon);

  final String code;
  final String label;
  final IconData icon;

  static SongSortMode fromCode(String? code) {
    return switch (code) {
      'artist' => SongSortMode.artist,
      'added' => SongSortMode.added,
      _ => SongSortMode.title,
    };
  }
}

/// Header state owned by the songs page (`/songs`). The header itself only
/// renders the batch action row and the overflow menu; tab navigation lives
/// inside [SongsPage].
@immutable
class SongsToolbarState {
  const SongsToolbarState({
    this.owner,
    this.songCount = 0,
    this.selectedCount = 0,
    this.allSelected = false,
    this.batchMode = false,
    this.onSearch,
    this.onOpenHistory,
    this.onToggleBatch,
    this.onToggleSelectAll,
  });

  final Object? owner;
  final int songCount;
  final int selectedCount;
  final bool allSelected;
  final bool batchMode;
  final VoidCallback? onSearch;
  final VoidCallback? onOpenHistory;
  final VoidCallback? onToggleBatch;
  final VoidCallback? onToggleSelectAll;

  bool get attached => owner != null;
  bool get hasSongs => songCount > 0;
  String get searchLabel => '搜索本地歌曲';

  bool matchesView({
    required Object owner,
    required int songCount,
    required int selectedCount,
    required bool allSelected,
    required bool batchMode,
  }) {
    return identical(this.owner, owner) &&
        this.songCount == songCount &&
        this.selectedCount == selectedCount &&
        this.allSelected == allSelected &&
        this.batchMode == batchMode;
  }
}

final songsToolbarStateProvider = StateProvider<SongsToolbarState>(
  (ref) => const SongsToolbarState(),
);

/// The dedicated search route normally focuses its field on entry. Playing a
/// result temporarily leaves that route; when the player returns, focus must
/// stay released so the persistent bottom toolbar is not hidden again.
final songsSearchAutoFocusProvider = StateProvider<bool>((ref) => true);

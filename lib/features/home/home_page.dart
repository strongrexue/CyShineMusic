import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/enums.dart';
import '../../core/models/music_info.dart';
import '../../core/models/playlist_summary.dart';
import '../discovery/discovery_controller.dart';
import '../discovery/widgets/discovery_helpers.dart';
import '../downloads/download_history_store.dart';
import '../../theme/app_theme.dart';
import '../music_sources/music_source_action_guard.dart';
import '../player/player_controller.dart';
import '../playlists/playlist_models.dart';
import '../songs/liked_songs_provider.dart';
import '../songs/play_history_provider.dart';
import 'home_recommend_provider.dart';
import 'widgets/home_search_view.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  bool _searchMode = false;

  void _enterSearch() {
    setState(() => _searchMode = true);
  }

  void _exitSearch() {
    setState(() => _searchMode = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_searchMode) {
      return HomeSearchView(onExit: _exitSearch);
    }
    final scheme = Theme.of(context).colorScheme;
    final history = ref.watch(playHistoryProvider);
    final liked = ref.watch(likedSongsProvider);
    final downloads = ref.watch(downloadHistoryProvider);

    // 推荐音乐：在线取排行榜前 6 首，失败回退本地下载
    final onlineMusic = ref.watch(homeRecommendMusicProvider);
    final recommendedMusic = onlineMusic.asData?.value ??
        downloads
            .where((e) => e.musicInfo != null)
            .take(6)
            .map((e) => e.musicInfo!)
            .toList();
    final isOnlineMusic = onlineMusic.asData?.value != null;

    return ColoredBox(
      color: scheme.surface,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: _HomeSearchEntry(onTap: _enterSearch),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 140),
                children: [
                  _HomeAlbumSection(),
                  const SizedBox(height: 28),
                  if (recommendedMusic.isNotEmpty) ...[
                    _HomeSection(
                      title: '推荐音乐',
                      items: recommendedMusic,
                      onTapItem: isOnlineMusic
                          ? (music) => _playFromOnlineList(music, recommendedMusic)
                          : (music) => _playFromDownloadsList(music, downloads),
                      emptyMessage: '还没有推荐音乐',
                      onSeeAll: () => context.go('/discover'),
                    ),
                    const SizedBox(height: 28),
                  ],
                  _HomeSection(
                    title: '最近播放',
                    items: history.take(6).toList(),
                    onTapItem: (music) => _playFromHistory(music, history),
                    emptyMessage: '还没有播放记录',
                    onSeeAll: history.isNotEmpty
                        ? () => context.go('/songs')
                        : null,
                  ),
                  const SizedBox(height: 28),
                  _HomeSection(
                    title: '喜欢的歌',
                    items: liked.map((e) => e.music).take(6).toList(),
                    onTapItem: (music) => _playFromLiked(music, liked),
                    emptyMessage: '还没有喜欢的音乐',
                    onSeeAll: liked.isNotEmpty
                        ? () => context.go('/songs')
                        : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _playFromOnlineList(
    MusicInfo music,
    List<MusicInfo> items,
  ) async {
    final queue = <DownloadHistoryEntry>[];
    DownloadHistoryEntry? selected;
    for (final m in items) {
      final entry = PlaylistTrack.fromMusicInfo(m).toQueueEntry(
        playlistId: 'recommend',
      );
      if (entry == null) continue;
      queue.add(entry);
      if (m.id == music.id && m.source == music.source) selected = entry;
    }
    final entry = selected;
    if (entry == null) return;
    final available = await ensureQueueEntryMusicSourceAvailable(context, entry);
    if (!available || !mounted) return;
    context.go('/player', extra: '/');
    await ref
        .read(playerControllerProvider.notifier)
        .playFromPlaylistQueue(entry, queue);
  }

  Future<void> _playFromDownloadsList(
    MusicInfo music,
    List<DownloadHistoryEntry> downloads,
  ) async {
    final queue = <DownloadHistoryEntry>[];
    DownloadHistoryEntry? selected;
    for (final entry in downloads) {
      if (entry.musicInfo == null) continue;
      queue.add(entry);
      if (entry.musicId == music.id && entry.sourceCode == music.source.code) {
        selected = entry;
      }
    }
    final entry = selected;
    if (entry == null) return;
    final available = await ensureQueueEntryMusicSourceAvailable(context, entry);
    if (!available || !mounted) return;
    context.go('/player', extra: '/');
    await ref
        .read(playerControllerProvider.notifier)
        .playFromHistoryQueue(entry, queue);
  }

  Future<void> _playFromHistory(MusicInfo music, List<MusicInfo> history) async {
    final queue = <DownloadHistoryEntry>[];
    DownloadHistoryEntry? selected;
    for (final m in history) {
      final entry = PlaylistTrack.fromMusicInfo(m).toQueueEntry(
        playlistId: 'history',
      );
      if (entry == null) continue;
      queue.add(entry);
      if (m.id == music.id && m.source == music.source) selected = entry;
    }
    final entry = selected;
    if (entry == null) return;
    final available = await ensureQueueEntryMusicSourceAvailable(context, entry);
    if (!available || !mounted) return;
    context.go('/player', extra: '/');
    await ref
        .read(playerControllerProvider.notifier)
        .playFromPlaylistQueue(entry, queue);
  }

  Future<void> _playFromLiked(
    MusicInfo music,
    List<LikedSongEntry> liked,
  ) async {
    final queue = <DownloadHistoryEntry>[];
    DownloadHistoryEntry? selected;
    for (final likedEntry in liked) {
      final entry = PlaylistTrack.fromMusicInfo(
        likedEntry.music,
      ).toQueueEntry(playlistId: 'liked:songs');
      if (entry == null) continue;
      queue.add(entry);
      if (likedEntry.music.id == music.id &&
          likedEntry.music.source == music.source) {
        selected = entry;
      }
    }
    final entry = selected;
    if (entry == null) return;
    final available = await ensureQueueEntryMusicSourceAvailable(context, entry);
    if (!available || !mounted) return;
    context.go('/player', extra: '/');
    await ref
        .read(playerControllerProvider.notifier)
        .playFromPlaylistQueue(entry, queue);
  }
}

/// 首页默认态的搜索入口：只读，点击进入完整搜索视图。
class _HomeSearchEntry extends StatelessWidget {
  const _HomeSearchEntry({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: scheme.appInputFill,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            const SizedBox(width: 16),
            Icon(
              Icons.search_rounded,
              color: scheme.onSurfaceVariant,
              size: 21,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '搜索歌曲/歌手/专辑',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 14,
                  height: 1.15,
                ),
              ),
            ),
            const SizedBox(width: 16),
          ],
        ),
      ),
    );
  }
}

class _HomeSection extends StatelessWidget {
  const _HomeSection({
    required this.title,
    required this.items,
    required this.onTapItem,
    required this.emptyMessage,
    this.onSeeAll,
  });

  final String title;
  final List<MusicInfo> items;
  final void Function(MusicInfo) onTapItem;
  final String emptyMessage;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (onSeeAll != null)
                GestureDetector(
                  onTap: onSeeAll,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '查看全部',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: scheme.onSurfaceVariant,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              height: 120,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.22),
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                emptyMessage,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          )
        else
          SizedBox(
            height: 168,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) => _HomeTile(
                music: items[index],
                onTap: () => onTapItem(items[index]),
              ),
            ),
          ),
      ],
    );
  }
}

class _HomeTile extends StatelessWidget {
  const _HomeTile({required this.music, required this.onTap});

  final MusicInfo music;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final coverUrl = music.meta.picUrl;
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 120,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 120,
                height: 120,
                child: coverUrl != null && coverUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: coverUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => Container(
                          color: scheme.primaryContainer,
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.music_note_rounded,
                            color: scheme.onPrimaryContainer,
                            size: 38,
                          ),
                        ),
                        errorWidget: (_, _, _) => Container(
                          color: scheme.primaryContainer,
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.music_note_rounded,
                            color: scheme.onPrimaryContainer,
                            size: 38,
                          ),
                        ),
                      )
                    : Container(
                        color: scheme.primaryContainer,
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.music_note_rounded,
                          color: scheme.onPrimaryContainer,
                          size: 38,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              music.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              music.singer,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 推荐专辑区块：watch 发现页 featuredPlaylistsProvider（酷我源），
/// 加载中显示占位骨架，加载完成显示横向大封面卡片（160x160），
/// 点击跳歌单详情。
class _HomeAlbumSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final asyncPlaylists = ref.watch(
      featuredPlaylistsProvider(MusicSource.kw),
    );
    final playlists = asyncPlaylists.asData?.value ?? const [];
    final isLoading = asyncPlaylists.isLoading && playlists.isEmpty;
    if (playlists.isEmpty && !isLoading) return const SizedBox.shrink();
    final items = playlists.take(6).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '推荐专辑',
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => context.go('/discover'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '查看全部',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: scheme.onSurfaceVariant,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 210,
          child: isLoading
              ? ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: 4,
                  separatorBuilder: (_, _) => const SizedBox(width: 14),
                  itemBuilder: (_, _) => SizedBox(
                    width: 160,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            width: 160,
                            height: 160,
                            color: scheme.surfaceContainerLow,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: 14,
                          width: 100,
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 14),
                  itemBuilder: (context, index) {
                    final summary = items[index];
                    return _HomeAlbumTile(summary: summary);
                  },
                ),
        ),
      ],
    );
  }
}

class _HomeAlbumTile extends StatelessWidget {
  const _HomeAlbumTile({required this.summary});

  final PlaylistSummary summary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => context.push(discoveryPlaylistDetailPath(summary)),
      child: SizedBox(
        width: 160,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                width: 160,
                height: 160,
                child: summary.coverUrl != null &&
                    summary.coverUrl!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: summary.coverUrl!,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => Container(
                          color: scheme.primaryContainer,
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.album_rounded,
                            color: scheme.onPrimaryContainer,
                            size: 42,
                          ),
                        ),
                        errorWidget: (_, _, _) => Container(
                          color: scheme.primaryContainer,
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.album_rounded,
                            color: scheme.onPrimaryContainer,
                            size: 42,
                          ),
                        ),
                      )
                    : Container(
                        color: scheme.primaryContainer,
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.album_rounded,
                          color: scheme.onPrimaryContainer,
                          size: 42,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              summary.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              summary.creator?.trim().isNotEmpty == true
                  ? summary.creator!.trim()
                  : '${summary.source.label}精选',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

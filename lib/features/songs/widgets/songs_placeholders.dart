import 'package:flutter/material.dart';

import '../../../core/ui/expressive_loading_status.dart';

/// 本地音乐 Tab 的操作栏：播放全部胶囊 + 默认排序边框胶囊 + 批量操作图标。
class SongsLocalActions extends StatelessWidget {
  const SongsLocalActions({
    super.key,
    required this.count,
    required this.batchMode,
    required this.onPlayAll,
    required this.onOpenSort,
    required this.onToggleBatch,
  });

  final int count;
  final bool batchMode;
  final VoidCallback? onPlayAll;
  final VoidCallback onOpenSort;
  final VoidCallback? onToggleBatch;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          FilledButton.icon(
            key: const ValueKey('songs-play-all-button'),
            onPressed: count == 0 ? null : onPlayAll,
            icon: const Icon(Icons.play_arrow_rounded, size: 20),
            label: Text('播放全部 ($count)'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              minimumSize: const Size(0, 40),
              shape: const StadiumBorder(),
              textStyle: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Spacer(),
          OutlinedButton.icon(
            key: const ValueKey('songs-sort-button'),
            onPressed: onOpenSort,
            icon: const Icon(Icons.sort_rounded, size: 18),
            label: const Text('默认排序'),
            style: OutlinedButton.styleFrom(
              foregroundColor: scheme.onSurface,
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: const StadiumBorder(),
              side: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.56),
              ),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          _ActionIconButton(
            key: const ValueKey('songs-batch-button'),
            tooltip: batchMode ? '退出批量操作' : '批量操作',
            onPressed: onToggleBatch,
            active: batchMode,
            icon: const Icon(Icons.checklist_rounded, size: 21),
          ),
        ],
      ),
    );
  }
}

class _ActionIconButton extends StatelessWidget {
  const _ActionIconButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.active = false,
  });

  final String tooltip;
  final Widget icon;
  final VoidCallback? onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: 48,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          minimumSize: const Size.square(48),
          foregroundColor: active
              ? scheme.onSecondaryContainer
              : scheme.onSurfaceVariant,
          backgroundColor: active ? scheme.secondaryContainer : null,
          disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.34),
        ),
        icon: icon,
      ),
    );
  }
}

class SongsSearchBar extends StatelessWidget {
  const SongsSearchBar({
    super.key,
    required this.controller,
    this.focusNode,
    required this.query,
    this.autofocus = false,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String query;
  final bool autofocus;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SearchBar(
      key: const ValueKey('songs-search-bar'),
      controller: controller,
      focusNode: focusNode,
      autoFocus: autofocus,
      hintText: '搜索歌曲、歌手或专辑',
      leading: Icon(
        Icons.search_rounded,
        size: 21,
        color: scheme.onSurfaceVariant,
      ),
      trailing: query.isEmpty
          ? null
          : [
              IconButton(
                tooltip: '清除搜索',
                onPressed: onClear,
                icon: const Icon(Icons.close_rounded, size: 20),
              ),
            ],
      onChanged: onChanged,
      onSubmitted: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      elevation: const WidgetStatePropertyAll(0),
      backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerLow),
      side: WidgetStatePropertyAll(
        BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.56)),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      constraints: const BoxConstraints(minHeight: 50, maxHeight: 50),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 14),
      ),
    );
  }
}

class SongListDivider extends StatelessWidget {
  const SongListDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Divider(
      height: 1,
      thickness: 0.7,
      indent: 66,
      endIndent: 4,
      color: scheme.outlineVariant.withValues(alpha: 0.3),
    );
  }
}

class SongsLoading extends StatelessWidget {
  const SongsLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return const ExpressiveLoadingStatus(
      title: '正在整理本地音乐',
      subtitle: '正在读取本地音乐文件夹与歌曲信息，请稍候',
      bottomPadding: 108,
    );
  }
}

class EmptySongs extends StatelessWidget {
  const EmptySongs({super.key, this.error});

  final String? error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final normalizedError = error?.trim();
    final hasError = normalizedError != null && normalizedError.isNotEmpty;
    final containerColor = hasError
        ? scheme.errorContainer
        : scheme.secondaryContainer;
    final contentColor = hasError
        ? scheme.onErrorContainer
        : scheme.onSecondaryContainer;

    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 108),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 330),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: containerColor,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Icon(
                  hasError
                      ? Icons.sync_problem_rounded
                      : Icons.library_music_outlined,
                  size: 40,
                  color: contentColor,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                hasError ? '暂时无法读取歌曲' : '还没有本地歌曲',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                  letterSpacing: -0.15,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                hasError ? normalizedError : '本地音乐文件夹里的歌曲会自动出现在这里，也可以下拉重新扫描。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.swipe_down_alt_rounded,
                      size: 17,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      hasError ? '下拉重试' : '下拉重新扫描',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EmptyLikedSongs extends StatelessWidget {
  const EmptyLikedSongs({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 108),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 330),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Icon(
                  Icons.favorite_border_rounded,
                  size: 40,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                '还没有喜欢的歌曲',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                  letterSpacing: -0.15,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                '在歌曲列表点击右侧 ❤️ 即可收藏到这里',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EmptyPlaylists extends StatelessWidget {
  const EmptyPlaylists({super.key, required this.onManage});

  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 108),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 330),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Icon(
                  Icons.queue_music_rounded,
                  size: 40,
                  color: scheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                '还没有歌单',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                  letterSpacing: -0.15,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                '新建或导入歌单后会显示在这里',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.tonalIcon(
                onPressed: onManage,
                icon: const Icon(Icons.library_music_rounded, size: 19),
                label: const Text('去歌单管理'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  shape: const StadiumBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EmptySongSearch extends StatelessWidget {
  const EmptySongSearch({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 20, 28, 108),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 46,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 14),
            Text(
              '没有匹配的歌曲',
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '换一个歌曲名、歌手或专辑试试',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../theme/app_motion.dart';
import '../../songs/songs_toolbar_state.dart';
import '../shell_route_utils.dart';

class ShellHeader extends ConsumerWidget {
  const ShellHeader({
    super.key,
    required this.location,
    required this.playlistBackLocation,
  });

  final String location;
  final String playlistBackLocation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = shellSchemeFor(location, Theme.of(context).colorScheme);
    final top = MediaQuery.viewPaddingOf(context).top;
    final leaderboardDetail =
        location.startsWith('/discover/leaderboards/') &&
        location.split('/').length > 4;
    final onlineCollectionDetail =
        location.startsWith('/discover/playlists/') || leaderboardDetail;
    final compact =
        location == '/discover' ||
        isSongsLibraryLocation(location) ||
        onlineCollectionDetail;
    final headerTitle = _titleFor(location);

    if (location == '/songs') {
      final songsToolbar = ref.watch(songsToolbarStateProvider);
      return Padding(
        padding: EdgeInsets.fromLTRB(16, top + 10, 16, 8),
        child: SongsHeader(state: songsToolbar, scheme: scheme),
      );
    }

    final showHomeBack = location == '/settings';

    return ShellSectionHeader(
      title: headerTitle,
      compact: compact,
      fontSize: onlineCollectionDetail ? 18 : (compact ? 22 : null),
      leading: showHomeBack
          ? const HomeBackButton()
          : (location == '/playlists/import'
              ? IconButton(
                  tooltip: '返回上一页',
                  onPressed: () {
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go(playlistBackLocation);
                    }
                  },
                  icon: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: scheme.onSurface,
                    size: 21,
                  ),
                )
              : null),
    );
  }

  String _titleFor(String location) {
    if (location == '/') return '首页';
    if (location == '/discover') return '发现';
    if (location.startsWith('/discover/playlists/')) return '歌单详情';
    if (location.startsWith('/discover/leaderboards/')) {
      return location.split('/').length > 4 ? '榜单详情' : '排行榜';
    }
    if (location == '/playlists') return '歌单管理';
    if (location == '/playlists/import') return '导入歌单';
    if (location.startsWith('/playlists/')) return '歌单详情';
    if (location == '/songs/search') return '搜索本地歌曲';
    if (location == '/settings/sources') return '音源管理';
    if (location == '/settings/webdav') return 'WebDAV 同步';
    if (location == '/settings/equalizer') return '均衡器';
    switch (location) {
      case '/history':
      case '/downloads':
        return '下载';
      case '/songs':
        return '收藏';
      case '/player':
        return '播放';
      case '/settings':
        return '设置';
      case '/debug':
        return '调试日志';
      default:
        return '栖弦';
    }
  }
}

/// 分区标题行：状态栏留白 + 可选 leading + 标题。AppShell 的顶栏与自绘顶栏
/// 的发现区页面（`/` 的「发现」、排行榜列表）共用，保证同一套字号与留白。
///
/// 发现区页面自绘顶栏的原因：AppShell 对发现区全部路由不占顶栏空间，
/// 「发现 ↔ 歌单/榜单详情」之间导航器高度不变，详情页的容器变换才不会
/// 让下层列表跳动。
class ShellSectionHeader extends StatelessWidget {
  const ShellSectionHeader({
    super.key,
    required this.title,
    this.compact = false,
    this.fontSize,
    this.leading,
  });

  final String title;

  /// 紧凑留白（首页「发现」、歌曲库）。
  final bool compact;

  /// 为 null 时用 headlineSmall 的默认字号。
  final double? fontSize;

  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final top = MediaQuery.viewPaddingOf(context).top;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        18,
        top + (compact ? 10 : 16),
        18,
        compact ? 8 : 12,
      ),
      child: Row(
        children: [
          if (leading case final leading?) ...[
            leading,
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.headlineSmall?.copyWith(
                color: scheme.onSurface,
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                height: 1.05,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SongsHeader extends StatelessWidget {
  const SongsHeader({super.key, required this.state, required this.scheme});

  final SongsToolbarState state;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    if (state.batchMode) {
      return Container(
        key: const ValueKey('songs-header-batch'),
        height: 44,
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.34),
            ),
            bottom: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.34),
            ),
          ),
        ),
        child: Row(
          children: [
            TextButton(
              onPressed: state.hasSongs ? state.onToggleSelectAll : null,
              style: TextButton.styleFrom(
                minimumSize: const Size(72, 44),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                alignment: Alignment.centerLeft,
              ),
              child: Text(state.allSelected ? '取消全选' : '全选'),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: AppMotion.short,
                child: Text(
                  '已选中 ${state.selectedCount} 项',
                  key: ValueKey(state.selectedCount),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            SizedBox.square(
              dimension: 44,
              child: IconButton(
                tooltip: '退出批量管理',
                onPressed: state.onToggleBatch,
                icon: const Icon(Icons.close_rounded, size: 20),
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      key: const ValueKey('songs-header-normal'),
      height: 44,
      child: Row(
        children: [
          const HomeBackButton(),
          Text(
            '收藏',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: scheme.onSurface,
              fontSize: 22,
              fontWeight: FontWeight.w600,
              height: 1.05,
            ),
          ),
          const Spacer(),
          _LibraryOverflowMenu(
            onOpenHistory: state.onOpenHistory,
            searchLabel: state.searchLabel,
            onSearch: state.onSearch,
          ),
        ],
      ),
    );
  }
}

class _LibraryOverflowMenu extends StatelessWidget {
  const _LibraryOverflowMenu({
    this.onOpenHistory,
    this.searchLabel = '搜索本地歌曲',
    this.onSearch,
  });

  final VoidCallback? onOpenHistory;
  final String searchLabel;
  final VoidCallback? onSearch;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MenuAnchor(
      key: const ValueKey('songs-overflow-menu'),
      useRootOverlay: true,
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerHigh),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(3),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 6),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.search_rounded, size: 20),
          onPressed: onSearch == null
              ? null
              : () {
                  FocusManager.instance.primaryFocus?.unfocus();
                  onSearch!();
                },
          child: Text(searchLabel),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.queue_music_rounded, size: 20),
          onPressed: () => context.go('/playlists'),
          child: const Text('歌单管理'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.history_rounded, size: 20),
          onPressed: onOpenHistory ?? () => context.go('/downloads'),
          child: const Text('下载历史'),
        ),
      ],
      builder: (context, controller, child) => SizedBox.square(
        dimension: 44,
        child: IconButton(
          tooltip: '更多歌曲操作',
          onPressed: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
          icon: const Icon(Icons.more_vert_rounded, size: 21),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}

/// 返回首页箭头：统一用于发现/收藏/设置等顶层 Tab 页面的左上角。
/// 点击直接跳转到首页路由 `/`，不使用系统返回栈。
class HomeBackButton extends StatelessWidget {
  const HomeBackButton({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: 44,
      child: IconButton(
        tooltip: '返回首页',
        onPressed: () => context.go('/'),
        icon: Icon(
          Icons.arrow_back_ios_new_rounded,
          color: scheme.onSurface,
          size: 21,
        ),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

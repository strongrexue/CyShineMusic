import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart' hide SearchController;
import 'package:flutter/material.dart' as material show SearchController;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/music_api.dart';
import '../../../core/debug/debug_paint_guard.dart';
import '../../../core/models/enums.dart';
import '../../../core/models/music_info.dart';
import '../../../core/storage/settings_store.dart';
import '../../../core/ui/app_toast.dart';
import '../../../core/ui/expressive_loading_status.dart';
import '../../discovery/discovery_controller.dart';
import '../../downloads/download_progress.dart';
import '../../music_sources/music_source_action_guard.dart';
import '../../player/player_controller.dart';
import '../../playlists/playlist_browser_sheet.dart';
import '../../playlists/playlist_store.dart';
import '../../search/search_controller.dart';
import '../../search/search_toolbar_state.dart';
import '../../search/widgets/quality_picker_sheet.dart';
import '../../search/widgets/search_result_tile.dart';
import '../../search/widgets/source_filter_chips.dart';

/// 首页的完整搜索视图：搜索建议 + 音源标签 + 分页结果 + 「第 X 页」悬浮按钮。
/// 交互移植自源项目的发现页搜索；返回箭头 / 清除按钮通过 [onExit] 回到首页
/// 默认态（最近播放 / 喜欢的歌）。
class HomeSearchView extends ConsumerStatefulWidget {
  const HomeSearchView({required this.onExit, super.key});

  final VoidCallback onExit;

  @override
  ConsumerState<HomeSearchView> createState() => _HomeSearchViewState();
}

class _HomeSearchViewState extends ConsumerState<HomeSearchView> {
  late final material.SearchController _controller;
  late final ScrollController _resultsScrollController;
  Object? _tipRequest;
  Iterable<Widget> _lastSuggestionWidgets = const <Widget>[];
  AppToastHandle? _searchErrorToast;

  /// 按音源独立维护的分页累加状态（无限滚动）。
  final Map<MusicSource, _SourcePageState> _sourceStates =
      <MusicSource, _SourcePageState>{};

  _SourcePageState _stateFor(MusicSource source) =>
      _sourceStates.putIfAbsent(source, _SourcePageState.new);

  @override
  void initState() {
    super.initState();
    _controller = material.SearchController();
    _resultsScrollController = ScrollController();
    _resultsScrollController.addListener(_onResultsScroll);
    _controller.text = ref.read(searchControllerProvider).keyword;
    // 进入搜索视图即聚焦输入：打开 SearchAnchor 建议层并唤起键盘。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.isAttached) return;
      if (_controller.text.trim().isEmpty) {
        _controller.openView();
      }
    });
  }

  @override
  void dispose() {
    _tipRequest = null;
    _dismissSearchErrorToast();
    _resultsScrollController.removeListener(_onResultsScroll);
    _controller.dispose();
    _resultsScrollController.dispose();
    super.dispose();
  }

  Future<Iterable<Widget>> _buildSuggestionTiles(
    BuildContext context,
    material.SearchController controller,
  ) async {
    final query = controller.text.trim();
    if (query.isEmpty) {
      _tipRequest = null;
      _lastSuggestionWidgets = const <Widget>[];
      return _lastSuggestionWidgets;
    }

    // Identity-only marker — the SDK fan-out can't really cancel, so we just
    // ignore the result if a newer keystroke has started another tip lookup.
    final request = Object();
    _tipRequest = request;
    try {
      final api = ref.read(musicApiProvider);
      final tips = await api.searchTip(
        keyword: query,
        source: _sourceForSearchRequest(ref.read(searchControllerProvider)),
      );
      if (!identical(request, _tipRequest) || query != controller.text.trim()) {
        return _lastSuggestionWidgets;
      }
      final seen = <String>{};
      final items = tips
          .map((tip) => tip.trim())
          .where((tip) => tip.isNotEmpty && seen.add(tip))
          .take(8)
          .map(
            (tip) => _SuggestionTile(
              text: tip,
              onTap: () {
                controller.closeView(tip);
                _runSearch(keyword: tip);
              },
              onComplete: () {
                controller.text = tip;
                controller.selection = TextSelection.collapsed(
                  offset: controller.text.length,
                );
              },
            ),
          )
          .toList(growable: false);
      _lastSuggestionWidgets = items;
      return items;
    } on DioException {
      return _lastSuggestionWidgets;
    }
  }

  Future<void> _runSearch({String? keyword}) async {
    DebugPaintGuard.disableNow();
    final query = (keyword ?? _controller.text).trim();
    if (query.isEmpty) {
      showAppToast(context, '请输入歌名、歌手或专辑', type: AppToastType.warning);
      return;
    }
    _controller.text = query;
    _controller.selection = TextSelection.collapsed(offset: query.length);
    if (_controller.isAttached && _controller.isOpen) {
      _controller.closeView(query);
    }
    _dismissTransientRoutes();
    _releaseSearchFocus();

    // 关键词变化：清空所有音源的累加缓存，重新从第 1 页开始。
    for (final state in _sourceStates.values) {
      state
        ..page = 1
        ..results.clear()
        ..hasMore = true
        ..isLoadingMore = false;
    }

    final requestedSource = _sourceForSearchRequest(
      ref.read(searchControllerProvider),
    );
    await ref
        .read(searchControllerProvider.notifier)
        .search(keyword: query, source: requestedSource, page: 1);
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_resultsScrollController.hasClients) return;
      _resultsScrollController.jumpTo(
        _resultsScrollController.position.minScrollExtent,
      );
    });
  }

  /// 音源切换：缓存命中直接展示，未加载过才请求第 1 页。
  void _onSourceSelected(MusicSource source) {
    final current = ref.read(searchControllerProvider).source;
    if (source == current) return;
    ref.read(searchControllerProvider.notifier).selectSource(source);
    final st = _stateFor(source);
    if (st.results.isNotEmpty) return; // 缓存命中，直接展示
    final keyword = ref.read(searchControllerProvider).keyword.trim();
    if (keyword.isEmpty) return;
    ref
        .read(searchControllerProvider.notifier)
        .search(keyword: keyword, source: source, page: 1);
  }

  void _onResultsScroll() {
    if (!_resultsScrollController.hasClients) return;
    final position = _resultsScrollController.position;
    // 内容不足一屏时不触发加载，避免首屏过少时连续级联请求。
    if (position.maxScrollExtent <= 0) return;
    if (position.extentAfter >= 200) return;
    final source = ref.read(searchControllerProvider).source;
    final st = _stateFor(source);
    if (st.isLoadingMore || !st.hasMore) return;
    _loadNextPage(source);
  }

  Future<void> _loadNextPage(MusicSource source) async {
    final st = _stateFor(source);
    if (st.isLoadingMore) return;
    st.isLoadingMore = true;
    if (mounted) setState(() {});

    final keyword = ref.read(searchControllerProvider).keyword.trim();
    final requestPage = st.page + 1;
    try {
      final api = ref.read(musicApiProvider);
      final response = await api.searchMusic(
        keyword: keyword,
        source: source,
        page: requestPage,
        limit: 30,
      );
      if (!mounted) return;
      // 中途关键词或音源变化：丢弃本次结果。
      final stillCurrent =
          ref.read(searchControllerProvider).keyword.trim() == keyword &&
          ref.read(searchControllerProvider).source == source;
      if (!stillCurrent) return;

      if (response.list.isEmpty) {
        st.hasMore = false;
      } else {
        final seen = st.results.map((m) => m.id).toSet();
        for (final music in response.list) {
          if (seen.add(music.id)) st.results.add(music);
        }
        st.page = response.page;
      }
    } catch (error) {
      if (mounted) {
        showAppToast(context, '加载更多失败：$error', type: AppToastType.error);
      }
      // 保留 hasMore = true，下次滚动可重试。
    } finally {
      if (mounted) {
        st.isLoadingMore = false;
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(searchControllerProvider);
    final scheme = Theme.of(context).colorScheme;

    ref.listen<Set<MusicSource>>(
      settingsProvider.select((settings) => settings.enabledSearchSources),
      (previous, next) {
        _tipRequest = null;
        _lastSuggestionWidgets = const <Widget>[];
      },
    );

    ref.listen<SearchState>(searchControllerProvider, _handleSearchStateChanged);

    // 监听控制器响应（第 1 页）：把结果 seed 到对应音源的累加列表。
    // 加路由守卫，防止发现页共用 controller 时污染首页缓存。
    ref.listen(
      searchControllerProvider.select((s) => s.response),
      (previous, next) {
        if (next == null) return;
        final location = GoRouterState.of(context).uri.path;
        if (location != '/') return;
        final current = ref.read(searchControllerProvider);
        if (current.page != 1) return;
        final st = _stateFor(current.source);
        st
          ..page = 1
          ..results.clear()
          ..results.addAll(next.list)
          ..hasMore = next.list.isNotEmpty
          ..isLoadingMore = false;
        if (mounted) setState(() {});
      },
    );

    return BackButtonListener(
      onBackButtonPressed: _handleBackButton,
      child: ColoredBox(
        color: scheme.surface,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: _HomeSearchBarField(
                  controller: _controller,
                  onSubmitted: (v) => _runSearch(keyword: v),
                  loading: state.loading,
                  suggestionsBuilder: _buildSuggestionTiles,
                  onExit: _exitSearch,
                ),
              ),
              if (state.isSearchActive) ...[
                SourceFilterChips(onSourceSelected: _onSourceSelected),
                const SizedBox(height: 4),
              ],
              Expanded(
                child: _ResultsArea(
                  state: state,
                  sourceState: _stateFor(state.source),
                  scrollController: _resultsScrollController,
                  onTapItem: _openPicker,
                  onPlayItem: _play,
                  onAddToPlaylist: _selectPlaylistForMusic,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _handleBackButton() async {
    // 建议下拉层打开时，系统返回键先收起下拉；再次返回才退出搜索视图。
    if (_controller.isAttached && _controller.isOpen) {
      _controller.closeView(_controller.text);
      return true;
    }
    _exitSearch();
    return true;
  }

  Future<void> _openPicker(MusicInfo music) async {
    await showQualityPickerSheet(context, music);
  }

  Future<void> _play(MusicInfo music) async {
    final available = await ensureOnlineMusicSourcesAvailable(context, [
      music.source,
    ]);
    if (!available || !mounted) return;
    context.go('/player', extra: '/');
    await ref.read(playerControllerProvider.notifier).playFromMusic(music);
  }

  Future<void> _selectPlaylistForMusic(MusicInfo music) async {
    final destination = await showPlaylistBrowserSheet(
      context,
      mode: PlaylistBrowserMode.addSongs,
    );
    if (!mounted || destination == null) return;

    const prefix = '/playlists/';
    if (!destination.startsWith(prefix)) return;
    final playlistId = destination.substring(prefix.length);
    final store = ref.read(localPlaylistsProvider.notifier);
    final playlist = store.byId(playlistId);
    if (playlist == null) {
      showAppToast(context, '歌单不存在或已被删除', type: AppToastType.warning);
      return;
    }

    try {
      final added = await store.addMusic(playlistId, music);
      if (!mounted) return;
      showAppToast(
        context,
        added == 0 ? '歌曲已在「${playlist.name}」中' : '已添加到「${playlist.name}」',
        type: added == 0 ? AppToastType.info : AppToastType.success,
      );
    } catch (error) {
      if (!mounted) return;
      showAppToast(context, '添加到歌单失败：$error', type: AppToastType.error);
    }
  }

  void _exitSearch() {
    _controller.clear();
    if (_controller.isAttached && _controller.isOpen) {
      _controller.closeView('');
    }
    _tipRequest = null;
    _lastSuggestionWidgets = const <Widget>[];
    _dismissSearchErrorToast();
    ref.read(searchControllerProvider.notifier).resetToDiscovery();
    // 退出搜索时清空累加缓存。
    for (final st in _sourceStates.values) {
      st
        ..page = 1
        ..results.clear()
        ..hasMore = true
        ..isLoadingMore = false;
    }
    ref.read(searchToolbarStateProvider.notifier).state =
        const SearchToolbarState();
    _releaseSearchFocus();
    widget.onExit();
  }

  void _dismissTransientRoutes() {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(
      context,
      rootNavigator: true,
    ).popUntil((route) => route.isFirst);
  }

  void _releaseSearchFocus() {
    FocusManager.instance.primaryFocus?.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      FocusManager.instance.primaryFocus?.unfocus();
    });
  }

  void _handleSearchStateChanged(SearchState? previous, SearchState next) {
    if (!mounted) return;
    if (next.error != null && next.error != previous?.error) {
      _dismissSearchErrorToast();
      _searchErrorToast = showAppToast(
        context,
        next.error!,
        type: AppToastType.error,
      );
    } else if (next.error == null && previous?.error != null) {
      _dismissSearchErrorToast();
    }
  }

  void _dismissSearchErrorToast() {
    final toast = _searchErrorToast;
    _searchErrorToast = null;
    dismissAppToast(toast, showRemoveAnimation: false);
  }

  MusicSource _sourceForSearchRequest(SearchState state) {
    if (state.isSearchActive) return state.source;
    final discoverySource = ref.read(selectedDiscoverySourceProvider);
    final enabled = ref.read(settingsProvider).enabledSearchSources;
    if (enabled.contains(discoverySource)) return discoverySource;
    return state.source == MusicSource.all || !enabled.contains(state.source)
        ? MusicSource.all
        : state.source;
  }
}

class _HomeSearchBarField extends StatelessWidget {
  const _HomeSearchBarField({
    required this.controller,
    required this.onSubmitted,
    required this.onExit,
    required this.loading,
    required this.suggestionsBuilder,
  });

  final material.SearchController controller;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onExit;
  final bool loading;
  final Future<Iterable<Widget>> Function(
    BuildContext context,
    material.SearchController controller,
  )
  suggestionsBuilder;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textStyle = WidgetStatePropertyAll(
      TextStyle(
        color: scheme.onSurface,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        height: 1.1,
        letterSpacing: 0,
      ),
    );
    final hintStyle = WidgetStatePropertyAll(
      TextStyle(
        color: scheme.onSurfaceVariant.withValues(alpha: 0.76),
        fontSize: 13,
        fontWeight: FontWeight.w500,
        height: 1.1,
      ),
    );
    final shape = WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
    return SearchAnchor.bar(
      searchController: controller,
      isFullScreen: false,
      barHintText: '搜索歌曲、歌手、专辑',
      barLeading: IconButton(
        tooltip: '返回',
        onPressed: onExit,
        color: scheme.onSurfaceVariant,
        icon: const Icon(Icons.arrow_back_rounded, size: 22),
      ),
      barTrailing: [
        _SearchTrailing(
          controller: controller,
          loading: loading,
          onClear: onExit,
        ),
      ],
      barElevation: const WidgetStatePropertyAll(0),
      barBackgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerHigh),
      barOverlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return scheme.primary.withValues(alpha: 0.08);
        }
        if (states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.focused)) {
          return scheme.primary.withValues(alpha: 0.05);
        }
        return Colors.transparent;
      }),
      barSide: WidgetStatePropertyAll(
        BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.28)),
      ),
      barShape: shape,
      barPadding: const WidgetStatePropertyAll(
        EdgeInsetsDirectional.fromSTEB(4, 0, 6, 0),
      ),
      barTextStyle: textStyle,
      barHintStyle: hintStyle,
      constraints: const BoxConstraints(minHeight: 48, maxHeight: 48),
      viewConstraints: BoxConstraints(
        maxHeight: math.min(MediaQuery.sizeOf(context).height * 0.52, 520),
      ),
      viewShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      viewSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.8)),
      viewBackgroundColor: scheme.surfaceContainerHigh,
      viewElevation: 0,
      dividerColor: scheme.outlineVariant.withValues(alpha: 0.72),
      viewBarPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      viewHeaderHeight: 48,
      viewHeaderTextStyle: textStyle.value,
      viewHeaderHintStyle: hintStyle.value,
      shrinkWrap: true,
      textCapitalization: TextCapitalization.none,
      textInputAction: TextInputAction.search,
      keyboardType: TextInputType.text,
      suggestionsBuilder: suggestionsBuilder,
      onSubmitted: onSubmitted,
    );
  }
}

class _SearchTrailing extends StatelessWidget {
  const _SearchTrailing({
    required this.controller,
    required this.loading,
    required this.onClear,
  });

  final material.SearchController controller;
  final bool loading;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: 36,
      child: Center(
        child: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            if (value.text.isEmpty) {
              return const SizedBox.shrink(key: ValueKey('empty'));
            }
            return IconButton(
              key: const ValueKey('clear'),
              tooltip: loading ? '取消搜索' : '清除',
              visualDensity: VisualDensity.compact,
              color: scheme.onSurfaceVariant,
              onPressed: onClear,
              icon: loading
                  ? SizedBox.square(
                      key: const ValueKey('loading-cancel'),
                      dimension: 22,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircularProgressIndicator(
                            strokeWidth: 2,
                            color: scheme.primary,
                          ),
                          Icon(
                            Icons.close_rounded,
                            size: 14,
                            color: scheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    )
                  : const Icon(Icons.close_rounded),
            );
          },
        ),
      ),
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({
    required this.text,
    required this.onTap,
    required this.onComplete,
  });

  final String text;
  final VoidCallback onTap;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      minTileHeight: 54,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18),
      minLeadingWidth: 34,
      leading: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.history_rounded,
          color: scheme.onSurfaceVariant,
          size: 18,
        ),
      ),
      title: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: scheme.onSurface,
          fontSize: 14.5,
          fontWeight: FontWeight.w500,
          letterSpacing: -0.05,
        ),
      ),
      trailing: IconButton(
        tooltip: '补全',
        icon: const Icon(Icons.north_west_rounded),
        iconSize: 19,
        color: scheme.onSurfaceVariant,
        visualDensity: VisualDensity.compact,
        onPressed: onComplete,
      ),
      onTap: onTap,
    );
  }
}

class _SearchPreludeArt extends StatelessWidget {
  const _SearchPreludeArt();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: 108,
      child: CustomPaint(painter: _SearchPreludePainter(scheme)),
    );
  }
}

class _SearchPreludePainter extends CustomPainter {
  const _SearchPreludePainter(this.scheme);

  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    final primary = scheme.primary;
    final tertiary = scheme.tertiary;
    final surface = scheme.surfaceContainerHighest;

    final prismRect = Rect.fromLTWH(
      size.width * 0.28,
      size.height * 0.3,
      size.width * 0.44,
      size.height * 0.42,
    );
    final prismPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = surface.withValues(alpha: 0.64);
    final prismRadius = Radius.circular(size.width * 0.16);
    canvas.drawRRect(
      RRect.fromRectAndRadius(prismRect, prismRadius),
      prismPaint,
    );

    final lowerWavePath = Path()
      ..moveTo(size.width * 0.18, size.height * 0.58)
      ..cubicTo(
        size.width * 0.28,
        size.height * 0.38,
        size.width * 0.43,
        size.height * 0.8,
        size.width * 0.56,
        size.height * 0.52,
      )
      ..cubicTo(
        size.width * 0.68,
        size.height * 0.28,
        size.width * 0.78,
        size.height * 0.72,
        size.width * 0.86,
        size.height * 0.48,
      );
    final lowerWavePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.058
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = primary.withValues(alpha: 0.86);
    canvas.drawPath(lowerWavePath, lowerWavePaint);

    final upperWavePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.044
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = tertiary.withValues(alpha: 0.72);
    canvas.drawArc(
      Rect.fromLTWH(
        size.width * 0.16,
        size.height * 0.34,
        size.width * 0.68,
        size.height * 0.38,
      ),
      math.pi * 1.08,
      math.pi * 0.84,
      false,
      upperWavePaint,
    );

    final barPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.054
      ..strokeCap = StrokeCap.round
      ..color = tertiary.withValues(alpha: 0.82);
    final bars = <({double x, double top, double bottom})>[
      (x: 0.31, top: 0.51, bottom: 0.66),
      (x: 0.44, top: 0.41, bottom: 0.7),
      (x: 0.57, top: 0.37, bottom: 0.64),
      (x: 0.7, top: 0.47, bottom: 0.67),
    ];
    for (final bar in bars) {
      canvas.drawLine(
        Offset(size.width * bar.x, size.height * bar.top),
        Offset(size.width * bar.x, size.height * bar.bottom),
        barPaint,
      );
    }

    final glintPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.024
      ..strokeCap = StrokeCap.round
      ..color = primary.withValues(alpha: 0.36);
    canvas.drawLine(
      Offset(size.width * 0.28, size.height * 0.29),
      Offset(size.width * 0.34, size.height * 0.29),
      glintPaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.31, size.height * 0.26),
      Offset(size.width * 0.31, size.height * 0.32),
      glintPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _SearchPreludePainter oldDelegate) {
    return oldDelegate.scheme != scheme;
  }
}

class _SearchLoadingStatus extends StatelessWidget {
  const _SearchLoadingStatus();

  @override
  Widget build(BuildContext context) {
    return const ExpressiveLoadingStatus(
      title: '正在搜索',
      subtitle: '正在聚合多个音乐平台的结果',
    );
  }
}

class _CenterStatus extends StatelessWidget {
  const _CenterStatus({
    required this.title,
    this.subtitle,
    this.art,
    this.icon,
    this.compact = false,
  });

  final String title;
  final String? subtitle;
  final Widget? art;
  final IconData? icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visual =
        art ??
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(24),
          ),
          alignment: Alignment.center,
          child: Icon(
            icon ?? Icons.search_rounded,
            size: 34,
            color: scheme.onSurfaceVariant,
          ),
        );

    return Align(
      alignment: Alignment(0, compact ? -0.34 : -0.24),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            visual,
            SizedBox(height: art != null ? 8 : 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: scheme.onSurface,
                fontWeight: FontWeight.w600,
                fontSize: 17.5,
                height: 1.16,
                letterSpacing: -0.12,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 7),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  height: 1.42,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ResultsArea extends StatelessWidget {
  const _ResultsArea({
    required this.state,
    required this.sourceState,
    required this.scrollController,
    required this.onTapItem,
    required this.onPlayItem,
    required this.onAddToPlaylist,
  });

  final SearchState state;
  final _SourcePageState sourceState;
  final ScrollController scrollController;
  final ValueChanged<MusicInfo> onTapItem;
  final ValueChanged<MusicInfo> onPlayItem;
  final ValueChanged<MusicInfo> onAddToPlaylist;

  @override
  Widget build(BuildContext context) {
    if (state.loading && state.response == null) {
      return const _SearchLoadingStatus();
    }
    final response = state.response;
    if (response == null) {
      return const _CenterStatus(
        art: _SearchPreludeArt(),
        title: '即刻开始搜索',
        subtitle: '输入歌名、歌手或专辑，发现可播放与下载的版本',
      );
    }
    final list = sourceState.results;
    if (list.isEmpty) {
      if (state.loading) return const _SearchLoadingStatus();
      return const _CenterStatus(
        icon: Icons.manage_search_rounded,
        title: '没有找到结果',
        subtitle: '试试更换关键词或音乐来源',
        compact: true,
      );
    }
    return ListView.separated(
      key: const PageStorageKey('home-search-results-scroll'),
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 156),
      itemCount: list.length + 2,
      separatorBuilder: (_, index) {
        if (index == 0) return const SizedBox(height: 2);
        // 最后一条结果与 footer 之间不画分隔线。
        if (index == list.length) return const SizedBox.shrink();
        return const _SearchResultDivider();
      },
      itemBuilder: (_, index) {
        if (index == 0) {
          return _ResultsSummary(loadedCount: list.length);
        }
        if (index == list.length + 1) {
          return _LoadMoreFooter(
            isLoadingMore: sourceState.isLoadingMore,
            hasMore: sourceState.hasMore,
          );
        }
        final music = list[index - 1];
        return _ResultTile(
          music: music,
          onTapItem: onTapItem,
          onPlayItem: onPlayItem,
          onAddToPlaylist: onAddToPlaylist,
        );
      },
    );
  }
}

class _SearchResultDivider extends StatelessWidget {
  const _SearchResultDivider();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Divider(
      height: 1,
      thickness: 0.7,
      indent: 56,
      endIndent: 4,
      color: scheme.outlineVariant.withValues(alpha: 0.3),
    );
  }
}

class _ResultsSummary extends StatelessWidget {
  const _ResultsSummary({required this.loadedCount});

  final int loadedCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 2, 2, 4),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '搜索结果',
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
            TextSpan(
              text: '  ·  已加载 $loadedCount 首',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 10.75,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _LoadMoreFooter extends StatelessWidget {
  const _LoadMoreFooter({
    required this.isLoadingMore,
    required this.hasMore,
  });

  final bool isLoadingMore;
  final bool hasMore;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (isLoadingMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              color: scheme.primary,
            ),
          ),
        ),
      );
    }
    if (!hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(
            '没有更多结果',
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

class _SourcePageState {
  int page = 1;
  final List<MusicInfo> results = <MusicInfo>[];
  bool hasMore = true;
  bool isLoadingMore = false;
}

class _ResultTile extends ConsumerWidget {
  const _ResultTile({
    required this.music,
    required this.onTapItem,
    required this.onPlayItem,
    required this.onAddToPlaylist,
  });

  final MusicInfo music;
  final ValueChanged<MusicInfo> onTapItem;
  final ValueChanged<MusicInfo> onPlayItem;
  final ValueChanged<MusicInfo> onAddToPlaylist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watching the per-music task (instances are reused for untouched tasks)
    // keeps progress updates from rebuilding every tile in the list.
    final task = ref.watch(
      downloadProgressProvider.select((p) => p.latestTaskForMusic(music.id)),
    );
    return SearchResultTile(
      music: music,
      onDownload: () => onTapItem(music),
      onPlay: () => onPlayItem(music),
      onAddToPlaylist: () => onAddToPlaylist(music),
      downloadTask: task,
    );
  }
}

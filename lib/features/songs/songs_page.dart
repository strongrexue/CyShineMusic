import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/enums.dart';
import '../../core/services/embedded_artwork_cache.dart';
import '../../core/services/tagger.dart';
import '../../core/storage/settings_store.dart';
import '../../core/ui/app_scrollbar.dart';
import '../../core/ui/app_toast.dart';
import '../../core/ui/app_refresh_indicator.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_theme.dart';
import '../downloads/download_history_store.dart';
import '../music_sources/music_source_action_guard.dart';
import '../player/player_controller.dart';
import '../playlists/playlist_browser_sheet.dart';
import '../playlists/playlist_models.dart';
import '../playlists/playlist_store.dart';
import '../playlists/widgets/playlist_artwork.dart';
import '../search/widgets/quality_picker_sheet.dart';
import '../search/widgets/search_result_tile.dart';
import '../shell/shell_toolbar_visibility.dart';
import 'liked_songs_provider.dart';
import 'local_song_scan_cache.dart';
import 'scanned_song_file.dart';
import 'song_search.dart';
import 'songs_toolbar_state.dart';
import 'widgets/song_row.dart';
import 'widgets/songs_batch_action_bar.dart';
import 'widgets/songs_placeholders.dart';
import 'widgets/songs_sort_sheet.dart';

const _songTagReadTimeout = Duration(seconds: 8);
const _songScanCacheTtl = Duration(seconds: 12);
const _songSortModeKey = 'songs_sort_mode_v1';
const _songSortAscendingKey = 'songs_sort_ascending_v1';

enum _CollectionTab { liked, local, playlists }

class SongsPage extends ConsumerStatefulWidget {
  const SongsPage({super.key, this.searchMode = false});

  final bool searchMode;

  @override
  ConsumerState<SongsPage> createState() => _SongsPageState();
}

class _SongsPageState extends ConsumerState<SongsPage> {
  SongSortMode _sortMode = SongSortMode.title;
  bool _ascending = true;
  bool _batchMode = false;
  _CollectionTab _tab = _CollectionTab.local;
  String _searchQuery = '';
  final Object _toolbarOwner = Object();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode(debugLabel: 'songs-search');
  bool? _toolbarVisibilityBeforeSearchFocus;
  bool _tabRestored = false;
  static const _tabStorageKey = ValueKey('songs-collection-tab');
  List<DownloadHistoryEntry> _visibleSongs = const [];
  final Set<String> _selectedIds = <String>{};
  final Map<String, EmbeddedAudioTags?> _tagCache = {};
  final Map<String, DateTime> _tagModifiedAt = {};
  final Set<String> _tagLoadingKeys = <String>{};
  List<ScannedSongFile>? _scannedFiles;
  String? _scanError;
  int _scanGeneration = 0;
  Timer? _tagFlushTimer;
  ProviderSubscription<String>? _localMusicDirSubscription;
  late final StateController<SongsToolbarState> _toolbarStateController;
  late final LocalSongScanCache _scanCache;
  late final Future<void> _firstRouteTransitionSettled;

  @override
  void initState() {
    super.initState();
    final prefs = ref.read(sharedPreferencesProvider);
    _sortMode = SongSortMode.fromCode(prefs.getString(_songSortModeKey));
    _ascending = prefs.getBool(_songSortAscendingKey) ?? true;
    _toolbarStateController = ref.read(songsToolbarStateProvider.notifier);
    _scanCache = ref.read(localSongScanCacheProvider);
    _seedFromScanCache();
    _scanCache.addListener(_handleScanCacheChanged);
    if (widget.searchMode) _enableSearchFocusHandling();
    _firstRouteTransitionSettled = _waitForFirstRouteTransition();
    _localMusicDirSubscription = ref.listenManual(
      settingsProvider.select((settings) => settings.localMusicDir),
      (previous, next) {
        if (previous == null || previous == next) return;
        // Keep the currently rendered library in place while the new folder is
        // scanned, then swap the result in one frame. This avoids a loading
        // flash when the local music folder changes from Settings.
        unawaited(_scanLocalMusicFolder());
      },
    );
    unawaited(_initializeScan());
  }

  void _seedFromScanCache() {
    // Restore against the real list on the first frame; an empty loading frame
    // would clamp PageStorage's saved scroll offset back to zero.
    final snapshot = _scanCache.snapshot;
    if (snapshot == null ||
        snapshot.directory != ref.read(settingsProvider).localMusicDir) {
      return;
    }
    _scannedFiles = [
      for (final file in snapshot.files) ScannedSongFile.fromSnapshot(file),
    ];
    _scanError = snapshot.error;
    _tagCache.addAll(songTagCacheSnapshot);
    _tagModifiedAt.addAll(songTagModifiedAtSnapshot);
  }

  @override
  void didUpdateWidget(covariant SongsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchMode == widget.searchMode) return;
    if (widget.searchMode) {
      _enableSearchFocusHandling();
    } else {
      _disableSearchFocusHandling();
    }
  }

  Future<void> _initializeScan() async {
    await _scanCache.ensureLoaded();
    if (!mounted) return;

    _handleScanCacheChanged();
    final snapshot = _scanCache.snapshot;
    final currentDirectory = ref.read(settingsProvider).localMusicDir;
    final shouldRefresh =
        snapshot == null ||
        snapshot.directory != currentDirectory ||
        snapshot.error != null ||
        DateTime.now().difference(snapshot.cachedAt) >= _songScanCacheTtl;
    if (shouldRefresh) {
      unawaited(_scanCache.refresh(directory: currentDirectory));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_tabRestored) return;
    _tabRestored = true;
    final stored = PageStorage.of(
      context,
    ).readState(context, identifier: _tabStorageKey);
    if (stored is String) {
      final restored = _CollectionTab.values.asNameMap()[stored];
      if (restored != null) _tab = restored;
    }
  }

  void _selectTab(_CollectionTab tab) {
    if (_tab == tab) return;
    setState(() => _tab = tab);
    PageStorage.of(
      context,
    ).writeState(context, tab.name, identifier: _tabStorageKey);
  }

  @override
  void dispose() {
    _scanGeneration++;
    _disableSearchFocusHandling();
    _scanCache.removeListener(_handleScanCacheChanged);
    _localMusicDirSubscription?.close();
    _tagFlushTimer?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    final toolbarStateController = _toolbarStateController;
    final toolbarOwner = _toolbarOwner;
    scheduleMicrotask(() {
      if (!toolbarStateController.mounted) return;
      final toolbarState = toolbarStateController.state;
      if (identical(toolbarState.owner, toolbarOwner)) {
        toolbarStateController.state = const SongsToolbarState();
      }
    });
    super.dispose();
  }

  void _enableSearchFocusHandling() {
    _searchFocusNode.addListener(_handleSearchFocusChanged);
    if (!ref.read(songsSearchAutoFocusProvider)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !widget.searchMode) return;
        final toolbar = ref.read(shellToolbarVisibleProvider.notifier);
        if (toolbar.mounted) toolbar.state = true;
      });
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.searchMode) _searchFocusNode.requestFocus();
    });
  }

  void _disableSearchFocusHandling() {
    _searchFocusNode.removeListener(_handleSearchFocusChanged);
    _restoreToolbarAfterSearchFocus();
  }

  void _handleSearchFocusChanged() {
    if (!mounted || !widget.searchMode) return;
    if (!_searchFocusNode.hasFocus) {
      _restoreToolbarAfterSearchFocus();
      return;
    }

    _toolbarVisibilityBeforeSearchFocus ??= ref.read(
      shellToolbarVisibleProvider,
    );
    final toolbar = ref.read(shellToolbarVisibleProvider.notifier);
    if (toolbar.mounted) toolbar.state = false;
  }

  void _restoreToolbarAfterSearchFocus() {
    final previous = _toolbarVisibilityBeforeSearchFocus;
    if (previous == null) return;
    _toolbarVisibilityBeforeSearchFocus = null;
    final toolbar = ref.read(shellToolbarVisibleProvider.notifier);
    if (toolbar.mounted) toolbar.state = previous;
  }

  Future<void> _waitForFirstRouteTransition() async {
    await WidgetsBinding.instance.endOfFrame;
    final reduceMotion = WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    if (!reduceMotion) await Future<void>.delayed(AppMotion.long);
  }

  bool _isActiveScan(int generation) {
    if (!mounted || generation != _scanGeneration) return false;
    return _isSongsRouteActive();
  }

  bool _isSongsRouteActive() {
    if (!mounted) return false;
    final path = GoRouter.of(context).routeInformationProvider.value.uri.path;
    return path == (widget.searchMode ? '/songs/search' : '/songs');
  }

  Future<void> _resumeCachedHydration(
    List<ScannedSongFile> files,
    int generation,
  ) async {
    await _firstRouteTransitionSettled;
    if (!_isActiveScan(generation)) return;
    await _hydrateScannedTags(files, generation);
  }

  void _handleScanCacheChanged() {
    if (!mounted) return;
    final snapshot = _scanCache.snapshot;
    if (snapshot == null) return;
    final currentDirectory = ref.read(settingsProvider).localMusicDir;
    if (snapshot.directory != currentDirectory) return;

    final files = [
      for (final file in snapshot.files) ScannedSongFile.fromSnapshot(file),
    ];
    final previousFiles = _scannedFiles ?? const <ScannedSongFile>[];
    final nextFilesByKey = {
      for (final file in files) _pathKey(file.path): file,
    };
    for (final previous in previousFiles) {
      final next = nextFilesByKey[_pathKey(previous.path)];
      if (next == null || next.modifiedAt != previous.modifiedAt) {
        EmbeddedArtworkCache.evictPath(previous.path);
      }
    }

    final generation = ++_scanGeneration;
    setState(() {
      _scannedFiles = files;
      _scanError = snapshot.error;
      final currentKeys = nextFilesByKey.keys.toSet();
      _tagCache.removeWhere((key, _) => !currentKeys.contains(key));
      _tagModifiedAt.removeWhere((key, _) => !currentKeys.contains(key));
      _tagLoadingKeys.clear();
      _selectedIds.clear();
      _batchMode = false;
      _tagCache.addAll(songTagCacheSnapshot);
      _tagModifiedAt.addAll(songTagModifiedAtSnapshot);
    });
    if (snapshot.error == null && files.isNotEmpty) {
      unawaited(_resumeCachedHydration(files, generation));
    }
  }

  Future<void> _scanLocalMusicFolder() {
    return _scanCache.refresh(
      directory: ref.read(settingsProvider).localMusicDir,
    );
  }

  List<DownloadHistoryEntry> _songs(List<DownloadHistoryEntry> history) {
    final scannedFiles = _scannedFiles;
    if (scannedFiles == null) return const [];
    final historyByPath = <String, DownloadHistoryEntry>{};
    for (final entry in history) {
      final path = entry.savedPath;
      if (path == null || path.isEmpty) continue;
      historyByPath[_pathKey(path)] = entry;
    }

    final out = <DownloadHistoryEntry>[];
    final seen = <String>{};
    for (final file in scannedFiles) {
      final key = _pathKey(file.path);
      final tags = _tagCache[key];
      final historyEntry = historyByPath[key];
      final entry = historyEntry == null
          ? _syntheticEntryFor(file, tags)
          : _entryWithScannedFile(historyEntry, file, tags);
      if (seen.add(key)) out.add(entry);
    }

    int compare(DownloadHistoryEntry a, DownloadHistoryEntry b) {
      switch (_sortMode) {
        case SongSortMode.title:
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case SongSortMode.artist:
          return a.singer.toLowerCase().compareTo(b.singer.toLowerCase());
        case SongSortMode.added:
          return a.createdAt.compareTo(b.createdAt);
      }
    }

    out.sort(_ascending ? compare : (a, b) => compare(b, a));
    return out;
  }

  DownloadHistoryEntry _entryWithScannedFile(
    DownloadHistoryEntry entry,
    ScannedSongFile file,
    EmbeddedAudioTags? tags,
  ) {
    return DownloadHistoryEntry(
      id: entry.id,
      musicId: entry.musicId,
      name: _preferTag(
        tags?.title,
        entry.name.isEmpty ? file.title : entry.name,
      ),
      singer: _preferTag(tags?.artist, entry.singer),
      albumName: _preferTag(tags?.album, entry.albumName),
      sourceCode: entry.sourceCode,
      qualityCode: entry.qualityCode,
      status: entry.status,
      createdAt: file.createdAt,
      savedPath: file.path,
      message: entry.message,
      picUrl: entry.picUrl,
      sizeBytes: file.sizeBytes,
      musicJson: entry.musicJson,
    );
  }

  DownloadHistoryEntry _syntheticEntryFor(
    ScannedSongFile file,
    EmbeddedAudioTags? tags,
  ) {
    return DownloadHistoryEntry(
      id: 'file:${file.path}',
      musicId: file.path,
      name: _preferTag(tags?.title, file.title),
      singer: _preferTag(tags?.artist, file.artist),
      albumName: _preferTag(tags?.album, ''),
      sourceCode: MusicSource.all.code,
      qualityCode: file.extension.toLowerCase(),
      status: DownloadHistoryStatus.completed,
      createdAt: file.createdAt,
      savedPath: file.path,
      sizeBytes: file.sizeBytes,
    );
  }

  Future<void> _hydrateScannedTags(
    List<ScannedSongFile> files,
    int generation,
  ) async {
    for (final file in files) {
      if (!_isActiveScan(generation)) return;
      final key = _pathKey(file.path);
      if (_tagCache.containsKey(key) &&
          _tagModifiedAt[key] == file.modifiedAt) {
        continue;
      }
      if (!_tagLoadingKeys.add(key)) continue;
      EmbeddedAudioTags? tags;
      try {
        tags = await Tagger.readEmbeddedTags(
          file.path,
          includeLyrics: false,
          includeArtwork: false,
        ).timeout(_songTagReadTimeout);
      } catch (_) {
        tags = null;
      }
      if (!_isActiveScan(generation)) {
        _tagLoadingKeys.remove(key);
        return;
      }
      _tagLoadingKeys.remove(key);
      if (tags == null) {
        _tagCache.remove(key);
        _tagModifiedAt.remove(key);
        songTagCacheSnapshot.remove(key);
        songTagModifiedAtSnapshot.remove(key);
      } else {
        _tagCache[key] = tags;
        _tagModifiedAt[key] = file.modifiedAt;
        songTagCacheSnapshot[key] = tags;
        songTagModifiedAtSnapshot[key] = file.modifiedAt;
      }
      // One setState per file means N full list rebuild+sorts while a large
      // library hydrates; coalesce text metadata into small batches.
      _scheduleTagFlush();
    }
  }

  void _scheduleTagFlush() {
    _tagFlushTimer ??= Timer(const Duration(milliseconds: 90), () {
      _tagFlushTimer = null;
      if (_isSongsRouteActive()) setState(() {});
    });
  }

  Future<void> _play(
    DownloadHistoryEntry entry,
    List<DownloadHistoryEntry> queue,
  ) async {
    final path = entry.savedPath;
    final hasLocalFile =
        path != null && path.isNotEmpty && File(path).existsSync();
    if (!hasLocalFile) {
      showAppToast(context, '文件不存在，可能已被移动或删除', type: AppToastType.warning);
      return;
    }
    final available = await ensureQueueEntryMusicSourceAvailable(
      context,
      entry,
    );
    if (!available || !mounted) return;
    if (widget.searchMode) {
      ref.read(songsSearchAutoFocusProvider.notifier).state = false;
      _searchFocusNode.unfocus();
      _restoreToolbarAfterSearchFocus();
    }
    context.go(
      '/player',
      extra: widget.searchMode ? '/songs/search' : '/songs',
    );
    await ref
        .read(playerControllerProvider.notifier)
        .playFromHistoryQueue(entry, queue);
  }

  void _playAll(List<DownloadHistoryEntry> songs) {
    if (songs.isEmpty) return;
    unawaited(_play(songs.first, songs));
  }

  Future<void> _playSelected(List<DownloadHistoryEntry> songs) async {
    final selected = songs
        .where((entry) => _selectedIds.contains(entry.id))
        .where((entry) {
          final path = entry.savedPath;
          return (path != null && path.isNotEmpty && File(path).existsSync()) ||
              entry.musicInfo != null;
        })
        .toList(growable: false);
    if (selected.isEmpty) {
      showAppToast(context, '请先选择可播放的歌曲', type: AppToastType.warning);
      return;
    }
    setState(() {
      _selectedIds.clear();
      _batchMode = false;
    });
    await _play(selected.first, selected);
  }

  Future<void> _addNext(DownloadHistoryEntry entry) async {
    final path = entry.savedPath;
    final hasLocalFile =
        path != null && path.isNotEmpty && File(path).existsSync();
    if (!hasLocalFile && entry.musicInfo == null) {
      showAppToast(context, '文件不存在，无法加入队列', type: AppToastType.warning);
      return;
    }
    final available = await ensureQueueEntryMusicSourceAvailable(
      context,
      entry,
    );
    if (!available || !mounted) return;
    await ref.read(playerControllerProvider.notifier).enqueueNext(entry);
    if (!mounted) return;
    showAppToast(context, '已添加到下一首播放', type: AppToastType.success);
  }

  Future<void> _addSongToPlaylist(
    DownloadHistoryEntry entry,
    LocalPlaylist playlist,
  ) async {
    try {
      final added = await ref.read(localPlaylistsProvider.notifier).addEntries(
        playlist.id,
        [entry],
      );
      if (!mounted) return;
      if (added == 0) {
        showAppToast(
          context,
          '歌曲已在「${playlist.name}」中',
          type: AppToastType.info,
        );
        return;
      }
      showAppToast(
        context,
        '已添加到「${playlist.name}」',
        type: AppToastType.success,
      );
    } catch (error) {
      if (!mounted) return;
      showAppToast(context, '添加到歌单失败：$error', type: AppToastType.error);
    }
  }

  Future<void> _selectPlaylistForSong(DownloadHistoryEntry entry) async {
    final destination = await showPlaylistBrowserSheet(
      context,
      mode: PlaylistBrowserMode.addSongs,
    );
    if (!mounted || destination == null) return;

    const prefix = '/playlists/';
    if (!destination.startsWith(prefix)) return;
    final playlistId = destination.substring(prefix.length);
    LocalPlaylist? playlist;
    for (final candidate in ref.read(localPlaylistsProvider)) {
      if (candidate.id == playlistId) {
        playlist = candidate;
        break;
      }
    }
    if (playlist == null) {
      showAppToast(context, '歌单不存在或已被删除', type: AppToastType.warning);
      return;
    }
    await _addSongToPlaylist(entry, playlist);
  }

  Future<void> _deleteSong(DownloadHistoryEntry entry) async {
    try {
      await _deleteSongData(entry);
      await _scanLocalMusicFolder();
      if (!mounted) return;
      showAppToast(context, '歌曲已删除', type: AppToastType.success);
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, '删除失败：$e', type: AppToastType.error);
    }
  }

  Future<void> _deleteSongData(DownloadHistoryEntry entry) async {
    await _deleteSongFile(entry);
    if (!entry.id.startsWith('file:')) {
      await ref.read(downloadHistoryProvider.notifier).remove(entry.id);
    }
  }

  Future<void> _deleteSongFile(DownloadHistoryEntry entry) async {
    final path = entry.savedPath;
    if (path == null || path.isEmpty) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
    await ref
        .read(localPlaylistsProvider.notifier)
        .removeLocalPathFromAll(path);
    _forgetTagCache(path);
  }

  void _openHistory() {
    context.go('/downloads');
  }

  void _openSearch() {
    ref.read(songsSearchAutoFocusProvider.notifier).state = true;
    context.go('/songs/search');
  }

  void _setSort(SongSortMode mode, bool ascending) {
    if (!mounted || (_sortMode == mode && _ascending == ascending)) return;
    setState(() {
      _sortMode = mode;
      _ascending = ascending;
    });
    unawaited(_persistSongSortPreferences());
  }

  Future<void> _openSortSheet() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final toolbar = ref.read(shellToolbarVisibleProvider.notifier);
    final wasToolbarVisible = ref.read(shellToolbarVisibleProvider);
    toolbar.state = false;
    try {
      await showSongsSortSheet(
        context: context,
        initialMode: _sortMode,
        initialAscending: _ascending,
        onChanged: _setSort,
      );
    } finally {
      if (toolbar.mounted) toolbar.state = wasToolbarVisible;
    }
  }

  void _updateSearchQuery(String query) {
    if (_searchQuery == query) return;
    setState(() {
      _searchQuery = query;
      if (_batchMode) _selectedIds.clear();
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _updateSearchQuery('');
    FocusManager.instance.primaryFocus?.unfocus();
  }

  Future<void> _persistSongSortPreferences() async {
    final prefs = ref.read(sharedPreferencesProvider);
    await Future.wait([
      prefs.setString(_songSortModeKey, _sortMode.code),
      prefs.setBool(_songSortAscendingKey, _ascending),
    ]);
  }

  void _toggleVisibleSelection() {
    _toggleSelectAll(_visibleSongs);
  }

  Future<void> _addSelectedToPlaylist(List<DownloadHistoryEntry> songs) async {
    final selected = songs
        .where((entry) => _selectedIds.contains(entry.id))
        .toList(growable: false);
    if (selected.isEmpty) {
      showAppToast(context, '请先选择歌曲', type: AppToastType.warning);
      return;
    }
    final destination = await showPlaylistBrowserSheet(
      context,
      mode: PlaylistBrowserMode.addSongs,
    );
    if (!mounted || destination == null) return;
    const prefix = '/playlists/';
    if (!destination.startsWith(prefix)) return;
    final playlistId = destination.substring(prefix.length);
    final added = await ref
        .read(localPlaylistsProvider.notifier)
        .addEntries(playlistId, selected);
    if (!mounted) return;
    if (added == 0) {
      showAppToast(context, '所选歌曲已在这个歌单中', type: AppToastType.info);
      return;
    }
    setState(() {
      _selectedIds.clear();
      _batchMode = false;
    });
    showAppToast(context, '已加入 $added 首歌曲', type: AppToastType.success);
  }

  void _forgetTagCache(String path) {
    final key = _pathKey(path);
    _tagCache.remove(key);
    _tagModifiedAt.remove(key);
    _tagLoadingKeys.remove(key);
    songTagCacheSnapshot.remove(key);
    songTagModifiedAtSnapshot.remove(key);
    EmbeddedArtworkCache.evictPath(path);
  }

  void _toggleBatchMode() {
    _setBatchMode(!_batchMode);
  }

  void _setBatchMode(bool enabled) {
    if (_batchMode == enabled) return;
    setState(() {
      _batchMode = enabled;
      if (!enabled) _selectedIds.clear();
    });
  }

  void _toggleSelection(DownloadHistoryEntry entry) {
    setState(() {
      if (!_selectedIds.add(entry.id)) _selectedIds.remove(entry.id);
    });
  }

  void _toggleSelectAll(List<DownloadHistoryEntry> songs) {
    if (songs.isEmpty) return;
    final ids = {for (final entry in songs) entry.id};
    setState(() {
      final selectedCount = _selectedIds.where(ids.contains).length;
      if (selectedCount == ids.length) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(ids);
      }
    });
  }

  Future<void> _confirmDeleteSelected(List<DownloadHistoryEntry> songs) async {
    final selected = songs
        .where((entry) => _selectedIds.contains(entry.id))
        .toList(growable: false);
    if (selected.isEmpty) {
      showAppToast(context, '请先选择要删除的歌曲', type: AppToastType.warning);
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.delete_outline_rounded),
        title: const Text('删除已选歌曲？'),
        content: Text('将删除 ${selected.length} 首本地歌曲文件，并移除对应下载记录。此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final historyIds = <String>[];
    final deletedIds = <String>[];
    final failures = <String>[];
    for (final entry in selected) {
      try {
        await _deleteSongFile(entry);
        deletedIds.add(entry.id);
        if (!entry.id.startsWith('file:')) historyIds.add(entry.id);
      } catch (e) {
        final name = entry.name.trim().isEmpty
            ? entry.savedPath ?? entry.id
            : entry.name;
        failures.add('$name：$e');
      }
    }

    if (historyIds.isNotEmpty) {
      await ref.read(downloadHistoryProvider.notifier).removeMany(historyIds);
    }
    await _scanLocalMusicFolder();
    if (!mounted) return;
    setState(() {
      _selectedIds.removeAll(deletedIds);
      if (failures.isEmpty) {
        _selectedIds.clear();
        _batchMode = false;
      }
    });

    if (failures.isEmpty) {
      showAppToast(
        context,
        '已删除 ${deletedIds.length} 首歌曲',
        type: AppToastType.success,
      );
    } else {
      final type = deletedIds.isEmpty
          ? AppToastType.error
          : AppToastType.warning;
      showAppToast(
        context,
        '已删除 ${deletedIds.length} 首，${failures.length} 首失败：${failures.first}',
        type: type,
      );
    }
  }

  void _syncToolbarState({required int songCount, required int selectedCount}) {
    final allSelected = songCount > 0 && selectedCount == songCount;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final current = ref.read(songsToolbarStateProvider);
      if (current.matchesView(
        owner: _toolbarOwner,
        songCount: songCount,
        selectedCount: selectedCount,
        allSelected: allSelected,
        batchMode: _batchMode,
      )) {
        return;
      }
      ref.read(songsToolbarStateProvider.notifier).state = SongsToolbarState(
        owner: _toolbarOwner,
        songCount: songCount,
        selectedCount: selectedCount,
        allSelected: allSelected,
        batchMode: _batchMode,
        onSearch: _openSearch,
        onOpenHistory: _openHistory,
        onToggleBatch: _toggleBatchMode,
        onToggleSelectAll: _toggleVisibleSelection,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final playlists = ref.watch(localPlaylistsProvider);
    final history = ref.watch(downloadHistoryProvider);
    final allSongs = _songs(history);
    final songs = widget.searchMode
        ? filterSongsByQuery(allSongs, _searchQuery)
        : allSongs;
    final scanning = _scannedFiles == null;
    final playbackIdentity = ref.watch(
      playerControllerProvider.select((state) {
        final queueIndex = state.queueIndex;
        final queueEntry = queueIndex >= 0 && queueIndex < state.queue.length
            ? state.queue[queueIndex]
            : null;
        return (
          queueEntry: queueEntry,
          localPath: state.track?.localPath,
          playing: state.playing,
        );
      }),
    );
    final artworkVersionByPath = <String, int>{
      for (final file in _scannedFiles ?? const <ScannedSongFile>[])
        _pathKey(file.path): file.modifiedAt.microsecondsSinceEpoch,
    };
    final selectedCount = songs
        .where((entry) => _selectedIds.contains(entry.id))
        .length;
    _visibleSongs = songs;
    _syncToolbarState(songCount: songs.length, selectedCount: selectedCount);

    final Widget view = widget.searchMode
        ? _buildSearchView(
            songs: songs,
            hasAnySongs: allSongs.isNotEmpty,
            scanning: scanning,
            playbackIdentity: playbackIdentity,
            artworkVersionByPath: artworkVersionByPath,
          )
        : _buildCollectionView(
            songs: allSongs,
            playlists: playlists,
            scanning: scanning,
            playbackIdentity: playbackIdentity,
            artworkVersionByPath: artworkVersionByPath,
          );

    return Scaffold(
      backgroundColor: Colors.transparent,
      bottomNavigationBar: _batchMode
          ? SongsBatchActionBar(
              selectedCount: selectedCount,
              onDelete: selectedCount == 0
                  ? null
                  : () => unawaited(_confirmDeleteSelected(songs)),
              onAddToPlaylist: selectedCount == 0
                  ? null
                  : () => unawaited(_addSelectedToPlaylist(songs)),
              onPlaySelected: selectedCount == 0
                  ? null
                  : () => unawaited(_playSelected(songs)),
            )
          : null,
      body: !widget.searchMode && _tab == _CollectionTab.local && !_batchMode
          ? AppRefreshIndicator(onRefresh: _scanLocalMusicFolder, child: view)
          : view,
    );
  }

  Widget _buildCollectionView({
    required List<DownloadHistoryEntry> songs,
    required List<LocalPlaylist> playlists,
    required bool scanning,
    required ({
      DownloadHistoryEntry? queueEntry,
      String? localPath,
      bool playing,
    })
    playbackIdentity,
    required Map<String, int> artworkVersionByPath,
  }) {
    return AppScrollbar(
      controller: _scrollController,
      child: CustomScrollView(
        controller: _scrollController,
        key: const PageStorageKey('songs-collection-scroll'),
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
            sliver: SliverToBoxAdapter(
              child: _CollectionTabBar(current: _tab, onChanged: _selectTab),
            ),
          ),
          ...switch (_tab) {
            _CollectionTab.liked => _buildLikedSlivers(),
            _CollectionTab.local => _buildLocalSlivers(
              songs: songs,
              scanning: scanning,
              playbackIdentity: playbackIdentity,
              artworkVersionByPath: artworkVersionByPath,
            ),
            _CollectionTab.playlists => [
              if (playlists.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyPlaylists(
                    onManage: () => context.go('/playlists'),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(14, 2, 14, 104),
                  sliver: SliverList.separated(
                    itemCount: playlists.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      return _PlaylistTile(
                        playlist: playlists[index],
                        onTap: () =>
                            context.go('/playlists/${playlists[index].id}'),
                      );
                    },
                  ),
                ),
            ],
          },
        ],
      ),
    );
  }

  List<Widget> _buildLikedSlivers() {
    final liked = ref.watch(likedSongsProvider);
    if (liked.isEmpty) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyLikedSongs(),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 104),
        sliver: SliverList.separated(
          itemCount: liked.length,
          separatorBuilder: (_, _) => const SongListDivider(),
          itemBuilder: (context, index) {
            final item = liked[index];
            final music = item.music;
            return SearchResultTile(
              key: ValueKey('liked-song-${item.id}'),
              music: music,
              liked: true,
              onToggleLike: () =>
                  ref.read(likedSongsProvider.notifier).toggle(music),
              onPlay: () => unawaited(_playLiked(item, liked)),
              onDownload: () => showQualityPickerSheet(context, music),
            );
          },
        ),
      ),
    ];
  }

  Future<void> _playLiked(
    LikedSongEntry item,
    List<LikedSongEntry> liked,
  ) async {
    final queue = <DownloadHistoryEntry>[];
    DownloadHistoryEntry? selected;
    for (final likedEntry in liked) {
      final queueEntry = PlaylistTrack.fromMusicInfo(
        likedEntry.music,
      ).toQueueEntry(playlistId: 'liked:songs');
      if (queueEntry == null) continue;
      queue.add(queueEntry);
      if (likedEntry.id == item.id) selected = queueEntry;
    }
    final entry = selected;
    if (entry == null) return;
    final available = await ensureQueueEntryMusicSourceAvailable(
      context,
      entry,
    );
    if (!available || !mounted) return;
    context.go('/player', extra: '/songs');
    await ref
        .read(playerControllerProvider.notifier)
        .playFromPlaylistQueue(entry, queue);
  }

  List<Widget> _buildLocalSlivers({
    required List<DownloadHistoryEntry> songs,
    required bool scanning,
    required ({
      DownloadHistoryEntry? queueEntry,
      String? localPath,
      bool playing,
    })
    playbackIdentity,
    required Map<String, int> artworkVersionByPath,
  }) {
    if (scanning) {
      return const [
        SliverFillRemaining(hasScrollBody: false, child: SongsLoading()),
      ];
    }
    if (songs.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptySongs(error: _scanError),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 2),
        sliver: SliverToBoxAdapter(
          child: SongsLocalActions(
            count: songs.length,
            batchMode: _batchMode,
            onPlayAll: () => _playAll(songs),
            onOpenSort: () => unawaited(_openSortSheet()),
            onToggleBatch: songs.isEmpty ? null : _toggleBatchMode,
          ),
        ),
      ),
      SliverPadding(
        padding: EdgeInsets.fromLTRB(12, 0, 12, _batchMode ? 12 : 104),
        sliver: _buildSongSliver(
          songs: songs,
          playbackIdentity: playbackIdentity,
          artworkVersionByPath: artworkVersionByPath,
        ),
      ),
    ];
  }

  Widget _buildSearchView({
    required List<DownloadHistoryEntry> songs,
    required bool hasAnySongs,
    required bool scanning,
    required ({
      DownloadHistoryEntry? queueEntry,
      String? localPath,
      bool playing,
    })
    playbackIdentity,
    required Map<String, int> artworkVersionByPath,
  }) {
    return AppScrollbar(
      controller: _scrollController,
      child: CustomScrollView(
        controller: _scrollController,
        key: const PageStorageKey('songs-search-scroll'),
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 0),
            sliver: SliverToBoxAdapter(
              child: SongsSearchBar(
                controller: _searchController,
                focusNode: _searchFocusNode,
                query: _searchQuery,
                autofocus: ref.watch(songsSearchAutoFocusProvider),
                onChanged: _updateSearchQuery,
                onClear: _clearSearch,
              ),
            ),
          ),
          if (scanning)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: SongsLoading(),
            )
          else if (!hasAnySongs)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptySongs(error: _scanError),
            )
          else if (songs.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptySongSearch(),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 104),
              sliver: _buildSongSliver(
                songs: songs,
                playbackIdentity: playbackIdentity,
                artworkVersionByPath: artworkVersionByPath,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSongSliver({
    required List<DownloadHistoryEntry> songs,
    required ({
      DownloadHistoryEntry? queueEntry,
      String? localPath,
      bool playing,
    })
    playbackIdentity,
    required Map<String, int> artworkVersionByPath,
  }) {
    return SlidableAutoCloseBehavior(
      child: SliverList.separated(
        itemCount: songs.length,
        separatorBuilder: (_, _) => const SongListDivider(),
        itemBuilder: (context, index) {
          final entry = songs[index];
          final path = entry.savedPath;
          final playing = _matchesPlayingEntry(
            entry,
            playbackIdentity.queueEntry,
            playbackIdentity.localPath,
          );
          return SongRow(
            key: ValueKey(entry.id),
            entry: entry,
            artworkVersion: path == null
                ? null
                : artworkVersionByPath[_pathKey(path)],
            playing: playing,
            playingActive: playing && playbackIdentity.playing,
            batchMode: _batchMode,
            selected: _selectedIds.contains(entry.id),
            onToggleSelected: () => _toggleSelection(entry),
            onAddNext: () => _addNext(entry),
            onAddToPlaylist: () => unawaited(_selectPlaylistForSong(entry)),
            onPlay: () => _play(entry, songs),
            onDelete: () => _deleteSong(entry),
          );
        },
      ),
    );
  }
}

class _CollectionTabBar extends StatelessWidget {
  const _CollectionTabBar({required this.current, required this.onChanged});

  final _CollectionTab current;
  final ValueChanged<_CollectionTab> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _CollectionTabPill(
            label: '喜欢',
            icon: current == _CollectionTab.liked
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            selected: current == _CollectionTab.liked,
            onTap: () => onChanged(_CollectionTab.liked),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _CollectionTabPill(
            label: '本地音乐',
            icon: Icons.smartphone_rounded,
            selected: current == _CollectionTab.local,
            onTap: () => onChanged(_CollectionTab.local),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _CollectionTabPill(
            label: '歌单',
            icon: Icons.queue_music_rounded,
            selected: current == _CollectionTab.playlists,
            onTap: () => onChanged(_CollectionTab.playlists),
          ),
        ),
      ],
    );
  }
}

class _CollectionTabPill extends StatelessWidget {
  const _CollectionTabPill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Material(
      color: selected ? scheme.appInputFill : Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          height: 40,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: foreground),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaylistTile extends StatelessWidget {
  const _PlaylistTile({required this.playlist, required this.onTap});

  final LocalPlaylist playlist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.22),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(16),
        child: ListTile(
          onTap: onTap,
          minTileHeight: 72,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          leading: PlaylistCover(
            playlist: playlist,
            size: 48,
            radius: 14,
            placeholder: Container(
              width: 48,
              height: 48,
              color: scheme.secondaryContainer,
              alignment: Alignment.center,
              child: Icon(
                Icons.queue_music_rounded,
                color: scheme.onSecondaryContainer,
                size: 24,
              ),
            ),
          ),
          title: Text(
            playlist.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text('${playlist.tracks.length} 首歌曲'),
          trailing: Icon(
            Icons.chevron_right_rounded,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

String _pathKey(String path) {
  final normalized = path.replaceAll('\\', '/');
  return Platform.isWindows ? normalized.toLowerCase() : normalized;
}

bool _matchesPlayingEntry(
  DownloadHistoryEntry entry,
  DownloadHistoryEntry? queueEntry,
  String? playerLocalPath,
) {
  if (queueEntry != null) {
    if (queueEntry.id == entry.id) return true;
    final queuedPath = queueEntry.savedPath?.trim();
    final entryPath = entry.savedPath?.trim();
    if (queuedPath != null &&
        queuedPath.isNotEmpty &&
        entryPath != null &&
        entryPath.isNotEmpty &&
        _pathKey(queuedPath) == _pathKey(entryPath)) {
      return true;
    }
    if (queueEntry.sourceCode == entry.sourceCode &&
        queueEntry.musicId.isNotEmpty &&
        queueEntry.musicId == entry.musicId) {
      return true;
    }
  }

  final entryPath = entry.savedPath?.trim();
  final activePath = playerLocalPath?.trim();
  return entryPath != null &&
      entryPath.isNotEmpty &&
      activePath != null &&
      activePath.isNotEmpty &&
      _pathKey(entryPath) == _pathKey(activePath);
}

String _preferTag(String? value, String fallback) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? fallback : trimmed;
}

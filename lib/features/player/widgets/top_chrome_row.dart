import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../downloads/download_progress.dart';
import '../../shell/player_pull_scope.dart';
import '../../songs/liked_songs_provider.dart';
import '../player_controller.dart';
import '../sleep_timer_controller.dart';
import 'player_palette.dart';
import 'player_sleep_timer_sheet.dart';
import 'track_change_switcher.dart';

class TopChromeRow extends ConsumerWidget {
  const TopChromeRow({super.key, required this.onOpenSongs});

  final VoidCallback onOpenSongs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = ref.watch(downloadProgressProvider.select((p) => p.isBusy));
    final trackMetadata = ref.watch(
      playerControllerProvider.select(
        (s) =>
            (id: s.track?.id, title: s.track?.title, artist: s.track?.artist),
      ),
    );
    // 远程曲目才有稳定的 source:id 键；本地文件不显示红心。
    final likedKey = ref.watch(
      playerControllerProvider.select((s) {
        final id = s.track?.id;
        if (id == null || !id.endsWith(':remote')) return null;
        return id.substring(0, id.length - ':remote'.length);
      }),
    );
    final liked = likedKey != null
        ? ref.watch(
            likedSongsProvider.select(
              (entries) => entries.any((entry) => entry.id == likedKey),
            ),
          )
        : false;
    return PlayerPullHandle(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 8, 12, 4),
        child: Row(
          children: [
            Expanded(
              child: TrackChangeSwitcher(
                transitionKey:
                    'top-title:${trackMetadata.id ?? 'loading'}:'
                    '${trackMetadata.title ?? ''}:'
                    '${trackMetadata.artist ?? ''}',
                alignment: Alignment.centerLeft,
                child:
                    trackMetadata.title != null &&
                        trackMetadata.title!.trim().isNotEmpty
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            key: const ValueKey('player-header-title'),
                            trackMetadata.title!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: playerInk(context),
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                              height: 1.05,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            key: const ValueKey('player-header-artist'),
                            trackMetadata.artist?.trim().isNotEmpty == true
                                ? trackMetadata.artist!.trim()
                                : '未知歌手',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: playerMuted(
                                context,
                              ).withValues(alpha: 0.78),
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                              height: 1.05,
                            ),
                          ),
                        ],
                      )
                    : const SizedBox(height: 36),
              ),
            ),
            const SizedBox(width: 12),
            if (likedKey != null)
              _ChromeLikeButton(
                liked: liked,
                onPressed: () {
                  final music = ref
                      .read(playerControllerProvider.notifier)
                      .currentMusic;
                  if (music == null) return;
                  ref.read(likedSongsProvider.notifier).toggle(music);
                },
              ),
            if (likedKey != null) const SizedBox(width: 8),
            const _SleepTimerButton(),
            const SizedBox(width: 8),
            _ChromeIconButton(
              icon: Symbols.library_music_rounded,
              tooltip: '本地歌曲',
              onPressed: onOpenSongs,
              badge: busy,
            ),
          ],
        ),
      ),
    );
  }
}

class _SleepTimerButton extends ConsumerWidget {
  const _SleepTimerButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remaining = ref.watch(sleepTimerProvider);
    if (remaining == null) {
      return _ChromeIconButton(
        key: const ValueKey('player-sleep-timer-button'),
        icon: Icons.timer_outlined,
        tooltip: '定时关闭音乐',
        onPressed: () => showPlayerSleepTimerSheet(context, ref),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final label = formatSleepTimerRemaining(remaining);
    return Tooltip(
      message: '定时关闭音乐 · 剩余 $label',
      child: Material(
        color: scheme.primaryContainer,
        shape: const StadiumBorder(),
        child: InkWell(
          key: const ValueKey('player-sleep-timer-button'),
          customBorder: const StadiumBorder(),
          onTap: () => showPlayerSleepTimerSheet(context, ref),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: SizedBox(
              height: 36,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.timer_rounded,
                    color: scheme.onPrimaryContainer,
                    size: 18,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: TextStyle(
                      color: scheme.onPrimaryContainer,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChromeLikeButton extends StatelessWidget {
  const _ChromeLikeButton({required this.liked, required this.onPressed});

  final bool liked;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: liked ? '取消喜欢' : '喜欢',
      child: Material(
        color: Colors.white.withValues(alpha: 0.28),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(
              liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: liked ? scheme.primary : playerInk(context),
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}

class _ChromeIconButton extends StatelessWidget {
  const _ChromeIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.badge = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withValues(alpha: 0.28),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(icon, color: playerInk(context), size: 20),
                if (badge)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFF6B57),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

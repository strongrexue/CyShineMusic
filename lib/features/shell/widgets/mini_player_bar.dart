import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/cover_image_source.dart';
import '../../../theme/app_motion.dart';
import '../../player/player_controller.dart';

class MiniPlayerBar extends ConsumerWidget {
  const MiniPlayerBar({super.key, required this.onOpenPlayer});

  final VoidCallback onOpenPlayer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vm = ref.watch(
      playerControllerProvider.select(
        (state) => (
          track: state.track,
          playing: state.playing,
          loading: state.loading,
          buffering: state.buffering,
          ended: state.processingState == PlayerProcessingState.completed,
        ),
      ),
    );
    final controller = ref.read(playerControllerProvider.notifier);
    final track = vm.track;
    if (track == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final canControl = !vm.loading;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.28),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onOpenPlayer,
            child: SizedBox(
              height: 64,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                child: Row(
                  children: [
                    _MiniCover(track: track),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          _MiniLyricLine(fallback: track.artist),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    _MiniSkipButton(
                      icon: Icons.skip_previous_rounded,
                      tooltip: '上一首',
                      onPressed: canControl ? controller.playPrevious : null,
                    ),
                    _MiniPlayButton(
                      playing: vm.playing,
                      showSpinner: vm.loading || vm.buffering,
                      ended: vm.ended,
                      canControl: canControl,
                      controller: controller,
                    ),
                    _MiniSkipButton(
                      icon: Icons.skip_next_rounded,
                      tooltip: '下一首',
                      onPressed: canControl ? controller.playNext : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniCover extends StatelessWidget {
  const _MiniCover({required this.track});

  final PlayerTrack track;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final normalized = CoverImageSource.normalizeUrl(track.coverUrl, size: 200);
    final placeholder = Container(
      width: 48,
      height: 48,
      color: scheme.onSurface.withValues(alpha: 0.08),
      alignment: Alignment.center,
      child: Icon(
        Icons.album_rounded,
        color: scheme.onSurfaceVariant,
        size: 22,
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox.square(
        dimension: 48,
        child: track.coverBytes != null && track.coverBytes!.isNotEmpty
            ? Image.memory(
                track.coverBytes!,
                fit: BoxFit.cover,
                cacheWidth: 120,
                cacheHeight: 120,
                errorBuilder: (_, _, _) => placeholder,
              )
            : normalized == null || normalized.isEmpty
            ? placeholder
            : CachedNetworkImage(
                imageUrl: normalized,
                httpHeaders: CoverImageSource.headersFor(normalized),
                fit: BoxFit.cover,
                memCacheWidth: 120,
                memCacheHeight: 120,
                placeholder: (_, _) => placeholder,
                errorWidget: (_, _, _) => placeholder,
              ),
      ),
    );
  }
}

class _MiniLyricLine extends ConsumerWidget {
  const _MiniLyricLine({required this.fallback});

  final String fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vm = ref.watch(
      playerControllerProvider.select(
        (state) => (
          lyrics: state.lyrics,
          activeIndex: state.lyricLoading || state.lyrics.isEmpty
              ? -1
              : state.lyrics.activeIndex(state.position),
        ),
      ),
    );
    final scheme = Theme.of(context).colorScheme;
    final line = vm.activeIndex >= 0 ? vm.lyrics.lines[vm.activeIndex] : null;
    final text = (line?.text.trim().isNotEmpty ?? false)
        ? line!.text
        : fallback;
    if (text.trim().isEmpty) return const SizedBox.shrink();
    return AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : AppMotion.medium,
      switchInCurve: AppMotion.emphasizedDecelerate,
      switchOutCurve: AppMotion.emphasizedAccelerate,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.4),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: Text(
        text,
        key: ValueKey(
          vm.activeIndex >= 0 ? 'lyric-${vm.activeIndex}' : 'artist',
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: scheme.onSurfaceVariant,
          fontSize: 12,
          fontWeight: FontWeight.w400,
          height: 1.2,
        ),
      ),
    );
  }
}

class _MiniSkipButton extends StatelessWidget {
  const _MiniSkipButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 44, height: 48),
      icon: Icon(icon, color: scheme.onSurface, size: 24),
    );
  }
}

class _MiniPlayButton extends StatelessWidget {
  const _MiniPlayButton({
    required this.playing,
    required this.showSpinner,
    required this.ended,
    required this.canControl,
    required this.controller,
  });

  final bool playing;
  final bool showSpinner;
  final bool ended;
  final bool canControl;
  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Widget glyph;
    if (showSpinner) {
      glyph = SizedBox.square(
        dimension: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2.2,
          color: scheme.primary,
        ),
      );
    } else {
      glyph = Icon(
        ended
            ? Icons.replay_rounded
            : playing
            ? Icons.pause_rounded
            : Icons.play_arrow_rounded,
        color: scheme.primary,
        size: 26,
      );
    }
    return IconButton(
      tooltip: ended
          ? '重播'
          : playing
          ? '暂停'
          : '播放',
      onPressed: canControl
          ? (ended ? controller.replay : controller.toggle)
          : null,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      icon: AnimatedSwitcher(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : AppMotion.medium,
        switchInCurve: AppMotion.emphasizedDecelerate,
        switchOutCurve: AppMotion.emphasizedAccelerate,
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.82, end: 1).animate(animation),
              child: child,
            ),
          );
        },
        child: glyph,
      ),
    );
  }
}

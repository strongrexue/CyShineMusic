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
    final label = [
      track.title,
      if (track.artist.trim().isNotEmpty) track.artist,
    ].join(' · ');

    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
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
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.15,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _MiniPlayButton(
                  playing: vm.playing,
                  showSpinner: vm.loading || vm.buffering,
                  ended: vm.ended,
                  canControl: canControl,
                  controller: controller,
                ),
              ],
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
      borderRadius: BorderRadius.circular(8),
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

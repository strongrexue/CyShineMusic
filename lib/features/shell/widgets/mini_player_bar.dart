import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/cover_image_source.dart';
import '../../../theme/app_motion.dart';
import '../../player/lyric_parser.dart';
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
        child: Stack(
          children: [
            Material(
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
            const Positioned(
              left: 16,
              right: 16,
              bottom: 1,
              height: 12,
              child: _MiniProgressBar(),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniProgressBar extends ConsumerStatefulWidget {
  const _MiniProgressBar();

  @override
  ConsumerState<_MiniProgressBar> createState() => _MiniProgressBarState();
}

class _MiniProgressBarState extends ConsumerState<_MiniProgressBar> {
  /// 拖动中跟手显示；松手时只 seek 一次，与完整播放页 transport_bar 一致。
  double? _dragMs;

  @override
  Widget build(BuildContext context) {
    final vm = ref.watch(
      playerControllerProvider.select(
        (s) => (
          position: s.position,
          duration: s.duration,
          canControl: s.track != null && !s.loading,
        ),
      ),
    );
    final controller = ref.read(playerControllerProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final maxMs = math.max(1, vm.duration.inMilliseconds).toDouble();
    final shownMs = (_dragMs ?? vm.position.inMilliseconds.toDouble()).clamp(
      0.0,
      maxMs,
    );

    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 3,
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.onSurface.withValues(alpha: 0.14),
        thumbColor: scheme.primary,
        overlayColor: scheme.primary.withValues(alpha: 0.12),
        disabledActiveTrackColor: scheme.onSurfaceVariant.withValues(
          alpha: 0.4,
        ),
        disabledInactiveTrackColor: scheme.onSurface.withValues(alpha: 0.1),
        disabledThumbColor: scheme.onSurfaceVariant,
        thumbShape: const _MiniProgressThumbShape(),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 9),
        padding: EdgeInsets.zero,
      ),
      child: Slider(
        value: shownMs,
        max: maxMs,
        onChanged: vm.canControl
            ? (value) => setState(() => _dragMs = value)
            : null,
        onChangeEnd: vm.canControl
            ? (value) async {
                await controller.seek(
                  Duration(milliseconds: value.round()),
                );
                if (mounted) setState(() => _dragMs = null);
              }
            : null,
      ),
    );
  }
}

/// 平时不绘制圆点，只保留底部细线；手指按下拖动时圆点随激活动画显现。
class _MiniProgressThumbShape extends SliderComponentShape {
  const _MiniProgressThumbShape();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size.square(10);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final progress = activationAnimation.value;
    if (progress <= 0) return;
    final radius = 2.5 + 2.5 * progress;
    context.canvas.drawCircle(
      center,
      radius,
      Paint()..color = sliderTheme.thumbColor!,
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
    final hasLineText = line != null && line.text.trim().isNotEmpty;
    if (!hasLineText && fallback.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    final Widget child;
    if (hasLineText && line.hasWordTiming) {
      child = _MiniKaraokeText(
        key: ValueKey('mini-karaoke-${line.startMs}'),
        line: line,
      );
    } else if (hasLineText) {
      child = Text(
        line.text,
        key: ValueKey('lyric-${vm.activeIndex}'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: scheme.onSurface,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          height: 1.2,
        ),
      );
    } else {
      child = Text(
        fallback,
        key: const ValueKey('artist'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: scheme.onSurfaceVariant,
          fontSize: 12,
          fontWeight: FontWeight.w400,
          height: 1.2,
        ),
      );
    }
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
      child: child,
    );
  }
}

/// 迷你条逐字卡拉OK：与完整播放页 _KaraokeLineText 同思路——position stream
/// 只是锚点（约 200ms 一跳），播放中用 Ticker 按墙钟外推到逐帧；高亮只在
/// 单词起始边界跨越时变化，因此仅在跨越瞬间 setState，不做逐帧重建。
class _MiniKaraokeText extends ConsumerStatefulWidget {
  const _MiniKaraokeText({super.key, required this.line});

  final KaraokeLyricLine line;

  @override
  ConsumerState<_MiniKaraokeText> createState() => _MiniKaraokeTextState();
}

class _MiniKaraokeTextState extends ConsumerState<_MiniKaraokeText>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final Stopwatch _sinceAnchor = Stopwatch();
  late int _anchorMs;
  int _sweptCount = 0;

  @override
  void initState() {
    super.initState();
    _anchorMs = ref.read(playerControllerProvider).position.inMilliseconds;
    _ticker = createTicker((_) => _sweep());
    _syncDrive();
  }

  @override
  void didUpdateWidget(covariant _MiniKaraokeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.line, oldWidget.line)) {
      _anchorMs = ref.read(playerControllerProvider).position.inMilliseconds;
      _sinceAnchor.reset();
      _syncDrive();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  int get _effectiveMs => _anchorMs + _sinceAnchor.elapsedMilliseconds;

  int _countAt(int ms) {
    var count = 0;
    for (final word in widget.line.words) {
      if (ms < word.startMs) break;
      count++;
    }
    return count;
  }

  void _syncDrive() {
    final s = ref.read(playerControllerProvider);
    final clockRunning = s.playing && !s.buffering;
    if (clockRunning) {
      _sinceAnchor.start();
    } else {
      _sinceAnchor.stop();
    }
    if (clockRunning && !_ticker.isActive) {
      _ticker.start();
    } else if (!clockRunning && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _sweep() {
    final count = _countAt(_effectiveMs);
    if (count != _sweptCount) {
      setState(() => _sweptCount = count);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = ref.watch(
      playerControllerProvider.select(
        (s) =>
            (position: s.position, playing: s.playing, buffering: s.buffering),
      ),
    );
    final anchorMs = vm.position.inMilliseconds;
    if (anchorMs != _anchorMs) {
      _anchorMs = anchorMs;
      _sinceAnchor.reset();
    }
    final clockRunning = vm.playing && !vm.buffering;
    if (clockRunning) {
      _sinceAnchor.start();
    } else {
      _sinceAnchor.stop();
    }
    if (clockRunning && !_ticker.isActive) _ticker.start();
    if (!clockRunning && _ticker.isActive) _ticker.stop();
    _sweptCount = _countAt(_effectiveMs);

    final scheme = Theme.of(context).colorScheme;
    final swept = TextStyle(
      color: scheme.onSurface,
      fontSize: 12,
      fontWeight: FontWeight.bold,
      height: 1.2,
    );
    final pending = TextStyle(
      color: scheme.onSurfaceVariant,
      fontSize: 12,
      fontWeight: FontWeight.w400,
      height: 1.2,
    );
    return Text.rich(
      TextSpan(
        children: [
          for (var i = 0; i < widget.line.words.length; i++)
            TextSpan(
              text: widget.line.words[i].text,
              style: i < _sweptCount ? swept : pending,
            ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
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

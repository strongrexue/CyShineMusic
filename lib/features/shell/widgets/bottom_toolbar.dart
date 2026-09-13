import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../theme/app_motion.dart';
import '../../player/player_controller.dart';
import '../../playlists/playlist_detail_toolbar_state.dart';
import '../../songs/songs_toolbar_state.dart';
import '../shell_route_utils.dart';
import '../shell_toolbar_visibility.dart';
import '../tab_location_memory.dart';
import 'toolbar_metrics.dart';

class BottomToolbar extends ConsumerWidget {
  const BottomToolbar({
    super.key,
    required this.location,
    required this.routeLocation,
    required this.reveal,
    required this.travelExtent,
  });

  final String location;
  final String routeLocation;
  final Animation<double> reveal;
  final double travelExtent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shellVisible = ref.watch(shellToolbarVisibleProvider);
    final playerHasContent = ref.watch(
      playerControllerProvider.select(
        (state) => state.hasTrack || state.loading,
      ),
    );
    final songsBatchMode =
        isSongsLibraryLocation(location) &&
        ref.watch(songsToolbarStateProvider.select((state) => state.batchMode));
    final playlistBatchMode =
        isPlaylistDetailLocation(location) &&
        ref.watch(
          playlistDetailToolbarStateProvider.select((state) => state.batchMode),
        );
    final visible =
        shellVisible &&
        !songsBatchMode &&
        !playlistBatchMode &&
        (location != '/player' || !playerHasContent);

    final toolbar = SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scheme = Theme.of(context).colorScheme;
          final viewport = MediaQuery.sizeOf(context);
          final actionWidth = math.max(
            toolbarMinActionWidth,
            math.min(
              toolbarMaxActionWidthFor(viewport),
              (constraints.maxWidth - toolbarHorizontalPadding) /
                  toolbarActionCount,
            ),
          );
          final scaledLabelHeight = MediaQuery.textScalerOf(
            context,
          ).scale(toolbarLabelFontSizeFor(viewport));
          final actionHeight = math.max(
            toolbarMinActionHeightFor(viewport),
            toolbarActionVerticalChromeFor(viewport) + scaledLabelHeight,
          );
          final toolbarHeight = actionHeight + 8;
          return Center(
            child: RepaintBoundary(
              child: AnimatedContainer(
                duration: AppMotion.long,
                curve: AppMotion.emphasized,
                height: toolbarHeight,
                padding: const EdgeInsets.symmetric(horizontal: 5),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.shadow.withValues(alpha: 0.28),
                      blurRadius: 28,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: _NavToolbar(
                  location: location,
                  routeLocation: routeLocation,
                  actionWidth: actionWidth,
                  actionHeight: actionHeight,
                  toolbarHeight: toolbarHeight,
                ),
              ),
            ),
          );
        },
      ),
    );

    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, 1.25),
        duration: AppMotion.medium,
        curve: AppMotion.emphasized,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: AppMotion.short,
          curve: AppMotion.emphasized,
          child: AnimatedBuilder(
            animation: reveal,
            child: toolbar,
            builder: (context, child) {
              final progress = reveal.value.clamp(0.0, 1.0).toDouble();
              final opacity = toolbarOpacityFor(progress);
              final translated = Transform.translate(
                offset: Offset(0, (1 - progress) * travelExtent),
                child: child,
              );
              return IgnorePointer(
                ignoring: progress <= toolbarHitTestRevealThreshold,
                child: Opacity(opacity: opacity, child: translated),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _NavToolbar extends ConsumerWidget {
  const _NavToolbar({
    required this.location,
    required this.routeLocation,
    required this.actionWidth,
    required this.actionHeight,
    required this.toolbarHeight,
  });

  final String location;
  final String routeLocation;
  final double actionWidth;
  final double actionHeight;
  final double toolbarHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIndex = toolbarIndexFor(location);
    return SizedBox(
      width: actionWidth * toolbarActionCount,
      height: toolbarHeight,
      child: Stack(
        alignment: Alignment.centerLeft,
        clipBehavior: Clip.none,
        children: [
          AnimatedPositioned(
            left: selectedIndex * actionWidth,
            top: (toolbarHeight - actionHeight) / 2,
            duration: AppMotion.medium,
            curve: AppMotion.emphasized,
            child: _ToolbarSlidingIndicator(
              width: actionWidth,
              height: actionHeight,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ToolbarAction(
                tooltip: '首页',
                label: '首页',
                icon: Icons.home_rounded,
                selected: location == '/',
                width: actionWidth,
                height: actionHeight,
                onPressed: () =>
                    _goTab(context, ref, location, routeLocation, '/'),
              ),
              _ToolbarAction(
                tooltip: '发现',
                label: '发现',
                icon: Icons.explore_rounded,
                selected: isDiscoveryLocation(location),
                width: actionWidth,
                height: actionHeight,
                onPressed: () =>
                    _goTab(context, ref, location, routeLocation, '/discover'),
              ),
              _ToolbarAction(
                tooltip: '收藏',
                label: '收藏',
                icon: Icons.favorite_rounded,
                selected:
                    isSongsLibraryLocation(location) ||
                    location == '/downloads' ||
                    isPlaylistLocation(location),
                width: actionWidth,
                height: actionHeight,
                onPressed: () =>
                    _goTab(context, ref, location, routeLocation, '/songs'),
              ),
              _ToolbarAction(
                tooltip: '设置',
                label: '设置',
                icon: Icons.tune_rounded,
                selected:
                    location.startsWith('/settings') || location == '/debug',
                width: actionWidth,
                height: actionHeight,
                onPressed: () =>
                    _goTab(context, ref, location, routeLocation, '/settings'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ToolbarSlidingIndicator extends StatelessWidget {
  const _ToolbarSlidingIndicator({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: scheme.primary,
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

class _ToolbarAction extends StatefulWidget {
  const _ToolbarAction({
    required this.tooltip,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onPressed,
    required this.width,
    required this.height,
  });

  final String tooltip;
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;
  final double width;
  final double height;

  @override
  State<_ToolbarAction> createState() => _ToolbarActionState();
}

class _ToolbarActionState extends State<_ToolbarAction>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scale;

  @override
  void initState() {
    super.initState();
    _scale = AnimationController.unbounded(vsync: this, value: 1);
  }

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  void _springTo(double target) {
    _scale.animateWith(
      SpringSimulation(AppMotion.expressiveSpring, _scale.value, target, 0),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final iconExtent = toolbarIconExtentFor(viewport);
    final iconSize = toolbarIconSizeFor(viewport);
    final labelFontSize = toolbarLabelFontSizeFor(viewport);
    final scheme = Theme.of(context).colorScheme;
    final foregroundColor = widget.selected
        ? scheme.onPrimary
        : scheme.onSurfaceVariant;

    final child = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onPressed,
      onTapDown: (_) => _springTo(0.92),
      onTapUp: (_) => _springTo(1),
      onTapCancel: () => _springTo(1),
      child: AnimatedBuilder(
        animation: _scale,
        builder: (context, child) =>
            Transform.scale(scale: _scale.value, child: child),
        child: AnimatedContainer(
          duration: AppMotion.medium,
          curve: AppMotion.emphasized,
          width: widget.width,
          height: widget.height,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: iconExtent,
                  height: iconExtent,
                  child: Center(
                    child: Icon(
                      widget.icon,
                      color: foregroundColor,
                      size: iconSize,
                    ),
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foregroundColor,
                    fontSize: labelFontSize,
                    fontWeight: FontWeight.w600,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Tooltip(message: widget.tooltip, child: child);
  }
}

void _goTab(
  BuildContext context,
  WidgetRef ref,
  String location,
  String routeLocation,
  String path,
) {
  _dismissTransientRoutes(context);
  final targetIndex = toolbarIndexFor(path);
  final target = toolbarIndexFor(location) == targetIndex
      ? path
      : (ref.read(tabLocationMemoryProvider)[targetIndex] ?? path);
  if (target == routeLocation) return;
  context.go(target);
}

void _dismissTransientRoutes(BuildContext context) {
  FocusManager.instance.primaryFocus?.unfocus();
  Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
}

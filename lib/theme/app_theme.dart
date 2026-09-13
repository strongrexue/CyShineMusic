import 'package:flutter/material.dart';

import 'app_motion.dart';
import 'color_style.dart';

class AppTheme {
  const AppTheme._();

  static const Color designSeed = Color(0xFF7C3AED);

  /// Same CJK stack the player lyrics render with, so body text across the
  /// app matches the lyric typography.
  static const List<String> fontFallback = [
    'Noto Sans CJK SC',
    'Source Han Sans SC',
    'HarmonyOS Sans SC',
    'PingFang SC',
    'Microsoft YaHei',
  ];

  static ThemeData light([
    Color seed = designSeed,
    AppColorStyle style = AppColorStyle.fallback,
  ]) => _build(Brightness.light, seed, style);

  static ThemeData dark([
    Color seed = designSeed,
    AppColorStyle style = AppColorStyle.fallback,
  ]) => _build(Brightness.dark, seed, style);

  static ThemeData fromScheme(ColorScheme scheme) => _buildFromScheme(scheme);

  /// 用给定风格展开种子色。设置页的风格预览也走这里，保证预览与实际一致。
  static ColorScheme schemeFor(
    Color seed,
    Brightness brightness,
    AppColorStyle style,
  ) => ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
    dynamicSchemeVariant: style.variant,
  );

  static ThemeData _build(
    Brightness brightness,
    Color seed,
    AppColorStyle style,
  ) {
    return _buildFromScheme(schemeFor(seed, brightness, style));
  }

  static ThemeData _buildFromScheme(ColorScheme scheme) {
    final resolvedScheme = scheme.brightness == Brightness.dark
        ? scheme.copyWith(surfaceContainerLow: const Color(0xFF1E1E1E))
        : scheme;
    return ThemeData(
      useMaterial3: true,
      colorScheme: resolvedScheme,
      fontFamilyFallback: fontFallback,
      scaffoldBackgroundColor: resolvedScheme.appSurface,
      visualDensity: VisualDensity.standard,
      splashFactory: InkRipple.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: resolvedScheme.surface,
        foregroundColor: resolvedScheme.onSurface,
        scrolledUnderElevation: 2,
        surfaceTintColor: resolvedScheme.surfaceTint,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: resolvedScheme.onSurface,
          fontSize: 22,
          fontWeight: FontWeight.w500,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: resolvedScheme.appContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
      ),
      chipTheme: ChipThemeData(
        labelStyle: TextStyle(color: resolvedScheme.onSurfaceVariant),
        side: BorderSide(color: resolvedScheme.outlineVariant),
      ),
      dividerTheme: DividerThemeData(
        color: resolvedScheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: resolvedScheme.onSurfaceVariant,
        textColor: resolvedScheme.onSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: resolvedScheme.appInputFill,
        hoverColor: resolvedScheme.onSurface.withValues(alpha: 0.04),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: resolvedScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: resolvedScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: resolvedScheme.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: resolvedScheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: resolvedScheme.error, width: 1.6),
        ),
        labelStyle: TextStyle(color: resolvedScheme.onSurfaceVariant),
        hintStyle: TextStyle(color: resolvedScheme.onSurfaceVariant),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        backgroundColor: resolvedScheme.appContainerHigh,
        contentTextStyle: TextStyle(color: resolvedScheme.onSurface),
        actionTextColor: resolvedScheme.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: resolvedScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: resolvedScheme.appContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(28)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(72, 48),
          shape: const StadiumBorder(),
        ).copyWith(animationDuration: AppMotion.medium),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(72, 48),
          shape: const StadiumBorder(),
          side: BorderSide(color: resolvedScheme.outline),
        ).copyWith(animationDuration: AppMotion.medium),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: const CircleBorder(),
        ).copyWith(animationDuration: AppMotion.medium),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: resolvedScheme.outline),
            ),
          ),
        ),
      ),
      searchBarTheme: SearchBarThemeData(
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: WidgetStatePropertyAll(resolvedScheme.appInputFill),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        side: WidgetStatePropertyAll(
          BorderSide(color: resolvedScheme.outlineVariant),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 16),
        ),
      ),
      searchViewTheme: SearchViewThemeData(
        backgroundColor: resolvedScheme.appContainerHigh,
        surfaceTintColor: Colors.transparent,
        side: BorderSide(color: resolvedScheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
    );
  }
}

extension AppColorScheme on ColorScheme {
  Color get appSurface => surfaceContainerLow.withValues(alpha: 1);

  Color get appContainerLow => surfaceContainerLow;

  Color get appContainerHigh => surfaceContainerHigh;

  Color get appContainerHighest => surfaceContainerHighest;

  Color get appInputFill =>
      _blendPrimary(brightness == Brightness.dark ? 0.14 : 0.07);

  Color _blendPrimary(double alpha) {
    return Color.alphaBlend(
      primary.withValues(alpha: alpha),
      appSurface,
    ).withValues(alpha: 1);
  }
}

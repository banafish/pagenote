import 'package:flutter/material.dart';

/// 应用主题：Material 3，柔和暖色，纸张质感。
class AppTheme {
  AppTheme._();

  static const _fontFamilyFallback = [
    'Microsoft YaHei UI',
    'Microsoft YaHei',
    'PingFang SC',
    'Noto Sans SC',
    'sans-serif',
  ];

  static ThemeData light(Color seed) => _base(
    ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light),
  );

  static ThemeData dark(Color seed) =>
      _base(ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark));

  static ThemeData _base(ColorScheme scheme) {
    final isLight = scheme.brightness == Brightness.light;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamilyFallback: _fontFamilyFallback,
      scaffoldBackgroundColor: isLight
          ? const Color(0xFFFAF6F1)
          : const Color(0xFF16130F),
      canvasColor: isLight ? const Color(0xFFFAF6F1) : const Color(0xFF16130F),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: isLight
            ? const Color(0xFFFAF6F1)
            : const Color(0xFF16130F),
        foregroundColor: scheme.onSurface,
        titleTextStyle: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
          fontFamilyFallback: _fontFamilyFallback,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.5),
        space: 1,
        thickness: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isLight ? Colors.white : scheme.surfaceContainerLow,
        hintStyle: TextStyle(
          color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        height: 68,
        backgroundColor: isLight
            ? const Color(0xFFFAF6F1)
            : const Color(0xFF16130F),
        indicatorColor: scheme.primaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 26,
            color: states.contains(WidgetState.selected)
                ? scheme.onPrimaryContainer
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        elevation: 0,
        backgroundColor: isLight
            ? const Color(0xFFFAF6F1)
            : const Color(0xFF16130F),
        indicatorColor: scheme.primaryContainer,
        selectedIconTheme: IconThemeData(
          color: scheme.onPrimaryContainer,
          size: 26,
        ),
        unselectedIconTheme: IconThemeData(
          color: scheme.onSurfaceVariant,
          size: 24,
        ),
        selectedLabelTextStyle: TextStyle(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
          fontSize: 12.5,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontSize: 12.5,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      textTheme: _applyFallback(
        TextTheme(
          displaySmall: const TextStyle(
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
          headlineMedium: const TextStyle(
            fontWeight: FontWeight.w700,
            height: 1.25,
          ),
          headlineSmall: const TextStyle(
            fontWeight: FontWeight.w700,
            height: 1.3,
          ),
          titleLarge: const TextStyle(
            fontWeight: FontWeight.w700,
            height: 1.35,
          ),
          titleMedium: const TextStyle(
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
          titleSmall: const TextStyle(fontWeight: FontWeight.w600, height: 1.4),
          bodyLarge: const TextStyle(height: 1.55),
          bodyMedium: const TextStyle(height: 1.55),
          bodySmall: const TextStyle(height: 1.5),
        ),
      ),
    );
  }

  static TextTheme _applyFallback(TextTheme base) {
    return base.apply(fontFamilyFallback: _fontFamilyFallback);
  }
}

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 强调色种子选项。
class SeedColorOption {
  const SeedColorOption(this.name, this.color);
  final String name;
  final Color color;
}

const seedColorOptions = [
  SeedColorOption('暖橘', Color(0xFFE8734A)),
  SeedColorOption('豆沙', Color(0xFFB4576B)),
  SeedColorOption('黛蓝', Color(0xFF3F6C9C)),
  SeedColorOption('青竹', Color(0xFF3E8468)),
  SeedColorOption('紫藤', Color(0xFF7B5EA7)),
  SeedColorOption('琥珀', Color(0xFFB07D2B)),
];

/// 应用设置：主题模式、强调色、正文字号缩放。
class SettingsProvider extends ChangeNotifier {
  SettingsProvider(this._prefs);

  final SharedPreferences _prefs;

  static const _keyThemeMode = 'themeMode';
  static const _keySeedIndex = 'seedColorIndex';
  static const _keyFontScale = 'fontScale';

  ThemeMode get themeMode {
    final index = _prefs.getInt(_keyThemeMode) ?? ThemeMode.system.index;
    return ThemeMode.values[index.clamp(0, ThemeMode.values.length - 1)];
  }

  Color get seedColor =>
      seedColorOptions[_seedIndex.clamp(0, seedColorOptions.length - 1)].color;

  int get _seedIndex => _prefs.getInt(_keySeedIndex) ?? 0;

  /// 当前选中的强调色序号（供设置页高亮）。
  int get seedIndexCache =>
      _seedIndex.clamp(0, seedColorOptions.length - 1);

  /// 正文字号缩放，1.0 为标准。
  double get fontScale {
    final v = _prefs.getDouble(_keyFontScale) ?? 1.0;
    return v.clamp(0.85, 1.3);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await _prefs.setInt(_keyThemeMode, mode.index);
    notifyListeners();
  }

  Future<void> setSeedIndex(int index) async {
    await _prefs.setInt(_keySeedIndex, index);
    notifyListeners();
  }

  Future<void> setFontScale(double scale) async {
    await _prefs.setDouble(_keyFontScale, scale.clamp(0.85, 1.3));
    notifyListeners();
  }
}

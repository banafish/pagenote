import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/webdav_service.dart';

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

/// 应用锁触发延时时长（REQ-08.2）。
const lockDelayOptions = [
  Duration.zero,
  Duration(minutes: 1),
  Duration(minutes: 5),
];

/// 应用设置：主题模式、强调色、正文字号缩放、提醒、应用锁等。
class SettingsProvider extends ChangeNotifier {
  SettingsProvider(this._prefs);

  final SharedPreferences _prefs;

  static const _keyThemeMode = 'themeMode';
  static const _keySeedIndex = 'seedColorIndex';
  static const _keyFontScale = 'fontScale';

  // 时光页时间轴多列视图切换。
  static const _keyTimelineGrid = 'timeline.grid';

  // 回顾页当日列表多列视图切换。
  static const _keyCalendarGrid = 'calendar.grid';

  // 每日一问「换一条」（REQ-04.2）。
  static const _keyPromptDate = 'prompt.refreshDate';
  static const _keyPromptCount = 'prompt.refreshCount';
  static const _keyPromptOffset = 'prompt.offset';

  // 写作提醒（REQ-07）。
  static const _keyReminderEnabled = 'reminder.enabled';
  static const _keyReminderMinutes = 'reminder.minutes';

  // 应用锁（REQ-08）。
  static const _keyLockSalt = 'lock.salt';
  static const _keyPinHash = 'lock.pinHash';
  static const _keyLockBiometric = 'lock.biometric';
  static const _keyLockDelayIndex = 'lock.delayIndex';

  // 分享图署名（REQ-11.3）。
  static const _keyShareSignature = 'share.signature';

  // 月报引导卡片已展示到的月份（REQ-10.3）。
  static const _keyReportPromptMonth = 'report.promptMonth';

  // 自定义活动（REQ-12.1）。
  static const _keyCustomActivities = 'activities.custom';

  // WebDAV 自动备份（REQ-15）。
  static const _keyWebdavUrl = 'webdav.url';
  static const _keyWebdavUsername = 'webdav.username';
  static const _keyWebdavPassword = 'webdav.password';
  static const _keyWebdavEnabled = 'webdav.enabled';
  static const _keyWebdavIntervalDays = 'webdav.intervalDays';
  static const _keyWebdavLastBackupAt = 'webdav.lastBackupAt';
  static const _keyWebdavLastError = 'webdav.lastError';

  // WebDAV 自动备份间隔选项（REQ-15 定期备份）。
  static const webdavIntervalChoices = [1, 3, 7];

  // 素材面板最近使用与收藏（REQ-17.1 / REQ-17.2）。
  static const _keyRecentStickers = 'stickers.recent';
  static const _keyFavoriteStickers = 'stickers.favorite';

  /// 最近使用素材保留的最大条数（REQ-17.1）。
  static const _recentStickerLimit = 24;

  ThemeMode get themeMode {
    final index = _prefs.getInt(_keyThemeMode) ?? ThemeMode.system.index;
    return ThemeMode.values[index.clamp(0, ThemeMode.values.length - 1)];
  }

  Color get seedColor =>
      seedColorOptions[_seedIndex.clamp(0, seedColorOptions.length - 1)].color;

  int get _seedIndex => _prefs.getInt(_keySeedIndex) ?? 0;

  /// 当前选中的强调色序号（供设置页高亮）。
  int get seedIndexCache => _seedIndex.clamp(0, seedColorOptions.length - 1);

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

  /// 时光页时间轴是否为多列视图，默认单列。
  bool get timelineGrid => _prefs.getBool(_keyTimelineGrid) ?? false;

  Future<void> setTimelineGrid(bool enabled) async {
    await _prefs.setBool(_keyTimelineGrid, enabled);
    notifyListeners();
  }

  /// 回顾页当日手账列表是否为多列视图，默认单列。
  bool get calendarGrid => _prefs.getBool(_keyCalendarGrid) ?? false;

  Future<void> setCalendarGrid(bool enabled) async {
    await _prefs.setBool(_keyCalendarGrid, enabled);
    notifyListeners();
  }

  // ---------------- 每日一问 ----------------

  /// 今日已「换一条」的次数（跨天自动清零）。
  int promptRefreshUsedToday(String todayKey) {
    final date = _prefs.getString(_keyPromptDate);
    if (date != todayKey) return 0;
    return _prefs.getInt(_keyPromptCount) ?? 0;
  }

  /// 当日的累计偏移量：换一条后 +1，同一天内保持稳定。
  int promptOffsetFor(String todayKey) {
    final date = _prefs.getString(_keyPromptDate);
    if (date != todayKey) return 0;
    return _prefs.getInt(_keyPromptOffset) ?? 0;
  }

  /// 记录一次「换一条」，返回是否还有额度（每日 3 次）。
  Future<bool> usePromptRefresh(String todayKey) async {
    if (promptRefreshUsedToday(todayKey) >= 3) return false;
    final used = promptRefreshUsedToday(todayKey);
    final offset = promptOffsetFor(todayKey);
    await _prefs.setString(_keyPromptDate, todayKey);
    await _prefs.setInt(_keyPromptCount, used + 1);
    await _prefs.setInt(_keyPromptOffset, offset + 1);
    notifyListeners();
    return true;
  }

  // ---------------- 写作提醒 ----------------

  bool get reminderEnabled => _prefs.getBool(_keyReminderEnabled) ?? false;

  /// 提醒时间，距 0 点的分钟数（默认 21:30）。
  int get reminderMinutes => _prefs.getInt(_keyReminderMinutes) ?? 21 * 60 + 30;

  Future<void> setReminder(bool enabled, int minutes) async {
    await _prefs.setBool(_keyReminderEnabled, enabled);
    await _prefs.setInt(_keyReminderMinutes, minutes);
    notifyListeners();
  }

  // ---------------- 应用锁 ----------------

  /// 应用锁是否开启（设置了 PIN 即开启）。
  bool get lockEnabled => (_prefs.getString(_keyPinHash) ?? '').isNotEmpty;

  String get lockSalt => _prefs.getString(_keyLockSalt) ?? '';

  String get pinHash => _prefs.getString(_keyPinHash) ?? '';

  bool get lockBiometric => _prefs.getBool(_keyLockBiometric) ?? false;

  /// 后台返回多久后需要重新解锁（见 lockDelayOptions）。
  int get lockDelayIndex {
    final v = _prefs.getInt(_keyLockDelayIndex) ?? 0;
    return v.clamp(0, lockDelayOptions.length - 1);
  }

  Duration get lockDelay => lockDelayOptions[lockDelayIndex];

  Future<void> setPin(String salt, String hash) async {
    await _prefs.setString(_keyLockSalt, salt);
    await _prefs.setString(_keyPinHash, hash);
    notifyListeners();
  }

  Future<void> setLockBiometric(bool enabled) async {
    await _prefs.setBool(_keyLockBiometric, enabled);
    notifyListeners();
  }

  Future<void> setLockDelayIndex(int index) async {
    await _prefs.setInt(
      _keyLockDelayIndex,
      index.clamp(0, lockDelayOptions.length - 1),
    );
    notifyListeners();
  }

  /// 关闭应用锁（需先验证身份）。
  Future<void> disableLock() async {
    await _prefs.remove(_keyPinHash);
    await _prefs.remove(_keyLockSalt);
    await _prefs.setBool(_keyLockBiometric, false);
    notifyListeners();
  }

  // ---------------- 分享图 ----------------

  bool get shareSignatureEnabled => _prefs.getBool(_keyShareSignature) ?? true;

  Future<void> setShareSignature(bool enabled) async {
    await _prefs.setBool(_keyShareSignature, enabled);
    notifyListeners();
  }

  // ---------------- 月报引导 ----------------

  /// 已展示过「上月月报」引导卡片的月份（yyyy-MM）。
  String get reportPromptMonth => _prefs.getString(_keyReportPromptMonth) ?? '';

  Future<void> setReportPromptMonth(String ym) async {
    await _prefs.setString(_keyReportPromptMonth, ym);
    notifyListeners();
  }

  // ---------------- 自定义活动 ----------------

  List<String> get customActivities {
    final raw = _prefs.getString(_keyCustomActivities);
    if (raw == null || raw.isEmpty) return [];
    return (jsonDecode(raw) as List).cast<String>();
  }

  Future<void> addCustomActivity(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final list = customActivities;
    if (list.contains(trimmed)) return;
    await _prefs.setString(
      _keyCustomActivities,
      jsonEncode([...list, trimmed]),
    );
    notifyListeners();
  }

  Future<void> removeCustomActivity(String name) async {
    final list = customActivities..remove(name);
    await _prefs.setString(_keyCustomActivities, jsonEncode(list));
    notifyListeners();
  }

  // ---------------- WebDAV 自动备份（REQ-15） ----------------

  String get webdavUrl => _prefs.getString(_keyWebdavUrl) ?? '';

  String get webdavUsername => _prefs.getString(_keyWebdavUsername) ?? '';

  /// 应用密码以 base64 混淆存储（仅防明文直读,非加密）。
  String get webdavPassword {
    final raw = _prefs.getString(_keyWebdavPassword);
    if (raw == null || raw.isEmpty) return '';
    try {
      return utf8.decode(base64Decode(raw));
    } on FormatException {
      return '';
    }
  }

  /// 是否已填写完整的服务器配置。
  bool get webdavConfigured =>
      webdavUrl.isNotEmpty &&
      webdavUsername.isNotEmpty &&
      webdavPassword.isNotEmpty;

  bool get webdavEnabled => _prefs.getBool(_keyWebdavEnabled) ?? false;

  /// 自动备份间隔（天,默认每天）。
  int get webdavIntervalDays =>
      _prefs.getInt(_keyWebdavIntervalDays) ?? webdavIntervalChoices.first;

  /// 上次成功自动备份时间;null 表示从未备份。
  DateTime? get webdavLastBackupAt {
    final ms = _prefs.getInt(_keyWebdavLastBackupAt);
    return ms == null || ms <= 0
        ? null
        : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// 上次自动备份的错误信息（展示在设置页,空串为无错误）。
  String get webdavLastError => _prefs.getString(_keyWebdavLastError) ?? '';

  Future<void> setWebdavConfig({
    required String url,
    required String username,
    required String password,
  }) async {
    await _prefs.setString(_keyWebdavUrl, url.trim());
    await _prefs.setString(_keyWebdavUsername, username.trim());
    await _prefs.setString(
      _keyWebdavPassword,
      password.isEmpty ? '' : base64Encode(utf8.encode(password)),
    );
    notifyListeners();
  }

  Future<void> setWebdavEnabled(bool enabled) async {
    await _prefs.setBool(_keyWebdavEnabled, enabled);
    notifyListeners();
  }

  Future<void> setWebdavIntervalDays(int days) async {
    await _prefs.setInt(_keyWebdavIntervalDays, days);
    notifyListeners();
  }

  Future<void> setWebdavLastBackupAt(DateTime? time) async {
    await _prefs.setInt(
      _keyWebdavLastBackupAt,
      time?.millisecondsSinceEpoch ?? 0,
    );
    notifyListeners();
  }

  Future<void> setWebdavLastError(String message) async {
    await _prefs.setString(_keyWebdavLastError, message);
    notifyListeners();
  }

  /// 是否到达本次启动应执行自动备份的时间。
  bool get webdavBackupDue => isBackupDue(
    enabled: webdavEnabled && webdavConfigured,
    last: webdavLastBackupAt,
    intervalDays: webdavIntervalDays,
    now: DateTime.now(),
  );

  // ---------------- 素材最近使用与收藏（REQ-17） ----------------

  /// 读取以 JSON 数组存储的素材 key 列表。
  List<String> _stickerKeys(String prefsKey) {
    final raw = _prefs.getString(prefsKey);
    if (raw == null || raw.isEmpty) return [];
    return (jsonDecode(raw) as List).cast<String>();
  }

  /// 最近使用的素材 key，最新在前（REQ-17.1，只存 key 不存素材本体）。
  List<String> get recentStickerKeys => _stickerKeys(_keyRecentStickers);

  /// 记录一次素材使用：置顶去重，超出上限丢弃最旧的。
  Future<void> pushRecentSticker(String key) async {
    if (key.isEmpty) return;
    final list = recentStickerKeys..remove(key);
    list.insert(0, key);
    if (list.length > _recentStickerLimit) {
      list.removeRange(_recentStickerLimit, list.length);
    }
    await _prefs.setString(_keyRecentStickers, jsonEncode(list));
    notifyListeners();
  }

  /// 收藏的素材 key，列表顺序即展示顺序（REQ-17.2）。
  List<String> get favoriteStickerKeys => _stickerKeys(_keyFavoriteStickers);

  bool isFavoriteSticker(String key) => favoriteStickerKeys.contains(key);

  /// 切换收藏状态，新收藏排在最前。
  Future<void> toggleFavoriteSticker(String key) async {
    if (key.isEmpty) return;
    final list = favoriteStickerKeys;
    if (!list.remove(key)) list.insert(0, key);
    await _prefs.setString(_keyFavoriteStickers, jsonEncode(list));
    notifyListeners();
  }

  /// 手动拖拽排序后整体覆盖收藏顺序（REQ-17.2）。
  Future<void> reorderFavoriteStickers(List<String> keys) async {
    await _prefs.setString(_keyFavoriteStickers, jsonEncode(keys));
    notifyListeners();
  }
}

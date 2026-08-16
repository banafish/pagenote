import 'dart:io';

import 'package:flutter/services.dart';

import '../data/prompts.dart';
import '../providers/journal_provider.dart';
import '../utils/date_utils.dart';
import 'notification_service.dart';

/// 桌面小组件展示内容（REQ-14）:连续天数 + 今日是否已写 + 今日一问。
/// 纯数据类便于在无插件的测试环境中构造与断言。
class WidgetContent {
  const WidgetContent({
    required this.streakDays,
    required this.writtenToday,
    required this.prompt,
  });

  final int streakDays;
  final bool writtenToday;
  final String prompt;

  /// 从手账数据派生小组件内容。
  static WidgetContent from(JournalProvider journal, [DateTime? now]) {
    final n = now ?? DateTime.now();
    return WidgetContent(
      streakDays: journal.streakDays,
      writtenToday: journal.entries.any((e) => e.date == DateUtils2.dateKey(n)),
      prompt: promptForDate(DateUtils2.dateKey(n)),
    );
  }

  Map<String, Object?> toChannelMap() => {
    'streak': streakDays,
    'writtenToday': writtenToday,
    'prompt': prompt,
  };
}

/// Android 桌面小组件桥接（REQ-14,仅 Android;Windows 端为无操作）。
/// 通过 MainActivity 的 MethodChannel('pagenote/app') 写入小组件数据并触发刷新;
/// 点击小组件拉起 MainActivity(open_editor)→ 本服务转发到编辑页路由。
class WidgetService {
  WidgetService._();

  static final WidgetService instance = WidgetService._();

  static const _channel = MethodChannel('pagenote/app');

  bool get supported => Platform.isAndroid;

  /// 冷启动时由小组件拉起待处理的「写手账」动作。
  bool _pendingEditor = false;

  /// 初始化:注册原生回调;检查启动 intent 是否来自小组件点击。
  Future<void> init() async {
    if (!supported) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'widget.openEditor') {
        _openEditor();
      }
    });
    try {
      final open = await _channel.invokeMethod<bool>(
        'widget.consumeLaunchAction',
      );
      if (open == true) _pendingEditor = true;
    } on MissingPluginException {
      // 原生侧尚未就绪（如测试环境）:忽略。
    } on PlatformException {
      // 忽略,不影响启动。
    }
  }

  void _openEditor() {
    // 复用写作提醒的通知导航通道（REQ-07.3）直达编辑页。
    NotificationService.instance.navigatorKey.currentState?.pushNamed('/write');
  }

  /// 冷启动待处理动作的消费者（由 RootShell 调用,与通知一致）。
  void consumePendingEditor(VoidCallback openEditor) {
    if (_pendingEditor) {
      _pendingEditor = false;
      openEditor();
    }
  }

  /// 把最新数据推给小组件;失败静默（小组件不影响主流程）。
  Future<void> updateFrom(JournalProvider journal) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>(
        'widget.update',
        WidgetContent.from(journal).toChannelMap(),
      );
    } on MissingPluginException {
      // 原生侧尚未就绪。
    } on PlatformException {
      // 忽略。
    }
  }
}

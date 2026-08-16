import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// 写作提醒通知（REQ-07）。仅 Android 支持本地通知；
/// Windows 端在设置页展示降级说明（NFR-04）。
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  /// 全局导航键：点击通知后跳转到编辑页。
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  /// 通知点击后待处理的动作（冷启动时由 RootShell 消费）。
  String? pendingAction;

  bool _initialized = false;
  final _plugin = FlutterLocalNotificationsPlugin();

  static const _channelId = 'journal_reminder';
  static const _notificationId = 1001;

  /// 平台是否支持写作提醒（Android）。
  bool get supported => Platform.isAndroid;

  /// 提醒文案池（REQ-07.1：随机挑选）。
  static const reminderCopies = [
    '今天过得怎么样？睡前写下今天的这一页 📖',
    '此刻的心情值得被记住，来写今天的手账吧 ✍️',
    '再忙也别忘了记录生活，今天有什么小确幸？✨',
    '一日一页，未来的你会感谢现在记录的你 🌙',
    '今天遇到了什么有趣的事？写下来吧 💭',
    '睡前五分钟，把今天轻轻放进手账里 🍃',
  ];

  static String randomCopy() =>
      reminderCopies[Random().nextInt(reminderCopies.length)];

  Future<void> init() async {
    if (!supported || _initialized) return;
    tzdata.initializeTimeZones();
    try {
      final localTz = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localTz));
    } catch (_) {
      // 拿不到时区时退化为 UTC，不影响调度。
    }

    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (response) {
        final action = response.payload;
        if (action == 'write') {
          _handleWriteAction();
        }
      },
    );
    _initialized = true;

    // 冷启动：检查是否由通知点击拉起。
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      final payload = launchDetails?.notificationResponse?.payload;
      if (payload == 'write') pendingAction = 'write';
    }
  }

  void _handleWriteAction() {
    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      pendingAction = 'write';
      return;
    }
    navigator.pushNamed('/write');
  }

  void consumePendingAction(void Function() onWrite) {
    if (pendingAction == 'write') {
      pendingAction = null;
      onWrite();
    }
  }

  /// 请求通知权限，返回是否授予。
  Future<bool> requestPermission() async {
    if (!supported) return false;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return false;
    return await android.requestNotificationsPermission() ?? false;
  }

  /// 调度每日提醒。返回调度结果：
  /// - denied：通知权限被拒；
  /// - inexact：精确闹钟权限被拒，已降级为非精确提醒（可能略有偏差）；
  /// - exact：精确提醒。
  Future<ReminderScheduleResult> scheduleDaily(int hour, int minute) async {
    if (!supported) return ReminderScheduleResult.denied;
    await cancelDaily();

    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final granted = await android?.requestNotificationsPermission();
    if (granted == false) return ReminderScheduleResult.denied;

    var exact = true;
    try {
      // Android 12+ 需用户授予精确闹钟权限；未授予时降级为非精确提醒。
      final granted = await android?.requestExactAlarmsPermission();
      exact = granted ?? false;
    } catch (_) {
      // 部分 ROM 不支持引导授权，忽略。
    }

    final now = tz.TZDateTime.now(tz.local);
    var when = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (!when.isAfter(now)) {
      when = when.add(const Duration(days: 1));
    }

    await _plugin.zonedSchedule(
      _notificationId,
      '该写手账啦',
      randomCopy(),
      when,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          '写作提醒',
          channelDescription: '每日写作提醒通知',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode: exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: 'write',
    );
    return exact
        ? ReminderScheduleResult.exact
        : ReminderScheduleResult.inexact;
  }

  Future<void> cancelDaily() async {
    if (!supported) return;
    await _plugin.cancel(_notificationId);
  }
}

enum ReminderScheduleResult { exact, inexact, denied }

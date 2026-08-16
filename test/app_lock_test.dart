import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pagenote/providers/settings_provider.dart';
import 'package:pagenote/services/app_lock.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('PIN 加盐哈希：同 PIN 同盐结果一致，不同盐不同（REQ-08.1）', () {
    final salt1 = PinHasher.newSalt();
    final salt2 = PinHasher.newSalt();
    expect(salt1, isNot(equals(salt2)));

    final h1 = PinHasher.hash('1234', salt1);
    expect(PinHasher.verify('1234', salt1, h1), isTrue);
    expect(PinHasher.verify('1235', salt1, h1), isFalse);
    expect(PinHasher.verify('1234', salt2, h1), isFalse, reason: '盐不同则哈希不同');
  });

  test('连续错 5 次锁定 30 秒（REQ-08.3）', () {
    var now = DateTime(2026, 8, 16, 10, 0, 0);
    final guard = PinAttemptGuard(() => now);

    for (var i = 0; i < 4; i++) {
      expect(guard.registerFailure(), isFalse, reason: '前 4 次不触发锁定');
    }
    expect(guard.isLocked, isFalse);

    // 第 5 次触发锁定。
    expect(guard.registerFailure(), isTrue);
    expect(guard.isLocked, isTrue);
    expect(guard.lockRemainingSeconds, 30);

    // 29 秒后仍锁定。
    now = now.add(const Duration(seconds: 29));
    expect(guard.isLocked, isTrue);

    // 30 秒后解锁，计数已重置。
    now = now.add(const Duration(seconds: 2));
    expect(guard.isLocked, isFalse);
    expect(guard.attempts, 0);
  });

  test('成功验证清空计数', () {
    final guard = PinAttemptGuard();
    guard.registerFailure();
    guard.registerFailure();
    expect(guard.attempts, 2);
    guard.registerSuccess();
    expect(guard.attempts, 0);
    expect(guard.isLocked, isFalse);
  });

  test('设置项：PIN 存取与开关状态（REQ-08.1/2）', () async {
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsProvider(prefs);

    expect(settings.lockEnabled, isFalse);
    expect(settings.lockDelay, Duration.zero);

    final salt = PinHasher.newSalt();
    await settings.setPin(salt, PinHasher.hash('8888', salt));
    expect(settings.lockEnabled, isTrue);
    expect(
      PinHasher.verify('8888', settings.lockSalt, settings.pinHash),
      isTrue,
    );

    await settings.setLockDelayIndex(1);
    expect(settings.lockDelay, const Duration(minutes: 1));
    await settings.setLockBiometric(true);
    expect(settings.lockBiometric, isTrue);

    await settings.disableLock();
    expect(settings.lockEnabled, isFalse);
    expect(settings.lockBiometric, isFalse, reason: '关闭应用锁同时关闭生物识别');
  });
}

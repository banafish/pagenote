import 'package:local_auth/local_auth.dart';

/// 生物识别（REQ-08）：Android 生物识别 / Windows Hello。
/// 不支持的平台安静降级为仅 PIN（NFR-04）。
class BiometricService {
  BiometricService._();

  static final _auth = LocalAuthentication();

  /// 设备是否有可用的生物识别。
  static Future<bool> get isAvailable async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final supported = await _auth.isDeviceSupported();
      return canCheck && supported;
    } catch (_) {
      return false;
    }
  }

  /// 拉起生物识别验证，失败或不可用返回 false。
  static Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}

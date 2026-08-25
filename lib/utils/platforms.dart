import 'package:flutter/foundation.dart';

/// 是否运行在原生 Android 应用。Web 端恒为 false——浏览器的
/// defaultTargetPlatform 会按宿主操作系统报值，不能用来判断系统能力。
bool get isNativeAndroid =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// 是否运行在原生 iOS 应用；Web 端恒为 false。
bool get isNativeIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

/// 是否为原生移动应用（Android/iOS 客户端，不含 Web）。
bool get isNativeMobile => isNativeAndroid || isNativeIOS;

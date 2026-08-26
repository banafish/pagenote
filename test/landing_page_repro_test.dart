import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pagenote/pages/landing_page.dart';
import 'package:pagenote/theme/app_theme.dart';

/// 品牌主页布局回归：
/// 1. 功能卡片区曾用 IntrinsicHeight + stretch 强制等高，Web 端字体异步
///    加载后行高被冻结在首帧偏矮值，所有卡片溢出一行（BOTTOM OVERFLOWED
///    BY ~23 PIXELS），现改为自然高度顶对齐；
/// 2. Hero 纸页装饰的日期行在正文字号放大（fontScale > 1）时会水平溢出，
///    现在日期文本可收缩省略。
/// 页面含无限循环的漂浮动画，只能用 pump 推进固定时长，不能 pumpAndSettle。
void main() {
  Widget buildApp({TextScaler textScaler = TextScaler.noScaling}) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(const Color(0xFFFDEAE3)),
      locale: const Locale('zh'),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
      home: const LandingPage(),
    );
  }

  void useViewport(WidgetTester tester, Size logicalSize, double dpr) {
    tester.view.physicalSize = logicalSize * dpr;
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.reset);
  }

  // (说明, 视口, DPR, 字号缩放)
  const cases = <(String, Size, double, double)>[
    ('桌面 3 列 @1333/DPR1.5', Size(1333, 900), 1.5, 1.0),
    ('桌面 3 列 @1920/DPR1', Size(1920, 1080), 1.0, 1.0),
    ('平板 2 列 @900', Size(900, 900), 1.0, 1.0),
    ('手机 1 列 @390', Size(390, 844), 2.0, 1.0),
    ('桌面 3 列 + 大字号 1.2', Size(1333, 900), 1.5, 1.2),
    ('平板 2 列 + 最大字号 1.3', Size(900, 900), 1.0, 1.3),
  ];

  for (final (name, size, dpr, scale) in cases) {
    testWidgets('品牌主页无溢出：$name', (tester) async {
      useViewport(tester, size, dpr);
      await tester.pumpWidget(buildApp(textScaler: TextScaler.linear(scale)));
      // 推进入场动画与首帧后的重排，捕获布局异常。
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);
    });
  }
}

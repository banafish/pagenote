import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app.dart';
import '../models/sticker_assets.dart';
import '../utils/landing_links.dart';
import '../utils/open_external_url.dart';
import '../widgets/lock_gate.dart';
import '../widgets/share_pack_gate.dart';

/// Web 品牌主页：产品介绍 +「开始使用」入口。
/// 仅 Web 端作为应用首页；点击开始后整页替换进入应用本体。
/// 装饰全部复用应用内置的矢量贴纸 / 和纸胶带绘制器，延续零图片资产定位。
class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage>
    with TickerProviderStateMixin {
  final _featuresKey = GlobalKey();

  /// 入场渐显动画（一次性）。
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..forward();

  /// 装饰元素漂浮动画（循环）。
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 7),
  )..repeat();

  @override
  void dispose() {
    _intro.dispose();
    _drift.dispose();
    super.dispose();
  }

  void _enterApp() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) =>
            const LockGate(child: SharePackGate(child: RootShell())),
      ),
    );
  }

  void _toFeatures() {
    final ctx = _featuresKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 1000;
    final sidePad = math.max(20.0, math.min(width * 0.06, 72.0));

    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildNav(scheme, wide, sidePad),
            _buildHero(scheme, wide, sidePad),
            _buildFeatures(scheme, wide, sidePad),
            if (_hasExternalLinks) _buildDownload(scheme, wide, sidePad),
            _buildFooter(scheme),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- 顶部导航

  Widget _buildNav(ColorScheme scheme, bool wide, double sidePad) {
    final isLight = scheme.brightness == Brightness.light;
    return Padding(
      padding: EdgeInsets.fromLTRB(sidePad, 18, sidePad, 4),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1160),
          child: Row(
            children: [
              _logoBadge(scheme, isLight, 40),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '拾页',
                    style: TextStyle(
                      fontFamily: 'LXGW WenKai',
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                    ),
                  ),
                  Text(
                    'PAGENOTE',
                    style: TextStyle(
                      fontSize: 9,
                      letterSpacing: 3.4,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              if (wide)
                FilledButton.tonal(
                  onPressed: _enterApp,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                  ),
                  child: const Text('开始使用'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _logoBadge(ColorScheme scheme, bool isLight, double size) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isLight ? Colors.white : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(size * 0.32),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.24),
        child: Image.asset('assets/icon/app_icon.png'),
      ),
    );
  }

  // -------------------------------------------------------------- 首屏 Hero

  Widget _buildHero(ColorScheme scheme, bool wide, double sidePad) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // 柔和色斑背景。
        Positioned(left: -150, top: -80, child: _blob(400, scheme.primary)),
        Positioned(
          right: -170,
          top: 140,
          child: _blob(480, scheme.tertiary),
        ),
        Positioned(
          left: 40,
          bottom: -180,
          child: _blob(340, scheme.secondary),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            sidePad,
            wide ? 60 : 40,
            sidePad,
            wide ? 90 : 60,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1160),
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(flex: 11, child: _heroText(scheme, wide)),
                        const SizedBox(width: 48),
                        Expanded(flex: 10, child: _mockup(scheme, wide)),
                      ],
                    )
                  : Column(
                      children: [
                        _heroText(scheme, wide),
                        const SizedBox(height: 56),
                        _mockup(scheme, wide),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }

  /// 径向渐变柔光色斑。
  Widget _blob(double size, Color base) {
    final color = base.withValues(alpha: 0.09);
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }

  Widget _heroText(ColorScheme scheme, bool wide) {
    final width = MediaQuery.sizeOf(context).width;
    final titleSize = wide ? 56.0 : math.max(34.0, math.min(width * 0.095, 46));
    final align = wide ? TextAlign.start : TextAlign.center;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Column(
          crossAxisAlignment: wide
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: [
            _reveal(0.0, _badge(scheme, align)),
            const SizedBox(height: 24),
            _reveal(
              0.1,
              Column(
                crossAxisAlignment: wide
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.center,
                children: [
                  Text(
                    '拾起生活中的',
                    textAlign: align,
                    style: TextStyle(
                      fontSize: titleSize * 0.68,
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Stack(
                    children: [
                      Positioned.fill(
                        left: -4,
                        right: -10,
                        child: CustomPaint(
                          painter: _BrushStroke(
                            color: scheme.primary.withValues(alpha: 0.22),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          '每一页',
                          style: TextStyle(
                            fontFamily: 'Ma Shan Zheng',
                            fontSize: titleSize * 1.12,
                            height: 1.2,
                            color: scheme.primary,
                            letterSpacing: 6,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            _reveal(
              0.22,
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Text(
                  '拾页是一款精美的手账应用 —— 像拼贴一样自由排布文字、照片、'
                  '贴纸与胶带，再记下当天的心情与天气，把平凡日子装订成'
                  '一页页温柔的记忆。',
                  textAlign: align,
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.85,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 34),
            _reveal(0.34, _ctaRow(scheme, wide)),
            const SizedBox(height: 20),
            _reveal(0.42, _hintRow(scheme, wide)),
            const SizedBox(height: 38),
            _reveal(0.5, _statsRow(scheme, wide)),
          ],
        ),
        // 散落在文字旁的小装饰。
        if (wide) ...[
          Positioned(
            left: -46,
            top: -18,
            child: _floaty(
              dy: 8,
              phase: 1.2,
              child: Opacity(
                opacity: 0.9,
                child: Transform.rotate(
                  angle: -0.18,
                  child: _sticker('paperplane', 52),
                ),
              ),
            ),
          ),
          Positioned(
            right: -52,
            top: 128,
            child: _floaty(
              dy: 7,
              phase: 3.6,
              child: Opacity(
                opacity: 0.85,
                child: Transform.rotate(
                  angle: 0.14,
                  child: _sticker('star', 40),
                ),
              ),
            ),
          ),
        ] else
          Positioned(
            right: -6,
            top: -34,
            child: _floaty(
              dy: 6,
              phase: 2.2,
              child: Opacity(
                opacity: 0.8,
                child: Transform.rotate(
                  angle: 0.12,
                  child: _sticker('star', 34),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _badge(ColorScheme scheme, TextAlign align) {
    final centered = align == TextAlign.center;
    return Align(
      alignment: centered ? Alignment.center : Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.favorite_rounded, size: 13, color: scheme.primary),
            const SizedBox(width: 7),
            Text(
              '免费 · 无广告 · 数据留在本机',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ctaRow(ColorScheme scheme, bool wide) {
    final buttonStyle = FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 18),
      textStyle: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700),
    );
    final secondary = OutlinedButton.icon(
      onPressed: _toFeatures,
      icon: const Icon(Icons.expand_more_rounded, size: 20),
      label: const Text('了解更多'),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 17),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    );
    final primary = FilledButton.icon(
      onPressed: _enterApp,
      icon: const Icon(Icons.auto_stories_rounded, size: 20),
      label: const Text('开始使用'),
      style: buttonStyle,
    );
    if (wide) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        primary,
        const SizedBox(width: 14),
        secondary,
      ]);
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [primary, const SizedBox(width: 14), secondary],
    );
  }

  Widget _hintRow(ColorScheme scheme, bool wide) {
    Widget item(String text) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_rounded,
              size: 14,
              color: scheme.primary.withValues(alpha: 0.8),
            ),
            const SizedBox(width: 5),
            Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.9),
              ),
            ),
          ],
        );

    final items = [
      item('无需注册'),
      item('免费无广告'),
      item('离线可用'),
    ];
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        items[0],
        const SizedBox(width: 16),
        items[1],
        const SizedBox(width: 16),
        items[2],
      ],
    );
    return wide
        ? row
        : Center(
            child: row,
          );
  }

  Widget _statsRow(ColorScheme scheme, bool wide) {
    Widget stat(String number, String label) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment:
              wide ? CrossAxisAlignment.start : CrossAxisAlignment.center,
          children: [
            Text(
              number,
              style: const TextStyle(
                fontFamily: 'LXGW WenKai',
                fontSize: 25,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                letterSpacing: 0.5,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
              ),
            ),
          ],
        );

    final stats = [
      stat('81+', '矢量贴纸'),
      stat('132', '和纸胶带配色'),
      stat('12', '整页版式模板'),
      stat('0', '图片资产'),
    ];

    Widget separator() => Container(
          width: 1,
          height: 30,
          color: scheme.outlineVariant.withValues(alpha: 0.6),
        );

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        stats[0],
        const SizedBox(width: 26),
        separator(),
        const SizedBox(width: 26),
        stats[1],
        const SizedBox(width: 26),
        separator(),
        const SizedBox(width: 26),
        stats[2],
        const SizedBox(width: 26),
        separator(),
        const SizedBox(width: 26),
        stats[3],
      ],
    );
    return wide
        ? row
        : Center(
            child: FittedBox(child: row),
          );
  }

  // ------------------------------------------------------------ 手账页样张

  /// 右侧展示区：一张「正在书写的手账页」，叠加拍立得与便利贴，
  /// 全部由应用内置素材绘制器拼贴而成，随呼吸轻轻漂浮。
  Widget _mockup(ColorScheme scheme, bool wide) {
    final pw = wide ? 348.0 : math.min(352.0, MediaQuery.sizeOf(context).width - 88);
    final compact = !wide;

    return AnimatedBuilder(
      animation: _drift,
      builder: (context, _) {
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // 左后方：拍立得照片。
            Positioned(
              left: compact ? -pw * 0.16 : -pw * 0.3,
              top: compact ? 26 : 40,
              child: _floaty(
                dy: 7,
                dx: 3,
                phase: 1.4,
                child: Transform.rotate(
                  angle: -0.13,
                  child: _polaroid(),
                ),
              ),
            ),
            // 右下方：便利贴。
            Positioned(
              right: compact ? -pw * 0.06 : -pw * 0.16,
              bottom: compact ? 4 : 10,
              child: _floaty(
                dy: 8,
                dx: 3,
                phase: 3.9,
                child: Transform.rotate(
                  angle: 0.1,
                  child: _stickyNote(),
                ),
              ),
            ),
            // 主手账纸。
            _floaty(
              dy: 5,
              child: Transform.rotate(
                angle: 0.028,
                child: _mainPaper(scheme, pw),
              ),
            ),
            // 右上角彩虹贴纸。
            Positioned(
              right: compact ? -4 : -18,
              top: compact ? -36 : -44,
              child: _floaty(
                dy: 9,
                phase: 2.6,
                child: Transform.rotate(
                  angle: 0.12,
                  child: _sticker('rainbow', wide ? 66 : 54),
                ),
              ),
            ),
            // 左下叶子。
            Positioned(
              left: compact ? -6 : -26,
              bottom: compact ? -22 : -30,
              child: _floaty(
                dy: 6,
                phase: 5.1,
                child: Transform.rotate(
                  angle: -0.2,
                  child: _sticker('leaf', 46),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  static const _ink = Color(0xFF43392D);
  static const _inkSoft = Color(0xFF6E604F);
  static const _paper = Color(0xFFFFFDF6);
  static const _paperEdge = Color(0xFFE7DCCB);
  static const _paperChip = Color(0xFFF6EEE1);

  /// 主手账纸卡片：日期行 + 标题 + 正文 + 贴纸排。
  Widget _mainPaper(ColorScheme scheme, double pw) {
    final now = DateTime.now();
    const weeks = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    final dateLabel = '${now.month}月${now.day}日 · ${weeks[now.weekday - 1]}';

    Widget chip(String text) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: _paperChip,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            text,
            style: const TextStyle(fontSize: 11, color: _inkSoft),
          ),
        );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: pw,
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
          decoration: BoxDecoration(
            color: _paper,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _paperEdge),
            boxShadow: const [
              BoxShadow(
                color: Color(0x296B5433),
                blurRadius: 36,
                offset: Offset(0, 18),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  // 正文字号放大时纸页宽度固定，日期文本可能放不下，需可收缩。
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        dateLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'LXGW WenKai',
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: _inkSoft,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  chip('☀️ 晴'),
                  const SizedBox(width: 6),
                  chip('😊 开心'),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                '街角的猫 🐈',
                style: TextStyle(
                  fontFamily: 'ZCOOL KuaiLe',
                  fontSize: 23,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                '今天在巷口的花店门口，遇见一只晒太阳的橘猫。'
                '买了杯燕麦拿铁坐在窗边，把它画进了这一页。',
                style: TextStyle(
                  fontFamily: 'LXGW WenKai',
                  fontSize: 14.5,
                  height: 1.85,
                  color: _inkSoft,
                ),
              ),
              const SizedBox(height: 16),
              Container(height: 1, color: _paperEdge),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Transform.rotate(angle: -0.12, child: _sticker('coffee', 42)),
                  const SizedBox(width: 12),
                  Transform.rotate(angle: 0.08, child: _sticker('cat', 50)),
                  const SizedBox(width: 12),
                  Transform.rotate(angle: -0.05, child: _sticker('flower', 34)),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Transform.rotate(
                      angle: 0.15,
                      child: _sticker('heart', 22),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // 顶部的和纸胶带。
        Positioned(
          top: -11,
          left: pw * 0.5 - 54,
          child: Transform.rotate(
            angle: -0.05,
            child: _tape(108, 26, 'dots', const Color(0xFFF4A9A0)),
          ),
        ),
      ],
    );
  }

  /// 拍立得小卡：海边的落日。
  Widget _polaroid() {
    return Container(
      width: 146,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _paperEdge),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33604A30),
            blurRadius: 22,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 106,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFFFE3BC), Color(0xFFBFDDE8)],
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  right: 14,
                  top: 12,
                  child: _sticker('sun', 34),
                ),
                Positioned(
                  left: 12,
                  bottom: 10,
                  child: Opacity(
                    opacity: 0.95,
                    child: _sticker('wave', 44),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '周末的海边',
            style: TextStyle(fontFamily: 'ZCOOL KuaiLe', fontSize: 12.5, color: _ink),
          ),
        ],
      ),
    );
  }

  /// 便利贴：连续记录打卡。
  Widget _stickyNote() {
    return Container(
      width: 112,
      height: 112,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1BF),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFFEBDFA6)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2E604A30),
            blurRadius: 16,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _sticker('heart', 28),
          const SizedBox(height: 6),
          const Text(
            '连续 21 天 ✨',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'LXGW WenKai',
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: _ink,
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------- 功能介绍

  Widget _buildFeatures(ColorScheme scheme, bool wide, double sidePad) {
    final isLight = scheme.brightness == Brightness.light;
    final width = MediaQuery.sizeOf(context).width;
    final cols = width >= 1060 ? 3 : (width >= 620 ? 2 : 1);
    final titleSize = math.max(25.0, math.min(width * 0.045, 32.0));

    // 按 cols 分行，卡片取自然高度、顶对齐。
    // 不能用 IntrinsicHeight + stretch 强制等高：Web 端字体异步加载完成后，
    // 文本度量变化无法穿过紧高度约束的重布局边界，首帧（字体未就绪时）偏矮
    // 的行高会被永久冻结，导致卡片内容溢出一行。
    final rows = <List<_Feature>>[];
    for (var i = 0; i < _featureCards.length; i += cols) {
      rows.add(
        _featureCards.sublist(i, math.min(i + cols, _featureCards.length)),
      );
    }

    return Container(
      key: _featuresKey,
      width: double.infinity,
      color: isLight
          ? Colors.white.withValues(alpha: 0.45)
          : scheme.surfaceContainerLow.withValues(alpha: 0.35),
      padding: EdgeInsets.symmetric(
        horizontal: sidePad,
        vertical: wide ? 84.0 : 60.0,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1160),
          child: Column(
            children: [
              _sectionPill(scheme, '为什么是拾页'),
              const SizedBox(height: 16),
              Text(
                '为每一次记录而设计',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: titleSize,
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '写起来愉快，看起来温暖，翻回来有故事。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'LXGW WenKai',
                  fontSize: 15,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 48),
              for (var r = 0; r < rows.length; r++) ...[
                if (r > 0) const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var c = 0; c < rows[r].length; c++) ...[
                      if (c > 0) const SizedBox(width: 18),
                      Expanded(child: _FeatureCard(feature: rows[r][c])),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionPill(ColorScheme scheme, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
          color: scheme.onPrimaryContainer,
        ),
      ),
    );
  }

  // ----------------------------------------------------------------- 下载

  /// 任一外链经 `--dart-define` 注入时才展示下载区块（本地默认构建隐藏）。
  bool get _hasExternalLinks =>
      kLandingGithubRepoUrl.isNotEmpty ||
      kLandingGithubReleasesUrl.isNotEmpty ||
      kLandingDownloadAndroidUrl.isNotEmpty ||
      kLandingDownloadPcUrl.isNotEmpty;

  Widget _buildDownload(ColorScheme scheme, bool wide, double sidePad) {
    final width = MediaQuery.sizeOf(context).width;
    final titleSize = math.max(25.0, math.min(width * 0.045, 32.0));

    final cards = <Widget>[
      if (kLandingDownloadAndroidUrl.isNotEmpty)
        _downloadCard(
          scheme,
          icon: Icons.smartphone_rounded,
          title: '安卓版',
          subtitle: 'APK 安装包',
          url: kLandingDownloadAndroidUrl,
        ),
      if (kLandingDownloadPcUrl.isNotEmpty)
        _downloadCard(
          scheme,
          icon: Icons.desktop_windows_rounded,
          title: 'Windows 版',
          subtitle: '桌面安装包',
          url: kLandingDownloadPcUrl,
        ),
    ];

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: sidePad,
        vertical: wide ? 84.0 : 60.0,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1160),
          child: Column(
            children: [
              _sectionPill(scheme, '客户端下载'),
              const SizedBox(height: 16),
              Text(
                '把拾页装进你的设备',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: titleSize,
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '安卓与 Windows 客户端同样免费、数据留在本机，'
                '也可以现在就在浏览器里开始记录。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'LXGW WenKai',
                  fontSize: 15,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (cards.isNotEmpty) ...[
                const SizedBox(height: 44),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: cards.length == 2 && width >= 620
                        ? Row(
                            children: [
                              Expanded(child: cards[0]),
                              const SizedBox(width: 18),
                              Expanded(child: cards[1]),
                            ],
                          )
                        : Column(
                            children: [
                              for (var i = 0; i < cards.length; i++) ...[
                                if (i > 0) const SizedBox(height: 18),
                                cards[i],
                              ],
                            ],
                          ),
                  ),
                ),
              ],
              if (kLandingGithubRepoUrl.isNotEmpty ||
                  kLandingGithubReleasesUrl.isNotEmpty) ...[
                const SizedBox(height: 30),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (kLandingGithubRepoUrl.isNotEmpty)
                      TextButton.icon(
                        onPressed: () =>
                            openExternalUrl(kLandingGithubRepoUrl),
                        icon: const Icon(Icons.code_rounded, size: 18),
                        label: const Text('GitHub 仓库'),
                      ),
                    if (kLandingGithubRepoUrl.isNotEmpty &&
                        kLandingGithubReleasesUrl.isNotEmpty)
                      const SizedBox(width: 8),
                    if (kLandingGithubReleasesUrl.isNotEmpty)
                      TextButton.icon(
                        onPressed: () =>
                            openExternalUrl(kLandingGithubReleasesUrl),
                        icon: const Icon(Icons.download_rounded, size: 18),
                        label: const Text('GitHub Releases'),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 平台下载卡片：图标 + 平台名 + 直链下载按钮。
  Widget _downloadCard(
    ColorScheme scheme, {
    required IconData icon,
    required String title,
    required String subtitle,
    required String url,
  }) {
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: scheme.primary, size: 24),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => openExternalUrl(url),
              icon: const Icon(Icons.download_rounded, size: 19),
              label: const Text('直接下载'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 15),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ 页脚

  Widget _buildFooter(ColorScheme scheme) {
    final isLight = scheme.brightness == Brightness.light;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 44),
      child: Column(
        children: [
          _logoBadge(scheme, isLight, 36),
          const SizedBox(height: 12),
          const Text(
            '拾页 PageNote',
            style: TextStyle(
              fontFamily: 'LXGW WenKai',
              fontSize: 16.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '拾起生活中的每一页',
            style: TextStyle(
              fontFamily: 'LXGW WenKai',
              fontSize: 13,
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (kLandingGithubRepoUrl.isNotEmpty ||
              kLandingGithubReleasesUrl.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (kLandingGithubRepoUrl.isNotEmpty)
                  _footerLink(scheme, 'GitHub 仓库', kLandingGithubRepoUrl),
                if (kLandingGithubRepoUrl.isNotEmpty &&
                    kLandingGithubReleasesUrl.isNotEmpty)
                  _footerChipDivider(scheme),
                if (kLandingGithubReleasesUrl.isNotEmpty)
                  _footerLink(
                    scheme,
                    'GitHub Releases',
                    kLandingGithubReleasesUrl,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 18),
          Text(
            'Flutter 构建 · 全部素材程序自绘 · 中文字体遵循 SIL OFL 开源许可',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '© 2026 PageNote',
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  /// 页脚小号文字链接。
  Widget _footerLink(ColorScheme scheme, String label, String url) {
    return TextButton(
      onPressed: () => openExternalUrl(url),
      style: TextButton.styleFrom(
        foregroundColor: scheme.onSurfaceVariant.withValues(alpha: 0.85),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    );
  }

  /// 页脚链接之间的「·」分隔点。
  Widget _footerChipDivider(ColorScheme scheme) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Text(
          '·',
          style: TextStyle(
            fontSize: 12.5,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
          ),
        ),
      );

  // ------------------------------------------------------------- 小组件封装

  /// 入场渐显 + 上浮。
  Widget _reveal(double begin, Widget child) {
    return AnimatedBuilder(
      animation: _intro,
      builder: (context, _) {
        final reduce = MediaQuery.of(context).disableAnimations;
        final t = reduce
            ? 1.0
            : CurvedAnimation(
                parent: _intro,
                curve: Interval(
                  begin,
                  math.min(1.0, begin + 0.55),
                  curve: Curves.easeOutCubic,
                ),
              ).value;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 26),
            child: child,
          ),
        );
      },
    );
  }

  /// 循环漂浮包装。
  Widget _floaty({
    required Widget child,
    double dx = 0,
    double dy = 6,
    double phase = 0,
  }) {
    return AnimatedBuilder(
      animation: _drift,
      builder: (context, _) {
        final v = _drift.value * 2 * math.pi;
        return Transform.translate(
          offset: Offset(
            math.sin(v + phase) * dx,
            math.sin(v + phase * 1.7) * dy,
          ),
          child: child,
        );
      },
    );
  }

  /// 内置矢量贴纸。
  Widget _sticker(String id, double size) =>
      CustomPaint(size: Size.square(size), painter: StickerPainter(id));

  /// 和纸胶带条。
  Widget _tape(double w, double h, String style, Color color) =>
      CustomPaint(size: Size(w, h), painter: TapePainter(style: style, color: color));
}

/// 功能卡片数据。
typedef _Feature = ({
  IconData icon,
  String title,
  String desc,
  Color bg,
  Color fg,
});

const List<_Feature> _featureCards = [
  (
    icon: Icons.draw_rounded,
    title: '画布手账编辑器',
    desc: '文字、照片、贴纸、胶带都是独立图层，自由拖拽、缩放、旋转，所见即所得。',
    bg: Color(0xFFFDEAE3),
    fg: Color(0xFFC4502E),
  ),
  (
    icon: Icons.auto_awesome_motion_rounded,
    title: '海量矢量素材',
    desc: '81 款免抠贴纸 × 132 种和纸胶带，全部程序绘制，任意缩放不模糊、零版权负担。',
    bg: Color(0xFFFDF3D1),
    fg: Color(0xFFA87B18),
  ),
  (
    icon: Icons.dashboard_customize_rounded,
    title: '整页版式模板',
    desc: '12 套模板一键套用，「今日手账」自动填入每日一问；任意手账可另存为模板。',
    bg: Color(0xFFE4F2E4),
    fg: Color(0xFF3E8468),
  ),
  (
    icon: Icons.insights_rounded,
    title: '回顾与统计',
    desc: '月历回看每一天的心情，连续记录天数、字数趋势与写作月报一目了然。',
    bg: Color(0xFFE3EEF8),
    fg: Color(0xFF3F6C9C),
  ),
  (
    icon: Icons.cloud_sync_rounded,
    title: '备份与同步',
    desc: 'WebDAV 自动备份、跨平台导入导出，数据始终保存在你自己的设备与网盘里。',
    bg: Color(0xFFEFE9F8),
    fg: Color(0xFF7B5EA7),
  ),
  (
    icon: Icons.nightlight_round,
    title: '舒适夜间书写',
    desc: '深浅双主题、6 种强调色与 3 款花样字体，深夜的记录也温柔护眼。',
    bg: Color(0xFFFAE8EF),
    fg: Color(0xFFB4576B),
  ),
];

/// 功能卡片：悬停轻微上浮加深阴影。
class _FeatureCard extends StatefulWidget {
  const _FeatureCard({required this.feature});

  final _Feature feature;

  @override
  State<_FeatureCard> createState() => _FeatureCardState();
}

class _FeatureCardState extends State<_FeatureCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final f = widget.feature;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: _hover ? 1.02 : 1,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: _hover
                  ? scheme.primary.withValues(alpha: 0.55)
                  : scheme.outlineVariant.withValues(alpha: 0.5),
            ),
            boxShadow: [
              BoxShadow(
                color: _hover
                    ? scheme.primary.withValues(alpha: dark ? 0.16 : 0.12)
                    : Colors.transparent,
                blurRadius: 26,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: dark ? f.bg.withValues(alpha: 0.16) : f.bg,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(f.icon, color: dark ? f.bg : f.fg, size: 24),
              ),
              const SizedBox(height: 16),
              Text(
                f.title,
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                f.desc,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.7,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 「每一页」背后的马克笔笔触。
class _BrushStroke extends CustomPainter {
  const _BrushStroke({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final h = size.height;
    // 两道略微错位的圆头横笔，模拟手绘马克笔高亮。
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, h * 0.44, size.width, h * 0.42),
        Radius.circular(h * 0.2),
      ),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.03, h * 0.56, size.width * 0.94, h * 0.3),
        Radius.circular(h * 0.15),
      ),
      paint..color = color.withValues(alpha: 0.7),
    );
  }

  @override
  bool shouldRepaint(covariant _BrushStroke oldDelegate) =>
      oldDelegate.color != color;
}

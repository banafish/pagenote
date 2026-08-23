import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/painting.dart';

import 'journal_entry.dart';

/// 手账画布元素类型（REQ-13 完整版：元素树模型）。
enum CanvasElementType { text, image, sticker, tape, component }

/// 照片遮罩（调研一阶段：照片贴纸化）。
enum ImageMask { none, circle, polaroid }

/// 结构化组件种类：既参与自由排版，又继续供统计页使用。
enum ComponentKind { date, mood, weather, activities }

/// 画布元素基类。几何全部以「页宽 = 1」归一化：
/// x/y/w/h 均为页宽倍数，页面高度存于 [JournalCanvas.height]。
/// 这样编辑器、时间线卡片与分享长图可按任意实际宽度无损缩放（WYSIWYG）。
/// z 序即元素列表顺序（末尾在最上层）。
/// sealed：渲染端 switch 可穷尽匹配全部元素类型。
sealed class CanvasElement {
  CanvasElement({
    String? id,
    this.x = 0.5,
    this.y = 0.5,
    this.w = 0.2,
    this.h = 0.2,
    this.rotation = 0,
    this.opacity = 1,
  }) : id = id ?? makeElementId();

  final String id;

  /// 元素左上角（未旋转时）横坐标，单位为页宽倍数。
  double x;

  /// 元素左上角纵坐标，单位为页宽倍数。
  double y;

  /// 元素宽度，单位为页宽倍数。
  double w;

  /// 元素高度，单位为页宽倍数（文本元素为最小高度，实际随内容测量）。
  double h;

  /// 旋转角度（度）。
  double rotation;

  /// 不透明度（0–1）。
  double opacity;

  CanvasElementType get type;

  Map<String, Object?> toMap() => {
    'id': id,
    'x': x,
    'y': y,
    'w': w,
    'h': h,
    'r': rotation,
    'o': opacity,
  };

  Map<String, Object?> typeMap();

  Map<String, Object?> encode() => {...toMap(), 't': type.name, ...typeMap()};

  /// 元素中心点。
  Offset get center => Offset(x + w / 2, y + h / 2);

  /// 按新中心点平移（保持尺寸）。
  void moveTo(Offset newCenter) {
    x = newCenter.dx - w / 2;
    y = newCenter.dy - h / 2;
  }
}

var _elementSeq = 0;

String makeElementId() =>
    'el-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}'
    '-${(_elementSeq++).toRadixString(36)}';

/// 文本框元素：手写体可选、字号/颜色可调（调研一阶段「花样字体」）。
/// [role] 为 'title' / 'body' 时与条目的标题/正文字段同步，'' 为自由文本。
class TextElement extends CanvasElement {
  TextElement({
    super.id,
    super.x,
    super.y,
    super.w = 0.86,
    super.h = 0.2,
    super.rotation,
    super.opacity,
    this.text = '',
    this.fontScale = 0.04,
    this.color = 0xFF4A3F35,
    this.fontFamily = '',
    this.align = 0,
    this.bold = false,
    this.role = '',
    this.lineHeight = 1.7,
  });

  String text;

  /// 字号（页宽倍数；0.04 ≈ 16px @ 400 宽）。
  double fontScale;

  /// 文字颜色（0xAARRGGBB）。
  int color;

  /// 字体族名，空串为应用默认；可选值见 models/app_fonts.dart。
  String fontFamily;

  /// 对齐：0 左 / 1 中 / 2 右。
  int align;

  bool bold;

  /// title / body / ''（自由文本）。
  String role;

  double lineHeight;

  @override
  CanvasElementType get type => CanvasElementType.text;

  @override
  Map<String, Object?> typeMap() => {
    'text': text,
    'fs': fontScale,
    'c': color,
    'f': fontFamily,
    'a': align,
    'b': bold ? 1 : 0,
    'role': role,
    'lh': lineHeight,
  };

  static TextElement fromMap(Map<String, Object?> map) => TextElement(
    id: map['id'] as String?,
    x: _d(map['x'], 0.5),
    y: _d(map['y'], 0.5),
    w: _d(map['w'], 0.86),
    h: _d(map['h'], 0.2),
    rotation: _d(map['r'], 0),
    opacity: _d(map['o'], 1),
    text: (map['text'] ?? '') as String,
    fontScale: _d(map['fs'], 0.04),
    color: _i(map['c'], 0xFF4A3F35),
    fontFamily: (map['f'] ?? '') as String,
    align: _i(map['a'], 0).clamp(0, 2),
    bold: _i(map['b'], 0) == 1,
    role: (map['role'] ?? '') as String,
    lineHeight: _d(map['lh'], 1.7),
  );
}

/// 图片元素：相册照片贴纸化（调研一阶段），支持圆形 / 拍立得遮罩。
/// path 为空串时渲染为「添加照片」占位框（旅行等整页模板用）。
class ImageElement extends CanvasElement {
  ImageElement({
    super.id,
    super.x,
    super.y,
    super.w = 0.4,
    super.h = 0.3,
    super.rotation,
    super.opacity,
    this.path = '',
    this.mask = ImageMask.none,
    this.radius = 0.03,
  });

  String path;
  ImageMask mask;

  /// 圆角半径（页宽倍数，仅 [ImageMask.none] 生效）。
  double radius;

  @override
  CanvasElementType get type => CanvasElementType.image;

  @override
  Map<String, Object?> typeMap() => {'p': path, 'm': mask.name, 'rad': radius};

  static ImageElement fromMap(Map<String, Object?> map) => ImageElement(
    id: map['id'] as String?,
    x: _d(map['x'], 0.5),
    y: _d(map['y'], 0.5),
    w: _d(map['w'], 0.4),
    h: _d(map['h'], 0.3),
    rotation: _d(map['r'], 0),
    opacity: _d(map['o'], 1),
    path: (map['p'] ?? '') as String,
    mask: switch (map['m']) {
      'circle' => ImageMask.circle,
      'polaroid' => ImageMask.polaroid,
      _ => ImageMask.none,
    },
    radius: _d(map['rad'], 0.03),
  );
}

/// 贴纸元素：key 为 `vec:<id>`（内置矢量贴纸）、`emoji:<字符>`
/// 或 `img:<sha1>`（自定义图片贴纸，REQ-20）。
class StickerElement extends CanvasElement {
  StickerElement({
    super.id,
    super.x,
    super.y,
    super.w = 0.16,
    super.h = 0.16,
    super.rotation,
    super.opacity,
    required this.key,
    this.tint,
  });

  String key;

  /// 矢量贴纸的换色色调（0xAARRGGBB，REQ-19）；
  /// null 为素材原配色 —— 存量数据无该字段时不出现视觉突变。
  int? tint;

  @override
  CanvasElementType get type => CanvasElementType.sticker;

  @override
  Map<String, Object?> typeMap() => {'k': key, if (tint != null) 'tc': tint};

  static StickerElement fromMap(Map<String, Object?> map) => StickerElement(
    id: map['id'] as String?,
    x: _d(map['x'], 0.5),
    y: _d(map['y'], 0.5),
    w: _d(map['w'], 0.16),
    h: _d(map['h'], 0.16),
    rotation: _d(map['r'], 0),
    opacity: _d(map['o'], 1),
    key: (map['k'] ?? 'emoji:⭐️') as String,
    tint: map['tc'] == null ? null : _i(map['tc'], 0),
  );
}

/// 胶带元素：半透明和纸胶带（调研一阶段素材体系）。
class TapeElement extends CanvasElement {
  TapeElement({
    super.id,
    super.x,
    super.y,
    super.w = 0.3,
    super.h = 0.09,
    super.rotation = -8,
    super.opacity = 1,
    this.style = 'stripes',
    this.color = 0xFFF4A9A0,
  });

  /// 纹样 id，见 models/sticker_assets.dart 的 tapeStyles。
  String style;

  /// 胶带底色（0xAARRGGBB）。
  int color;

  @override
  CanvasElementType get type => CanvasElementType.tape;

  @override
  Map<String, Object?> typeMap() => {'st': style, 'c': color};

  static TapeElement fromMap(Map<String, Object?> map) => TapeElement(
    id: map['id'] as String?,
    x: _d(map['x'], 0.5),
    y: _d(map['y'], 0.5),
    w: _d(map['w'], 0.3),
    h: _d(map['h'], 0.09),
    rotation: _d(map['r'], -8),
    opacity: _d(map['o'], 1),
    style: (map['st'] ?? 'stripes') as String,
    color: _i(map['c'], 0xFFF4A9A0),
  );
}

/// 结构化组件元素：日期/心情/天气/活动。数据始终来自条目结构化字段
/// （mood/weather/activities/date），组件只负责在画布上排版展示，
/// 因此统计页照常可用（「既好看又能统计」的差异化定位）。
class StructuredElement extends CanvasElement {
  StructuredElement({
    super.id,
    super.x,
    super.y,
    super.w = 0.4,
    super.h = 0.12,
    super.rotation,
    super.opacity,
    required this.kind,
  });

  final ComponentKind kind;

  @override
  CanvasElementType get type => CanvasElementType.component;

  @override
  Map<String, Object?> typeMap() => {'ck': kind.name};

  static StructuredElement fromMap(Map<String, Object?> map) =>
      StructuredElement(
        id: map['id'] as String?,
        x: _d(map['x'], 0.5),
        y: _d(map['y'], 0.5),
        w: _d(map['w'], 0.4),
        h: _d(map['h'], 0.12),
        rotation: _d(map['r'], 0),
        opacity: _d(map['o'], 1),
        kind: switch (map['ck']) {
          'mood' => ComponentKind.mood,
          'weather' => ComponentKind.weather,
          'activities' => ComponentKind.activities,
          _ => ComponentKind.date,
        },
      );
}

/// 画布高度下限（页宽倍数）：16:9 横版（9/16 ≈ 0.5625）再留余量。
const canvasMinHeight = 0.5;

/// 一页手账画布：背景纸张 + 元素列表（调研三阶段元素树）。
class JournalCanvas {
  JournalCanvas({
    String? id,
    this.paperId = 'plain',
    this.height = 4 / 3,
    List<CanvasElement>? elements,
  }) : id = id ?? makeElementId().replaceFirst('el-', 'cv'),
       elements = elements ?? [];

  final String id;

  /// 背景纸张 id（models/decoration.dart），空串为不装饰。
  String paperId;

  /// 页面高度（页宽倍数）。默认 4/3 即 3:4 竖版；
  /// 小于 1 为横版（4:3 横版 = 3/4，16:9 横版 = 9/16），平板与桌面可建横屏手账。
  double height;

  /// 元素列表，顺序即 z 序（末尾在最上层）。
  List<CanvasElement> elements;

  /// 实际渲染高度：至少容纳全部元素底边（文本元素按内容测量）。
  double get effectiveHeight {
    var bottom = height;
    for (final e in elements) {
      var eh = e.h;
      if (e is TextElement) eh = math.max(e.h, measureTextHeight(e));
      bottom = math.max(bottom, e.y + eh + 0.06);
    }
    return bottom.clamp(canvasMinHeight, 6);
  }

  Iterable<TextElement> get texts => elements.whereType<TextElement>();

  TextElement? firstOfRole(String role) =>
      texts.where((t) => t.role == role).firstOrNull;

  Iterable<ImageElement> get images => elements.whereType<ImageElement>();

  Iterable<StickerElement> get stickers => elements.whereType<StickerElement>();

  /// 画布引用到的全部贴纸 key（引用完整性校验用，FIX-03 / REQ-21）。
  Set<String> get stickerKeys => {for (final s in stickers) s.key};

  Iterable<StructuredElement> get components =>
      elements.whereType<StructuredElement>();

  StructuredElement? componentOf(ComponentKind kind) =>
      components.where((c) => c.kind == kind).firstOrNull;

  Map<String, Object?> toMap() => {
    'id': id,
    'paper': paperId,
    'h': height,
    'elements': [for (final e in elements) e.encode()],
  };

  static JournalCanvas fromMap(Map<String, Object?> map) {
    final canvas = JournalCanvas(
      id: map['id'] as String?,
      paperId: (map['paper'] ?? 'plain') as String,
      height: _d(map['h'], 4 / 3).clamp(canvasMinHeight, 6),
    );
    for (final raw in (map['elements'] as List? ?? [])) {
      if (raw is! Map) continue;
      final m = raw.cast<String, Object?>();
      final element = switch (m['t']) {
        'text' => TextElement.fromMap(m),
        'image' => ImageElement.fromMap(m),
        'sticker' => StickerElement.fromMap(m),
        'tape' => TapeElement.fromMap(m),
        'component' => StructuredElement.fromMap(m),
        _ => null,
      };
      if (element != null) canvas.elements.add(element);
    }
    return canvas;
  }

  JournalCanvas clone() => JournalCanvas.fromMap(toMap());

  /// 调整画布高度以容纳全部内容（正文增长时页面自动变长）。
  void fitHeight() {
    height = effectiveHeight;
  }

  /// 切换画布比例（竖版 ↔ 方形 ↔ 横版）：元素纵坐标按新旧高度等比重排,
  /// 版面相对位置不变、内容仍在页内;重排后仍放不下的（如超高文本）
  /// 由 [fitHeight] 兜底把页面拉长。宽度方向的坐标全部不变。
  void reshape(double newHeight) {
    final target = newHeight.clamp(canvasMinHeight, 6).toDouble();
    final k = target / height;
    for (final e in elements) {
      e.y *= k;
    }
    height = target;
  }

  /// 把图片元素路径按 basename 重映射（备份导入后附件路径变化）。
  void remapImagePaths(String Function(String path) convert) {
    for (final e in elements) {
      if (e is ImageElement && e.path.isNotEmpty) e.path = convert(e.path);
    }
  }

  /// 清空全部照片路径，只留占位框（FIX-01.1）。
  /// 「另存为模板」默认走这里：模板的语义就是让使用者填自己的照片，
  /// 同时避免把本机绝对路径（含用户名）写进模板与分享包。
  void clearImagePaths() {
    for (final e in elements) {
      if (e is ImageElement) e.path = '';
    }
  }

  /// 画布内是否含本机绝对路径（导出前自检，REQ-21.4）。
  bool get hasImagePaths => images.any((e) => e.path.isNotEmpty);
}

/// 序列化到 entries.canvas 列；空画布存空串。
String encodeCanvas(JournalCanvas? canvas) =>
    canvas == null ? '' : jsonEncode(canvas.toMap());

/// 反序列化：损坏数据返回 null（条目仍可打开，退回表单视图数据）。
JournalCanvas? decodeCanvas(String raw) {
  if (raw.trim().isEmpty) return null;
  try {
    return JournalCanvas.fromMap(
      (jsonDecode(raw) as Map).cast<String, Object?>(),
    );
  } catch (_) {
    return null;
  }
}

/// 文本测量基准宽度（px）：归一化字号/宽度 × 400 得到像素值。
const canvasMeasureWidth = 400.0;

/// 测量文本元素的内容高度（页宽倍数），与渲染端参数一致。
double measureTextHeight(TextElement e) {
  final painter = TextPainter(
    text: TextSpan(
      text: e.text,
      style: TextStyle(
        fontSize: e.fontScale * canvasMeasureWidth,
        fontFamily: e.fontFamily.isEmpty ? null : e.fontFamily,
        fontFamilyFallback: e.fontFamily.isEmpty
            ? null
            : const [
                'Microsoft YaHei UI',
                'Microsoft YaHei',
                'PingFang SC',
                'Noto Sans SC',
                'sans-serif',
              ],
        fontWeight: e.bold ? FontWeight.w700 : FontWeight.w400,
        height: e.lineHeight,
      ),
    ),
    textAlign: switch (e.align) { 1 => TextAlign.center, 2 => TextAlign.right, _ => TextAlign.left },
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: e.w * canvasMeasureWidth);
  final h = painter.height / canvasMeasureWidth;
  painter.dispose();
  return h;
}

/// 为旧数据（无 canvas 列）自动合成等价画布（调研三阶段数据迁移）：
/// 日期/心情/天气组件 + 标题文本框 + 正文文本框 + 图片网格 + 旧贴纸。
/// 非破坏性：旧字段不动，编辑保存后 canvas 才成为版面事实源。
JournalCanvas synthesizeCanvas(JournalEntry entry) {
  final canvas = JournalCanvas(paperId: entry.paper.isEmpty ? 'plain' : entry.paper);

  void place(CanvasElement e) => canvas.elements.add(e);

  place(
    StructuredElement(
      kind: ComponentKind.date,
      x: 0.08,
      y: 0.05,
      w: 0.5,
      h: 0.12,
    ),
  );
  if (entry.mood != null) {
    place(
      StructuredElement(
        kind: ComponentKind.mood,
        x: 0.62,
        y: 0.04,
        w: 0.3,
        h: 0.14,
      ),
    );
  }
  if (entry.weather != null) {
    place(
      StructuredElement(
        kind: ComponentKind.weather,
        x: 0.62,
        y: 0.16,
        w: 0.3,
        h: 0.1,
      ),
    );
  }

  var cursor = 0.22;
  // 标题与正文始终放置文本框（空内容时作为可点击的占位输入位）。
  final titleEl = TextElement(
    x: 0.08,
    y: cursor,
    w: 0.84,
    text: entry.title.trim(),
    fontScale: 0.052,
    bold: true,
    role: 'title',
    lineHeight: 1.5,
  );
  titleEl.h = measureTextHeight(titleEl).clamp(0.05, 1);
  place(titleEl);
  cursor += titleEl.h + 0.05;
  final bodyEl = TextElement(
    x: 0.08,
    y: cursor,
    w: 0.84,
    text: entry.content,
    fontScale: 0.038,
    role: 'body',
  );
  bodyEl.h = measureTextHeight(bodyEl).clamp(0.05, 4);
  place(bodyEl);
  cursor += bodyEl.h + 0.06;

  // 照片：两列网格摆放。
  if (entry.images.isNotEmpty) {
    var row = 0;
    for (var i = 0; i < entry.images.length; i += 2) {
      for (var col = 0; col < 2 && i + col < entry.images.length; col++) {
        place(
          ImageElement(
            path: entry.images[i + col],
            x: 0.08 + col * 0.45,
            y: cursor + row * 0.36,
            w: 0.39,
            h: 0.3,
          ),
        );
      }
      row++;
    }
    cursor += row * 0.36 + 0.04;
  }

  if (entry.activities.isNotEmpty) {
    place(
      StructuredElement(
        kind: ComponentKind.activities,
        x: 0.08,
        y: math.max(cursor, 4 / 3 - 0.18),
        w: 0.84,
        h: 0.12,
      ),
    );
    cursor = math.max(cursor, 4 / 3 - 0.18) + 0.14;
  }

  // 旧贴纸（emoji + 归一化位置）→ 贴纸元素。
  for (final s in entry.stickers) {
    place(
      StickerElement(
        key: 'emoji:${s.emoji}',
        x: (s.dx - 0.08).clamp(0.0, 0.9),
        y: s.dy * 4 / 3,
        w: 0.16 * s.scale,
        h: 0.16 * s.scale,
        rotation: s.rotation,
      ),
    );
  }

  canvas.height = canvas.effectiveHeight;
  return canvas;
}

double _d(Object? v, double fallback) =>
    v is num ? v.toDouble() : (v is String ? double.tryParse(v) ?? fallback : fallback);

int _i(Object? v, int fallback) =>
    v is num ? v.toInt() : (v is String ? int.tryParse(v) ?? fallback : fallback);

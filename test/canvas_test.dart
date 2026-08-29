import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:pagenote/models/app_fonts.dart';
import 'package:pagenote/models/canvas_page.dart';
import 'package:pagenote/models/decoration.dart';
import 'package:pagenote/models/journal_entry.dart';
import 'package:pagenote/models/mood.dart';
import 'package:pagenote/models/sticker_assets.dart';
import 'package:pagenote/models/template.dart';

void main() {
  group('画布元素树模型（调研三阶段）', () {
    test('各类元素序列化往返保留全部属性', () {
      final canvas = JournalCanvas(
        paperId: 'sakura',
        height: 1.5,
        elements: [
          TextElement(
            x: 0.1,
            y: 0.2,
            w: 0.8,
            text: '标题',
            fontScale: 0.05,
            color: 0xFF3B3B3B,
            fontFamily: 'LXGW WenKai',
            align: 1,
            bold: true,
            role: 'title',
            lineHeight: 1.6,
          ),
          TextElement(x: 0.1, y: 0.4, text: '正文', rotation: -15, opacity: 0.6),
          ImageElement(
            path: '/tmp/a.jpg',
            x: 0.2,
            y: 0.6,
            mask: ImageMask.polaroid,
            radius: 0.05,
          ),
          ImageElement(path: '', mask: ImageMask.circle),
          StickerElement(key: 'vec:cat', w: 0.3, h: 0.3, rotation: 30),
          StickerElement(key: 'emoji:🌸'),
          TapeElement(style: 'dots', color: 0xFF9CCB8B, rotation: -25),
          StructuredElement(kind: ComponentKind.mood, x: 0.6, y: 0.05),
        ],
      );

      final restored = decodeCanvas(encodeCanvas(canvas))!;
      expect(restored.paperId, 'sakura');
      expect(restored.height, 1.5);

      final title = restored.elements.whereType<TextElement>().first;
      expect(title.text, '标题');
      expect(title.fontFamily, 'LXGW WenKai');
      expect(title.align, 1);
      expect(title.bold, isTrue);
      expect(title.role, 'title');
      expect(title.lineHeight, 1.6);

      final freeText = restored.elements.whereType<TextElement>().last;
      expect(freeText.rotation, -15);
      expect(freeText.opacity, 0.6);

      final polaroid = restored.elements.whereType<ImageElement>().first;
      expect(polaroid.path, '/tmp/a.jpg');
      expect(polaroid.mask, ImageMask.polaroid);
      expect(polaroid.radius, 0.05);
      final circle = restored.elements.whereType<ImageElement>().last;
      expect(circle.mask, ImageMask.circle);

      final sticker = restored.elements.whereType<StickerElement>().first;
      expect(sticker.key, 'vec:cat');
      expect(sticker.rotation, 30);

      final tape = restored.elements.whereType<TapeElement>().single;
      expect(tape.style, 'dots');
      expect(tape.color, 0xFF9CCB8B);

      final mood = restored.elements.whereType<StructuredElement>().single;
      expect(mood.kind, ComponentKind.mood);
    });

    test('decodeCanvas 对空串与损坏数据安全退化', () {
      expect(decodeCanvas(''), isNull);
      expect(decodeCanvas('   '), isNull);
      expect(decodeCanvas('not json'), isNull);
      expect(
        decodeCanvas('{"paper":"x","elements":[{"t":"bogus"}]}'),
        isNotNull,
        reason: '未知元素类型被跳过,画布仍可解析',
      );
      expect(
        decodeCanvas('{"paper":"x","elements":[{"t":"bogus"}]}')!.elements,
        isEmpty,
      );
    });

    test('条目 canvas 列随 toMap/fromMap 往返', () {
      final now = DateTime(2026, 8, 17);
      final entry = JournalEntry(
        id: 'c1',
        date: '2026-08-17',
        title: 't',
        content: 'c',
        canvas: JournalCanvas(
          paperId: 'mist',
          elements: [TextElement(text: 'hello', role: 'body')],
        ),
        createdAt: now,
        updatedAt: now,
      );
      final restored = JournalEntry.fromMap(entry.toMap());
      expect(restored.canvas, isNotNull);
      expect(restored.canvas!.paperId, 'mist');
      expect(restored.canvas!.firstOfRole('body')!.text, 'hello');
    });

    test('旧数据合成等价画布（调研三阶段数据迁移）', () {
      final now = DateTime(2026, 8, 17);
      final entry = JournalEntry(
        id: 'old1',
        date: '2026-08-17',
        title: '旧标题',
        content: '旧正文',
        mood: Mood.happy,
        weather: Weather.sunny,
        activities: ['运动', '阅读'],
        paper: 'stars',
        stickers: [Sticker(emoji: '🌙', dx: 0.8, dy: 0.2, rotation: 15)],
        images: ['/tmp/1.jpg', '/tmp/2.jpg'],
        createdAt: now,
        updatedAt: now,
      );

      final canvas = synthesizeCanvas(entry);
      // 结构化组件：日期 + 心情 + 天气 + 活动。
      expect(canvas.componentOf(ComponentKind.date), isNotNull);
      expect(canvas.componentOf(ComponentKind.mood), isNotNull);
      expect(canvas.componentOf(ComponentKind.weather), isNotNull);
      expect(canvas.componentOf(ComponentKind.activities), isNotNull);
      // 文本框同步标题与正文。
      expect(canvas.firstOfRole('title')!.text, '旧标题');
      expect(canvas.firstOfRole('body')!.text, '旧正文');
      // 图片成为可摆放元素。
      expect(canvas.images.length, 2);
      expect(canvas.images.first.path, '/tmp/1.jpg');
      // 旧贴纸转贴纸元素。
      final sticker = canvas.elements.whereType<StickerElement>().single;
      expect(sticker.key, 'emoji:🌙');
      expect(sticker.rotation, 15);
      // 纸张沿用。
      expect(canvas.paperId, 'stars');
    });

    test('无活动旧数据不合成活动组件', () {
      final now = DateTime(2026, 8, 17);
      final entry = JournalEntry(
        id: 'old2',
        date: '2026-08-17',
        title: '',
        content: '只有正文',
        createdAt: now,
        updatedAt: now,
      );
      final canvas = synthesizeCanvas(entry);
      expect(canvas.componentOf(ComponentKind.activities), isNull);
      // 标题/正文占位始终存在（空标题也有可点击输入位）。
      expect(canvas.firstOfRole('title')!.text, '');
      expect(canvas.firstOfRole('body')!.text, '只有正文');
    });

    test('effectiveHeight 至少容纳全部元素底边且在合理区间', () {
      final canvas = JournalCanvas(
        height: 4 / 3,
        elements: [StickerElement(key: 'vec:star', y: 2.0, w: 0.2, h: 0.2)],
      );
      expect(canvas.effectiveHeight, greaterThanOrEqualTo(2.2 + 0.06 - 1e-9));
      expect(canvas.effectiveHeight, lessThanOrEqualTo(6));
    });

    test('横版画布：高度可小于 1 并序列化往返（平板/电脑横屏手账）', () {
      final canvas = JournalCanvas(
        height: 9 / 16,
        elements: [StickerElement(key: 'vec:star', x: 0.1, y: 0.1)],
      );
      expect(canvas.height, closeTo(9 / 16, 1e-9));
      expect(
        canvas.effectiveHeight,
        closeTo(9 / 16, 1e-9),
        reason: '元素不出界时保持横版高度',
      );
      final restored = decodeCanvas(encodeCanvas(canvas))!;
      expect(restored.height, closeTo(9 / 16, 1e-9));
    });

    test('effectiveHeight 下限放宽到 canvasMinHeight（16:9 横版可容纳）', () {
      final canvas = JournalCanvas(height: 0.2);
      expect(canvas.effectiveHeight, closeTo(canvasMinHeight, 1e-9));
      // 反序列化同样按新下限钳制。
      final restored = JournalCanvas.fromMap({'h': 0.1, 'elements': []});
      expect(restored.height, closeTo(canvasMinHeight, 1e-9));
    });

    test('reshape 切比例：元素纵坐标按新旧高度等比重排,宽度不动', () {
      final canvas = JournalCanvas(
        height: 4 / 3,
        elements: [
          StickerElement(key: 'vec:star', x: 0.2, y: 0.6, w: 0.2, h: 0.2),
          ImageElement(path: '/tmp/a.jpg', x: 0.5, y: 1.0),
        ],
      );
      canvas.reshape(9 / 16);
      final k = (9 / 16) / (4 / 3);
      expect(canvas.height, closeTo(9 / 16, 1e-9));
      final sticker = canvas.elements.whereType<StickerElement>().single;
      expect(sticker.x, 0.2, reason: '横向坐标不动');
      expect(sticker.y, closeTo(0.6 * k, 1e-9));
      final image = canvas.elements.whereType<ImageElement>().single;
      expect(image.y, closeTo(1.0 * k, 1e-9));
      // 高度钳制下限。
      canvas.reshape(0.1);
      expect(canvas.height, closeTo(canvasMinHeight, 1e-9));
    });

    test('remapImagePaths 按回调重映射画布图片', () {
      final canvas = JournalCanvas(
        elements: [
          ImageElement(path: '/old/dir/a.jpg'),
          StickerElement(key: 'vec:star'),
        ],
      );
      canvas.remapImagePaths((p) => p.replaceFirst('/old/dir', '/new/dir'));
      expect(canvas.images.single.path, '/new/dir/a.jpg');
    });
  });

  group('素材库（调研一阶段）', () {
    test('矢量贴纸 ≥30 款,id 唯一且按 4 分类组织', () {
      expect(vectorStickers.length, greaterThanOrEqualTo(30));
      final ids = vectorStickers.map((s) => s.id).toSet();
      expect(ids.length, vectorStickers.length, reason: 'id 不重复');
      for (final category in stickerCategories) {
        expect(
          vectorStickers.where((s) => s.category == category).length,
          greaterThanOrEqualTo(6),
          reason: '分类「$category」至少 6 款',
        );
      }
      expect(stickerById('cat')!.name, '猫咪');
      expect(stickerById('bogus'), isNull);
    });

    test('全部贴纸与胶带样式均可绘制（不抛异常）', () {
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      for (final sticker in vectorStickers) {
        StickerPainter(sticker.id).paint(canvas, const Size(48, 48));
      }
      for (final style in tapeStyles) {
        for (final color in tapePalette) {
          TapePainter(
            style: style.id,
            color: Color(color),
          ).paint(canvas, const Size(96, 28));
        }
      }
      recorder.endRecording().dispose();
    });

    test('胶带纹样与色板非空', () {
      expect(tapeStyles.length, greaterThanOrEqualTo(6));
      expect(tapePalette.length, greaterThanOrEqualTo(6));
      expect(tapeStyleById('dots')!.name, '波点');
    });

    test('纸张含纹理/纯色/渐变三族（调研一阶段第 4 条）', () {
      expect(
        paperStyles.where((p) => p.kind == PaperKind.texture).length,
        greaterThanOrEqualTo(9),
      );
      expect(
        paperStyles.where((p) => p.kind == PaperKind.solid).length,
        greaterThanOrEqualTo(8),
      );
      expect(
        paperStyles.where((p) => p.kind == PaperKind.gradient).length,
        greaterThanOrEqualTo(5),
      );
      for (final paper in paperStyles.where(
        (p) => p.kind == PaperKind.gradient,
      )) {
        expect(paper.end, isNotNull, reason: '渐变纸必须有终止色');
      }
      // 渐变纸浅/深模式都可解析出底色与终止色。
      final mist = paperById('mist')!;
      expect(resolvePaperBase(mist), mist.base);
      expect(resolvePaperEnd(mist), isNotNull);
      expect(resolvePaperEnd(mist, dark: true)!, isNot(mist.end));
    });

    test('花样字体注册表：10 款开源中文字体（NFR-08：family 只增不删）', () {
      final custom = appFonts.where((f) => f.family.isNotEmpty).toList();
      expect(custom, hasLength(10));
      // 已随历史版本分发的 family 不得重命名或删除（素材与模板管理需求 NFR-08）。
      final families = custom.map((f) => f.family).toList();
      expect(
        families,
        containsAll([
          'LXGW WenKai',
          'Ma Shan Zheng',
          'ZCOOL KuaiLe',
          'ZCOOL XiaoWei',
          'ZCOOL QingKe HuangYou',
          'Long Cang',
          'Zhi Mang Xing',
          'Liu Jian Mao Cao',
          'Smiley Sans',
          'Zhuque Fangsong',
        ]),
      );
      expect(
        families.toSet(),
        hasLength(families.length),
        reason: 'family 不得重复',
      );
      expect(fontByFamily('LXGW WenKai')!.name, '霞鹜文楷');
      expect(fontByFamily('Smiley Sans')!.name, '得意黑');
      expect(fontByFamily(''), isNull, reason: '空串表示应用默认字体');
      expect(canvasFontFallback, isNotEmpty);
      // 每款自定义字体都应指向真实存在的字体文件（与 pubspec 一致）。
      for (final font in custom) {
        expect(
          font.asset,
          endsWith('.ttf'),
          reason: '${font.family} 的 asset 路径异常',
        );
        expect(
          File(font.asset).existsSync(),
          isTrue,
          reason: '缺少字体文件 ${font.asset}',
        );
      }
      // web 急加载名单必须是注册表的子集。
      final all = families.toSet();
      expect(webEagerFontFamilies.every(all.contains), isTrue);
    });
  });

  group('整页版式模板（调研二阶段）', () {
    test('内置模板 ≥6 套且每套含整页画布版式', () {
      expect(builtinTemplates.length, greaterThanOrEqualTo(6));
      for (final template in builtinTemplates) {
        expect(template.canvas, isNotNull, reason: '「${template.name}」应有版式');
        expect(template.canvas!.elements, isNotEmpty);
        expect(template.canvas!.paperId, isNotEmpty);
      }
    });

    test('今日手账模板：日期/心情/天气组件 + 空标题正文占位', () {
      final today = builtinTemplates
          .where((t) => t.id == 'builtin-today')
          .single;
      expect(today.isTodayTemplate, isTrue);
      final canvas = today.canvas!;
      expect(canvas.componentOf(ComponentKind.date), isNotNull);
      expect(canvas.componentOf(ComponentKind.mood), isNotNull);
      expect(canvas.componentOf(ComponentKind.weather), isNotNull);
      expect(canvas.firstOfRole('title')!.text, isEmpty);
      expect(canvas.firstOfRole('body')!.text, isEmpty);
    });

    test('模板 toMap/fromMap 往返保留画布版式', () {
      final template = builtinTemplates.first;
      final restored = JournalTemplate.fromMap(template.toMap());
      expect(restored.canvas, isNotNull);
      expect(restored.canvas!.paperId, template.canvas!.paperId);
      expect(
        restored.canvas!.elements.length,
        template.canvas!.elements.length,
      );
    });
  });
}

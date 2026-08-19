import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pagenote/models/app_fonts.dart';
import 'package:pagenote/models/canvas_page.dart';
import 'package:pagenote/models/decoration.dart';
import 'package:pagenote/models/journal_entry.dart';
import 'package:pagenote/models/sticker_assets.dart';
import 'package:pagenote/models/template.dart';
import 'package:pagenote/providers/template_provider.dart';
import 'package:pagenote/widgets/canvas/canvas_view.dart';

/// FIX-03：未知素材 id 不再静默回退为星星。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const unknownKey = 'vec:__no_such_sticker__';
  const unknownCanvasJson =
      '{"paper":"plain","elements":['
      '{"t":"sticker","k":"$unknownKey","x":0.1,"y":0.1,"w":0.2,"h":0.2}]}';

  /// 把贴纸画到离屏位图，取原始像素字节。
  Future<Uint8List> renderSticker(String id) async {
    final recorder = ui.PictureRecorder();
    StickerPainter(id).paint(ui.Canvas(recorder), const Size(64, 64));
    final picture = recorder.endRecording();
    final image = await picture.toImage(64, 64);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    picture.dispose();
    image.dispose();
    return data!.buffer.asUint8List();
  }

  group('未知贴纸 id 的解码与校验（FIX-03）', () {
    test('含未知 key 的画布正常解码,且 key 原样保留', () {
      final canvas = decodeCanvas(unknownCanvasJson);
      expect(canvas, isNotNull);
      final sticker = canvas!.stickers.single;
      expect(sticker.key, unknownKey, reason: '不得被悄悄改写成星星');
      expect(canvas.stickerKeys, contains(unknownKey));
    });

    test('isKnownStickerKey 区分本机可渲染与缺失', () {
      expect(isKnownStickerKey(unknownKey), isFalse);
      expect(isKnownStickerKey('vec:star'), isTrue);
      expect(isKnownStickerKey('emoji:🌸'), isTrue, reason: 'emoji 由系统字体兜底');
      expect(isKnownStickerKey('emoji:🍰'), isTrue);
      expect(isKnownStickerKey('img:${'a' * 40}'), isFalse, reason: '本机无此自定义贴纸');
    });

    test('stickerKeyLabel 对三类 key 都给出可读名称', () {
      expect(stickerKeyLabel('vec:cat'), '猫咪');
      expect(stickerKeyLabel(unknownKey), contains('矢量贴纸'));
      expect(stickerKeyLabel('emoji:🌸'), '🌸');
      expect(stickerKeyLabel('img:${'a' * 40}'), contains('自定义贴纸'));
    });
  });

  group('未知贴纸 id 的渲染（FIX-03.2）', () {
    test('缺失占位与星星的渲染结果不同', () async {
      final missing = await renderSticker('__no_such__');
      final star = await renderSticker('star');
      expect(missing.length, star.length);
      expect(missing, isNot(equals(star)), reason: '缺失占位不得伪装成星星');
    });

    testWidgets('含未知 key 的画布渲染不崩溃', (tester) async {
      final canvas = decodeCanvas(unknownCanvasJson)!;
      final now = DateTime(2026, 8, 19);
      final entry = JournalEntry(
        id: 'fix03',
        date: '2026-08-19',
        title: '',
        content: '',
        createdAt: now,
        updatedAt: now,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              child: SingleChildScrollView(
                child: CanvasView(canvas: canvas, entry: entry),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CanvasView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('引用完整性校验（FIX-03.1）', () {
    test('缺失贴纸/纸张/字体各计一项,清单可读', () {
      final template = JournalTemplate(
        id: 'miss1',
        name: '缺素材模板',
        canvas: JournalCanvas(
          paperId: '__no_such_paper__',
          elements: [
            StickerElement(key: unknownKey),
            TextElement(text: '标题', fontFamily: '__no_such_font__'),
          ],
        ),
      );

      final report = checkMissingAssets(
        [template],
        hasPaper: (id) => paperById(id) != null,
        hasFont: (family) => fontByFamily(family) != null,
      );

      expect(report.isEmpty, isFalse);
      expect(report.count, 3);
      expect(report.stickerKeys, {unknownKey});
      expect(report.paperIds, {'__no_such_paper__'});
      expect(report.fontFamilies, {'__no_such_font__'});

      final labels = report.labels;
      expect(labels.length, 3);
      for (final label in labels) {
        expect(label, matches(RegExp(r'[一-龥]')), reason: '「$label」应为中文可读');
      }
    });

    test('素材齐全的内置模板无缺失项', () {
      final report = checkMissingAssets(
        builtinTemplates,
        hasPaper: (id) => paperById(id) != null,
        hasFont: (family) => fontByFamily(family) != null,
      );
      expect(report.isEmpty, isTrue);
      expect(report.count, 0);
    });
  });
}

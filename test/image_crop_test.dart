import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:pagenote/widgets/canvas/image_crop_dialog.dart';

void main() {
  late Directory tmp;

  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('pagenote_crop_test');
  });

  tearDownAll(() {
    tmp.deleteSync(recursive: true);
  });

  /// 造一张确定尺寸的临时照片。
  File makePhoto(String name, int width, int height) {
    final image = img.Image(width: width, height: height);
    img.fill(image, color: img.ColorRgb8(180, 60, 60));
    final file = File('${tmp.path}${Platform.pathSeparator}$name');
    file.writeAsBytesSync(img.encodePng(image));
    return file;
  }

  testWidgets('默认整图原比例;「使用原图」按真实尺寸返回', (tester) async {
    final photo = makePhoto('a.png', 400, 200);
    CroppedImage? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showImageCropDialog(context, photo.path);
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('使用原图'), findsOneWidget);
    // 裁剪框默认即整张原图:尺寸行显示 400 × 200 / 400 × 200。
    expect(find.text('400 × 200 / 400 × 200'), findsOneWidget);

    await tester.tap(find.text('使用原图'));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.width, 400);
    expect(result!.height, 200);
    expect(result!.aspect, closeTo(0.5, 1e-9), reason: '横图 2:1,高宽比 0.5');
    expect(result!.path, photo.path, reason: '使用原图直接沿用原路径');
  });

  testWidgets('拖角自由裁剪:按裁剪区域尺寸返回,结果写盘', (tester) async {
    final photo = makePhoto('b.png', 400, 200);
    final persisted = <String>[];
    CroppedImage? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showImageCropDialog(
                context,
                photo.path,
                persist: (bytes, ext) async {
                  final target = '${tmp.path}${Platform.pathSeparator}out$ext';
                  File(target).writeAsBytesSync(bytes);
                  persisted.add(target);
                  return target;
                },
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 把右下角手柄往左上拖,裁掉一块。
    await tester.drag(
      find.byKey(const ValueKey('crop_handle_3')),
      const Offset(-120, -60),
    );
    await tester.pump();
    final sizeText = (find
            .textContaining('×')
            .evaluate()
            .single
            .widget as Text)
        .data!;
    expect(sizeText, isNot(contains('400 × 200 /')), reason: '拖角后尺寸行已变化');

    await tester.tap(find.text('裁剪并添加'));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(persisted, hasLength(1), reason: '裁剪结果写盘一次');
    // 返回尺寸与裁剪框一致（从尺寸行解析）,且比例随裁剪区域走。
    final cropPart = sizeText.split(' / ').first;
    final dims = cropPart
        .split('×')
        .map((s) => int.parse(s.trim()))
        .toList();
    expect(result!.width, dims[0]);
    expect(result!.height, dims[1]);
    expect(result!.aspect, closeTo(dims[1] / dims[0], 1e-9));
  });
}

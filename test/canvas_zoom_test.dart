import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pagenote/widgets/canvas/canvas_zoom.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('适配模式：整页恰好装进视口,且为缩放下限', (tester) async {
    final key = GlobalKey<CanvasZoomState>();
    await tester.pumpWidget(
      _host(Center(
        child: SizedBox(
          width: 200,
          height: 200,
          child: CanvasZoom(
            key: key,
            fitToViewport: true,
            wheelMode: CanvasWheelMode.zoom,
            childSize: const Size(400, 800),
            child: const SizedBox.expand(),
          ),
        ),
      )),
    );
    await tester.pumpAndSettle();
    // 视口 200×200,内容 400×800 → 基准缩放 = min(0.5, 0.25) = 0.25。
    expect(key.currentState!.scale, closeTo(0.25, 1e-6));
  });

  testWidgets('双指捏合：放大画布,松手后保持', (tester) async {
    final key = GlobalKey<CanvasZoomState>();
    await tester.pumpWidget(
      _host(Center(
        child: SizedBox(
          width: 300,
          height: 300,
          child: CanvasZoom(
            key: key,
            childSize: const Size(300, 300),
            child: const SizedBox.expand(),
          ),
        ),
      )),
    );
    await tester.pumpAndSettle();
    expect(key.currentState!.scale, 1.0);

    final center = const Offset(400, 300); // 300×300 盒子在 800×600 画布居中
    final g1 = await tester.startGesture(center - const Offset(40, 0));
    final g2 = await tester.startGesture(center + const Offset(40, 0));
    await tester.pump(kPressTimeout);
    await g1.moveBy(const Offset(-35, 0));
    await g2.moveBy(const Offset(35, 0));
    await tester.pump();
    await g1.up();
    await g2.up();
    await tester.pumpAndSettle();
    // 两指间距 80 → 150,约 1.8 倍;取宽松下界防手势取整误差。
    expect(key.currentState!.scale, greaterThan(1.4));
  });

  testWidgets('缩放下限：适配模式下捏合缩小不小于整页适配值', (tester) async {
    final key = GlobalKey<CanvasZoomState>();
    await tester.pumpWidget(
      _host(Center(
        child: SizedBox(
          width: 200,
          height: 200,
          child: CanvasZoom(
            key: key,
            fitToViewport: true,
            wheelMode: CanvasWheelMode.zoom,
            childSize: const Size(400, 800),
            child: const SizedBox.expand(),
          ),
        ),
      )),
    );
    await tester.pumpAndSettle();
    expect(key.currentState!.scale, closeTo(0.25, 1e-6));

    final center = const Offset(400, 300); // 200×200 盒子在 800×600 画布居中
    final g1 = await tester.startGesture(center - const Offset(30, 0));
    final g2 = await tester.startGesture(center + const Offset(30, 0));
    await tester.pump(kPressTimeout);
    // 两指收拢（60 → 20）,远小于 1 倍。
    await g1.moveBy(const Offset(20, 0));
    await g2.moveBy(const Offset(-20, 0));
    await tester.pump();
    await g1.up();
    await g2.up();
    await tester.pumpAndSettle();
    expect(key.currentState!.scale, closeTo(0.25, 1e-6));
  });

  testWidgets('滚轮：zoom 模式缩放 / scroll 模式平移', (tester) async {
    final zoomKey = GlobalKey<CanvasZoomState>();
    final panKey = GlobalKey<CanvasZoomState>();
    await tester.pumpWidget(
      _host(Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 300,
              height: 150,
              child: CanvasZoom(
                key: zoomKey,
                wheelMode: CanvasWheelMode.zoom,
                childSize: const Size(300, 300),
                child: const SizedBox.expand(),
              ),
            ),
            SizedBox(
              width: 300,
              height: 150,
              child: CanvasZoom(
                key: panKey,
                wheelMode: CanvasWheelMode.scroll,
                childSize: const Size(300, 600),
                child: const SizedBox.expand(),
              ),
            ),
          ],
        ),
      )),
    );
    await tester.pumpAndSettle();

    // 上滚（负 delta）作用于上半块（zoom 模式）→ 放大。
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: const Offset(400, 250),
        scrollDelta: const Offset(0, -120),
      ),
    );
    await tester.pumpAndSettle();
    expect(zoomKey.currentState!.scale, greaterThan(1.5));

    // 下滚作用于下半块（scroll 模式）→ 纵向平移（内容 600 高于视口 150）。
    final before = panKey.currentState!.offset;
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: const Offset(400, 350),
        scrollDelta: const Offset(0, 100),
      ),
    );
    await tester.pumpAndSettle();
    expect(panKey.currentState!.offset.dy, lessThan(before.dy));
  });
}

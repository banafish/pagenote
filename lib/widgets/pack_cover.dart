
import 'package:flutter/material.dart';

import '../models/sticker_assets.dart';
import '../utils/pack_cover_store.dart';
import 'stored_image.dart';

/// 包封面缩略（REQ-27.1）：有封面显示图片；未设置显示统一占位
/// ——主色底 + 包名首字（名字为空回退包图标）。
/// 不做从包内容自动合成：包的边界用固定占位样式表达，
/// 不会因为包里有贴纸就自作主张拼一张。
class PackCoverImage extends StatelessWidget {
  const PackCoverImage({super.key, required this.pack});

  final StickerPack pack;

  @override
  Widget build(BuildContext context) {
    final cover = pack.coverPath;
    if (cover != null) {
      return Image(
        image: storedImageProvider(PackCoverStore.pathOf(cover)),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _placeholder(context),
      );
    }
    return _placeholder(context);
  }

  Widget _placeholder(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = pack.name.trim();
    final initial = name.isEmpty ? '' : name.characters.first;
    return Container(
      color: scheme.primaryContainer.withValues(alpha: 0.5),
      alignment: Alignment.center,
      child: initial.isEmpty
          ? Icon(
              Icons.inventory_2_rounded,
              size: 22,
              color: scheme.onPrimaryContainer,
            )
          : Text(
              initial,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: scheme.onPrimaryContainer,
              ),
            ),
    );
  }
}

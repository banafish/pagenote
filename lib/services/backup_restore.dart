import '../providers/custom_sticker_provider.dart';
import '../utils/pack_cover_store.dart';
import 'backup_service.dart';

/// 恢复备份内的素材资产（REQ-20.6 贴纸 / v7 包记录 / REQ-27.7 封面），
/// 设置页与 WebDAV 恢复共用，返回落地张数与跳过张数。
///
/// 顺序：覆盖模式先清空既有素材与包 → 重建包记录（贴纸的 packId 才有落位）
/// → 恢复**新建**包的封面 → 逐张导入贴纸。合并模式下同 id 的包保留本机
/// 版本（含封面），不覆盖。
Future<({int saved, int skipped})> restoreStickerAssets(
  CustomStickerProvider stickers,
  BackupData data, {
  required bool overwrite,
}) async {
  if (overwrite) await stickers.clearAll();
  final createdPacks = await stickers.ensurePacksExist(data.stickerPacks);
  // 封面按文件名重映射（REQ-27.7，与贴纸路径重映射同一套语义）：
  // 备份里的文件名经落盘归一化后可能变化（超限被压缩过 sha1 会漂移），
  // 因此拿落盘后的新文件名回写 coverPath；字节缺失或无效则置空，
  // 包卡片回落为占位样式，不留下指向不存在文件的脏引用。
  for (final pack in createdPacks) {
    final cover = pack.coverPath;
    if (cover == null) continue;
    final bytes = data.packCoverBytes[_coverKey(cover)];
    final stored =
        bytes == null ? null : await PackCoverStore.importFromBytes(bytes);
    await stickers.setPackCover(pack.id, stored);
  }
  var count = 0;
  var skipped = 0;
  for (final sticker in data.customStickers) {
    final bytes = data.stickerBytes[sticker.fileName];
    if (bytes == null) {
      skipped++;
      continue;
    }
    final saved = await stickers.importFromBytes(
      bytes,
      name: sticker.name,
      category: sticker.category,
      ext: sticker.ext,
      packId: sticker.packId,
    );
    if (saved != null) {
      count++;
    } else {
      skipped++;
    }
  }
  return (saved: count, skipped: skipped);
}

/// 备份清单里存的是相对文件名；防御性取 basename，避免被篡改的名字
/// 用于字典查找时失配（真正落盘的路径消毒在 PackCoverStore 内）。
String _coverKey(String fileName) {
  final slash = fileName.lastIndexOf('/');
  return slash < 0 ? fileName : fileName.substring(slash + 1);
}

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

import '../database/app_database.dart';
import '../models/canvas_page.dart';
import '../models/journal_entry.dart';
import '../models/sticker_assets.dart';
import '../models/template.dart' show JournalTemplate;
import '../utils/sticker_store.dart';

/// 自定义图片贴纸仓库（REQ-20）：维护 DB 记录、stickers/ 目录文件与
/// 全局索引 [CustomStickerIndex] 三者同步。
class CustomStickerProvider extends ChangeNotifier {
  CustomStickerProvider({AppDatabase? database})
    : _db = database ?? AppDatabase.instance;

  final AppDatabase _db;

  List<CustomSticker> _backing = [];
  bool loaded = false;

  /// 全部自定义贴纸，新导入的在前。
  List<CustomSticker> get stickers => List.unmodifiable(_backing);

  /// 现有分组（REQ-20.4「我的」页签按此分段）。
  List<String> get categories {
    final names = _backing.map((s) => s.category).toSet().toList()..sort();
    return names;
  }

  CustomSticker? byId(String id) =>
      _backing.where((s) => s.id == id).firstOrNull;

  /// 读 DB 并刷新全局索引。渲染端（CanvasView / 分享长图）拿不到 Provider，
  /// 一律经 [CustomStickerIndex] 取路径，因此增删改后都要同步这份索引。
  Future<void> load() async {
    await StickerStore.ensureDir();
    _backing = await _db.getAllCustomStickers();
    _syncIndex();
    loaded = true;
    notifyListeners();
  }

  /// 从相册导入一张图片（REQ-20.1）：同 sha1 视为同一张素材，
  /// 已存在则不重复入库，直接返回既有记录（REQ-20.2）。
  /// 图片无法解码时返回 null。
  Future<CustomSticker?> importFromFile(XFile file, {String? name}) async {
    final sticker = await StickerStore.importFile(file, name: name ?? '');
    if (sticker == null) return null;
    return _put(sticker);
  }

  /// 从字节导入（备份恢复 REQ-20.6 与分享包安装 REQ-21.3 复用）：
  /// id 由字节 sha1 推导，与包内 `<sha1>.png` 的文件名天然对齐，
  /// 因此模板里的 `img:<sha1>` 引用无需重映射。字节原样落盘，不再压缩，
  /// 否则 sha1 变化会打断引用。
  Future<CustomSticker?> importFromBytes(
    Uint8List bytes, {
    required String name,
    String category = '我的',
    String ext = '.png',
  }) async {
    if (bytes.isEmpty) return null;
    final safeExt = ext.isEmpty ? '.png' : ext;
    final id = StickerStore.idOf(bytes);
    await StickerStore.persistBytes(bytes, safeExt);
    return _put(
      CustomSticker(id: id, name: name, category: category, ext: safeExt),
    );
  }

  /// 重命名（REQ-20.4）。
  Future<void> rename(String id, String name) async {
    final sticker = byId(id);
    final trimmed = name.trim();
    if (sticker == null || trimmed.isEmpty || sticker.name == trimmed) return;
    sticker.name = trimmed;
    await _db.insertCustomSticker(sticker);
    _syncIndex();
    notifyListeners();
  }

  /// 改分组（REQ-20.4）。
  Future<void> setCategory(String id, String category) async {
    final sticker = byId(id);
    final trimmed = category.trim();
    if (sticker == null || trimmed.isEmpty || sticker.category == trimmed) {
      return;
    }
    sticker.category = trimmed;
    await _db.insertCustomSticker(sticker);
    notifyListeners();
  }

  /// 删除记录与文件（REQ-20.4）；被引用时由调用方先做二次确认，
  /// 删除后引用处退化为缺失占位（FIX-03）。
  Future<void> delete(String id) async {
    final sticker = byId(id);
    if (sticker == null) return;
    await _db.deleteCustomSticker(id);
    await StickerStore.delete(StickerStore.pathOf(sticker.id, sticker.ext));
    _backing = _backing.where((s) => s.id != id).toList();
    _syncIndex();
    notifyListeners();
  }

  /// 清空全部自定义贴纸（备份覆盖导入前调用）。
  Future<void> clearAll() async {
    await _db.deleteAllCustomStickers();
    await StickerStore.clearAll();
    _backing = [];
    _syncIndex();
    notifyListeners();
  }

  /// 该素材是否被现有手账或模板引用（REQ-20.4 删除二次确认）。
  bool isReferenced(
    String id,
    Iterable<JournalEntry> entries,
    Iterable<JournalTemplate> templates,
  ) {
    final key = '$stickerKeyImage$id';
    bool used(JournalCanvas? canvas) =>
        canvas != null && canvas.stickerKeys.contains(key);
    return entries.any((e) => used(e.canvas)) ||
        templates.any((t) => used(t.canvas));
  }

  /// 文件名 → 字节，供备份（REQ-20.6）与分享包（REQ-21.3）打包；
  /// [ids] 非空时只导出指定素材，用于分享包只带被引用的那几张。
  Future<Map<String, Uint8List>> exportBytes({Iterable<String>? ids}) async {
    final wanted = ids?.toSet();
    final out = <String, Uint8List>{};
    for (final s in _backing) {
      if (wanted != null && !wanted.contains(s.id)) continue;
      final bytes = await StickerStore.readBytes(s.id, s.ext);
      if (bytes != null) out[s.fileName] = bytes;
    }
    return out;
  }

  /// 已存在同 sha1 则复用既有记录，不重复写库（REQ-20.2 去重）。
  Future<CustomSticker> _put(CustomSticker sticker) async {
    final existing = byId(sticker.id);
    if (existing != null) return existing;
    await _db.insertCustomSticker(sticker);
    _backing = [sticker, ..._backing];
    _syncIndex();
    notifyListeners();
    return sticker;
  }

  void _syncIndex() {
    CustomStickerIndex.instance.replaceAll(
      {for (final s in _backing) s.id: StickerStore.pathOf(s.id, s.ext)},
      {for (final s in _backing) s.id: s.name},
    );
  }
}

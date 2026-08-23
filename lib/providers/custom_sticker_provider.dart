import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../database/app_database.dart';
import '../models/canvas_page.dart';
import '../models/journal_entry.dart';
import '../models/sticker_assets.dart';
import '../models/template.dart' show JournalTemplate;
import '../utils/journal_id.dart';
import '../utils/pack_cover_store.dart';
import '../utils/sticker_store.dart';

/// 自定义图片贴纸仓库（REQ-20）：维护 DB 记录、stickers/ 目录文件与
/// 全局索引 [CustomStickerIndex] 三者同步。
///
/// v7 起同时管理素材包（[StickerPack]）：分享包导入与手工新建的分组容器，
/// 贴纸经 [CustomSticker.packId]、模板经 `JournalTemplate.packId`（v8）
/// 挂到包上，null 为未分组。
class CustomStickerProvider extends ChangeNotifier {
  CustomStickerProvider({AppDatabase? database})
    : _db = database ?? AppDatabase.instance;

  final AppDatabase _db;

  List<CustomSticker> _backing = [];
  List<StickerPack> _packBacking = [];
  bool loaded = false;

  /// 全部自定义贴纸，新导入的在前。
  List<CustomSticker> get stickers => List.unmodifiable(_backing);

  /// 全部素材包，按手动顺序排列（REQ-26.5），同序时新建在前。
  List<StickerPack> get packs => List.unmodifiable(_packBacking);

  /// 未分组（packId 为 null）的贴纸。
  List<CustomSticker> get ungroupedStickers =>
      [for (final s in _backing) if (s.packId == null) s];

  /// 指定包内的贴纸（包不存在时为空）。
  List<CustomSticker> stickersOfPack(String packId) =>
      [for (final s in _backing) if (s.packId == packId) s];

  CustomSticker? byId(String id) =>
      _backing.where((s) => s.id == id).firstOrNull;

  StickerPack? packById(String id) =>
      _packBacking.where((p) => p.id == id).firstOrNull;

  StickerPack? packByOriginId(String? originId) => originId == null
      ? null
      : _packBacking.where((p) => p.originId == originId).firstOrNull;

  /// 读 DB 并刷新全局索引。渲染端（CanvasView / 分享长图）拿不到 Provider，
  /// 一律经 [CustomStickerIndex] 取路径，因此增删改后都要同步这份索引。
  Future<void> load() async {
    await StickerStore.ensureDir();
    await PackCoverStore.ensureDir();
    _backing = await _db.getAllCustomStickers();
    _packBacking = await _db.getAllStickerPacks();
    _syncIndex();
    loaded = true;
    notifyListeners();
  }

  /// 从相册导入一张图片（REQ-20.1）：同 sha1 视为同一张素材，
  /// 已存在则不重复入库，直接返回既有记录（REQ-20.2）。
  /// 图片无法解码、或尺寸超出解码上限（NFR-06）时返回 null。
  /// [packId] 指定落位素材包（详情页导入时直接进包）；null 为未分组。
  Future<CustomSticker?> importFromFile(
    XFile file, {
    String? name,
    String? packId,
  }) async {
    final sticker = await StickerStore.importFile(file, name: name ?? '');
    if (sticker == null) return null;
    sticker.packId = packId;
    return _put(sticker);
  }

  /// 从字节导入（备份恢复 REQ-20.6 与分享包安装 REQ-21.3 复用）：
  /// 走与 [importFromFile] 相同的归一化路径——先读文件头过尺寸闸（NFR-06），
  /// 再保证落盘结果在 REQ-20.5 的上限内，不可信字节不会原样落盘。
  ///
  /// id 仍是落盘字节的 sha1，与包内 `<sha1>.png` 的文件名天然对齐，
  /// 因此模板里的 `img:<sha1>` 引用无需重映射；
  /// 只有超限被压缩过的图 sha1 会变，其引用退化为缺失占位（FIX-03）。
  ///
  /// [packId] 指定落位素材包（分享包导入按包落位）；null 为未分组。
  /// [category] 是旧版「分组」字段的透传：备份与分享包清单里带着它，
  /// 导入时原样保留（分组 UI 已下线，不再有编辑入口）。
  /// 返回 null 表示**这一张被跳过**：空字节、格式无法识别、尺寸超上限或解码失败。
  /// 不抛异常，调用方按返回值计数并继续导入其余素材，不中断整包。
  Future<CustomSticker?> importFromBytes(
    Uint8List bytes, {
    required String name,
    String category = '我的',
    String ext = '.png',
    String? packId,
  }) async {
    final stored = await StickerStore.persistNormalizedBytes(bytes, ext: ext);
    if (stored == null) return null;
    return _put(
      CustomSticker(
        id: stored.id,
        name: name,
        category: category,
        ext: stored.ext,
        packId: packId,
      ),
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

  /// 把贴纸移入素材包；packId 为 null 即移回未分组。
  Future<void> moveStickerToPack(String stickerId, String? packId) async {
    final sticker = byId(stickerId);
    if (sticker == null || sticker.packId == packId) return;
    sticker.packId = packId;
    await _db.setCustomStickerPack(stickerId, packId);
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

  /// 清空全部自定义贴纸与素材包（备份覆盖导入前调用）。
  Future<void> clearAll() async {
    await _db.deleteAllCustomStickers();
    await _db.deleteAllStickerPacks();
    await StickerStore.clearAll();
    await PackCoverStore.clearAll();
    _backing = [];
    _packBacking = [];
    _syncIndex();
    notifyListeners();
  }

  // ---------------- 素材包（v7；排序与封面 v9） ----------------

  /// 包列表的手动顺序：sortIndex 升序，同序时新建在前（REQ-26.5）。
  void _sortPacks() {
    _packBacking.sort((a, b) {
      if (a.sortIndex != b.sortIndex) return a.sortIndex.compareTo(b.sortIndex);
      return b.createdAt.compareTo(a.createdAt);
    });
  }

  /// 新包的初始 sortIndex：取当前最小值 - 1，落在列表最前（REQ-26.5）。
  int _frontSortIndex() {
    if (_packBacking.isEmpty) return 0;
    var min = _packBacking.first.sortIndex;
    for (final pack in _packBacking) {
      if (pack.sortIndex < min) min = pack.sortIndex;
    }
    return min - 1;
  }

  /// 手工新建素材包；名称为空时不建。
  Future<StickerPack?> createPack(String name, {String author = ''}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    final pack = StickerPack(
      id: 'pack-${makeId()}',
      name: trimmed,
      author: author.trim(),
      sortIndex: _frontSortIndex(),
    );
    await _db.insertStickerPack(pack);
    _packBacking = [pack, ..._packBacking]..sort((a, b) {
      if (a.sortIndex != b.sortIndex) return a.sortIndex.compareTo(b.sortIndex);
      return b.createdAt.compareTo(a.createdAt);
    });
    notifyListeners();
    return pack;
  }

  /// 重命名包。
  Future<void> renamePack(String packId, String name) async {
    final pack = packById(packId);
    final trimmed = name.trim();
    if (pack == null || trimmed.isEmpty || pack.name == trimmed) return;
    pack.name = trimmed;
    await _db.insertStickerPack(pack);
    notifyListeners();
  }

  /// 分享包导入的落位包（REQ-21.3）：同一个包（pack.json 的 id 相同）
  /// 重复导入时归位到既有包，而不是再建一个同名包——与模板 installTemplates
  /// 的 originId 溯源同一套语义。包名缺省时退回「未命名素材包」。
  Future<StickerPack> ensureImportedPack({
    required String name,
    String author = '',
    String? originId,
  }) async {
    final existing = packByOriginId(originId);
    if (existing != null) return existing;
    final trimmed = name.trim();
    final pack = StickerPack(
      id: 'pack-${makeId()}',
      name: trimmed.isEmpty ? '未命名素材包' : trimmed,
      author: author.trim(),
      originId: originId,
      sortIndex: _frontSortIndex(),
    );
    await _db.insertStickerPack(pack);
    _packBacking = [pack, ..._packBacking];
    _sortPacks();
    notifyListeners();
    return pack;
  }

  /// 备份恢复前确保包记录存在（v7 备份带 sticker_packs.json；
  /// 老备份没有包，贴纸与模板的 packId 也不会有，自然全部落未分组）。
  /// 已有同 id 的包保留本机版本，不覆盖（合并恢复语义）。
  /// 返回本次**新建**的包——封面等随包资产只对它们重映射（REQ-27.7）。
  Future<List<StickerPack>> ensurePacksExist(Iterable<StickerPack> packs) async {
    final created = <StickerPack>[];
    for (final pack in packs) {
      if (packById(pack.id) != null) continue;
      await _db.insertStickerPack(pack);
      _packBacking = [pack, ..._packBacking];
      created.add(pack);
    }
    if (created.isNotEmpty) {
      _sortPacks();
      notifyListeners();
    }
    return created;
  }

  /// 取包的稳定分享 id（整包导出时写进 pack.json 的 id）：
  /// 导入来的包直接用它的 originId；手工建的包首次导出时现场分配并落库。
  /// 此后这个包无论经几手转发，导回任何设备（包括本机）都按它归位到
  /// 同一个包，而不是每次导出都变成一个新包。
  Future<String> ensurePackOriginId(String packId) async {
    final pack = packById(packId);
    if (pack == null) return 'pack-${makeId()}';
    if (pack.originId != null) return pack.originId!;
    pack.originId = 'pack-${makeId()}';
    await _db.insertStickerPack(pack);
    return pack.originId!;
  }

  /// 包列表手动排序（REQ-26.5）：按传入顺序重编 sortIndex（0..n-1）
  /// 并落库，列表页长按拖拽后调用。传入应包含全部包 id。
  Future<void> reorderPacks(List<String> orderedIds) async {
    var changed = false;
    for (var i = 0; i < orderedIds.length; i++) {
      final pack = packById(orderedIds[i]);
      if (pack == null || pack.sortIndex == i) continue;
      pack.sortIndex = i;
      await _db.insertStickerPack(pack);
      changed = true;
    }
    if (!changed) return;
    _sortPacks();
    notifyListeners();
  }

  /// 设置 / 更换 / 移除包封面（REQ-27.2）。
  /// [coverPath] 为 pack_covers/ 内的相对文件名；null 即移除。
  /// 更换与移除时旧封面文件一并清理（REQ-27.8）。
  Future<void> setPackCover(String packId, String? coverPath) async {
    final pack = packById(packId);
    if (pack == null || pack.coverPath == coverPath) return;
    final old = pack.coverPath;
    pack.coverPath = coverPath;
    await _db.insertStickerPack(pack);
    if (old != null && old != coverPath) {
      await PackCoverStore.delete(PackCoverStore.pathOf(old));
    }
    notifyListeners();
  }

  /// 解散包：贴纸全部移回未分组，包记录与封面删除，素材与引用不受影响。
  /// 包内还挂有模板（v8）时，调用方需接着 `TemplateProvider.detachPack`
  /// 把模板也移回未分组。
  Future<void> dissolvePack(String packId) async {
    final pack = packById(packId);
    if (pack == null) return;
    for (final sticker in stickersOfPack(packId)) {
      sticker.packId = null;
      await _db.setCustomStickerPack(sticker.id, null);
    }
    await _db.deleteStickerPack(packId);
    if (pack.coverPath != null) {
      await PackCoverStore.delete(PackCoverStore.pathOf(pack.coverPath!));
    }
    _packBacking = _packBacking.where((p) => p.id != packId).toList();
    notifyListeners();
  }

  /// 删除包与包内全部贴纸（含文件）；被引用时由调用方先做二次确认。
  /// 包内模板不跟随删除，调用方需 `TemplateProvider.detachPack` 移回未分组。
  Future<void> deletePack(String packId) async {
    final pack = packById(packId);
    if (pack == null) return;
    for (final sticker in stickersOfPack(packId)) {
      await _db.deleteCustomSticker(sticker.id);
      await StickerStore.delete(StickerStore.pathOf(sticker.id, sticker.ext));
      _backing = _backing.where((s) => s.id != sticker.id).toList();
    }
    await _db.deleteStickerPack(packId);
    if (pack.coverPath != null) {
      await PackCoverStore.delete(PackCoverStore.pathOf(pack.coverPath!));
    }
    _packBacking = _packBacking.where((p) => p.id != packId).toList();
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

  /// 封面文件名 → 字节，供备份打包（REQ-27.7）；
  /// 只含已设置封面且文件仍存在的包。
  Future<Map<String, Uint8List>> exportCoverBytes() async {
    final out = <String, Uint8List>{};
    for (final pack in _packBacking) {
      final cover = pack.coverPath;
      if (cover == null) continue;
      final bytes = await PackCoverStore.readBytes(cover);
      if (bytes != null) out[p.basename(cover)] = bytes;
    }
    return out;
  }

  /// 已存在同 sha1 则复用既有记录，不重复写库（REQ-20.2 去重）。
  /// 去重命中时若本次导入带着包（packId 非空），先前散落在未分组的
  /// 贴纸归位回包——与模板 installTemplates 同一套语义（如自己导出
  /// 又导回）；用户已把它挪进其它包的，归属保持不变。
  Future<CustomSticker> _put(CustomSticker sticker) async {
    final existing = byId(sticker.id);
    if (existing != null) {
      if (sticker.packId != null && existing.packId == null) {
        existing.packId = sticker.packId;
        await _db.setCustomStickerPack(existing.id, existing.packId);
        notifyListeners();
      }
      return existing;
    }
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

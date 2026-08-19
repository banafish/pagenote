import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../database/app_database.dart';
import '../models/canvas_page.dart';
import '../models/journal_entry.dart';
import '../models/sticker_assets.dart';
import '../models/template.dart' as tpl show builtinTemplates;
import '../models/template.dart'
    show JournalTemplate, isBuiltinTemplateId, newTemplateId;
import '../utils/attachments.dart';

/// 模板列表排序方式（REQ-18.4）。
enum TemplateSort { manual, recent, created }

/// 模板引用的、本机缺失的素材（FIX-03.1 / REQ-21.7）。
class MissingAssetReport {
  const MissingAssetReport({
    required this.stickerKeys,
    required this.paperIds,
    required this.fontFamilies,
  });

  static const empty = MissingAssetReport(
    stickerKeys: {},
    paperIds: {},
    fontFamilies: {},
  );

  final Set<String> stickerKeys;
  final Set<String> paperIds;
  final Set<String> fontFamilies;

  int get count => stickerKeys.length + paperIds.length + fontFamilies.length;

  bool get isEmpty => count == 0;

  /// 「3 个素材本机缺失，导入后显示为占位框」用的可读清单。
  List<String> get labels => [
    for (final k in stickerKeys) stickerKeyLabel(k),
    for (final id in paperIds) '纸张 $id',
    for (final f in fontFamilies) '字体 $f',
  ];
}

/// 手账模板仓库（REQ-09）：内置模板 + 用户自建模板。
class TemplateProvider extends ChangeNotifier {
  TemplateProvider({AppDatabase? database})
    : _db = database ?? AppDatabase.instance;

  final AppDatabase _db;

  List<JournalTemplate> _backing = [];
  bool loaded = false;

  TemplateSort _sort = TemplateSort.manual;

  /// 当前排序方式（REQ-18.4，由设置层持久化后注入）。
  TemplateSort get sort => _sort;

  /// 全部模板：内置在前，按当前排序方式排列。
  List<JournalTemplate> get templates => List.unmodifiable(_backing);

  List<JournalTemplate> get builtinTemplates =>
      _backing.where((t) => t.builtin).toList();

  List<JournalTemplate> get userTemplates =>
      _backing.where((t) => !t.builtin).toList();

  /// 首次启动补种内置模板（已存在则跳过）。
  /// 内置模板升级出整页版式后（canvas 列）,存量安装也自动补上版式,
  /// 但保留用户改过的名字等字段。
  Future<void> load() async {
    final existing = await _db.getAllTemplates();
    // 注意：此处必须引用 models/template.dart 的顶层种子列表，
    // 而非本类的 builtinTemplates getter（此时 _backing 尚为空）。
    for (final b in tpl.builtinTemplates) {
      final stored = existing.where((t) => t.id == b.id).firstOrNull;
      if (stored == null) {
        await _db.insertTemplate(b);
      } else if (b.canvas != null && stored.canvas == null && stored.builtin) {
        stored.canvas = b.canvas;
        await _db.insertTemplate(stored);
      }
    }
    _backing = _sorted(await _db.getAllTemplates());
    loaded = true;
    notifyListeners();
  }

  /// 切换排序方式（REQ-18.4）。
  void setSort(TemplateSort sort) {
    if (_sort == sort) return;
    _sort = sort;
    _backing = _sorted(_backing);
    notifyListeners();
  }

  List<JournalTemplate> _sorted(List<JournalTemplate> list) {
    final sorted = List.of(list);
    sorted.sort((a, b) {
      // 内置模板恒在前，与既有列表习惯一致。
      if (a.builtin != b.builtin) return a.builtin ? -1 : 1;
      return switch (_sort) {
        // 从未使用过的排在用过的之后。
        TemplateSort.recent => _descNullable(a.lastUsedAt, b.lastUsedAt),
        TemplateSort.created => b.createdAt.compareTo(a.createdAt),
        TemplateSort.manual =>
          a.sortIndex != b.sortIndex
              ? a.sortIndex.compareTo(b.sortIndex)
              : b.updatedAt.compareTo(a.updatedAt),
      };
    });
    return sorted;
  }

  static int _descNullable(DateTime? a, DateTime? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return b.compareTo(a);
  }

  JournalTemplate? byId(String id) =>
      _backing.where((t) => t.id == id).firstOrNull;

  /// 新建或更新模板（重命名走这里）。
  Future<void> saveTemplate(JournalTemplate template) async {
    template.updatedAt = DateTime.now();
    await _db.insertTemplate(template);
    await load();
  }

  /// 记录一次套用（REQ-18.4「按最近使用」排序的数据来源）。
  Future<void> markUsed(String id) async {
    final template = byId(id);
    if (template == null) return;
    template.lastUsedAt = DateTime.now();
    await _db.insertTemplate(template);
    _backing = _sorted(_backing);
    notifyListeners();
  }

  /// 将一篇手账另存为模板（REQ-09.3）：连同整页版式一起保存。
  ///
  /// [keepPhotos] 默认 false —— 清空全部照片路径只留占位框（FIX-01.1）。
  /// 模板的语义本就是让使用者填自己的照片；保留本机绝对路径会导致
  /// 跨设备碎图，还会把本机用户名泄露进备份包与分享包。
  Future<JournalTemplate> saveFromEntry(
    JournalEntry entry,
    String name, {
    JournalCanvas? canvas,
    bool keepPhotos = false,
  }) async {
    final cloned = canvas?.clone();
    if (!keepPhotos) cloned?.clearImagePaths();
    final template = JournalTemplate(
      id: newTemplateId(),
      name: name,
      title: entry.title,
      content: entry.content,
      tags: List.from(entry.tags),
      canvas: cloned,
    );
    await saveTemplate(template);
    return template;
  }

  /// 复制模板为一份可自由编辑的用户模板（REQ-18.2 / REQ-18.3）。
  /// 内置模板也可复制，副本 `builtin = false`，能改名、编辑、删除。
  Future<JournalTemplate> duplicateTemplate(
    JournalTemplate source, {
    String? name,
  }) async {
    final copy = source.copyAsNew(
      name: name ?? _uniqueName('${source.name} 副本'),
    );
    await saveTemplate(copy);
    return copy;
  }

  /// 删除模板；内置模板不可删（REQ-09.3）。
  Future<void> deleteTemplate(String id) async {
    final template = byId(id);
    if (template == null || template.builtin) return;
    await _db.deleteTemplate(id);
    await load();
  }

  /// 手动排序：把模板移动到列表指定位置并持久化 sortIndex（REQ-18.4）。
  Future<void> reorderUserTemplates(List<String> orderedIds) async {
    for (var i = 0; i < orderedIds.length; i++) {
      final t = byId(orderedIds[i]);
      if (t == null || t.builtin) continue;
      t.sortIndex = i;
      await _db.insertTemplate(t);
    }
    _sort = TemplateSort.manual;
    await load();
  }

  // ---------------- 导入：恢复 vs 安装（FIX-02.3 两条路径分离） ----------------

  /// 导入**备份**中的模板（REQ-09.4，恢复语义）：
  /// 按 id 去重、`updatedAt` 新者胜；覆盖模式清空后导入。
  ///
  /// 与分享包安装的区别：备份是「自己的数据」，因此保留原 id 与同步语义；
  /// 但 `builtin` 标志一律由本机内置清单推导，不接受文件自称（FIX-02.1）。
  /// [attachments] 为备份包内的附件字节，模板画布里的照片按文件名重映射
  /// 到落地后的新路径（FIX-01.3）。
  Future<void> importTemplates(
    List<JournalTemplate> incoming, {
    required bool overwrite,
    Map<String, Uint8List> attachments = const {},
  }) async {
    if (overwrite) await _db.deleteAllTemplates();
    for (final raw in incoming) {
      final t = _sanitize(raw);
      await _remapTemplatePhotos(t, attachments);
      if (!overwrite) {
        final existing = byId(t.id);
        if (existing != null && !t.updatedAt.isAfter(existing.updatedAt)) {
          continue;
        }
      }
      await _db.insertTemplate(t);
    }
    await load();
  }

  /// 安装**分享包**中的模板（REQ-21.8，安装语义）：
  /// 一律重新分配本地 id、原 id 落为 `originId`、`builtin = false`，
  /// 同名默认保留两者（自动加后缀）。返回实际写入的模板。
  Future<List<JournalTemplate>> installTemplates(
    List<JournalTemplate> incoming, {
    Map<String, Uint8List> attachments = const {},
    bool overwriteSameName = false,
  }) async {
    final installed = <JournalTemplate>[];
    for (final raw in incoming) {
      final sameName = _backing
          .where((t) => !t.builtin && t.name == raw.name)
          .firstOrNull;
      if (overwriteSameName && sameName != null) {
        await _db.deleteTemplate(sameName.id);
        _backing.remove(sameName);
      }
      final t = raw.copyAsNew(
        name: overwriteSameName ? raw.name : _uniqueName(raw.name),
        originId: raw.originId ?? raw.id,
      );
      await _remapTemplatePhotos(t, attachments);
      await _db.insertTemplate(t);
      _backing.add(t);
      installed.add(t);
    }
    await load();
    return installed;
  }

  /// 外部文件来的模板一律重新推导 builtin，防止伪造出删不掉的模板。
  JournalTemplate _sanitize(JournalTemplate t) {
    if (t.builtin == isBuiltinTemplateId(t.id)) return t;
    return JournalTemplate.fromExternalMap(t.toMap());
  }

  /// 模板画布内的照片：按文件名从附件落盘并重映射为本机新路径。
  /// 找不到对应附件的路径直接清空 —— 与内置旅行模板一致退化为占位框，
  /// 绝不把外来的路径字符串留在本地数据里（FIX-01.3）。
  Future<void> _remapTemplatePhotos(
    JournalTemplate t,
    Map<String, Uint8List> attachments,
  ) async {
    final canvas = t.canvas;
    if (canvas == null || !canvas.hasImagePaths) return;
    final resolved = <String, String>{};
    for (final img in canvas.images) {
      if (img.path.isEmpty) continue;
      final name = p.basename(img.path);
      if (resolved.containsKey(name)) continue;
      final bytes = attachments[name];
      if (bytes == null) continue;
      resolved[name] = await Attachments.persistBytes(
        bytes,
        p.extension(name),
      );
    }
    canvas.remapImagePaths((path) => resolved[p.basename(path)] ?? '');
  }

  /// 同名时自动加后缀（REQ-21.8「默认保留两者」）。
  String _uniqueName(String name) {
    final taken = _backing.map((t) => t.name).toSet();
    if (!taken.contains(name)) return name;
    for (var i = 2; i < 1000; i++) {
      final candidate = '$name ($i)';
      if (!taken.contains(candidate)) return candidate;
    }
    return '$name (${DateTime.now().millisecondsSinceEpoch})';
  }
}

/// 校验一批模板引用的素材在本机是否齐全（FIX-03.1 / REQ-21.7）。
/// 放在 provider 层之外的顶层函数，导入预览页与渲染端可共用。
MissingAssetReport checkMissingAssets(
  Iterable<JournalTemplate> templates, {
  required bool Function(String paperId) hasPaper,
  required bool Function(String family) hasFont,
}) {
  final stickers = <String>{};
  final papers = <String>{};
  final fonts = <String>{};
  for (final t in templates) {
    final canvas = t.canvas;
    if (canvas == null) continue;
    for (final key in canvas.stickerKeys) {
      if (!isKnownStickerKey(key)) stickers.add(key);
    }
    if (canvas.paperId.isNotEmpty && !hasPaper(canvas.paperId)) {
      papers.add(canvas.paperId);
    }
    for (final text in canvas.texts) {
      if (text.fontFamily.isNotEmpty && !hasFont(text.fontFamily)) {
        fonts.add(text.fontFamily);
      }
    }
  }
  return MissingAssetReport(
    stickerKeys: stickers,
    paperIds: papers,
    fontFamilies: fonts,
  );
}

import 'package:flutter/foundation.dart';

import '../database/app_database.dart';
import '../models/journal_entry.dart';
import '../models/template.dart' as tpl show builtinTemplates;
import '../models/template.dart' show JournalTemplate, newTemplateId;

/// 手账模板仓库（REQ-09）：内置模板 + 用户自建模板。
class TemplateProvider extends ChangeNotifier {
  TemplateProvider({AppDatabase? database})
    : _db = database ?? AppDatabase.instance;

  final AppDatabase _db;

  List<JournalTemplate> _backing = [];
  bool loaded = false;

  /// 全部模板：内置在前，按更新时间倒序。
  List<JournalTemplate> get templates => List.unmodifiable(_backing);

  List<JournalTemplate> get builtinTemplates =>
      _backing.where((t) => t.builtin).toList();

  List<JournalTemplate> get userTemplates =>
      _backing.where((t) => !t.builtin).toList();

  /// 首次启动补种内置模板（已存在则跳过）。
  Future<void> load() async {
    final existing = await _db.getAllTemplates();
    final existingIds = existing.map((t) => t.id).toSet();
    // 注意：此处必须引用 models/template.dart 的顶层种子列表，
    // 而非本类的 builtinTemplates getter（此时 _backing 尚为空）。
    for (final b in tpl.builtinTemplates) {
      if (!existingIds.contains(b.id)) {
        await _db.insertTemplate(b);
      }
    }
    _backing = await _db.getAllTemplates();
    loaded = true;
    notifyListeners();
  }

  JournalTemplate? byId(String id) =>
      _backing.where((t) => t.id == id).firstOrNull;

  /// 新建或更新模板（重命名走这里）。
  Future<void> saveTemplate(JournalTemplate template) async {
    template.updatedAt = DateTime.now();
    await _db.insertTemplate(template);
    await load();
  }

  /// 将一篇手账另存为模板（REQ-09.3）。
  Future<JournalTemplate> saveFromEntry(JournalEntry entry, String name) async {
    final template = JournalTemplate(
      id: newTemplateId(),
      name: name,
      title: entry.title,
      content: entry.content,
      tags: List.from(entry.tags),
    );
    await saveTemplate(template);
    return template;
  }

  /// 删除模板；内置模板不可删（REQ-09.3）。
  Future<void> deleteTemplate(String id) async {
    final template = byId(id);
    if (template == null || template.builtin) return;
    await _db.deleteTemplate(id);
    await load();
  }

  /// 导入备份中的模板（REQ-09.4）：合并按 id 去重、更新时间新者胜；
  /// 覆盖模式清空后导入。内置模板标志始终保留。
  Future<void> importTemplates(
    List<JournalTemplate> incoming, {
    required bool overwrite,
  }) async {
    if (overwrite) {
      await _db.deleteAllTemplates();
      for (final t in incoming) {
        await _db.insertTemplate(t);
      }
    } else {
      for (final t in incoming) {
        final existing = byId(t.id);
        if (existing != null && !t.updatedAt.isAfter(existing.updatedAt)) {
          continue;
        }
        await _db.insertTemplate(t);
      }
    }
    await load();
  }
}

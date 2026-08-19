import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import '../data/prompts.dart';
import '../models/canvas_page.dart';
import '../models/journal_entry.dart';
import '../models/mood.dart';
import '../models/template.dart';
import '../providers/journal_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/template_provider.dart';
import '../utils/attachments.dart';
import '../utils/date_utils.dart';
import '../widgets/activity_selector.dart';
import '../widgets/canvas/canvas_editor.dart';
import '../widgets/canvas/canvas_view.dart';
import '../widgets/canvas/canvas_tool_sheets.dart';
import '../widgets/daily_prompt_card.dart';
import '../widgets/emoji_selector.dart';
import '../widgets/tag_editor.dart';
import '../widgets/template_picker.dart';

/// 手账编辑器（调研三阶段重构）：一页手账 = 一张自由画布。
/// 文字框 / 照片 / 贴纸 / 胶带 / 日期心情天气组件全部是可独立移动、
/// 缩放、旋转的图层元素；正文不再是文档流,而是画布上的文本元素。
/// 心情/天气/活动保留为结构化字段（「信息」面板编辑）,统计照常可用。
class EditorPage extends StatefulWidget {
  const EditorPage({super.key, this.entry, this.isNew = false});

  /// 传入则为编辑已有手账（先进查看态），否则为新建。
  final JournalEntry? entry;

  /// 新建入口（右下角按钮、每日一问引导）：即使带预填草稿也直接进编辑态。
  final bool isNew;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  late final JournalEntry _draft;
  late final bool _isEditing;
  bool _saved = false;
  bool _dirty = false;

  /// 查看态：打开已有手账先进只读浏览,点右上角编辑图标后才可改动。
  bool _viewMode = false;

  late JournalCanvas _canvas;
  final _editorKey = GlobalKey<CanvasEditorState>();

  // 撤销/重做（调研二阶段）：历史为画布 JSON 快照。
  final List<String> _history = [];
  int _historyIndex = -1;

  // 每日一问（REQ-04）。
  late String _todayKey;
  int _promptOffset = 0;
  int _promptRemaining = 3;

  @override
  void initState() {
    super.initState();
    _draft =
        widget.entry?.copy() ??
        JournalEntry(
          id: JournalProvider.newId(),
          date: DateUtils2.dateKey(DateTime.now()),
          title: '',
          content: '',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
    _isEditing = widget.entry != null && !widget.isNew;
    _viewMode = _isEditing;
    // 旧数据无画布 → 自动合成等价元素（文本框 + 图片 + 组件 + 旧贴纸）。
    _canvas = _draft.canvas ?? synthesizeCanvas(_draft);
    _draft.canvas = _canvas;
    _syncComponents();
    _canvas.fitHeight();
    _pushHistory(markDirty: false);

    final settings = context.read<SettingsProvider>();
    // 每日一问按「今天」展示（REQ-04.1），与补写日期无关。
    _todayKey = DateUtils2.dateKey(DateTime.now());
    _promptOffset = settings.promptOffsetFor(_todayKey);
    _promptRemaining =
        3 - settings.promptRefreshUsedToday(_todayKey).clamp(0, 3);
  }

  // ---------------- 撤销 / 重做 ----------------

  void _pushHistory({bool markDirty = true}) {
    _history.removeRange(_historyIndex + 1, _history.length);
    _history.add(encodeCanvas(_canvas));
    if (_history.length > 60) _history.removeAt(0);
    _historyIndex = _history.length - 1;
    // 初始基线快照不算用户修改（否则「从模板开始」引导永不出现）。
    if (markDirty) _dirty = true;
    setState(() {});
  }

  bool get _canUndo => _historyIndex > 0;
  bool get _canRedo => _historyIndex < _history.length - 1;

  void _undo() {
    if (!_canUndo) return;
    _historyIndex--;
    _restoreHistory();
  }

  void _redo() {
    if (!_canRedo) return;
    _historyIndex++;
    _restoreHistory();
  }

  void _restoreHistory() {
    _canvas = decodeCanvas(_history[_historyIndex]) ?? _canvas;
    _draft.canvas = _canvas;
    _draft.paper = _canvas.paperId;
    _editorKey.currentState?.clearSelection();
    setState(() {});
  }

  /// 画布操作完成（手势结束 / 增删 / 面板保存）后的统一提交。
  void _commit() {
    _canvas.fitHeight();
    _pushHistory();
  }

  // ---------------- 组件同步（结构化字段 ↔ 画布组件元素） ----------------

  void _syncComponents() {
    void ensure(ComponentKind kind, bool present, Offset at) {
      final existing = _canvas.componentOf(kind);
      if (!present) {
        if (existing != null) _canvas.elements.remove(existing);
        return;
      }
      if (existing == null) {
        _canvas.elements.add(
          StructuredElement(
            kind: kind,
            x: at.dx,
            y: at.dy,
            w: kind == ComponentKind.date ? 0.52 : 0.32,
            h: kind == ComponentKind.date ? 0.12 : 0.14,
          ),
        );
      }
    }

    ensure(ComponentKind.date, true, const Offset(0.08, 0.06));
    ensure(
      ComponentKind.mood,
      _draft.mood != null,
      const Offset(0.6, 0.05),
    );
    ensure(
      ComponentKind.weather,
      _draft.weather != null,
      const Offset(0.6, 0.19),
    );
    ensure(
      ComponentKind.activities,
      _draft.activities.isNotEmpty,
      Offset(0.08, _canvas.effectiveHeight - 0.18),
    );
  }

  // ---------------- 保存 ----------------

  TextElement? get _titleElement => _canvas.firstOfRole('title');

  TextElement? get _bodyElement => _canvas.firstOfRole('body');

  bool get _hasText {
    final title = _titleElement?.text.trim() ?? '';
    final body = _bodyElement?.text.trim() ?? '';
    final free = _canvas.texts
        .where((t) => t.role.isEmpty && t.text.trim().isNotEmpty)
        .isNotEmpty;
    return title.isNotEmpty || body.isNotEmpty || free;
  }

  bool get _hasPhotos =>
      _canvas.images.any((e) => e.path.isNotEmpty) || _draft.images.isNotEmpty;

  Future<void> _save() async {
    if (!_hasText && !_hasPhotos) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('写点什么再保存吧 ✏️')));
      return;
    }
    _syncComponents();
    _canvas.fitHeight();

    // 画布 → 结构化字段：标题/正文回写（搜索、统计、导出依赖）,
    // 照片元素路径同步进 images（备份、回收站清理、只看有图复用现有逻辑）。
    final title = _titleElement;
    final oldImages = List<String>.from(_draft.images);
    _draft.title = title?.text.trim() ?? '';
    final bodyTexts = [
      if (_bodyElement != null && _bodyElement!.text.trim().isNotEmpty)
        _bodyElement!.text.trim(),
      for (final t in _canvas.texts.where((t) => t.role.isEmpty))
        if (t.text.trim().isNotEmpty) t.text.trim(),
    ];
    _draft.content = bodyTexts.join('\n\n');
    _draft.images = [
      for (final e in _canvas.images)
        if (e.path.isNotEmpty) e.path,
    ];
    _draft
      ..paper = _canvas.paperId
      ..canvas = _canvas
      // 整理速记：在编辑页保存即转为正式手账（REQ-16）。
      ..isQuickNote = false
      ..updatedAt = DateTime.now();

    // 清理本次编辑中移除的照片文件。
    for (final path in oldImages) {
      if (!_draft.images.contains(path)) await Attachments.delete(path);
    }
    if (!mounted) return;

    await context.read<JournalProvider>().saveEntry(_draft);
    _saved = true;
    if (mounted) Navigator.of(context).pop();
  }

  Future<bool> _confirmDiscard() async {
    // 查看态 / 无改动时直接返回，不弹放弃确认（含打开已有手账未编辑的情况）。
    if (_saved || !_dirty) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('放弃这篇手账？'),
        content: const Text('未保存的修改将会丢失。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('继续编辑'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('放弃'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // ---------------- 每日一问（REQ-04） ----------------

  String get _prompt => promptForDate(_todayKey, _promptOffset);

  void _insertPrompt() {
    final body =
        _bodyElement ??
        () {
          final el = TextElement(
            role: 'body',
            x: 0.08,
            y: 0.36,
            w: 0.84,
            fontScale: 0.038,
          );
          _canvas.elements.add(el);
          return el;
        }();
    final text = body.text;
    body.text = text.isEmpty ? '$_prompt\n' : '$_prompt\n\n$text';
    body.h = measureTextHeight(body);
    _commit();
  }

  Future<void> _showPromptSheet() async {
    final settings = context.read<SettingsProvider>();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DailyPromptCard(
                prompt: _prompt,
                initiallyExpanded: true,
                onInsert: () {
                  Navigator.pop(sheetContext);
                  _insertPrompt();
                },
                onRefresh: () async {
                  final ok = await settings.usePromptRefresh(_todayKey);
                  if (!ok || !mounted) return;
                  setState(() {
                    _promptOffset = settings.promptOffsetFor(_todayKey);
                    _promptRemaining =
                        3 - settings.promptRefreshUsedToday(_todayKey);
                  });
                },
                refreshRemaining: _promptRemaining,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------- 日期 ----------------

  Future<void> _pickDate() async {
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (dialogContext) => Localizations.override(
        context: dialogContext,
        locale: const Locale('zh'),
        delegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        child: Builder(
          builder: (innerContext) => Theme(
            data: Theme.of(innerContext),
            child: DatePickerDialog(
              initialDate: DateUtils2.parseKey(_draft.date),
              firstDate: DateTime(2000),
              lastDate: DateTime.now().add(const Duration(days: 1)),
            ),
          ),
        ),
      ),
    );
    if (picked != null) {
      setState(() => _draft.date = DateUtils2.dateKey(picked));
    }
  }

  // ---------------- 素材添加 ----------------

  Future<void> _addSticker() async {
    final element = await showStickerPalette(context);
    if (element == null || !mounted) return;
    setState(() => _canvas.elements.add(element));
    _commit();
    _editorKey.currentState?.select(element.id);
  }

  Future<void> _addPhoto() async {
    final existing = _canvas.images.length;
    if (existing >= Attachments.maxImages) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('最多添加 ${Attachments.maxImages} 张照片')),
      );
      return;
    }
    final paths = await Attachments.pickImages(
      remaining: Attachments.maxImages - existing,
    );
    if (paths.isEmpty || !mounted) return;
    setState(() {
      var i = 0;
      for (final path in paths) {
        _canvas.elements.add(
          ImageElement(
            path: path,
            x: 0.1 + (i % 2) * 0.45,
            y: _canvas.effectiveHeight - 0.4 + (i ~/ 2) * 0.36,
            w: 0.4,
            h: 0.32,
          ),
        );
        i++;
      }
    });
    _commit();
  }

  Future<void> _addText() async {
    final element = TextElement(
      x: 0.2,
      y: _canvas.effectiveHeight - 0.25,
      w: 0.6,
      text: '',
      fontScale: 0.04,
    );
    setState(() => _canvas.elements.add(element));
    _commit();
    _editorKey.currentState?.select(element.id);
    await _editText(element);
  }

  Future<void> _pickPaper() async {
    final id = await showPaperPicker(context, _canvas.paperId);
    if (id == null || !mounted) return;
    setState(() {
      _canvas.paperId = id;
      _draft.paper = id;
    });
    _commit();
  }

  // ---------------- 元素编辑 ----------------

  Future<void> _editText(TextElement element) async {
    final before = element.encode();
    final changed = await showTextElementEditor(context, element);
    if (!changed || !mounted) return;
    if (element.role == 'title') {
      _draft.title = element.text.trim();
    }
    element.h = measureTextHeight(element);
    // 正文变化可能需要页面变长。
    setState(() => _canvas.fitHeight());
    if (element.encode().toString() != before.toString()) _commit();
  }

  Future<void> _editImage(ImageElement element) async {
    if (element.path.isEmpty) {
      // 占位框：直接选照片（整页模板的照片位）。
      final paths = await Attachments.pickImages(remaining: 1);
      if (paths.isEmpty || !mounted) return;
      setState(() => element.path = paths.first);
      _commit();
      return;
    }
    final changed = await showImageElementEditor(context, element);
    if (changed && mounted) _commit();
  }

  Future<void> _editComponent(StructuredElement element) async {
    switch (element.kind) {
      case ComponentKind.date:
        await _pickDate();
      case ComponentKind.mood:
        await _showEmojiPicker(
          '今日心情',
          Mood.values.map(
            (m) => EmojiItem(
              id: m.id,
              emoji: m.emoji,
              label: m.label,
              color: m.color,
            ),
          ),
          _draft.mood?.id,
          (id) => _draft.mood = id == null ? null : Mood.fromId(id),
        );
      case ComponentKind.weather:
        await _showEmojiPicker(
          '今日天气',
          Weather.values.map(
            (w) => EmojiItem(
              id: w.id,
              emoji: w.emoji,
              label: w.label,
              color: w.color,
            ),
          ),
          _draft.weather?.id,
          (id) => _draft.weather = id == null ? null : Weather.fromId(id),
        );
      case ComponentKind.activities:
        await _showInfoSheet();
    }
  }

  Future<void> _showEmojiPicker(
    String label,
    Iterable<EmojiItem> items,
    String? selectedId,
    void Function(String?) apply,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: EmojiSelector(
            label: label,
            items: items.toList(),
            selectedId: selectedId,
            onSelected: (id) {
              setState(() {
                apply(id);
                _syncComponents();
              });
              Navigator.pop(sheetContext);
              _commit();
            },
          ),
        ),
      ),
    );
  }

  // ---------------- 信息面板（日期/心情/天气/活动/标签） ----------------

  Future<void> _showInfoSheet() async {
    // sheet 内自管理选中状态并即时刷新：ModalBottomSheet 的 builder
    // 不会随页面 setState 重建,若直接读 _draft 选中态会一直不更新。
    var mood = _draft.mood;
    var weather = _draft.weather;
    var activities = List<String>.from(_draft.activities);

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          // 同时刷新页面与 sheet：页面负责画布组件同步,sheet 负责选中态。
          void apply(VoidCallback fn) {
            setState(fn);
            _syncComponents();
            _commit();
            setSheetState(() {
              mood = _draft.mood;
              weather = _draft.weather;
              activities = List<String>.from(_draft.activities);
            });
          }

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.7,
            builder: (_, controller) => ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                Text(
                  '手账信息',
                  style: Theme.of(
                    sheetContext,
                  ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  '心情、天气与活动同时用于统计,也可在画布上自由排版',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                _dateSelector(sheetContext, () => setSheetState(() {})),
                const SizedBox(height: 18),
                EmojiSelector(
                  label: '今日心情',
                  items: [
                    for (final m in Mood.values)
                      EmojiItem(
                        id: m.id,
                        emoji: m.emoji,
                        label: m.label,
                        color: m.color,
                      ),
                  ],
                  selectedId: mood?.id,
                  onSelected: (id) =>
                      apply(() => _draft.mood = id == null ? null : Mood.fromId(id)),
                ),
                const SizedBox(height: 18),
                EmojiSelector(
                  label: '今日天气',
                  items: [
                    for (final w in Weather.values)
                      EmojiItem(
                        id: w.id,
                        emoji: w.emoji,
                        label: w.label,
                        color: w.color,
                      ),
                  ],
                  selectedId: weather?.id,
                  onSelected: (id) => apply(
                    () => _draft.weather = id == null ? null : Weather.fromId(id),
                  ),
                ),
                const SizedBox(height: 20),
                ActivitySelector(
                  selected: activities,
                  customActivities:
                      sheetContext.watch<SettingsProvider>().customActivities,
                  onChanged: (next) =>
                      apply(() => _draft.activities = List.of(next)),
                  onAddCustom: (name) =>
                      sheetContext.read<SettingsProvider>().addCustomActivity(name),
                ),
                const SizedBox(height: 20),
                TagEditor(
                  tags: _draft.tags,
                  suggestions: sheetContext.watch<JournalProvider>().allTags,
                  onChanged: (tags) {
                    setState(() => _draft.tags = tags);
                    _dirty = true;
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _dateSelector(BuildContext context, VoidCallback onChanged) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () async {
        await _pickDate();
        onChanged();
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: scheme.primaryContainer.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_rounded, size: 19, color: scheme.primary),
            const SizedBox(width: 10),
            Text(
              DateUtils2.fullDate(_draft.date),
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            const Spacer(),
            Icon(
              Icons.expand_more_rounded,
              size: 20,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- 模板（REQ-09 + 整页版式） ----------------

  Future<void> _pickTemplate() async {
    final template = await showTemplatePicker(context);
    if (template == null || !mounted) return;
    _applyTemplate(template);
  }

  void _applyTemplate(JournalTemplate template) {
    final titleText = _titleElement?.text.trim() ?? '';
    final bodyText = _bodyElement?.text.trim() ?? _draft.content.trim();

    setState(() {
      if (template.canvas != null) {
        final next = template.canvas!.clone();
        final nextTitle = next.firstOfRole('title');
        final nextBody = next.firstOfRole('body');
        if (nextTitle != null) {
          nextTitle.text = titleText.isNotEmpty ? titleText : nextTitle.text;
          nextTitle.h = measureTextHeight(nextTitle);
        }
        if (nextBody != null) {
          var templateBody = nextBody.text;
          // 今日手账模板：当天每日一问自动填入正文占位。
          if (template.isTodayTemplate && templateBody.trim().isEmpty) {
            templateBody = '✨ 今日一问：$_prompt\n\n';
          }
          nextBody.text = bodyText.isNotEmpty
              ? '$templateBody\n\n$bodyText'
              : templateBody;
          nextBody.h = measureTextHeight(nextBody);
        }
        _canvas = next;
      } else {
        // 纯文本模板（旧数据/用户旧模板）：沿用文字填充逻辑。
        final title = _titleElement;
        if (title != null) {
          title.text = titleText.isEmpty ? template.title : titleText;
          title.h = measureTextHeight(title);
        }
        final body = _bodyElement;
        if (body != null) {
          body.text = bodyText.isEmpty
              ? template.content
              : '${template.content}\n\n$bodyText';
          body.h = measureTextHeight(body);
        }
      }
      for (final tag in template.tags) {
        if (!_draft.tags.contains(tag)) _draft.tags.add(tag);
      }
      _draft.paper = _canvas.paperId;
      _draft.canvas = _canvas;
      _syncComponents();
      _canvas.fitHeight();
    });
    _pushHistory();
    _editorKey.currentState?.clearSelection();
    // 记一次套用时间，供模板管理页「按最近使用」排序（REQ-18.4）；不阻塞套用。
    context.read<TemplateProvider>().markUsed(template.id);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已套用「${template.name}」✨ 点文字替换内容')));
    }
  }

  Future<void> _saveAsTemplate() async {
    final controller = TextEditingController();
    // 只有画布确实带照片才给「保留照片」选项，否则勾了也没意义（FIX-01.2）。
    final hasPhotos = _canvas.hasImagePaths;
    var keepPhotos = false;
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        // 勾选态由对话框自管理：外层 setState 不会重建 showDialog 的 builder。
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('另存为模板'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(hintText: '给模板起个名字'),
              ),
              if (hasPhotos) ...[
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: keepPhotos,
                  onChanged: (v) =>
                      setDialogState(() => keepPhotos = v ?? false),
                  title: const Text('保留照片', style: TextStyle(fontSize: 14)),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
                Text(
                  '不勾选时照片位置会留成占位框，套用模板时填自己的照片',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty || !mounted) return;
    final kept = hasPhotos && keepPhotos;
    _draft
      ..title = _titleElement?.text.trim() ?? ''
      ..content = _bodyElement?.text.trim() ?? '';
    await context.read<TemplateProvider>().saveFromEntry(
      _draft,
      trimmed,
      canvas: _canvas,
      keepPhotos: kept,
    );
    if (mounted) {
      var tip = '已保存模板「$trimmed」📔';
      if (hasPhotos) tip += kept ? ' 已保留照片' : ' 照片已留成占位框';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tip)));
    }
  }

  // ---------------- 构建 ----------------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isWide = MediaQuery.sizeOf(context).width >= 780;

    // 新建且未动笔画布时,引导从整页模板开始（三步成稿）。
    final showTemplateChips =
        !_isEditing && !_dirty && !_hasText && _canvas.images.isEmpty;

    final canvasChild = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child:
                _viewMode
                    // 查看态：静态渲染,只读浏览。
                    ? SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: CanvasView(canvas: _canvas, entry: _draft),
                    )
                    // 画布编辑器自带纵向滚动与选中操作条;底部工具栏悬浮其上。
                    : CanvasEditor(
                      key: _editorKey,
                      canvas: _canvas,
                      entry: _draft,
                      onCommit: _commit,
                      onEditText: _editText,
                      onEditImage: _editImage,
                      onEditComponent: _editComponent,
                    ),
          ),
        ),
      ),
    );

    final page = Column(
      children: [
        if (showTemplateChips)
        if (showTemplateChips)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                ActionChip(
                  avatar: Icon(Icons.auto_awesome_rounded, size: 17, color: scheme.primary),
                  label: const Text('今日手账'),
                  onPressed: () {
                    final today = context
                        .read<TemplateProvider>()
                        .byId('builtin-today');
                    if (today != null) {
                      _applyTemplate(today);
                    } else {
                      _pickTemplate();
                    }
                  },
                ),
                const SizedBox(width: 8),
                ActionChip(
                  avatar: Icon(
                    Icons.description_outlined,
                    size: 17,
                    color: scheme.primary,
                  ),
                  label: const Text('从模板开始'),
                  onPressed: _pickTemplate,
                ),
              ],
            ),
          ),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(child: canvasChild),
              if (!_viewMode) _bottomToolbar(scheme),
            ],
          ),
        ),
      ],
    );

    final body = isWide
        ? Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: page,
            ),
          )
        : page;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _confirmDiscard();
        if (shouldPop && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () async {
              final shouldPop = await _confirmDiscard();
              if (shouldPop && context.mounted) Navigator.of(context).pop();
            },
          ),
          title: Text(_viewMode ? '手账' : (_isEditing ? '编辑手账' : '写手账')),
          actions: [
            if (_viewMode)
              IconButton(
                tooltip: '编辑',
                icon: const Icon(Icons.edit_rounded),
                onPressed: () => setState(() => _viewMode = false),
              )
            else ...[
              IconButton(
                tooltip: '撤销',
                icon: const Icon(Icons.undo_rounded),
                onPressed: _canUndo ? _undo : null,
              ),
              IconButton(
                tooltip: '重做',
                icon: const Icon(Icons.redo_rounded),
                onPressed: _canRedo ? _redo : null,
              ),
              PopupMenuButton<String>(
                icon: Icon(
                  Icons.more_vert_rounded,
                  color: scheme.onSurfaceVariant,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'template',
                    child: Row(
                      children: [
                        Icon(Icons.description_outlined, size: 19),
                        SizedBox(width: 10),
                        Text('套用模板'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'save_template',
                    child: Row(
                      children: [
                        Icon(Icons.bookmark_add_outlined, size: 19),
                        SizedBox(width: 10),
                        Text('另存为模板'),
                      ],
                    ),
                  ),
                ],
                onSelected: (value) {
                  if (value == 'template') _pickTemplate();
                  if (value == 'save_template') _saveAsTemplate();
                },
              ),
              IconButton(
                tooltip: '保存',
                icon: const Icon(Icons.save_rounded),
                onPressed: _save,
              ),
            ],
            const SizedBox(width: 12),
          ],
        ),
        body: body,
      ),
    );
  }

  /// 底部工具栏：贴纸 / 照片 / 文字 / 纸张 / 一问 / 信息。
  /// 悬浮在画布上方的胶囊长条（椭圆形）。
  Widget _bottomToolbar(ColorScheme scheme) {
    Widget tool(String label, IconData icon, VoidCallback onTap) => Tooltip(
      message: label,
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Icon(icon, size: 23, color: scheme.onSurfaceVariant),
        ),
      ),
    );

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        minimum: const EdgeInsets.only(bottom: 12),
        top: false,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(40),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  tool('贴纸', Icons.emoji_emotions_outlined, _addSticker),
                  tool('照片', Icons.add_photo_alternate_outlined, _addPhoto),
                  tool('文字', Icons.text_fields_rounded, _addText),
                  tool('纸张', Icons.layers_outlined, _pickPaper),
                  tool('一问', Icons.auto_awesome_rounded, _showPromptSheet),
                  tool('信息', Icons.tune_rounded, _showInfoSheet),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

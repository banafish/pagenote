import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import '../data/prompts.dart';
import '../models/decoration.dart';
import '../models/journal_entry.dart';
import '../models/mood.dart';
import '../providers/journal_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/template_provider.dart';
import '../utils/attachments.dart';
import '../utils/date_utils.dart';
import '../widgets/activity_selector.dart';
import '../widgets/daily_prompt_card.dart';
import '../widgets/emoji_selector.dart';
import '../widgets/sticker_layer.dart';
import '../widgets/tag_editor.dart';
import '../widgets/template_picker.dart';

/// 手账编辑器：新建或编辑一条手账。
class EditorPage extends StatefulWidget {
  const EditorPage({super.key, this.entry});

  /// 传入则为编辑模式，否则为新建。
  final JournalEntry? entry;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  late final JournalEntry _draft;
  late final TextEditingController _title;
  late final TextEditingController _content;
  late final bool _isEditing;
  bool _saved = false;

  // 装饰排版（REQ-13）：当前选中的贴纸下标,-1 为未选中。
  int _selectedSticker = -1;

  // 每日一问（REQ-04）。
  late String _todayKey;
  int _promptOffset = 0;
  int _promptRemaining = 3;

  static final _mediaQueryKey = GlobalKey();

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
    _isEditing = widget.entry != null;
    _title = TextEditingController(text: _draft.title);
    _content = TextEditingController(text: _draft.content);

    final settings = context.read<SettingsProvider>();
    // 每日一问按「今天」展示（REQ-04.1），与补写日期无关。
    _todayKey = DateUtils2.dateKey(DateTime.now());
    _promptOffset = settings.promptOffsetFor(_todayKey);
    _promptRemaining =
        3 - settings.promptRefreshUsedToday(_todayKey).clamp(0, 3);
  }

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  bool get _hasContent =>
      _title.text.trim().isNotEmpty || _content.text.trim().isNotEmpty;

  String get _prompt => promptForDate(_todayKey, _promptOffset);

  Future<void> _save() async {
    if (!_hasContent) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('写点什么再保存吧 ✏️')));
      return;
    }
    _draft
      ..title = _title.text.trim()
      ..content = _content.text.trim()
      // 整理速记：在编辑页保存即转为正式手账（REQ-16）。
      ..isQuickNote = false
      ..updatedAt = DateTime.now();
    await context.read<JournalProvider>().saveEntry(_draft);
    _saved = true;
    if (mounted) Navigator.of(context).pop();
  }

  Future<bool> _confirmDiscard() async {
    if (_saved || (!_hasContent && _draft.images.isEmpty)) return true;
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

  Future<void> _pickDate() async {
    // 独立 Localizations，使对话框星期文字为中文。
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

  Future<void> _addImages() async {
    final paths = await Attachments.pickImages(
      remaining: Attachments.maxImages - _draft.images.length,
    );
    if (paths.isNotEmpty) setState(() => _draft.images.addAll(paths));
  }

  // ---------------- 每日一问（REQ-04） ----------------

  void _insertPrompt() {
    final text = _content.text;
    _content.text = text.isEmpty ? '$_prompt\n' : '$_prompt\n\n$text';
    _content.selection = TextSelection.fromPosition(
      TextPosition(offset: _content.text.length),
    );
    setState(() {});
  }

  Future<void> _refreshPrompt() async {
    final settings = context.read<SettingsProvider>();
    final ok = await settings.usePromptRefresh(_todayKey);
    if (!ok || !mounted) return;
    setState(() {
      _promptOffset = settings.promptOffsetFor(_todayKey);
      _promptRemaining = 3 - settings.promptRefreshUsedToday(_todayKey);
    });
  }

  // ---------------- 装饰排版（REQ-13） ----------------

  Widget _decorationSection(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '纸张与贴纸',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
            const Spacer(),
            ActionChip(
              avatar: Icon(
                Icons.emoji_emotions_outlined,
                size: 17,
                color: scheme.primary,
              ),
              label: const Text('加贴纸'),
              onPressed: _showStickerPalette,
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: paperStyles.length + 1,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              // 首位「无」:恢复主题默认背景。
              if (i == 0) return _paperSwatch(scheme, null);
              return _paperSwatch(scheme, paperStyles[i - 1]);
            },
          ),
        ),
        if (_draft.stickers.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              '已放 ${_draft.stickers.length} 个贴纸 · 点击页面中的贴纸可移动、缩放、旋转',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }

  Widget _paperSwatch(ColorScheme scheme, PaperStyle? paper) {
    final selected = paper == null
        ? _draft.paper.isEmpty
        : _draft.paper == paper.id;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      key: ValueKey('paper-${paper?.id ?? 'none'}'),
      onTap: () => setState(() => _draft.paper = paper?.id ?? ''),
      child: Tooltip(
        message: paper?.name ?? '无',
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 2.2 : 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: paper == null
                ? Container(
                    color: isDark ? const Color(0xFF2A2521) : Colors.white,
                    alignment: Alignment.center,
                    child: Text(
                      '无',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : CustomPaint(
                    size: const Size(44, 44),
                    painter: PaperPainter(paper, dark: isDark),
                  ),
          ),
        ),
      ),
    );
  }

  Future<void> _showStickerPalette() async {
    final emoji = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360),
          child: GridView.count(
            crossAxisCount: 6,
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            children: [
              for (final e in stickerPalette)
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.pop(sheetContext, e),
                  child: Center(
                    child: Text(e, style: const TextStyle(fontSize: 26)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (emoji == null || !mounted) return;
    setState(() {
      // 新贴纸落在页面上方居中处,便于立刻看到并调整。
      _draft.stickers.add(Sticker(emoji: emoji, dx: 0.5, dy: 0.16));
      _selectedSticker = _draft.stickers.length - 1;
    });
  }

  // ---------------- 模板（REQ-09） ----------------

  Future<void> _pickTemplate() async {
    final template = await showTemplatePicker(context);
    if (template == null) return;
    setState(() {
      if (_title.text.trim().isEmpty) {
        _title.text = template.title;
      }
      if (_content.text.trim().isEmpty) {
        _content.text = template.content;
      } else {
        _content.text = '${template.content}\n\n${_content.text}';
      }
      for (final tag in template.tags) {
        if (!_draft.tags.contains(tag)) _draft.tags.add(tag);
      }
    });
  }

  Future<void> _saveAsTemplate() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('另存为模板'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '给模板起个名字'),
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
    );
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty || !mounted) return;
    await context.read<TemplateProvider>().saveFromEntry(
      JournalEntry(
        id: _draft.id,
        date: _draft.date,
        title: _title.text.trim(),
        content: _content.text.trim(),
        tags: List.from(_draft.tags),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      trimmed,
    );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已保存模板「$trimmed」📔')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isWide = MediaQuery.sizeOf(context).width >= 780;

    final form = ListView(
      key: _mediaQueryKey,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        _dateSelector(scheme),
        // 速记整理提示（REQ-16）：编辑未整理速记时说明保存即转正。
        if (_draft.isQuickNote)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              children: [
                Icon(Icons.bolt_rounded, size: 17, color: scheme.tertiary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '这是一条速记,补充心情与标签后保存即转为正式手账',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 18),

        // 每日一问（REQ-04.3：编辑已有条目默认收起）。
        DailyPromptCard(
          prompt: _prompt,
          initiallyExpanded: !_isEditing,
          onInsert: _insertPrompt,
          onRefresh: _refreshPrompt,
          refreshRemaining: _promptRemaining,
        ),
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
          selectedId: _draft.mood?.id,
          onSelected: (id) =>
              setState(() => _draft.mood = id == null ? null : Mood.fromId(id)),
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
          selectedId: _draft.weather?.id,
          onSelected: (id) => setState(
            () => _draft.weather = id == null ? null : Weather.fromId(id),
          ),
        ),
        const SizedBox(height: 20),
        ActivitySelector(
          selected: _draft.activities,
          customActivities: context.watch<SettingsProvider>().customActivities,
          onChanged: (activities) =>
              setState(() => _draft.activities = activities),
          onAddCustom: (name) =>
              context.read<SettingsProvider>().addCustomActivity(name),
        ),
        const SizedBox(height: 20),
        _decorationSection(scheme),
        const SizedBox(height: 20),
        if (!_isEditing && !_hasContent)
          Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: ActionChip(
              avatar: Icon(
                Icons.description_outlined,
                size: 17,
                color: scheme.primary,
              ),
              label: const Text('从模板开始'),
              onPressed: _pickTemplate,
            ),
          ),
        TextField(
          controller: _title,
          style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
          decoration: const InputDecoration(
            hintText: '标题',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          ),
          textInputAction: TextInputAction.next,
          maxLength: 60,
        ),
        Divider(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        const SizedBox(height: 6),
        TextField(
          controller: _content,
          maxLines: null,
          minLines: 6,
          style: const TextStyle(fontSize: 16, height: 1.8),
          decoration: const InputDecoration(
            hintText: '记录此刻的所思所感…',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          ),
        ),
        const SizedBox(height: 12),
        TagEditor(
          tags: _draft.tags,
          suggestions: context.watch<JournalProvider>().allTags,
          onChanged: (tags) => setState(() => _draft.tags = tags),
        ),
        const SizedBox(height: 18),
        _imageSection(scheme),
      ],
    );

    // 装饰排版（REQ-13）：纸张纹理作正文背景,贴纸浮于整页之上。
    final paper = paperById(_draft.paper);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final page = Stack(
      children: [
        if (paper != null)
          Positioned.fill(
            child: CustomPaint(painter: PaperPainter(paper, dark: isDark)),
          ),
        form,
        Positioned.fill(
          child: StickerOverlay(
            stickers: _draft.stickers,
            selectedIndex: _selectedSticker,
            onChanged: () => setState(() {}),
            onSelect: (i) => setState(
              () => _selectedSticker = _selectedSticker == i ? -1 : i,
            ),
          ),
        ),
        if (_selectedSticker >= 0 && _selectedSticker < _draft.stickers.length)
          Positioned(
            left: 16,
            right: 16,
            bottom: 18,
            child: StickerToolbar(
              sticker: _draft.stickers[_selectedSticker],
              onChanged: () => setState(() {}),
              onDelete: () => setState(() {
                _draft.stickers.removeAt(_selectedSticker);
                _selectedSticker = -1;
              }),
              onDone: () => setState(() => _selectedSticker = -1),
            ),
          ),
      ],
    );

    final body = isWide
        ? Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
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
          title: Text(_isEditing ? '编辑手账' : '写手账'),
          actions: [
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
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.check_rounded, size: 19),
                label: const Text('保存'),
              ),
            ),
          ],
        ),
        body: body,
      ),
    );
  }

  Widget _dateSelector(ColorScheme scheme) {
    return InkWell(
      onTap: _pickDate,
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

  Widget _imageSection(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '照片',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${_draft.images.length}/9',
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (var i = 0; i < _draft.images.length; i++)
              _imageTile(_draft.images[i], i, scheme),
            if (_draft.images.length < 9) _addTile(scheme),
          ],
        ),
      ],
    );
  }

  Widget _imageTile(String path, int index, ColorScheme scheme) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 104,
            height: 104,
            child: Image.file(
              File(path),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                color: scheme.surfaceContainerHighest,
                child: Icon(
                  Icons.broken_image_outlined,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: Material(
            color: Colors.black.withValues(alpha: 0.55),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () {
                final removed = _draft.images.removeAt(index);
                Attachments.delete(removed);
                setState(() {});
              },
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close, size: 15, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _addTile(ColorScheme scheme) {
    return InkWell(
      onTap: _addImages,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 104,
        height: 104,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.8),
          ),
        ),
        child: Icon(
          Icons.add_photo_alternate_outlined,
          size: 30,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

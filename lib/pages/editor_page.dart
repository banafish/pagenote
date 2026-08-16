import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import '../models/journal_entry.dart';
import '../models/mood.dart';
import '../providers/journal_provider.dart';
import '../utils/attachments.dart';
import '../utils/date_utils.dart';
import '../widgets/emoji_selector.dart';
import '../widgets/tag_editor.dart';

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

  static final _mediaQueryKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _draft = widget.entry?.copy() ??
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
  }

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  bool get _hasContent =>
      _title.text.trim().isNotEmpty || _content.text.trim().isNotEmpty;

  Future<void> _save() async {
    if (!_hasContent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('写点什么再保存吧 ✏️')),
      );
      return;
    }
    _draft
      ..title = _title.text.trim()
      ..content = _content.text.trim()
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isWide = MediaQuery.sizeOf(context).width >= 780;

    final form = ListView(
      key: _mediaQueryKey,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        _dateSelector(scheme),
        const SizedBox(height: 18),
        EmojiSelector(
          label: '今日心情',
          items: [
            for (final m in Mood.values)
              EmojiItem(id: m.id, emoji: m.emoji, label: m.label, color: m.color),
          ],
          selectedId: _draft.mood?.id,
          onSelected: (id) => setState(
            () => _draft.mood = id == null ? null : Mood.fromId(id),
          ),
        ),
        const SizedBox(height: 18),
        EmojiSelector(
          label: '今日天气',
          items: [
            for (final w in Weather.values)
              EmojiItem(id: w.id, emoji: w.emoji, label: w.label, color: w.color),
          ],
          selectedId: _draft.weather?.id,
          onSelected: (id) => setState(
            () => _draft.weather = id == null ? null : Weather.fromId(id),
          ),
        ),
        const SizedBox(height: 20),
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

    final body = isWide
        ? Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: form,
            ),
          )
        : form;

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
            Icon(Icons.calendar_today_rounded,
                size: 19, color: scheme.primary),
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
            Icon(Icons.expand_more_rounded,
                size: 20, color: scheme.onSurfaceVariant),
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
            if (_draft.images.length < 9)
              _addTile(scheme),
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
                child: Icon(Icons.broken_image_outlined,
                    color: scheme.onSurfaceVariant),
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
        child: Icon(Icons.add_photo_alternate_outlined,
            size: 30, color: scheme.onSurfaceVariant),
      ),
    );
  }
}

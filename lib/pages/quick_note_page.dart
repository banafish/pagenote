import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/journal_entry.dart';
import '../providers/journal_provider.dart';
import '../utils/attachments.dart';
import '../utils/date_utils.dart';

/// 快速速记（REQ-16）：不进完整编辑器的轻量入口。
/// 一句话 + 可选图片直接入库,标记「未整理」;
/// 稍后在时间轴点开即可补充心情/标签,保存后转为正式手账。
class QuickNotePage extends StatefulWidget {
  const QuickNotePage({super.key});

  @override
  State<QuickNotePage> createState() => _QuickNotePageState();
}

class _QuickNotePageState extends State<QuickNotePage> {
  static const maxImages = 4;

  final _text = TextEditingController();
  final List<String> _images = [];
  bool _saved = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _hasContent => _text.text.trim().isNotEmpty || _images.isNotEmpty;

  Future<void> _save() async {
    if (!_hasContent) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('写一句话再保存吧 ⚡')));
      return;
    }
    final now = DateTime.now();
    await context.read<JournalProvider>().saveEntry(
      JournalEntry(
        id: JournalProvider.newId(),
        date: DateUtils2.dateKey(now),
        title: '',
        content: _text.text.trim(),
        images: List.from(_images),
        isQuickNote: true,
        createdAt: now,
        updatedAt: now,
      ),
    );
    _saved = true;
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已存入速记,可稍后整理 ✨')));
      Navigator.of(context).pop();
    }
  }

  Future<void> _addImages() async {
    final paths = await Attachments.pickImages(
      remaining: maxImages - _images.length,
    );
    if (paths.isNotEmpty) setState(() => _images.addAll(paths));
  }

  Future<bool> _confirmDiscard() async {
    if (_saved || !_hasContent) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('放弃这条速记?'),
        content: const Text('未保存的内容将会丢失。'),
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

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
          title: const Text('速记'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.bolt_rounded, size: 19),
                label: const Text('记下'),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: TextField(
                  controller: _text,
                  autofocus: true,
                  maxLines: null,
                  minLines: 3,
                  textInputAction: TextInputAction.newline,
                  style: const TextStyle(fontSize: 17, height: 1.7),
                  decoration: const InputDecoration(
                    hintText: '一句话记下此刻…',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (var i = 0; i < _images.length; i++)
                      _imageTile(_images[i], i, scheme),
                    if (_images.length < maxImages) _addTile(scheme),
                  ],
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 15,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '速记会标记为「未整理」,之后点开即可补充心情与标签',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _imageTile(String path, int index, ColorScheme scheme) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 92,
            height: 92,
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
                final removed = _images.removeAt(index);
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
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 92,
        height: 92,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.8),
          ),
        ),
        child: Icon(
          Icons.add_photo_alternate_outlined,
          size: 28,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

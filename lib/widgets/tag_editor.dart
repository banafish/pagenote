import 'package:flutter/material.dart';

/// 标签编辑：展示已有标签 + 从建议中选择 + 输入新建。
class TagEditor extends StatefulWidget {
  const TagEditor({
    super.key,
    required this.tags,
    required this.suggestions,
    required this.onChanged,
  });

  final List<String> tags;
  final List<String> suggestions;
  final ValueChanged<List<String>> onChanged;

  @override
  State<TagEditor> createState() => _TagEditorState();
}

class _TagEditorState extends State<TagEditor> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _adding = false;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<String> get _unusedSuggestions => widget.suggestions
      .where((t) => !widget.tags.contains(t))
      .take(8)
      .toList();

  void _addTag(String raw) {
    final tag = raw.trim().replaceAll('#', '');
    if (tag.isEmpty || widget.tags.contains(tag)) {
      _controller.clear();
      return;
    }
    widget.onChanged([...widget.tags, tag]);
    _controller.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final suggestions = _unusedSuggestions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '标签',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${widget.tags.length} 个',
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (widget.tags.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in widget.tags)
                InputChip(
                  label: Text('#$tag'),
                  onDeleted: () {
                    widget.onChanged(
                      widget.tags.where((t) => t != tag).toList(),
                    );
                    setState(() {});
                  },
                  backgroundColor: scheme.primaryContainer.withValues(
                    alpha: 0.5,
                  ),
                ),
            ],
          ),
        if (widget.tags.isNotEmpty) const SizedBox(height: 12),
        if (_adding)
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: '输入标签名，回车确认',
                    isDense: true,
                  ),
                  onSubmitted: (value) {
                    _addTag(value);
                    setState(() => _adding = false);
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.check),
                onPressed: () {
                  _addTag(_controller.text);
                  setState(() => _adding = false);
                },
              ),
            ],
          )
        else
          ActionChip(
            avatar: const Icon(Icons.add, size: 17),
            label: const Text('添加标签'),
            onPressed: () => setState(() {
              _adding = true;
              _controller.clear();
            }),
          ),
        if (suggestions.isNotEmpty && !_adding) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in suggestions)
                ActionChip(
                  label: Text(
                    '#$tag',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  onPressed: () => _addTag(tag),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

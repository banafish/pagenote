import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/journal_entry.dart';
import '../providers/journal_provider.dart';
import '../widgets/entry_card.dart';
import 'editor_page.dart';

/// 搜索页：按标题、正文与标签搜索手账。
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  String _query = '';
  List<JournalEntry> _results = [];
  bool _searched = false;

  @override
  void initState() {
    super.initState();
    _focus.requestFocus();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      final q = value.trim();
      if (q.isEmpty) {
        setState(() {
          _query = '';
          _results = [];
          _searched = false;
        });
        return;
      }
      _runQuery(q);
    });
  }

  Future<void> _runQuery(String q) async {
    final results = await context.read<JournalProvider>().search(q);
    if (!mounted) return;
    setState(() {
      _query = q;
      _results = results;
      _searched = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final journal = context.watch<JournalProvider>();
    final scheme = Theme.of(context).colorScheme;
    final recentTags = journal.allTags.take(10).toList();

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          focusNode: _focus,
          decoration: InputDecoration(
            hintText: '搜索标题、内容或标签…',
            prefixIcon: const Icon(Icons.search, size: 21),
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear, size: 20),
                    onPressed: () {
                      _controller.clear();
                      _onChanged('');
                    },
                  ),
            contentPadding: EdgeInsets.zero,
          ),
          onChanged: (v) {
            _onChanged(v);
            setState(() {});
          },
          onSubmitted: _runQuery,
        ),
      ),
      body: !_searched
          ? ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (recentTags.isNotEmpty) ...[
                  Text(
                    '按标签浏览',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final tag in recentTags)
                        ActionChip(
                          label: Text('#$tag'),
                          onPressed: () {
                            _controller.text = tag;
                            _runQuery(tag);
                          },
                        ),
                    ],
                  ),
                ],
              ],
            )
          : _results.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search_off_rounded,
                          size: 52, color: scheme.onSurfaceVariant),
                      const SizedBox(height: 16),
                      Text(
                        '没有找到「$_query」相关的手账',
                        style:
                            TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: _results.length,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: EntryCard(
                      entry: _results[i],
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                EditorPage(entry: _results[i]),
                          ),
                        );
                        if (mounted) _runQuery(_query);
                      },
                      onToggleFavorite: (id) => context
                          .read<JournalProvider>()
                          .toggleFavorite(id),
                      onDelete: (id) => _confirmDelete(context, id),
                    ),
                  ),
                ),
    );
  }

  void _confirmDelete(BuildContext context, String id) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除这篇手账？'),
        content: const Text('删除后无法恢复，确定要删除吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE57373),
            ),
            onPressed: () {
              Navigator.pop(dialogContext);
              context.read<JournalProvider>().deleteEntry(id);
              _runQuery(_query);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/journal_provider.dart';

/// 软删除并展示「撤销」即时提示（REQ-02.1）。
/// 适用于首页/日历/搜索等全部删除入口。
Future<void> deleteWithUndo(BuildContext context, String id) async {
  final journal = context.read<JournalProvider>();
  await journal.softDelete(id);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: const Text('已移入回收站，30 天后自动清除'),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () => journal.restoreEntry(id),
        ),
      ),
    );
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/sticker_assets.dart';
import '../providers/custom_sticker_provider.dart';
import '../providers/template_provider.dart';
import '../services/share_pack_service.dart';
import 'pack_actions.dart';

/// 素材包导出页（REQ-21.1/21.2）：勾选模板与自定义贴纸后打包，
/// 包的 kind 由实际内容决定（只有模板 template、只有贴纸 sticker、都有 mixed）。
/// 入口原在设置页，为方便寻找已上移到素材页 AppBar（延续 REQ-26 的素材归属）。
class SharePackExportPage extends StatefulWidget {
  const SharePackExportPage({super.key});

  @override
  State<SharePackExportPage> createState() => _SharePackExportPageState();
}

class _SharePackExportPageState extends State<SharePackExportPage> {
  static const _defaultName = '我的素材包';

  final _nameController = TextEditingController(text: _defaultName);
  final _authorController = TextEditingController();
  final _templateIds = <String>{};
  final _stickerIds = <String>{};
  bool _exporting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _authorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 内置模板每台设备都有，打包发给别人没有意义，只列自建模板。
    final templates = context.watch<TemplateProvider>().userTemplates;
    final stickers = context.watch<CustomStickerProvider>().stickers;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('导出素材包')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _ExportCard(
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '包名',
                  hintText: '如：秋日旅行模板集',
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _authorController,
                decoration: const InputDecoration(labelText: '署名（可留空）'),
              ),
            ],
          ),
          const SizedBox(height: 22),
          _groupLabel('模板', '${templates.length} 套自建'),
          const SizedBox(height: 8),
          if (templates.isEmpty)
            _emptyHint('还没有自建模板，可在编辑页「另存为模板」后再来')
          else
            _ExportCard(
              children: [
                for (final t in templates)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: _templateIds.contains(t.id),
                    title: Text(
                      t.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      t.canvas == null ? '纯文本模板' : '整页版式',
                      style: const TextStyle(fontSize: 12),
                    ),
                    onChanged: (_) => _toggle(_templateIds, t.id),
                  ),
              ],
            ),
          const SizedBox(height: 22),
          _groupLabel('自定义贴纸', '${stickers.length} 张'),
          const SizedBox(height: 8),
          if (stickers.isEmpty)
            _emptyHint('还没有自定义贴纸，可在素材面板「我的」里从相册导入')
          else
            _ExportCard(
              children: [
                for (final s in stickers)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    secondary: _stickerThumb(s),
                    value: _stickerIds.contains(s.id),
                    title: Text(
                      s.name.isEmpty ? '未命名贴纸' : s.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      s.category,
                      style: const TextStyle(fontSize: 12),
                    ),
                    onChanged: (_) => _toggle(_stickerIds, s.id),
                  ),
              ],
            ),
          const SizedBox(height: 14),
          Text(
            '模板用到的自定义贴纸会自动随包带上，接收方开箱即用；'
            '模板里的本机照片默认不进包，只留占位框，导出时可以选择一并带上。',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.6,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      bottomNavigationBar: _bottomBar(),
    );
  }

  Widget _bottomBar() {
    final scheme = Theme.of(context).colorScheme;
    final empty = _templateIds.isEmpty && _stickerIds.isEmpty;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                empty
                    ? '至少选一项才能打包'
                    : '已选 ${_templateIds.length} 套模板 · ${_stickerIds.length} 张贴纸',
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: empty || _exporting ? null : _export,
              icon: const Icon(Icons.ios_share_rounded, size: 18),
              label: Text(_exporting ? '打包中…' : '导出'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _groupLabel(String text, String hint) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          text,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 8),
        Text(
          hint,
          style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _emptyHint(String text) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
      ),
    );
  }

  Widget _stickerThumb(CustomSticker sticker) {
    final scheme = Theme.of(context).colorScheme;
    final path = CustomStickerIndex.instance.pathOf(sticker.id);
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: path == null
          ? Icon(Icons.image_outlined, size: 18, color: scheme.onSurfaceVariant)
          : Image.file(
              File(path),
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => Icon(
                Icons.broken_image_outlined,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
            ),
    );
  }

  void _toggle(Set<String> ids, String id) {
    setState(() {
      if (!ids.remove(id)) ids.add(id);
    });
  }

  Future<void> _export() async {
    final templateProvider = context.read<TemplateProvider>();
    final stickerProvider = context.read<CustomStickerProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final picked = [
      for (final t in templateProvider.userTemplates)
        if (_templateIds.contains(t.id)) t,
    ];
    // 画布里还留着本机照片时先问一次带不带（FIX-01.2 / REQ-21.4）。
    final withPhotos = picked
        .where((t) => t.canvas?.hasImagePaths ?? false)
        .toList();
    var includePhotos = false;
    if (withPhotos.isNotEmpty) {
      final choice = await askIncludeTemplatePhotos(context, withPhotos);
      if (choice == null || !mounted) return;
      includePhotos = choice;
    }
    // 最后一步问存到哪（REQ-21.5）：挑文件夹直接落盘，或交给系统分享。
    final destination = await askPackExportDestination(context);
    if (destination == null || !mounted) return;

    // 带照片时把原始模板交给 buildPack，不带时先在这里清成占位框。
    final packed = includePhotos
        ? picked
        : [for (final t in picked) templateWithoutPhotos(t)];
    // 勾选的贴纸 + 模板引用到的贴纸（REQ-21.3）。
    final ids = {..._stickerIds, ...referencedStickerIds(packed)};
    final name = _nameController.text.trim();
    setState(() => _exporting = true);
    try {
      final path = await SharePackService.instance.exportPack(
        packName: name.isEmpty ? _defaultName : name,
        author: _authorController.text.trim(),
        templates: packed,
        stickers: [
          for (final s in stickerProvider.stickers)
            if (ids.contains(s.id)) s,
        ],
        stickerBytes: await stickerProvider.exportBytes(ids: ids),
        includePhotos: includePhotos,
        destination: destination,
      );
      // 用户在系统对话框里取消时返回 null，留在页面上不打扰。
      if (path != null) {
        messenger.showSnackBar(SnackBar(content: Text('素材包已导出：$path')));
        navigator.pop();
      }
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('导出失败，请重试')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
}

/// 与设置页卡片同一套观感：Material 承载背景与圆角，内部水波纹可见。
class _ExportCard extends StatelessWidget {
  const _ExportCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
}
